#!/usr/bin/env bash
# ClaudeThrottle 路径统一配置
# 所有 hook 和脚本通过 source 此文件获取路径，避免硬编码
#
# 修改默认安装目录：设置环境变量 CLAUDE_THROTTLE_DIR 即可，
# 或在 install.sh 之前 export CLAUDE_THROTTLE_DIR=/your/path

# ── 唯一的默认路径常量 ──────────────────────────────────────
THROTTLE_BASE_DEFAULT="$HOME/.claude/throttle"
THROTTLE_DIR="${CLAUDE_THROTTLE_DIR:-$THROTTLE_BASE_DEFAULT}"
LOG_DIR="$THROTTLE_DIR/logs"
RULES_DIR="$THROTTLE_DIR/rules"
CONFIG_DIR="$THROTTLE_DIR/config"
SCRIPTS_DIR="$THROTTLE_DIR/scripts"

USAGE_LOG="$LOG_DIR/usage.log"
TOKEN_STATS_LOG="$LOG_DIR/token-stats.log"
STOP_DEBUG_LOG="$LOG_DIR/stop-debug.log"
MODE_FILE="$CONFIG_DIR/mode.txt"
BOOST_FILE="$CONFIG_DIR/boost.txt"
