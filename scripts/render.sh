#!/usr/bin/env bash
#
# Generates the sdd-flow plugin's subagents and slash commands from the single source in src/.
#
#   ./scripts/render.sh [--check]
#
# --check renders into a temp dir and fails if the committed output is stale. CI runs it, so an
# edit made in src/ cannot be forgotten in the plugin, and a hand edit in the plugin is caught.
#
# Source format — src/agents/<name>.md:
#
#   ---
#   name: define
#   description: One sentence; Claude uses it to decide when to load the agent.
#   tools: Read, Grep, Glob, Write, Edit
#   model: inherit
#   color: blue
#   argument-hint: <ticket-o-slug>
#   ---
#   <agent body>
#   <!-- @command -->
#   <slash-command body; $ARGUMENTS is the ticket or slug>
#
# A line that is exactly `<!-- @include <name> -->` is replaced by src/partials/<name>.md, so blocks
# shared by several agents are written once.
#
# src/commands/<name>.md are hand-written slash commands with no subagent; they are copied verbatim
# (includes expanded).
#
# Outputs (fully generated, rebuilt from scratch):
#   plugins/sdd-flow/agents/<name>.md
#   plugins/sdd-flow/commands/<name>.md

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC_AGENTS="$HERE/src/agents"
SRC_COMMANDS="$HERE/src/commands"
SRC_PARTIALS="$HERE/src/partials"
PLUGIN_REL="plugins/sdd-flow"
CHECK="no"
[ "${1:-}" = "--check" ] && CHECK="yes"

OUT_ROOT="$HERE/$PLUGIN_REL"
if [ "$CHECK" = "yes" ]; then
  OUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sddrender.XXXXXX")"
  trap 'rm -rf "$OUT_ROOT"' EXIT
fi

GENERATED_TREES="agents commands"
for t in $GENERATED_TREES; do
  rm -rf "${OUT_ROOT:?}/$t"
  mkdir -p "$OUT_ROOT/$t"
done

GENERATED_NOTE="<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->"

fm_get() {
  # $1 = file, $2 = key. Prints the value from the YAML frontmatter block.
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---"  { exit }
    inside {
      idx = index($0, ":")
      if (idx > 0) {
        k = substr($0, 1, idx - 1)
        v = substr($0, idx + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", k)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (k == key) { print v; exit }
      }
    }' "$1"
}

frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; print; next }
       inside { print; if ($0 == "---") exit }' "$1"
}

body_after_frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---"  { inside = 0; started = 1; next }
       started { print }' "$1"
}

expand_includes() {
  local line name
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '<!-- @include '*' -->')
        name="${line#<!-- @include }"
        name="${name% -->}"
        if [ ! -f "$SRC_PARTIALS/$name.md" ]; then
          echo "error: missing partial src/partials/$name.md" >&2
          exit 1
        fi
        cat "$SRC_PARTIALS/$name.md"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

agent_body() {
  body_after_frontmatter "$1" | awk '/^<!-- @command -->$/ { exit } { print }' | expand_includes
}

command_body() {
  body_after_frontmatter "$1" | awk 'found { print } /^<!-- @command -->$/ { found = 1 }' | expand_includes
}

trim_blanks() {
  awk 'NF { hold[++n] = $0; last = n; next } n { hold[++n] = $0 }
       END { for (i = 1; i <= last; i++) print hold[i] }'
}

n_agents=0
for src in "$SRC_AGENTS"/*.md; do
  [ -f "$src" ] || continue
  name="$(fm_get "$src" name)"
  desc="$(fm_get "$src" description)"
  tools="$(fm_get "$src" tools)"
  model="$(fm_get "$src" model)"
  color="$(fm_get "$src" color)"
  hint="$(fm_get "$src" argument-hint)"
  ctools="$(fm_get "$src" command-tools)"

  [ -n "$name" ] || { echo "error: $src has no 'name'" >&2; exit 1; }
  [ -n "$desc" ] || { echo "error: $src has no 'description'" >&2; exit 1; }

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$desc"
    [ -n "$tools" ] && printf 'tools: %s\n' "$tools"
    [ -n "$model" ] && printf 'model: %s\n' "$model"
    [ -n "$color" ] && printf 'color: %s\n' "$color"
    printf -- '---\n'
    printf '%s\n\n' "$GENERATED_NOTE"
    agent_body "$src" | trim_blanks
  } > "$OUT_ROOT/agents/$name.md"

  {
    printf -- '---\n'
    printf 'description: %s\n' "$desc"
    [ -n "$hint" ] && printf 'argument-hint: %s\n' "$hint"
    [ -n "$ctools" ] && printf 'allowed-tools: %s\n' "$ctools"
    printf -- '---\n'
    printf '%s\n\n' "$GENERATED_NOTE"
    cb="$(command_body "$src" | trim_blanks)"
    if [ -n "$cb" ]; then
      printf '%s\n' "$cb"
    else
      # shellcheck disable=SC2016  # $ARGUMENTS is a literal placeholder for the slash command
      printf 'Usa el subagente `%s` para `$ARGUMENTS`.\n' "$name"
    fi
  } > "$OUT_ROOT/commands/$name.md"

  n_agents=$((n_agents + 1))
done

n_commands=0
for src in "$SRC_COMMANDS"/*.md; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .md)"
  {
    frontmatter "$src"
    printf '%s\n\n' "$GENERATED_NOTE"
    body_after_frontmatter "$src" | expand_includes | trim_blanks
  } > "$OUT_ROOT/commands/$name.md"
  n_commands=$((n_commands + 1))
done

if [ "$CHECK" = "yes" ]; then
  stale=0
  for t in $GENERATED_TREES; do
    diff -r -q "$OUT_ROOT/$t" "$HERE/$PLUGIN_REL/$t" >/dev/null 2>&1 || stale=1
  done
  if [ "$stale" -eq 0 ]; then
    echo "render: $PLUGIN_REL is up to date with src/ ($n_agents agents, $n_commands extra commands)"
  else
    echo "render: $PLUGIN_REL is STALE — run ./scripts/render.sh and commit" >&2
    for t in $GENERATED_TREES; do
      diff -r "$HERE/$PLUGIN_REL/$t" "$OUT_ROOT/$t" 2>&1 | sed "s|^|  |" || true
    done
    exit 1
  fi
else
  echo "render: wrote $n_agents agent(s) + command(s) and $n_commands extra command(s)"
fi
