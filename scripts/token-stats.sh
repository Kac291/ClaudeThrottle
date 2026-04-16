#!/usr/bin/env bash
# ClaudeThrottle Token 统计脚本
# 从 Claude Code .jsonl 会话文件提取真实 token 消耗
#
# 用法：
#   token-stats.sh                      — 统计当前会话（$CLAUDE_SESSION_ID）
#   token-stats.sh <session_id>         — 统计指定会话
#   token-stats.sh <sid_a> <sid_b>      — 对比两个会话（A vs B）
#   token-stats.sh --list               — 列出最近 10 个会话

set -e

PROJECTS_DIR="$HOME/.claude/projects"
# shellcheck source=../config/paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/paths.sh" 2>/dev/null \
    || source "$HOME/.claude/throttle/config/paths.sh"
CONFIG_FILE="$MODE_FILE"

CURRENT_MODE=$(cat "$CONFIG_FILE" 2>/dev/null || echo "unknown")

# Haiku 定价（每 1M tokens）：input $0.80, output $4.00
# Sonnet 定价：input $3.00, output $15.00
# Opus 定价：input $15.00, output $75.00
# 缓存读取约为原价的 10%，缓存写入约为原价的 125%
HAIKU_IN=0.0000008
HAIKU_OUT=0.0000040
SONNET_IN=0.0000030
SONNET_OUT=0.0000150
OPUS_IN=0.0000150
OPUS_OUT=0.0000750
CACHE_READ_FACTOR=0.1     # cache read = 10% of input price
CACHE_WRITE_FACTOR=1.25   # cache write = 125% of input price

# 查找 jsonl 文件（在所有项目目录下搜索）
# Purpose: Locate the JSONL session file for a given session ID in the projects directory
# Parameters: $1 = session_id (required)
# Return: Absolute path to the JSONL file, or empty string if not found
find_jsonl() {
    local sid="$1"
    find "$PROJECTS_DIR" -name "${sid}.jsonl" 2>/dev/null | head -1
}

# 从 jsonl 提取 token 汇总
# Purpose: Extract and aggregate token usage metrics from a JSONL session file
# Parameters: $1 = path to JSONL file (required)
# Return: Four space-separated integers: input_tokens cache_creation_tokens cache_read_tokens output_tokens
extract_tokens() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "0 0 0 0" && return
    grep -o '"[a-z_]*_tokens":[0-9]*' "$file" 2>/dev/null | awk -F: '
    {
        gsub(/"/, "", $1)
        sum[$1] += $2
    }
    END {
        print (sum["input_tokens"]+0), \
              (sum["cache_creation_input_tokens"]+0), \
              (sum["cache_read_input_tokens"]+0), \
              (sum["output_tokens"]+0)
    }'
}

# 从 usage.log 获取 subagent 调用次数
# Purpose: Count subagent (Haiku, Sonnet, Opus) invocation records from usage log
# Parameters: $1 = session_id (optional; if empty, counts all records)
# Return: Three space-separated integers: haiku_count sonnet_count opus_count
get_subagent_counts() {
    local sid="$1"
    if [[ ! -f "$USAGE_LOG" ]]; then
        echo "0 0 0"
        return
    fi
    local filter=""
    [[ -n "$sid" ]] && filter="|${sid}|"
    local records
    if [[ -n "$filter" ]]; then
        records=$(grep "$filter" "$USAGE_LOG" 2>/dev/null || echo "")
    else
        records=$(cat "$USAGE_LOG" 2>/dev/null || echo "")
    fi
    local haiku sonnet opus
    haiku=$(echo "$records" | grep -c "|agent|haiku|" 2>/dev/null || echo 0); haiku=${haiku:-0}
    sonnet=$(echo "$records" | grep -c "|agent|sonnet|" 2>/dev/null || echo 0); sonnet=${sonnet:-0}
    opus=$(echo "$records" | grep -c "|agent|opus|" 2>/dev/null || echo 0); opus=${opus:-0}
    echo "$haiku $sonnet $opus"
}

# 计算 Sonnet 主 agent 成本
# Purpose: Calculate estimated cost for main agent (Sonnet) token usage with cache adjustments
# Parameters: $1 = input_tokens $2 = cache_creation_tokens $3 = cache_read_tokens $4 = output_tokens
# Return: Cost in USD as a decimal number (e.g., "0.045230")
calc_main_cost() {
    local input=$1 cache_create=$2 cache_read=$3 output=$4
    awk -v i="$input" -v cc="$cache_create" -v cr="$cache_read" -v o="$output" \
        -v si=$SONNET_IN -v so=$SONNET_OUT \
        -v crf=$CACHE_READ_FACTOR -v cwf=$CACHE_WRITE_FACTOR \
    'BEGIN {
        cost = i*si + cc*(si*cwf) + cr*(si*crf) + o*so
        printf "%.6f", cost
    }'
}

# 估算 subagent 成本（平均每次调用 2K in + 1K out）
# Purpose: Estimate total cost for subagent invocations using average token assumptions
# Parameters: $1 = haiku_count $2 = sonnet_count $3 = opus_count
# Return: Estimated cost in USD (assumes 2000 input + 1000 output tokens per invocation)
calc_subagent_cost() {
    local haiku=$1 sonnet=$2 opus=$3
    awk -v h="$haiku" -v s="$sonnet" -v op="$opus" \
        -v hi=$HAIKU_IN -v ho=$HAIKU_OUT \
        -v si=$SONNET_IN -v so=$SONNET_OUT \
        -v oi=$OPUS_IN -v oo=$OPUS_OUT \
    'BEGIN {
        avg_in=2000; avg_out=1000
        cost = h*(avg_in*hi + avg_out*ho) \
             + s*(avg_in*si + avg_out*so) \
             + op*(avg_in*oi + avg_out*oo)
        printf "%.6f", cost
    }'
}

# 打印单个会话报告
# Purpose: Generate and display a detailed token usage report for a single session
# Parameters: $1 = session_id $2 = report_label (optional; defaults to "会话")
# Return: Formatted report printed to stdout; exits if session file not found
print_session_report() {
    local sid="$1"
    local label="${2:-会话}"
    local file
    file=$(find_jsonl "$sid")

    if [[ -z "$file" ]]; then
        echo "  ⚠️  未找到会话文件: $sid"
        return
    fi

    read -r input cache_create cache_read output <<< "$(extract_tokens "$file")"
    read -r h_count s_count op_count <<< "$(get_subagent_counts "$sid")"

    local main_cost
    main_cost=$(calc_main_cost "$input" "$cache_create" "$cache_read" "$output")
    local sub_cost
    sub_cost=$(calc_subagent_cost "$h_count" "$s_count" "$op_count")
    local total_cost
    total_cost=$(awk -v m="$main_cost" -v s="$sub_cost" 'BEGIN{printf "%.6f", m+s}')

    local total_in=$((input + cache_create + cache_read))
    local cache_hit_pct=0
    [[ $total_in -gt 0 ]] && cache_hit_pct=$(awk -v cr="$cache_read" -v t="$total_in" \
        'BEGIN{printf "%.0f", cr/t*100}')

    echo ""
    echo "  [$label] session: ${sid:0:8}..."
    echo "  主 Agent（Sonnet）token："
    echo "    input_tokens              : $(printf '%8d' $input)"
    echo "    cache_creation_tokens     : $(printf '%8d' $cache_create)"
    echo "    cache_read_tokens         : $(printf '%8d' $cache_read)"
    echo "    output_tokens             : $(printf '%8d' $output)"
    echo "    cache hit                 : ${cache_hit_pct}%"
    echo "  Subagent 调用："
    echo "    Haiku  : ${h_count} 次"
    echo "    Sonnet : ${s_count} 次"
    echo "    Opus   : ${op_count} 次"
    echo "  估算成本："
    echo "    主 Agent : \$${main_cost}"
    echo "    Subagent : \$${sub_cost}  (按均值估算)"
    echo "    合计     : \$${total_cost}"
}

# 对比两个会话
# Purpose: Generate a side-by-side cost comparison table for two sessions
# Parameters: $1 = session_id_a (baseline) $2 = session_id_b (comparison)
# Return: Formatted comparison table with cost difference and savings percentage
print_comparison() {
    local sid_a="$1" sid_b="$2"
    local file_a file_b
    file_a=$(find_jsonl "$sid_a")
    file_b=$(find_jsonl "$sid_b")

    read -r ia cca cra oa <<< "$(extract_tokens "$file_a")"
    read -r ib ccb crb ob <<< "$(extract_tokens "$file_b")"
    read -r ha sa opa <<< "$(get_subagent_counts "$sid_a")"
    read -r hb sb opb <<< "$(get_subagent_counts "$sid_b")"

    local cost_a cost_b sub_a sub_b
    cost_a=$(calc_main_cost "$ia" "$cca" "$cra" "$oa")
    cost_b=$(calc_main_cost "$ib" "$ccb" "$crb" "$ob")
    sub_a=$(calc_subagent_cost "$ha" "$sa" "$opa")
    sub_b=$(calc_subagent_cost "$hb" "$sb" "$opb")
    local total_a total_b
    total_a=$(awk -v m="$cost_a" -v s="$sub_a" 'BEGIN{printf "%.6f", m+s}')
    total_b=$(awk -v m="$cost_b" -v s="$sub_b" 'BEGIN{printf "%.6f", m+s}')

    local saved
    saved=$(awk -v a="$total_a" -v b="$total_b" 'BEGIN{
        if (a > 0) printf "%.1f", (1 - b/a)*100
        else print "N/A"
    }')

    echo ""
    echo "  ┌─────────────────────────────────────────────────┐"
    echo "  │              A vs B 成本对比                    │"
    echo "  ├──────────────────────┬──────────────┬───────────┤"
    printf "  │ %-20s │ %12s │ %9s │\n" "指标" "A (基准)" "B (插件)"
    echo "  ├──────────────────────┼──────────────┼───────────┤"
    printf "  │ %-20s │ %12d │ %9d │\n" "input_tokens" "$ia" "$ib"
    printf "  │ %-20s │ %12d │ %9d │\n" "cache_create" "$cca" "$ccb"
    printf "  │ %-20s │ %12d │ %9d │\n" "cache_read" "$cra" "$crb"
    printf "  │ %-20s │ %12d │ %9d │\n" "output_tokens" "$oa" "$ob"
    printf "  │ %-20s │ %12s │ %9s │\n" "Haiku subagent" "${ha}次" "${hb}次"
    printf "  │ %-20s │ %12s │ %9s │\n" "Opus subagent" "${opa}次" "${opb}次"
    echo "  ├──────────────────────┼──────────────┼───────────┤"
    printf "  │ %-20s │ \$%11s │ \$%8s │\n" "总成本(估算)" "$total_a" "$total_b"
    echo "  ├──────────────────────┴──────────────┴───────────┤"
    printf "  │  节省: %s%%  (B 相对 A)%*s│\n" "$saved" $((25 - ${#saved})) ""
    echo "  └───────────────────────────────────────────────────┘"
}

# 列出最近会话
# Purpose: Display the 10 most recently modified session files with their project directories
# Parameters: None
# Return: Formatted list printed to stdout (session_id and project directory)
list_sessions() {
    echo ""
    echo "  最近 10 个会话（按修改时间排序）："
    echo ""
    if find /dev/null -printf "" 2>/dev/null; then
        # GNU find: supports -printf
        find "$PROJECTS_DIR" -name "*.jsonl" -printf "%T@ %f %h\n" 2>/dev/null | \
            sort -rn | head -10 | \
            awk '{gsub(".jsonl","",$2); printf "  %s  %s\n", substr($2,1,36), $3}'
    else
        # BSD/macOS find: use stat for modification time
        find "$PROJECTS_DIR" -name "*.jsonl" 2>/dev/null | \
            while read -r f; do
                mt=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null || echo 0)
                echo "$mt $f"
            done | sort -rn | head -10 | \
            while read -r _ f; do
                sid=$(basename "$f" .jsonl)
                dir=$(dirname "$f" | xargs basename)
                echo "  $sid  ($dir)"
            done
    fi
}

# ─── 主逻辑 ───────────────────────────────────────────────

echo ""
echo "━━━ ClaudeThrottle Token 统计 ━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "当前模式: $CURRENT_MODE"

case "${1:-}" in
    --list)
        list_sessions
        ;;
    "")
        # 无参数：使用环境变量中的当前会话
        SID="${CLAUDE_SESSION_ID:-}"
        if [[ -z "$SID" ]]; then
            echo "  ⚠️  未检测到 CLAUDE_SESSION_ID，请传入 session_id"
            echo "  用法: token-stats.sh <session_id>"
            echo "        token-stats.sh --list  （查看可用会话）"
            exit 1
        fi
        print_session_report "$SID" "当前会话"
        ;;
    *)
        if [[ -n "${2:-}" ]]; then
            # 两个参数：对比模式
            print_comparison "$1" "$2"
        else
            # 一个参数：单会话报告
            print_session_report "$1" "会话"
        fi
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Subagent 成本为估算值（按均值 2K in + 1K out 计）"
echo ""
