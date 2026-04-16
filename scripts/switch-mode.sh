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
    # Set current.md to active state
    cat > "$RULES_DIR/current.md" << 'EOF'
# ClaudeThrottle — 状态：已启用

ClaudeThrottle 路由已激活。按 base.md 规则执行任务路由。

当前策略：L1/L2 → Haiku subagent | L2-debug/L3 → 主模型（用户选定的 Sonnet 或 Opus，自己执行）
EOF
    echo "on" > "$MODE_FILE"
    echo "off" > "$BOOST_FILE"
    echo "✅ ClaudeThrottle 已启用"
    echo "   L1/L2 → Haiku | L2-debug/L3 → 主模型（Sonnet 或 Opus）"
    echo "   预估节省：~79%（主模型为 Sonnet 时）；主模型越贵，绝对节省越多"
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
    echo "   所有任务回到主模型（用户 /model 选定）默认执行"
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

  broadcast)
    SUBCMD="${2:-}"
    case "$SUBCMD" in
      on)
        echo "on" > "$BROADCAST_FILE"
        echo "📢 会话摘要播报已开启"
        echo "   每次会话结束时将自动显示节省摘要"
        ;;
      off)
        echo "off" > "$BROADCAST_FILE"
        echo "🔇 会话摘要播报已关闭"
        echo "   摘要仍会写入日志，但不在对话中显示"
        ;;
      *)
        CURRENT_BC=$(cat "$BROADCAST_FILE" 2>/dev/null | tr -d ' \r\n' || echo "on")
        echo "📢 播报当前状态：$CURRENT_BC"
        echo "   用法: switch-mode.sh broadcast on|off"
        ;;
    esac
    echo "切换时间：$(date '+%Y-%m-%d %H:%M:%S')"
    ;;

  status)
    CURRENT=$(cat "$MODE_FILE" 2>/dev/null || echo "off")
    BOOST=$(cat "$BOOST_FILE" 2>/dev/null || echo "off")
    BROADCAST=$(cat "$BROADCAST_FILE" 2>/dev/null | tr -d ' \r\n' || echo "on")

    echo ""
    echo "━━━ ClaudeThrottle 状态 ━━━━━━━━━━━━━━━━━━━━"
    if [[ "$CURRENT" == "on" ]]; then
      echo "  路由：✅ 已启用"
      echo "  策略：L1/L2 → Haiku | L2-debug/L3 → 主模型（用户选定）"
    else
      echo "  路由：⏸️  已暂停"
    fi
    if [[ "$BOOST" == "on" ]]; then
      echo "  Boost：🚀 已激活（下一个 L3 → Opus）"
    else
      echo "  Boost：关闭"
    fi
    if [[ "$BROADCAST" == "on" ]]; then
      echo "  播报：📢 已开启（会话结束时显示摘要）"
    else
      echo "  播报：🔇 已关闭"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    ;;

  *)
    echo "❌ 无效命令: '$CMD'"
    echo "   用法: switch-mode.sh <on|off|boost|status|broadcast on|off>"
    exit 1
    ;;
esac
