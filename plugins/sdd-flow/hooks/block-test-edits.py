#!/usr/bin/env python3
"""PreToolUse hook (sdd-flow): TDD lock.

During the /implement phase, block any Edit/Write/MultiEdit targeting a test file.
Tests are written red in /test and are immutable in phase 1 (no test mutability).
Outside /implement, everything is allowed (tests are authored during /test).

Contract: read tool call JSON on stdin; emit {} to defer, or a permissionDecision=deny
JSON to block. Always exit 0.
"""
import sys
import os
import json


def load_state(cwd):
    for base in (os.environ.get("CLAUDE_PROJECT_DIR"), cwd, os.getcwd()):
        if not base:
            continue
        p = os.path.join(base, ".claude", ".sdd-state.json")
        if os.path.exists(p):
            try:
                with open(p) as f:
                    return json.load(f)
            except Exception:
                return None
    return None


TEST_DIRS = (
    "/commontest/", "/androidinstrumentedtest/", "/androidunittest/",
    "/iostest/", "/jstest/", "/wasmjstest/", "/desktoptest/",
    "/mobiletest/", "/webtest/", "/test/",
)


def is_test_path(path):
    if not path:
        return False
    p = path.replace("\\", "/")
    low = p.lower()
    if any(d in low for d in TEST_DIRS):
        return True
    base = p.rsplit("/", 1)[-1]
    return base.endswith("Test.kt") or base.endswith("Tests.kt")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("{}")
        return

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}
    cwd = tool_input.get("cwd") or data.get("cwd")

    state = load_state(cwd) or {}
    if state.get("phase") != "implement":
        print("{}")
        return
    if tool not in ("Edit", "Write", "MultiEdit"):
        print("{}")
        return

    path = tool_input.get("file_path") or tool_input.get("path")
    if is_test_path(path):
        reason = (
            "TDD lock (/implement): no se pueden modificar ficheros de test durante la fase de "
            "implementacion. Los tests se escribieron en rojo en /test y son inmutables en la fase 1. "
            "Si el spec realmente necesita otro test, cambia de fase con /test antes de tocarlos."
        )
        print(json.dumps({
            "hookSpecificOutput": {
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
        return

    print("{}")


if __name__ == "__main__":
    main()
