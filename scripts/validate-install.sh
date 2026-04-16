#!/usr/bin/env bash
# ClaudeThrottle 安装验证脚本
# 用法：bash validate-install.sh
#
# 检查 ClaudeThrottle 插件是否正确安装

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Source paths.sh 获取路径
# shellcheck source=../config/paths.sh
source "$REPO_DIR/config/paths.sh"

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SETTINGS_JSON="$HOME/.claude/settings.json"

# 计数器
PASS=0
FAIL=0

echo "ClaudeThrottle 安装验证"
echo "======================="
echo ""

# ──────────────────────────────────────────────────────────────
# 检查项 1: rules/base.md 存在
# ──────────────────────────────────────────────────────────────
echo -n "[1/5] 检查 rules/base.md ... "
if [[ -f "$RULES_DIR/base.md" ]]; then
    echo "✅"
    ((PASS++))
else
    echo "❌ 文件不存在: $RULES_DIR/base.md"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 检查项 2: rules/current.md 存在
# ──────────────────────────────────────────────────────────────
echo -n "[2/5] 检查 rules/current.md ... "
if [[ -f "$RULES_DIR/current.md" ]]; then
    echo "✅"
    ((PASS++))
else
    echo "❌ 文件不存在: $RULES_DIR/current.md"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 检查项 3: hooks 文件存在且可执行
# ──────────────────────────────────────────────────────────────
echo -n "[3/5] 检查 hooks (pre-tool-use.sh, stop.sh) ... "
PRE_TOOL_USE="$THROTTLE_DIR/hooks/pre-tool-use.sh"
STOP_SH="$THROTTLE_DIR/hooks/stop.sh"

if [[ -f "$PRE_TOOL_USE" && -x "$PRE_TOOL_USE" ]]; then
    PRE_TOOL_OK=1
else
    PRE_TOOL_OK=0
fi

if [[ -f "$STOP_SH" && -x "$STOP_SH" ]]; then
    STOP_OK=1
else
    STOP_OK=0
fi

if [[ $PRE_TOOL_OK -eq 1 && $STOP_OK -eq 1 ]]; then
    echo "✅"
    ((PASS++))
else
    echo "❌"
    [[ $PRE_TOOL_OK -eq 0 ]] && echo "   - pre-tool-use.sh 不存在或不可执行: $PRE_TOOL_USE"
    [[ $STOP_OK -eq 0 ]] && echo "   - stop.sh 不存在或不可执行: $STOP_SH"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 检查项 4: config/mode.txt 存在，值为 "on" 或 "off"
# ──────────────────────────────────────────────────────────────
echo -n "[4/5] 检查 config/mode.txt ... "
if [[ -f "$MODE_FILE" ]]; then
    MODE_VALUE=$(cat "$MODE_FILE" 2>/dev/null | tr -d ' \n')
    if [[ "$MODE_VALUE" == "on" || "$MODE_VALUE" == "off" ]]; then
        echo "✅ (值: $MODE_VALUE)"
        ((PASS++))
    else
        echo "❌ 值无效: '$MODE_VALUE' (应为 'on' 或 'off')"
        ((FAIL++))
    fi
else
    echo "❌ 文件不存在: $MODE_FILE"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 检查项 5a: ~/.claude/CLAUDE.md 包含 ClaudeThrottle 相关配置
# ──────────────────────────────────────────────────────────────
echo -n "[5a/5] 检查 ~/.claude/CLAUDE.md ... "
if [[ -f "$CLAUDE_MD" ]]; then
    if grep -q "ClaudeThrottle" "$CLAUDE_MD"; then
        echo "✅"
        ((PASS++))
    else
        echo "❌ 不包含 'ClaudeThrottle' 配置"
        ((FAIL++))
    fi
else
    echo "❌ 文件不存在: $CLAUDE_MD"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 检查项 5b: ~/.claude/settings.json 的 hooks 中注册了 hooks
# ──────────────────────────────────────────────────────────────
echo -n "[5b/5] 检查 ~/.claude/settings.json hooks ... "
if [[ -f "$SETTINGS_JSON" ]]; then
    # 检查是否包含 pre-tool-use.sh 和 stop.sh
    if grep -q "pre-tool-use.sh" "$SETTINGS_JSON" && grep -q "stop.sh" "$SETTINGS_JSON"; then
        echo "✅"
        ((PASS++))
    else
        echo "❌ hooks 未完全注册"
        grep -q "pre-tool-use.sh" "$SETTINGS_JSON" || echo "   - 缺失 pre-tool-use.sh"
        grep -q "stop.sh" "$SETTINGS_JSON" || echo "   - 缺失 stop.sh"
        ((FAIL++))
    fi
else
    echo "⚠️  $SETTINGS_JSON 不存在（可能未手动配置，或需要手动合并）"
    ((FAIL++))
fi

# ──────────────────────────────────────────────────────────────
# 汇总
# ──────────────────────────────────────────────────────────────
echo ""
echo "==============================="
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
    echo "✅ 验证通过: $PASS/$TOTAL 项"
    exit 0
else
    echo "❌ 验证失败: $PASS/$TOTAL 项通过，$FAIL 项失败"
    exit 1
fi
