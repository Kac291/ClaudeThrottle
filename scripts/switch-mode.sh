#!/usr/bin/env bash
# ClaudeThrottle 控制脚本
# 用法：switch-mode.sh <on|off|boost|status>

set -e

# shellcheck source=../config/paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/paths.sh" 2>/dev/null \
    || source "$HOME/.claude/throttle/config/paths.sh"

CMD="${1:-}"

case "$CMD" in
  on)
    cp "$RULES_DIR/base.md" "$RULES_DIR/base.md"  # no-op, base.md always present
    # Set current.md to active state
    cat > "$RULES_DIR/current.md" << 'EOF'
# ClaudeThrottle — 状态：已启用

ClaudeThrottle 路由已激活。按 base.md 规则执行任务路由。

当前策略：L1/L2 → Haiku subagent | L2-debug/L3 → Sonnet（自己执行）
EOF
    echo "on" > "$MODE_FILE"
    echo "off" > "$BOOST_FILE"
    echo "✅ ClaudeThrottle 已启用"
    echo "   L1/L2 → Haiku | L2-debug/L3 → Sonnet"
    echo "   预估节省：~79% vs 全 Sonnet"
    echo "切换时间：$(date '+%Y-%m-%d %H:%M:%S')"
    ;;

  off)
    cat > "$RULES_DIR/current.md" << 'EOF'
# ClaudeThrottle — 状态：已暂停

ClaudeThrottle 路由已暂停。忽略 base.md 中的路由规则，按默认方式执行所有任务。
EOF
    echo "off" > "$MODE_FILE"
    echo "off" > "$BOOST_FILE"
    echo "⏸️  ClaudeThrottle 已暂停"
    echo "   所有任务回到默认 Sonnet 执行"
    echo "切换时间：$(date '+%Y-%m-%d %H:%M:%S')"
    ;;

  boost)
    # Check if throttle is on
    CURRENT=$(cat "$MODE_FILE" 2>/dev/null || echo "off")
    if [[ "$CURRENT" != "on" ]]; then
      echo "⚠️  请先启用 ClaudeThrottle（/throttle on）再使用 boost"
      exit 1
    fi
    echo "on" > "$BOOST_FILE"
    echo "🚀 Boost 已激活"
    echo "   下一个 L3 任务将使用 Opus subagent"
    echo "   使用后自动关闭（一次性）"
    echo "切换时间：$(date '+%Y-%m-%d %H:%M:%S')"
    ;;

  status)
    CURRENT=$(cat "$MODE_FILE" 2>/dev/null || echo "off")
    BOOST=$(cat "$BOOST_FILE" 2>/dev/null || echo "off")

    echo ""
    echo "━━━ ClaudeThrottle 状态 ━━━━━━━━━━━━━━━━━━━━"
    if [[ "$CURRENT" == "on" ]]; then
      echo "  路由：✅ 已启用"
      echo "  策略：L1/L2 → Haiku | L2-debug/L3 → Sonnet"
    else
      echo "  路由：⏸️  已暂停"
    fi
    if [[ "$BOOST" == "on" ]]; then
      echo "  Boost：🚀 已激活（下一个 L3 → Opus）"
    else
      echo "  Boost：关闭"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    ;;

  *)
    echo "❌ 无效命令: '$CMD'"
    echo "   用法: switch-mode.sh <on|off|boost|status>"
    exit 1
    ;;
esac
