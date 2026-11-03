#!/usr/bin/env bash
#
# Installs or updates in a consumer repository what the sdd-flow plugin needs. Idempotent.
#
#   sdd-init.sh <repo> [--check]
#
# Harness-owned files (scripts/sdd/*, .claude/sdd/reglas.md, docs/sdd/README.md, specs/README.md) are
# always brought up to date. Project-owned files (spec templates, ADR template, PR template) are created
# only when missing. CLAUDE.md gets the sdd-flow section appended once. --check reports, writes nothing.

set -euo pipefail

PLUGIN="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$PLUGIN/scaffold"
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN/.claude-plugin/plugin.json" | head -1)"

TARGET=""
CHECK="no"
for arg in "$@"; do
  case "$arg" in
    --check) CHECK="yes" ;;
    -*) echo "error: unknown option $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: $0 <repo> [--check]" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "error: $TARGET is not a directory" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

HARNESS_OWNED="scripts/sdd/gradle-signal.sh scripts/sdd/spec-lint.sh scripts/sdd/new-feature.sh scripts/sdd/new-adr.sh .claude/sdd/reglas.md docs/sdd/README.md specs/README.md"
PROJECT_OWNED="specs/_templates/spec.md specs/_templates/spec-bug.md specs/_templates/plan.md specs/_templates/tasks.md specs/_templates/journal.md docs/decisions/_template.md .github/pull_request_template.md"

created=(); updated=(); same=(); kept=(); notes=()

place() {
  # $1 = relative path. Copies the scaffold file into the target.
  local rel="$1"
  [ "$CHECK" = "yes" ] && return 0
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp "$SCAFFOLD/$rel" "$TARGET/$rel"
  case "$rel" in *.sh) chmod +x "$TARGET/$rel" ;; esac
}

for rel in $HARNESS_OWNED; do
  if [ ! -f "$TARGET/$rel" ]; then
    place "$rel"; created+=("$rel")
  elif cmp -s "$SCAFFOLD/$rel" "$TARGET/$rel"; then
    same+=("$rel")
  else
    place "$rel"; updated+=("$rel")
  fi
done

for rel in $PROJECT_OWNED; do
  if [ ! -f "$TARGET/$rel" ]; then
    place "$rel"; created+=("$rel")
  elif cmp -s "$SCAFFOLD/$rel" "$TARGET/$rel"; then
    same+=("$rel")
  else
    kept+=("$rel")
  fi
done

# --- CLAUDE.md
CLAUDE="$TARGET/CLAUDE.md"
if [ ! -f "$CLAUDE" ]; then
  if [ "$CHECK" = "no" ]; then
    { printf '# CLAUDE.md\n\n'; cat "$SCAFFOLD/claude-md-section.md"; } > "$CLAUDE"
  fi
  created+=("CLAUDE.md")
elif grep -q '@\.claude/sdd/reglas\.md' "$CLAUDE"; then
  same+=("CLAUDE.md (sección sdd-flow)")
elif grep -q '^## Guardarraíles KMP' "$CLAUDE"; then
  # A 0.1 install: keep the project's own guardrails and add only the import of the rules.
  if [ "$CHECK" = "no" ]; then
    { printf '\n'; awk '/^## Guardarraíles KMP/ { exit } { print }' "$SCAFFOLD/claude-md-section.md"; } >> "$CLAUDE"
  fi
  updated+=("CLAUDE.md (añadida la sección SDD)")
  notes+=("CLAUDE.md ya tenía «Guardarraíles KMP» (v0.1): compárala con $SCAFFOLD/claude-md-section.md y divide los comandos en checks rápidos y caros.")
else
  if [ "$CHECK" = "no" ]; then
    { printf '\n'; cat "$SCAFFOLD/claude-md-section.md"; } >> "$CLAUDE"
  fi
  updated+=("CLAUDE.md (añadida la sección sdd-flow)")
fi

# --- .gitignore
GI="$TARGET/.gitignore"
if [ ! -f "$GI" ] || ! grep -qxF '.artifacts/' "$GI"; then
  if [ "$CHECK" = "no" ]; then
    [ -f "$GI" ] && [ -n "$(tail -c1 "$GI")" ] && printf '\n' >> "$GI"
    printf '# sdd-flow: full Gradle logs from scripts/sdd/gradle-signal.sh\n.artifacts/\n' >> "$GI"
  fi
  updated+=(".gitignore (.artifacts/)")
fi

# --- version stamp
if [ "$CHECK" = "no" ]; then
  mkdir -p "$TARGET/.claude/sdd"
  printf '%s\n' "$VERSION" > "$TARGET/.claude/sdd/VERSION"
fi

# --- legacy 0.1 state
[ -f "$TARGET/.claude/.sdd-state.json" ] \
  && notes+=(".claude/.sdd-state.json es de sdd-flow 0.1 y ya no se usa: se puede borrar.")

# --- report
list() {
  # $1 = title; rest = items
  local title="$1"; shift
  [ "$#" -gt 0 ] || return 0
  printf '%s\n' "$title"
  printf '  - %s\n' "$@"
}

mode="aplicado"
[ "$CHECK" = "yes" ] && mode="solo comprobación, sin escribir"
printf 'sdd-flow %s → %s (%s)\n' "$VERSION" "$TARGET" "$mode"
list "Creado:" ${created[@]+"${created[@]}"}
list "Actualizado:" ${updated[@]+"${updated[@]}"}
list "Del proyecto, ya existía y difiere de la plantilla (no se toca):" ${kept[@]+"${kept[@]}"}
printf 'Al día: %s fichero(s)\n' "${#same[@]}"
list "Notas:" ${notes[@]+"${notes[@]}"}

if [ -f "$CLAUDE" ]; then
  ph="$(awk '/^## Guardarraíles KMP/ { f = 1; next } f && /^## / { f = 0 } f' "$CLAUDE" \
    | grep -nE '<[^>]+>' | grep -v '^[0-9]*:>' || true)"
  if [ -n "$ph" ]; then
    printf 'Placeholders sin rellenar en «Guardarraíles KMP» de CLAUDE.md: %s línea(s)\n' "$(printf '%s\n' "$ph" | wc -l | tr -d ' ')"
    printf '%s\n' "$ph" | head -n 25 | sed 's/^[0-9]*:/  /'
  fi
fi
