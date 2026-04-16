控制 ClaudeThrottle 智能路由。

用法：/throttle <command>
有效命令：status | on | off | boost

执行步骤：
1. 解析 $ARGUMENTS 获取命令
2. 如果 $ARGUMENTS 是 "status"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh status，然后报告状态
3. 如果 $ARGUMENTS 是 "boost"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh boost，然后报告 Boost 已激活
4. 如果 $ARGUMENTS 是 "on" 或 "off"，使用 Bash 工具执行：bash ~/.claude/throttle/scripts/switch-mode.sh $ARGUMENTS，然后报告切换结果
5. 如果 $ARGUMENTS 为空或无效，显示用法说明

命令说明：
- status：查看当前路由状态和 Boost 状态
- on：启用路由（L1/L2 → Haiku，L2-debug/L3 → Sonnet，节省 ~79%）
- off：暂停路由（回到全 Sonnet 默认行为）
- boost：激活 Boost（下一个 L3 任务走 Opus，一次性）
