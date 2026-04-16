控制 ClaudeThrottle 智能路由。

用法：/throttle <command>
有效命令：status | on | off | boost | broadcast on | broadcast off

执行步骤：
1. 解析 $ARGUMENTS 获取命令
2. 如果 $ARGUMENTS 是 "status"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh status，然后报告状态
3. 如果 $ARGUMENTS 是 "boost"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh boost，然后报告 Boost 已激活
4. 如果 $ARGUMENTS 是 "on" 或 "off"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh $ARGUMENTS，然后报告切换结果
5. 如果 $ARGUMENTS 是 "broadcast on"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh broadcast on，然后报告播报已开启
6. 如果 $ARGUMENTS 是 "broadcast off"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh broadcast off，然后报告播报已关闭
7. 如果 $ARGUMENTS 为空或无效，显示用法说明

命令说明：
- status：查看当前路由状态、Boost 状态和播报状态
- on：启用路由（L1/L2 → Haiku，L2-debug/L3 → Sonnet，节省 ~79%）
- off：暂停路由（回到全 Sonnet 默认行为）
- boost：激活 Boost（下一个 L3 任务走 Opus，一次性）
- broadcast on：开启会话结束时的节省摘要播报（默认开启）
- broadcast off：关闭播报（摘要仍写入日志，但不在对话中显示）
