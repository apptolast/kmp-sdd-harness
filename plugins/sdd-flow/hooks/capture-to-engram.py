#!/usr/bin/env python3
"""PostToolUse hook (sdd-flow): capture failed builds and tests to engram (living memory).

Conservative, low-noise: fires only when a Gradle verification command FAILS — run directly or
through scripts/sdd/gradle-signal.sh. That is the "error + fix" trail /sdd-flow:promote distills,
without drowning engram in every tool call. Curated notes are written by the converge agent and by
/sdd-flow:promote.

The feature is identified by the git branch (feature/<JIRA-ID>-...), so there is no state file.
Never writes secrets: only the command and a bounded tail of the output. Best-effort: any error is a
silent no-op. Always exits 0.
"""
import json
import os
import shutil
import subprocess
import sys

VERIFY_WORDS = ("test", "Test", "check", "Check", "ktlint", "detekt", "compile", "Compile", "assemble", "link")


def project_dir(data):
    return os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()


def git_branch(cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=3,
        )
        return out.stdout.strip() or "?"
    except Exception:
        return "?"


def extract_output(resp):
    if isinstance(resp, dict):
        parts = [resp.get(k) for k in ("stdout", "stderr", "output", "content", "result")]
        code = resp.get("exit_code", resp.get("exitCode"))
        return "\n".join(p for p in parts if isinstance(p, str)), code
    return str(resp or ""), None


def failed(out, code):
    if code not in (0, None):
        return True
    if "gradle-signal: FAILED" in out or "BUILD FAILED" in out:
        return True
    return False


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    cmd = (data.get("tool_input") or {}).get("command") or ""
    if not ("gradlew" in cmd or "gradle-signal" in cmd):
        return
    if not any(w in cmd for w in VERIFY_WORDS):
        return

    resp = data.get("tool_response") or data.get("tool_result") or data.get("tool_output")
    out, code = extract_output(resp)
    if not failed(out, code) or not shutil.which("engram"):
        return

    cwd = project_dir(data)
    project = os.path.basename(cwd.rstrip("/")) or "unknown"
    branch = git_branch(cwd)

    tail = "\n".join(out.strip().splitlines()[-25:])[:1800]
    title = f"[auto] Fallo de build/test — {branch}"
    msg = f"Comando: {cmd[:300]}\nRama: {branch}\nSalida (cola):\n{tail}"

    try:
        subprocess.run(
            ["engram", "save", title, msg, "--project", project, "--scope", "project"],
            timeout=8, capture_output=True,
        )
    except Exception:
        pass


if __name__ == "__main__":
    main()
