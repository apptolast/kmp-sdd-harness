#!/usr/bin/env bash
# SDD phase state helper. State lives at <project>/.claude/.sdd-state.json
# Usage:
#   sdd-state.sh set-phase <spec|plan|design|test|implement|validate|done>
#   sdd-state.sh set-spec  <NNN-slug>
#   sdd-state.sh set-branch <branch>
#   sdd-state.sh set-project <name>
#   sdd-state.sh get
set -euo pipefail
STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
STATE="$STATE_DIR/.sdd-state.json"
mkdir -p "$STATE_DIR"
[ -f "$STATE" ] || echo '{}' > "$STATE"
python3 - "$STATE" "${1:-get}" "${2:-}" <<'PY'
import json, sys
path, cmd, val = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    s = json.load(open(path))
except Exception:
    s = {}
keymap = {"set-phase": "phase", "set-spec": "spec", "set-branch": "branch", "set-project": "project"}
if cmd in keymap:
    s[keymap[cmd]] = val
    json.dump(s, open(path, "w"), indent=2)
    print(f"SDD state: {keymap[cmd]} = {val}")
else:
    print(json.dumps(s, indent=2))
PY
