# nano-change

[![ci](https://github.com/inmomi/nano-change/actions/workflows/ci.yml/badge.svg)](https://github.com/inmomi/nano-change/actions/workflows/ci.yml)

把 nano 的键位改成 **Emacs** 或 **vim** 的手感——而且不用管你机器上装的是哪个版本的 nano。

nano 是各大发行版默认的编辑器，但它只提供一套固定键位。这个仓库给两套配置：

| 文件 | 作用 |
|---|---|
| `install-emacs-keys.sh` | 装上后：`^S` 存、`^Y` 粘、`M-w` 复制、`^Space` 选区、`M-%` 替换、`M-g` 跳行… |
| `install-vim-keys.sh` | 装上后：`Alt+hjkl` 移动、`M-d` 切行、`M-y` 复制行、`M-p` 粘贴、`M-/` 搜索… |
| `emacs.nanorc` / `vim.nanorc` | 同上的静态版本，适合手工复制粘贴 |
| `emacs-to-nano-cheatsheet.md` | 键位对照 + 版本差异说明 |

## 快速开始

```bash
git clone https://github.com/inmomi/nano-change.git
cd nano-change
./install-emacs-keys.sh --dry-run    # 先看会写入什么
./install-emacs-keys.sh              # 正式写入 ~/.nanorc
```

其他用法：

```bash
./install-emacs-keys.sh --target /tmp/test.nanorc   # 写到别处
./install-vim-keys.sh                               # 切到 vim 风格（会自动清掉 emacs 的块）
```

配置会以 `>>> emacs-nano` / `<<< emacs-nano` 为界写进 `~/.nanorc`，你原有的内容原样保留，改动前自动备份成 `~/.nanorc.bak.时间戳`。想撤销，删掉那两行标记之间的内容即可。

## 为什么需要"自动适配"

同一份 nanorc 换个版本就可能部分失效，因为：

- **函数名改过名**：`uncut` → `paste`、`prevpage` → `pageup`、`copytext` → `copy`
- **默认键位变过**：nano 8.x 里 `^F`/`^B` 是前/后搜索，老版本里是左右移动一个字符
- **新功能是后加的**：`undo`、`copy`、`findbracket` 在老版本上根本不存在
- **更老的版本连 `bind` 都没有**（1.x / pico 时代）

所以脚本不猜版本，而是**把每一条配置拿本机的 nano 真跑一遍**：报错就退到候选函数名，全都不行就跳过并告诉你。缺 `script` 命令时自动降级为"按常见名字全写"，哪些行无效 nano 启动时会自己提示，不影响使用。

实测覆盖：nano 2.9.8 / 5.9 / 6.2 / 7.2 / 8.7.1（见 CI）。

## 测试

```bash
bash tests/run-tests.sh
```

覆盖 45 项断言：参数处理、幂等（重复安装不叠加）、两种风格互斥、保留用户原有配置、备份、dry-run、单独拷贝可运行、降级分支、以及"生成的配置真能被 nano 加载"。全程把 `HOME` 指向临时目录，不会碰真实配置。

CI 见 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)：shellcheck + 多发行版矩阵 + 源码编译旧版 nano。

## 先说清做不到的

nano 不是可编程编辑器，有些事无论如何都做不到，别指望百分之百还原：

- **不能绑定裸字母键**。nanorc 只接受 `^X`、`M-X`、`Sh-M-X`、`F1`–`F24`、`Ins`、`Del`，字母必须留给打字。所以 vim 的 `hjkl` 只能用 `Alt+hjkl` 近似。
- **没有前缀键**。`C-x C-s`、`C-x C-c` 这类双键序列无法模拟，Emacs 用户请记 `^S` / `^X`。
- **没有模态，没有 `:` 命令行**。`3dd`、`ciw`、`%s/a/b/g` 都不存在。真要 vim 键位，请直接装 vim / neovim。

这套配置的价值在于：你日常顺手打开 nano 改个配置文件时，手不会乱按到奇怪的地方。

## 许可

MIT
