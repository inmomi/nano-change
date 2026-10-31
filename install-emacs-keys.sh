#!/usr/bin/env bash
# install-emacs-keys.sh —— 把 Emacs 风格键位装进 nano，自动适配版本
#
# 用法:
#   ./install-emacs-keys.sh                  # 写入 ~/.nanorc
#   ./install-emacs-keys.sh --target FILE    # 写到指定文件
#   ./install-emacs-keys.sh --dry-run        # 只打印，不落盘
#   ./install-emacs-keys.sh --help
#
# 原理: 不假设函数名。每一条都先拿真正的 nano 试运行一次，报错就退到
#       下一个候选名，全都不行就跳过。因此在 2.x 到 8.x 上都能得到一份
#       当前这份 nano 真正支持的配置。

set -u

BLOCK_ID="emacs-nano"
STYLE="Emacs"
DRYRUN=0

usage() {
  cat <<'USAGE'
install-emacs-keys.sh —— 让 nano 用起来像 Emacs

  --target FILE   写入指定文件（默认 ~/.nanorc）
  --dry-run       只打印将要写入的内容
  -h, --help      显示本帮助

退出码: 0 成功 / 1 环境问题 / 2 参数错误
USAGE
}

TARGET="${HOME}/.nanorc"

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      if [ $# -lt 2 ]; then
        echo "错误: --target 需要一个文件路径" >&2
        exit 2
      fi
      TARGET="$2"; shift 2 ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "错误: 未知参数 $1（用 --help 看用法）" >&2; exit 2 ;;
  esac
done

NANO=$(command -v nano 2>/dev/null) || { echo "错误: 找不到 nano，先装一个" >&2; exit 1; }
VER=$("$NANO" --version 2>/dev/null | head -1 | tr -d '\r')

if [ -d "$TARGET" ]; then
  echo "错误: $TARGET 是个目录，--target 需要文件名" >&2
  exit 1
fi

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t nanorc)
trap 'rm -rf "$WORK"' EXIT

export TERM="${TERM:-xterm}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# 自检需要 GNU 版 script（-c）。BSD/macOS 的 script 语法不同，检测不到就降级。
SELFCHECK=1
if ! have_cmd script; then
  SELFCHECK=0
elif ! script --help 2>&1 | grep -q -- ' --command\| -c,'; then
  SELFCHECK=0
fi
# 测试用开关：强制走"不自检"的降级分支
if [ "${FKEYS_NO_SELFCHECK:-0}" = "1" ]; then
  SELFCHECK=0
fi

# 在 pty 里跑一次 nano，看它有没有对这份 rc 报错
rc_works() {
  local rc="$1" out
  [ "$SELFCHECK" -eq 1 ] || return 0
  if have_cmd timeout; then
    out=$(printf '\030' | timeout 8 script -qec "$NANO --rcfile=$rc /dev/null" /dev/null 2>&1)
  else
    out=$(printf '\030' | script -qec "$NANO --rcfile=$rc /dev/null" /dev/null 2>&1)
  fi
  case "$out" in
    *错误*|*rror*) return 1 ;;
    *) return 0 ;;
  esac
}

# 单行探测：写一份只含该行的 rc，启动 nano 看它认不认
probe() {
  local line="$1" rc="$WORK/probe.nanorc"
  printf '%s\n' "$line" > "$rc"
  rc_works "$rc"
}

## 设置项（逐条探测，老版本不认识的会被跳过）
SETTINGS="
set linenumbers
set constantshow
set historylog
set multibuffer
"

## 按键 + 候选函数名（从左到右取第一个当前版本认识的）
MAP="
^S savefile writeout
^Y paste uncut
M-w copy copytext
^Space mark
M-% replace
M-g gotoline
M-< firstline
M-> lastline
M-v pageup prevpage
^_ undo
^O enter
"

echo "nano: $VER"
echo "位置: $NANO"
echo "风格: $STYLE"
if [ "$SELFCHECK" -eq 0 ]; then
  echo "提示: 没有可用的 script 命令，跳过逐条自检，按常见函数名全部写入。" >&2
  echo "      无效的行 nano 启动时会在底部提示，忽略即可。" >&2
fi
echo "---"

BLOCK="$WORK/block.txt"
echo "# >>> $BLOCK_ID 自动适配块（由 install-emacs-keys.sh 生成）>>>" > "$BLOCK"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  if probe "$line"; then
    echo "$line" >> "$BLOCK"
    printf '  ✓ %s\n' "$line"
  else
    printf '  ✗ %s  （本版本不支持，跳过）\n' "$line"
  fi
done <<EOF
$SETTINGS
EOF

OK=0
SKIP=""
while read -r key funcs; do
  [ -n "${key:-}" ] || continue
  placed=""
  # 这里需要按空格拆成多个候选函数名
  # shellcheck disable=SC2086
  for f in ${funcs:-}; do
    if probe "bind $key $f main"; then
      echo "bind $key $f main" >> "$BLOCK"
      printf '  ✓ %-8s → %-12s\n' "$key" "$f"
      placed=1
      OK=$((OK + 1))
      break
    fi
  done
  [ -n "$placed" ] || { printf '  ✗ %-8s   跳过（本版本无可用函数）\n' "$key"; SKIP="$SKIP $key"; }
done <<EOF
$MAP
EOF

echo "# <<< $BLOCK_ID 自动适配块 <<<" >> "$BLOCK"

echo "---"
echo "成功 $OK 条按键${SKIP:+，跳过:$SKIP}"

if [ "$DRYRUN" -eq 1 ]; then
  echo "（dry-run，内容如下，未写入）"
  cat "$BLOCK"
  exit 0
fi

if [ "$OK" -eq 0 ]; then
  echo "错误: 一条都没装上，这份 nano 可能太老或自检异常，未改动 $TARGET" >&2
  exit 1
fi

# 去掉旧块（emacs 与 vim 的块都清掉，避免两套配置互相抢键位）
CLEAN="$WORK/clean.txt"
: > "$CLEAN"
if [ -f "$TARGET" ]; then
  if ! awk '/^# >>> (emacs|vim)-nano/{s=1;next} /^# <<< (emacs|vim)-nano/{s=0;next} !s' \
       "$TARGET" > "$CLEAN"; then
    echo "错误: 读取 $TARGET 失败" >&2
    exit 1
  fi
  if cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"; then
    echo "已备份: $TARGET.bak.*"
  else
    echo "警告: 备份失败，继续写入" >&2
  fi
fi

cat "$CLEAN" "$BLOCK" > "$WORK/new.txt"

mkdir -p "$(dirname "$TARGET")" 2>/dev/null

if ! cat "$WORK/new.txt" > "$TARGET"; then
  echo "错误: 写不进 $TARGET（权限？）" >&2
  exit 1
fi

echo "已写入: $TARGET"
echo "重开 nano 生效。撤销：删掉文件里 >>> $BLOCK_ID 到 <<< $BLOCK_ID 之间的内容即可。"
