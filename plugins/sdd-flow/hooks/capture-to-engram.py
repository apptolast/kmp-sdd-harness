#!/usr/bin/env python3
"""PostToolUse hook (sdd-flow): capture raw learnings to engram (living memory).

Conservative, low-noise: only fires when a Gradle build/test command FAILS.
That is exactly the "errores + solucion" trail the SDD design wants, without
drowning engram in every tool call. Rich, curated notes are written by the
subagents via the engram MCP and distilled by /promote (D6).

Never writes secrets: it only stores the command and a bounded output tail.
Best-effort: any error -> silent no-op. Always exits 0.
"""
import sys
import os
import json
import shutil
import subprocess


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
                return {}
    return {}


def extract_output(resp):
    if isinstance(resp, dict):
        parts = []
        for k in ("stdout", "stderr", "output", "content", "result"):
            v = resp.get(k)
            if isinstance(v, str):
                parts.append(v)
        code = resp.get("exit_code", resp.get("exitCode"))
        return "\n".join(parts), code
    return str(resp or ""), None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    tool_input = data.get("tool_input", {}) or {}
    cmd = tool_input.get("command", "") or ""
    # only Gradle verification commands
    if "gradlew" not in cmd or not any(k in cmd for k in ("test", "Test", "check", "ktlint")):
        return

    resp = data.get("tool_response") or data.get("tool_result") or data.get("tool_output")
    out, code = extract_output(resp)
    failed = (code not in (0, None)) or ("BUILD FAILED" in out) or (
        "FAILED" in out and "BUILD SUCCESSFUL" not in out)
    if not failed:
        return

    if not shutil.which("engram"):
        return

    state = load_state(tool_input.get("cwd") or data.get("cwd"))
    spec = state.get("spec", "?")
    phase = state.get("phase", "?")
    project = state.get("project") or os.path.basename(os.environ.get("CLAUDE_PROJECT_DIR", "") or os.getcwd()) or "unknown"

    tail = "\n".join(out.strip().splitlines()[-18:])[:1400]
    title = f"[auto] Fallo build/test — spec {spec} (fase {phase})"
    msg = f"Comando: {cmd}\nFase: {phase} | Spec: {spec}\nSalida (cola):\n{tail}"

    try:
        subprocess.run(
            ["engram", "save", title, msg, "--project", project, "--scope", "project"],
            timeout=8, capture_output=True,
        )
    except Exception:
        pass


if __name__ == "__main__":
    main()
