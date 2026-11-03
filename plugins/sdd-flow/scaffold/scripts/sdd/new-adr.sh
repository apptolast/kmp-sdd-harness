#!/usr/bin/env bash
# sdd-flow — gestionado por el plugin; /sdd-flow:init lo sobrescribe. No lo edites aquí.
#
# Creates the next Architecture Decision Record and refreshes the index.
#
#   ./scripts/sdd/new-adr.sh "Título corto de la decisión"
#
# Numbering is derived from the existing files, so two people never pick the same number by eye.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/docs/decisions"
TITLE="${1:-}"
[ -n "$TITLE" ] || { echo "usage: $0 \"Título corto de la decisión\"" >&2; exit 1; }
[ -f "$DIR/_template.md" ] || { echo "error: $DIR/_template.md not found — run /sdd-flow:init" >&2; exit 1; }

LAST=0
for f in "$DIR"/[0-9][0-9][0-9][0-9]-*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"; n="${n%%-*}"
  [ "$((10#$n))" -gt "$LAST" ] && LAST="$((10#$n))"
done
NUM="$(printf '%04d' $((LAST + 1)))"
# Transliterate accents so the file name stays ASCII.
SLUG="$(printf '%s' "$TITLE" | sed 's/[áÁàÀ]/a/g; s/[éÉèÈ]/e/g; s/[íÍìÌ]/i/g; s/[óÓòÒ]/o/g; s/[úÚüÜùÙ]/u/g; s/[ñÑ]/n/g; s/[çÇ]/c/g')"
SLUG="$(printf '%s' "$SLUG" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
FILE="$DIR/$NUM-$SLUG.md"

esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

sed -e "s|ADR-NNNN|ADR-$NUM|g" \
    -e "s|<título corto>|$(esc "$TITLE")|g" \
    -e "s|<YYYY-MM-DD>|$(date -u +%Y-%m-%d)|g" \
    "$DIR/_template.md" > "$FILE"

{
  echo "# Decisiones de arquitectura"
  echo
  echo "Solo se añade. Crea una con \`./scripts/sdd/new-adr.sh \"Título\"\`; sustituye en vez de reescribir."
  echo
  echo "| ADR | Título | Estado | Fecha |"
  echo "|---|---|---|---|"
  for f in "$DIR"/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    n="${b%%-*}"
    t="$(sed -n 's/^# ADR-[0-9]*:[[:space:]]*//p' "$f" | head -1)"
    s="$(sed -n 's/^[-*][[:space:]]*Estado:[[:space:]]*//p' "$f" | head -1 | sed 's/|.*//; s/[[:space:]]*$//')"
    d="$(sed -n 's/^[-*][[:space:]]*Fecha:[[:space:]]*//p' "$f" | head -1)"
    printf '| [%s](./%s) | %s | %s | %s |\n' "$n" "$b" "${t:-?}" "${s:-?}" "${d:-?}"
  done
} > "$DIR/README.md"

echo "Creado docs/decisions/$NUM-$SLUG.md y actualizado el índice."
