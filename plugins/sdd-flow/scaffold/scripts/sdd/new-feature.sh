#!/usr/bin/env bash
# sdd-flow — gestionado por el plugin; /sdd-flow:init lo sobrescribe. No lo edites aquí.
#
# Scaffolds a feature directory from the templates: spec.md, plan.md and journal.md.
# tasks.md is created later by the tasks step, once the define gate is approved.
#
#   ./scripts/sdd/new-feature.sh [--bug] <slug> ["Nombre de la feature"]
#
# Example: ./scripts/sdd/new-feature.sh LJ-15-room-setup "Configurar Room"
# The slug is lower-cased, so Jira keys can be pasted verbatim. --bug scaffolds spec.md from the
# bug template: current, expected and unchanged behavior.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUG="no"
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --bug) BUG="yes" ;;
    -*)    echo "unknown option: $arg" >&2; exit 1 ;;
    *)     POSITIONAL+=("$arg") ;;
  esac
done

RAW="${POSITIONAL[0]:-}"
[ -n "$RAW" ] || { echo "usage: $0 [--bug] <slug> [\"Nombre de la feature\"]" >&2; exit 1; }

SLUG="$(printf '%s' "$RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
NAME="${POSITIONAL[1]:-$SLUG}"
DIR="$ROOT/specs/$SLUG"
TPL="$ROOT/specs/_templates"

[ -d "$TPL" ] || { echo "error: $TPL not found — run /sdd-flow:init" >&2; exit 1; }
[ -e "$DIR" ] && { echo "error: specs/$SLUG already exists" >&2; exit 1; }

TICKET="$(printf '%s' "$RAW" | grep -oE '[A-Za-z][A-Za-z0-9]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)"
[ -n "$TICKET" ] || TICKET="n/a"

# Escape the characters sed treats specially in a replacement.
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

mkdir -p "$DIR"
for f in spec plan journal; do
  src="$TPL/$f.md"
  if [ "$f" = "spec" ] && [ "$BUG" = "yes" ]; then
    src="$TPL/spec-bug.md"
  fi
  sed -e "s|<feature name>|$(esc "$NAME")|g" \
      -e "s|<feature-slug>|$SLUG|g" \
      -e "s|<slug>|$SLUG|g" \
      -e "s|<TICKET-ID o n/a>|$TICKET|g" \
      "$src" > "$DIR/$f.md"
done

kind="feature"
[ "$BUG" = "yes" ] && kind="bug"
echo "Creado specs/$SLUG/ (spec, plan, journal) para $kind $TICKET"
echo "Siguiente: /sdd-flow:define $SLUG"
