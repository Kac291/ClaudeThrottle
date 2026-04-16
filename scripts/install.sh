#!/usr/bin/env bash
# ClaudeThrottle 一键安装脚本
# 安装到用户全局 ~/.claude/throttle/
# 用法：bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# Source paths.sh to read the single source-of-truth default install dir
# shellcheck source=../config/paths.sh
source "$REPO_DIR/config/paths.sh"
INSTALL_DIR="$THROTTLE_DIR"
COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

echo "ClaudeThrottle 安装程序"
echo "========================"
echo "源目录  : $REPO_DIR"
echo "安装目录: $INSTALL_DIR"
echo ""

# 检测 JSON 合并工具（PowerShell 优先，回退 python3）
_detect_json_tool() {
    if powershell.exe -Command "exit 0" &>/dev/null 2>&1; then
        echo "powershell"
    elif command -v python3 &>/dev/null && python3 -c "print(1)" &>/dev/null 2>&1; then
        echo "python3"
    else
        echo "none"
    fi
}
JSON_TOOL=$(_detect_json_tool)
if [[ "$JSON_TOOL" == "none" ]]; then
    echo "⚠️  未找到 PowerShell 或 Python3，将跳过 settings.json 自动合并"
    echo "   安装完成后请手动添加 hooks（见 README.md）"
fi

# 1. 创建目录
echo "[1/5] 创建目录结构..."
mkdir -p "$INSTALL_DIR/rules" "$INSTALL_DIR/hooks" "$INSTALL_DIR/config" \
         "$INSTALL_DIR/scripts" "$INSTALL_DIR/logs" "$COMMANDS_DIR"

# 2. 复制规则文件
echo "[2/5] 复制规则文件..."
cp "$REPO_DIR/rules/base.md"     "$INSTALL_DIR/rules/base.md"
cp "$REPO_DIR/rules/base.en.md"  "$INSTALL_DIR/rules/base.en.md"
cp "$REPO_DIR/rules/paused.md"   "$INSTALL_DIR/rules/paused.md"
# 默认状态：启用
cp "$REPO_DIR/rules/current.md"  "$INSTALL_DIR/rules/current.md"

# 3. 复制配置 & 脚本
echo "[3/5] 复制配置和脚本..."
cp "$REPO_DIR/config/models.json"         "$INSTALL_DIR/config/models.json"
cp "$REPO_DIR/config/routing-table.json"  "$INSTALL_DIR/config/routing-table.json"
cp "$REPO_DIR/config/paths.sh"            "$INSTALL_DIR/config/paths.sh"
cp "$REPO_DIR/scripts/switch-mode.sh"      "$INSTALL_DIR/scripts/switch-mode.sh"
cp "$REPO_DIR/scripts/cost-report.sh"     "$INSTALL_DIR/scripts/cost-report.sh"
cp "$REPO_DIR/scripts/token-stats.sh"     "$INSTALL_DIR/scripts/token-stats.sh"
cp "$REPO_DIR/scripts/merge-settings.ps1" "$INSTALL_DIR/scripts/merge-settings.ps1"
cp "$REPO_DIR/scripts/merge-settings.py"  "$INSTALL_DIR/scripts/merge-settings.py"
chmod +x "$INSTALL_DIR/scripts/switch-mode.sh"
chmod +x "$INSTALL_DIR/scripts/cost-report.sh"
chmod +x "$INSTALL_DIR/scripts/token-stats.sh"

cp "$REPO_DIR/hooks/pre-tool-use.sh"  "$INSTALL_DIR/hooks/pre-tool-use.sh"
cp "$REPO_DIR/hooks/stop.sh"          "$INSTALL_DIR/hooks/stop.sh"
chmod +x "$INSTALL_DIR/hooks/pre-tool-use.sh"
chmod +x "$INSTALL_DIR/hooks/stop.sh"

# 初始化状态文件
echo "on"  > "$INSTALL_DIR/config/mode.txt"
echo "off" > "$INSTALL_DIR/config/boost.txt"
echo "on"  > "$INSTALL_DIR/config/broadcast.txt"

# 4. 安装 /throttle slash command
echo "[4/5] 安装 /throttle 命令..."
cp "$REPO_DIR/skills/throttle.md" "$COMMANDS_DIR/throttle.md"

# 5. 更新 ~/.claude/CLAUDE.md
echo "[5/5] 更新 ~/.claude/CLAUDE.md..."
SNIPPET="
# ClaudeThrottle 智能路由

@throttle/rules/base.md

@throttle/rules/current.md
"
if [[ -f "$CLAUDE_MD" ]]; then
    if grep -q "ClaudeThrottle" "$CLAUDE_MD"; then
        echo "   已包含 ClaudeThrottle，跳过"
    else
        printf '%s' "$SNIPPET" >> "$CLAUDE_MD"
        echo "   已追加到现有 CLAUDE.md"
    fi
else
    printf '%s' "$SNIPPET" > "$CLAUDE_MD"
    echo "   已创建 CLAUDE.md"
fi

# 6. 合并 settings.json hooks
echo "[6/6] 合并 hooks 到 settings.json..."
if [[ "$JSON_TOOL" == "powershell" ]]; then
    PS1_PATH=$(cygpath -w "$INSTALL_DIR/scripts/merge-settings.ps1" 2>/dev/null || echo "$INSTALL_DIR/scripts/merge-settings.ps1")
    powershell.exe -ExecutionPolicy Bypass -File "$PS1_PATH" install
elif [[ "$JSON_TOOL" == "python3" ]]; then
    python3 "$INSTALL_DIR/scripts/merge-settings.py" install
else
    echo "   ⚠️  跳过自动合并。请手动添加以下内容到 ~/.claude/settings.json 的 hooks 字段："
    cat << 'MANUAL_HOOKS'
    "PreToolUse": [{"matcher":"Agent","hooks":[{"type":"command","command":"bash ~/.claude/throttle/hooks/pre-tool-use.sh"}]}],
    "Stop": [{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/throttle/hooks/stop.sh"}]}]
MANUAL_HOOKS
fi

echo ""
echo "✅ ClaudeThrottle 安装完成！"
echo ""
echo "使用方法（在 Claude Code 对话中）："
echo "  /throttle status   — 查看路由状态"
echo "  /throttle on       — 启用路由（默认已启用）"
echo "  /throttle off      — 暂停路由"
echo "  /throttle boost    — 下一个 L3 任务走 Opus（一次性）"
echo ""
echo "默认策略：L1/L2 → Haiku | L2-debug/L3 → 主模型（用户 /model 选定） | 预估节省 ~79%"
echo ""
echo "卸载：bash $REPO_DIR/scripts/uninstall.sh"
