#!/usr/bin/env python3
"""PreToolUse hook (sdd-flow): device work needs the user's yes (golden rule 8).

Blocks Bash commands that start an emulator or simulator, install or drive the app, or run
instrumented tests, unless the command carries SDD_DEVICE_APPROVED=1 — which the agent adds only
after the user approved that specific run in chat.

It denies rather than asks so that the rule also holds in bypass-permissions mode
(--dangerously-skip-permissions), where an "ask" would not reach the user.

A device tool counts only where a command starts (start of the line, after a separator, inside
`-c "..."`, behind env assignments or wrappers), so a commit message or a grep that names it passes.
Gradle device tasks count anywhere in a Gradle invocation.

Contract: tool call JSON on stdin; prints {} to defer or a deny decision. Always exits 0.
"""
import json
import re
import sys

CMD_START = r"(?:^|[;&|({`\n]|\$\(|-c\s+[\"'])\s*"
WRAPPERS = r"(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|sudo|env|exec|nohup|time|command|xargs|timeout\s+[0-9.]+[smhd]?)\s+)*"
DEVICE_TOOL = (
    r"(?:[^\s;&|\"'\\]*/)?"
    r"(?:adb|emulator|avdmanager|ios-deploy"
    r"|xcrun\s+devicectl"
    r"|xcrun\s+simctl(?!\s+list)"
    r"|xcodebuild\b[^;&|\n]*\s(?:test|test-without-building)"
    r"|android\s+(?:emulator|install|run|screen|layout))"
    r"(?=[^\w-]|$)"
)
DEVICE_RE = re.compile(CMD_START + WRAPPERS + DEVICE_TOOL)

GRADLE_RE = re.compile(r"gradlew\b|(?:^|[\s;&|(])gradle\s")
GRADLE_DEVICE_TASK_RE = re.compile(
    r"(?:^|[\s:])(?:"
    r"\w*AndroidTest"  # connectedDebugAndroidTest, and Gradle Managed Devices (pixel6Api34DebugAndroidTest)
    r"|connectedCheck"
    r"|\w*[Dd]evices?Check"  # deviceCheck, allDevicesCheck
    r"|install[A-Z]\w*"
    r"|uninstall(?:All|[A-Z]\w*)"
    r")\b"
)

APPROVED_RE = re.compile(r"(?:^|[^\w])SDD_DEVICE_APPROVED=1(?:[^\w]|$)")

REASON = (
    "sdd-flow (regla de oro 8): comando de dispositivo, emulador/simulador o tests instrumentados. "
    "Pide al usuario aprobación para ESTA ejecución: el comando exacto, por qué no basta con el código, "
    "un test en commonTest o una @Preview, y cuánto tarda. Solo si dice que sí, repite el mismo comando "
    "con SDD_DEVICE_APPROVED=1 delante. Sin respuesta, no lo ejecutes: ponlo en 'No comprobado:'."
)


def is_device_command(cmd):
    if DEVICE_RE.search(cmd):
        return True
    return bool(GRADLE_RE.search(cmd) and GRADLE_DEVICE_TASK_RE.search(cmd))


def decide(data):
    if data.get("tool_name") != "Bash":
        return {}
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if not cmd or APPROVED_RE.search(cmd) or not is_device_command(cmd):
        return {}
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }
    }


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("{}")
        return
    try:
        print(json.dumps(decide(data)))
    except Exception:
        print("{}")


if __name__ == "__main__":
    main()
