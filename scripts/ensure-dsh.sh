#!/bin/bash
# ensure-dsh.sh — checks for DeepSeek Harness (dsh) and installs it if missing.
set -euo pipefail

echo "==> 检查 DeepSeek Harness (dsh) 运行环境..."

DSH_BIN=""
if command -v dsh >/dev/null 2>&1; then
    DSH_BIN="$(command -v dsh)"
else
    # Scan common installation directories
    for dir in "$HOME/.local/bin" "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.fnm/current/bin" "$HOME/.volta/bin" "$HOME/.pnpm-global/bin" "$HOME/.bun/bin" "$HOME/.yarn/bin"; do
        if [ -x "$dir/dsh" ]; then
            DSH_BIN="$dir/dsh"
            break
        fi
    done
    # Scan NVM directories
    if [ -z "$DSH_BIN" ] && [ -d "$HOME/.nvm/versions/node" ]; then
        for nvm_bin in "$HOME"/.nvm/versions/node/*/bin/dsh; do
            if [ -x "$nvm_bin" ]; then
                DSH_BIN="$nvm_bin"
                break
            fi
        done
    fi
fi

if [ -n "$DSH_BIN" ]; then
    echo "[✓] 检测到 DeepSeek Harness 已安装: $DSH_BIN"
    exit 0
fi

echo "[!] 本机尚未安装 DeepSeek Harness (dsh)，正在尝试自动安装..."

# Check available package managers
PKG_MGR=""
if command -v npm >/dev/null 2>&1; then
    PKG_MGR="npm install -g @deepseek-ai/dsh"
elif command -v pnpm >/dev/null 2>&1; then
    PKG_MGR="pnpm add -g @deepseek-ai/dsh"
elif command -v yarn >/dev/null 2>&1; then
    PKG_MGR="yarn global add @deepseek-ai/dsh"
elif command -v bun >/dev/null 2>&1; then
    PKG_MGR="bun install -g @deepseek-ai/dsh"
fi

if [ -n "$PKG_MGR" ]; then
    echo "正在执行: $PKG_MGR ..."
    if $PKG_MGR; then
        echo "[✓] DeepSeek Harness (@deepseek-ai/dsh) 自动安装成功！"
        exit 0
    else
        echo "全局安装遇到权限限制，尝试安装到用户主目录 (~/.local)..."
        mkdir -p "$HOME/.local"
        if npm install -g --prefix "$HOME/.local" @deepseek-ai/dsh; then
            echo "[✓] 已成功安装至 ~/.local/bin/dsh"
            exit 0
        else
            echo "[!] 自动安装受阻，请在终端手动运行：npm install -g @deepseek-ai/dsh"
        fi
    fi
else
    echo "[!] 未检测到 Node.js / npm 环境。"
    OS="$(uname -s)"
    if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
        echo "检测到 Homebrew，正在尝试通过 brew 安装 Node.js..."
        if brew install node; then
            echo "Node.js 安装成功，继续安装 DeepSeek Harness..."
            npm install -g @deepseek-ai/dsh && exit 0
        fi
    fi
    echo "[!] 请先访问 https://nodejs.org 安装 Node.js (推荐 v18+)，然后执行: npm install -g @deepseek-ai/dsh"
fi
