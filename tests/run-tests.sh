#!/usr/bin/env bash
# tests/run-tests.sh —— 两个安装脚本的回归测试
#
# 用法: bash tests/run-tests.sh
# 依赖: nano、bash；可选 script（提供时才能做"nano 是否接受配置"的真机校验）
#
# 全程把 HOME 指向临时目录，绝不碰真实 ~/.nanorc。

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EMACS="$ROOT/install-emacs-keys.sh"
VIM="$ROOT/install-vim-keys.sh"

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t fkeys)
trap 'rm -rf "$TMP"' EXIT

export TERM="${TERM:-xterm}"
export HOME="$TMP/home"
mkdir -p "$HOME"

PASS=0
FAIL=0
FAILED_MSG=""

color() {
  if [ -t 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}
pass() { PASS=$((PASS + 1)); printf '  %s %s\n' "$(color 32 ok)" "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  FAILED_MSG="${FAILED_MSG}
  - $1"
  printf '  %s %s\n' "$(color 31 FAIL)" "$1"
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1（期望 [$3]，实际 [$2]）"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1（输出里找不到 [$3]）" ;;
  esac
}
assert_file() {
  if [ -f "$2" ]; then pass "$1"; else fail "$1（$2 不存在）"; fi
}

newdir() { local d="$TMP/$1"; mkdir -p "$d"; printf '%s' "$d"; }

have_script() {
  command -v script >/dev/null 2>&1 &&
    script --help 2>&1 | grep -q -- ' --command\| -c,'
}

# 让真正的 nano 加载这份配置，看它有没有报错
nano_accepts() {
  local rc="$1" out
  out=$(printf '\030' | timeout 8 script -qec "nano --rcfile=$rc /dev/null" /dev/null 2>&1)
  case "$out" in
    *错误*|*rror*) return 1 ;;
    *) return 0 ;;
  esac
}

count_bind() { local n; n=$(grep -c '^bind ' "$1" 2>/dev/null); echo "${n:-0}"; }
count_marker() { local n; n=$(grep -c "^# >>> $1" "$2" 2>/dev/null); echo "${n:-0}"; }

echo "nano: $(nano --version 2>/dev/null | head -1)"
echo "root: $ROOT"
echo

# ── 1. 语法与参数处理 ─────────────────────────────────────
echo "语法与参数处理"

for f in "$EMACS" "$VIM" "$ROOT/tests/run-tests.sh"; do
  if bash -n "$f" 2>/dev/null; then pass "语法正确: $(basename "$f")"; else fail "语法错误: $f"; fi
done

out=$("$EMACS" --help 2>&1)
assert_eq "--help 退出码为 0" "$?" "0"
assert_contains "--help 打印用法" "$out" "--target"

out=$("$VIM" --help 2>&1)
assert_contains "vim 版 --help 打印用法" "$out" "--dry-run"

"$EMACS" --target >/dev/null 2>&1
assert_eq "--target 缺值时报错退出" "$?" "2"

"$VIM" --target >/dev/null 2>&1
assert_eq "vim 版 --target 缺值时报错退出" "$?" "2"

"$EMACS" --bogus >/dev/null 2>&1
assert_eq "未知参数退出码为 2" "$?" "2"

d=$(newdir dirarg)
mkdir -p "$d/adir"
"$EMACS" --target "$d/adir" >/dev/null 2>&1
assert_eq "--target 指向目录时报错退出" "$?" "1"

mkdir -p "$TMP/emptybin"
PATH="$TMP/emptybin" /bin/bash "$EMACS" --target "$d/x" >/dev/null 2>&1
assert_eq "找不到 nano 时退出码为 1" "$?" "1"

# ── 2. emacs 版安装行为 ───────────────────────────────────
echo
echo "emacs 版"

d=$(newdir emacs1)
RC="$d/.nanorc"
out=$("$EMACS" --target "$RC" 2>&1)
assert_eq "首次安装退出码为 0" "$?" "0"
assert_file "首次安装创建配置文件" "$RC"
assert_eq "只有一个配置块" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "1"
n=$(count_bind "$RC")
if [ "$n" -ge 8 ]; then pass "装上的按键数 $n >= 8"; else fail "按键数只有 $n"; fi
assert_contains "报告成功条数" "$out" "成功"

"$EMACS" --target "$RC" >/dev/null 2>&1
assert_eq "重复安装仍是单块" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "1"
assert_eq "重复安装按键数不变" "$(count_bind "$RC")" "$n"

i=0
while [ "$i" -lt 3 ]; do "$EMACS" --target "$RC" >/dev/null 2>&1; i=$((i + 1)); done
assert_eq "连续安装 5 次仍是单块" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "1"

ls "$RC".bak.* >/dev/null 2>&1
assert_eq "生成过备份文件" "$?" "0"

# 保留用户原有内容
d=$(newdir emacs2)
RC="$d/.nanorc"
printf 'set mouse\n# 我自己的设置\n' > "$RC"
"$EMACS" --target "$RC" >/dev/null 2>&1
if grep -q '^set mouse$' "$RC"; then pass "保留用户原有设置"; else fail "用户原有设置被删"; fi
if grep -q '^# 我自己的设置$' "$RC"; then pass "保留用户原有注释"; else fail "用户原有注释被删"; fi
assert_eq "用户内容 + 一个块" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "1"

# dry-run 不落盘
d=$(newdir dry)
out=$("$EMACS" --target "$d/none" --dry-run 2>&1)
assert_eq "dry-run 不创建文件" "$([ -f "$d/none" ] && echo yes || echo no)" "no"
assert_contains "dry-run 打印配置块" "$out" ">>> emacs-nano"

# 默认目标走 $HOME
H2="$TMP/home2"
mkdir -p "$H2"
HOME="$H2" "$EMACS" >/dev/null 2>&1
assert_file "不带参数时写入 \$HOME/.nanorc" "$H2/.nanorc"

# ── 3. vim 版安装行为 ────────────────────────────────────
echo
echo "vim 版"

d=$(newdir vim1)
RC="$d/.nanorc"
"$VIM" --target "$RC" >/dev/null 2>&1
assert_eq "首次安装退出码为 0" "$?" "0"
assert_eq "只有一个 vim 块" "$(count_marker 'vim-nano 自动适配块' "$RC")" "1"
n=$(count_bind "$RC")
if [ "$n" -ge 18 ]; then pass "装上的按键数 $n >= 18"; else fail "按键数只有 $n"; fi

# ── 4. 两种风格互斥 ──────────────────────────────────────
echo
echo "风格切换"

d=$(newdir switch)
RC="$d/.nanorc"
"$EMACS" --target "$RC" >/dev/null 2>&1
"$VIM" --target "$RC" >/dev/null 2>&1
assert_eq "装 vim 后 emacs 块被清除" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "0"
assert_eq "装 vim 后只剩 vim 块" "$(count_marker 'vim-nano 自动适配块' "$RC")" "1"

"$EMACS" --target "$RC" >/dev/null 2>&1
assert_eq "装回 emacs 后 vim 块被清除" "$(count_marker 'vim-nano 自动适配块' "$RC")" "0"
assert_eq "装回 emacs 后只剩 emacs 块" "$(count_marker 'emacs-nano 自动适配块' "$RC")" "1"

# ── 5. 降级分支（没有 script 时的行为）──────────────────
echo
echo "降级分支"

d=$(newdir degrade)
out=$(FKEYS_NO_SELFCHECK=1 "$EMACS" --target "$d/e.rc" 2>&1)
assert_eq "emacs 降级模式退出码为 0" "$?" "0"
assert_contains "emacs 降级模式给出提示" "$out" "跳过逐条自检"
assert_eq "emacs 降级模式仍写入全部按键" "$(count_bind "$d/e.rc")" "11"

out=$(FKEYS_NO_SELFCHECK=1 "$VIM" --target "$d/v.rc" 2>&1)
assert_eq "vim 降级模式退出码为 0" "$?" "0"
assert_contains "vim 降级模式给出提示" "$out" "跳过逐条自检"
assert_eq "vim 降级模式仍写入全部按键" "$(count_bind "$d/v.rc")" "26"

# ── 6. 独立运行（不依赖仓库里其它文件）──────────────────
echo
echo "独立性"

d=$(newdir solo)
cp "$EMACS" "$d/only.sh"
( cd "$d" && ./only.sh --target "$d/o.rc" >/dev/null 2>&1 )
if [ -f "$d/o.rc" ] && [ "$(count_bind "$d/o.rc")" -ge 8 ]; then
  pass "emacs 脚本单独拷出也能跑"
else
  fail "emacs 脚本单独拷出后失败"
fi

d=$(newdir solo2)
cp "$VIM" "$d/only.sh"
( cd "$d" && ./only.sh --target "$d/o.rc" >/dev/null 2>&1 )
if [ -f "$d/o.rc" ] && [ "$(count_bind "$d/o.rc")" -ge 18 ]; then
  pass "vim 脚本单独拷出也能跑"
else
  fail "vim 脚本单独拷出后失败"
fi

# ── 7. 生成的配置真的能被 nano 加载 ──────────────────────
echo
echo "配置有效性"

if have_script; then
  for style in emacs vim; do
    d=$(newdir "valid-$style")
    RC="$d/.nanorc"
    if [ "$style" = emacs ]; then "$EMACS" --target "$RC" >/dev/null 2>&1; else "$VIM" --target "$RC" >/dev/null 2>&1; fi
    if nano_accepts "$RC"; then pass "$style 版生成的配置被 nano 接受"; else fail "$style 版生成的配置 nano 报错"; fi
  done

  for f in "$ROOT/emacs.nanorc" "$ROOT/vim.nanorc"; do
    if nano_accepts "$f"; then pass "$(basename "$f") 静态文件被 nano 接受"; else fail "$(basename "$f") 静态文件 nano 报错"; fi
  done
else
  echo "  skip 没有可用的 script 命令，跳过真机加载校验"
fi

# ── 汇总 ─────────────────────────────────────────────────
echo
echo "----------------------------------------"
printf '通过 %s，失败 %s\n' "$(color 32 "$PASS")" "$(color 31 "$FAIL")"
if [ "$FAIL" -gt 0 ]; then
  printf '失败项:%s\n' "$FAILED_MSG"
  exit 1
fi
exit 0
