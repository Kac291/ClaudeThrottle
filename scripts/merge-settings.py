#!/usr/bin/env python3
"""
ClaudeThrottle settings.json 合并工具
用法：python3 merge-settings.py install | uninstall
"""
import json
import os
import sys

SETTINGS_FILE = os.path.expanduser("~/.claude/settings.json")

HOOKS_TO_ADD = {
    "PreToolUse": {
        "matcher": "Agent",
        "hooks": [
            {
                "type": "command",
                "command": "bash ~/.claude/throttle/hooks/pre-tool-use.sh"
            }
        ]
    },
    "Stop": {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": "bash ~/.claude/throttle/hooks/stop.sh"
            }
        ]
    }
}

THROTTLE_MARKER = "throttle"


def load_settings():
    if os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_settings(settings):
    with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")


def is_throttle_hook(entry):
    for h in entry.get("hooks", []):
        if THROTTLE_MARKER in h.get("command", ""):
            return True
    return False


def install():
    settings = load_settings()
    if "hooks" not in settings:
        settings["hooks"] = {}

    changed = False
    for event, hook_entry in HOOKS_TO_ADD.items():
        if event not in settings["hooks"]:
            settings["hooks"][event] = []

        already = any(is_throttle_hook(e) for e in settings["hooks"][event])
        if not already:
            settings["hooks"][event].append(hook_entry)
            changed = True
            print(f"  添加 {event} hook")
        else:
            print(f"  {event} hook 已存在，跳过")

    if changed:
        save_settings(settings)
        print("settings.json 更新完成")
    else:
        print("settings.json 无需更改")


def uninstall():
    if not os.path.exists(SETTINGS_FILE):
        print("settings.json 不存在，跳过")
        return

    settings = load_settings()
    if "hooks" not in settings:
        print("无 hooks 配置，跳过")
        return

    changed = False
    for event in list(settings["hooks"].keys()):
        before = len(settings["hooks"][event])
        settings["hooks"][event] = [
            e for e in settings["hooks"][event]
            if not is_throttle_hook(e)
        ]
        after = len(settings["hooks"][event])
        if before != after:
            changed = True
            print(f"  移除 {event} throttle hook")
        # 清理空数组
        if not settings["hooks"][event]:
            del settings["hooks"][event]

    if changed:
        save_settings(settings)
        print("settings.json 更新完成")
    else:
        print("未找到 throttle hooks，无需更改")


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "install":
        install()
    elif action == "uninstall":
        uninstall()
    else:
        print(f"用法：python3 {sys.argv[0]} install | uninstall")
        sys.exit(1)
