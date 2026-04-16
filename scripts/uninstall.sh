#!/usr/bin/env bash
# ClaudeThrottle 卸载脚本
# 用法：bash uninstall.sh [--purge]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# Source paths.sh to read the single source-of-truth default install dir
# shellcheck source=../config/paths.sh
source "$REPO_DIR/config/paths.sh" 2>/dev/null \
    || { THROTTLE_DIR="${CLAUDE_THROTTLE_DIR:-$HOME/.claude/throttle}"; }
INSTALL_DIR="$THROTTLE_DIR"
COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

echo "ClaudeThrottle 卸载程序"
echo "========================"

# 检测 JSON 工具
_detect_json_tool() {
    if powershell.exe -Command "exit 0" &>/dev/null 2>&1; then echo "powershell"
    elif command -v python3 &>/dev/null && python3 -c "print(1)" &>/dev/null 2>&1; then echo "python3"
    else echo "none"; fi
}
JSON_TOOL=$(_detect_json_tool)

# 1. 删除安装目录
if [[ "$1" == "--purge" ]]; then
    echo "[1/4] 删除安装目录（含日志）..."
    rm -rf "$INSTALL_DIR"
else
    echo "[1/4] 删除安装目录（保留日志）..."
    if [[ -d "$INSTALL_DIR/logs" ]]; then
        TMP_LOGS=$(mktemp -d)
        cp -r "$INSTALL_DIR/logs" "$TMP_LOGS/"
    fi
    rm -rf "$INSTALL_DIR"
    if [[ -d "${TMP_LOGS:-}/logs" ]]; then
        mkdir -p "$INSTALL_DIR"
        mv "$TMP_LOGS/logs" "$INSTALL_DIR/logs"
        rm -rf "$TMP_LOGS"
        echo "   日志已保留在 $INSTALL_DIR/logs/"
        echo "   彻底删除：bash uninstall.sh --purge"
    fi
fi

# 2. 删除 /throttle 命令
echo "[2/4] 移除 /throttle 命令..."
if [[ -f "$COMMANDS_DIR/throttle.md" ]]; then
    rm "$COMMANDS_DIR/throttle.md"
    echo "   已删除"
else
    echo "   不存在，跳过"
fi

# 3. 从 CLAUDE.md 移除 ClaudeThrottle 片段（纯 bash，无需外部工具）
echo "[3/4] 从 CLAUDE.md 移除配置..."
if [[ -f "$CLAUDE_MD" ]] && grep -q "ClaudeThrottle" "$CLAUDE_MD"; then
    TMP=$(mktemp)
    # 删除 ClaudeThrottle 标题行、@throttle 引用行和其间的空行
    awk '
        /# ClaudeThrottle/ { skip=1; next }
        skip && /^@throttle/ { next }
        skip && /^[[:space:]]*$/ { next }
        skip { skip=0 }
        { print }
    ' "$CLAUDE_MD" > "$TMP"
    # 移除尾部空行，保留一个换行结尾
    awk 'NF{found=NR} {lines[NR]=$0} END{for(i=1;i<=found;i++) print lines[i]}' "$TMP" > "$CLAUDE_MD"
    rm -f "$TMP"
    echo "   已移除"
else
    echo "   未找到 ClaudeThrottle 配置，跳过"
fi

# 4. 从 settings.json 移除 hooks
echo "[4/4] 从 settings.json 移除 hooks..."
PS1_SRC="$HOME/.claude/throttle/scripts/merge-settings.ps1"
# 如果安装目录已删除，从 repo 找
if [[ ! -f "$PS1_SRC" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PS1_SRC="$SCRIPT_DIR/merge-settings.ps1"
fi

if [[ "$JSON_TOOL" == "powershell" && -f "$PS1_SRC" ]]; then
    PS1_WIN=$(cygpath -w "$PS1_SRC" 2>/dev/null || echo "$PS1_SRC")
    powershell.exe -ExecutionPolicy Bypass -File "$PS1_WIN" uninstall
elif [[ "$JSON_TOOL" == "python3" ]]; then
    PY_SRC="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/merge-settings.py"
    python3 "$PY_SRC" uninstall
else
    echo "   ⚠️  请手动删除 ~/.claude/settings.json 中含 'throttle' 的 hooks"
fi

echo ""
echo "✅ ClaudeThrottle 已卸载"
echo "   路由已停止，所有任务将回到默认 Sonnet 执行"
