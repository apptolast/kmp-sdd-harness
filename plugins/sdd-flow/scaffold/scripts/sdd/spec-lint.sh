#!/usr/bin/env bash
# sdd-flow — gestionado por el plugin; /sdd-flow:init lo sobrescribe. No lo edites aquí.
#
# Validates the specs/ tree.
#
#   ./scripts/sdd/spec-lint.sh [<slug> ...]
#
# With no arguments, lints every feature. Errors fail the run; warnings do not.
# Specs written with sdd-flow 0.1 (Gherkin `Scenario [AC-01]`, no `- Estado:` line) are reported as
# legacy and skipped, so an existing specs/ tree keeps passing.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPECS="$ROOT/specs"

# Budgets — keep in sync with specs/_templates/ and .claude/sdd/reglas.md.
MAX_SPEC=60
MAX_PLAN=150
MAX_TASKS=60
MAX_DESIGN=15

STATUSES="borrador aprobado en-curso implementado hecho bloqueado"
TICKET_RE='[A-Z][A-Z0-9]+-[0-9]+'

ERRORS=0; WARNINGS=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; B=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'
else
  R=""; Y=""; G=""; B=""; D=""; Z=""
fi

err()  { printf '  %sfail%s  %s\n' "$R" "$Z" "$1"; ERRORS=$((ERRORS + 1)); }
warn() { printf '  %swarn%s  %s\n' "$Y" "$Z" "$1"; WARNINGS=$((WARNINGS + 1)); }
note() { printf '  %sinfo%s  %s\n' "$D" "$Z" "$1"; }

status_of() {
  # Reads the `- Estado: ...` line and strips backticks, pipes and parenthetical notes,
  # so `hecho (guardado en dispositivo aplazado)` still resolves to `hecho`.
  sed -n 's/^[-*][[:space:]]*Estado:[[:space:]]*//p' "$1" 2>/dev/null | head -1 \
    | sed 's/`//g; s/(.*//; s/|.*//; s/[[:space:]]*$//'
}

check_budget() {
  local n; n="$(wc -l < "$1" | tr -d ' ')"
  if [ "$n" -gt "$2" ]; then
    err "$3: $n líneas, el presupuesto es $2 — mueve la narrativa a journal.md"
  fi
}

ids_in() {
  # $1 = ID prefixes as an ERE alternation, e.g. 'AC|R'. Prints each ID found on stdin, one per line.
  grep -oE "(^|[^A-Za-z0-9])($1)[0-9]+" | grep -oE "($1)[0-9]+"
}

check_traceability() {
  # Tasks trace to acceptance criteria (spec.md) or approved refactors (plan.md's design assessment).
  local spec="$1" plan="$2" tasks="$3" defined refs id
  defined="$( {
      grep -E '^- \[[ x]\] AC[0-9]+' "$spec" | ids_in 'AC'
      awk '/^## / { s = ($0 ~ /^## Evaluación de diseño/) } s' "$plan" \
        | grep -E 'Refactors aprobados:|^[[:space:]]*- R[0-9]+' | ids_in 'R'
    } | sort -u )"
  printf '%s\n' "$defined" | grep -q '^AC' || return 0

  # Struck-through tasks (~~T5 ...~~) no longer count.
  refs="$(grep -E '^- \[[ x]\] ' "$tasks" | grep -v '~~' | grep -E '→|->' | sed -E 's/.*(→|->)//' \
    | ids_in 'AC|R' | sort -u)"
  for id in $refs; do
    printf '%s\n' "$defined" | grep -qx "$id" \
      || warn "tasks.md traza a $id, que no es un criterio de spec.md ni un refactor aprobado de plan.md"
  done
  [ -n "$refs" ] || return 0
  for id in $defined; do
    printf '%s\n' "$refs" | grep -qx "$id" || warn "$id no tiene ninguna tarea en tasks.md"
  done
}

check_bug_spec() {
  local spec="$1"
  grep -qE '^- Tipo:[[:space:]]*`?bug' "$spec" || return 0
  grep -q '^## Comportamiento actual' "$spec" || warn "el spec de bug no tiene '## Comportamiento actual'"
  awk '/^### Sin cambios/ { f = 1; next } /^#/ { f = 0 } f && /^- \[[ x]\]/ { n++ } END { exit !(n > 0) }' "$spec" \
    || warn "el spec de bug no lista comportamiento sin cambios — una regresión no tendría contra qué comprobarse"
}

check_design_budget() {
  local plan="$1" n
  n="$(awk '/^## / { s = ($0 ~ /^## Evaluación de diseño/); next } s && NF { n++ } END { print n + 0 }' "$plan")"
  if [ "$n" -gt "$MAX_DESIGN" ]; then
    warn "plan.md: la evaluación de diseño ocupa $n líneas, el presupuesto es $MAX_DESIGN — lleva el detalle a journal.md"
  fi
}

check_status() {
  # $1 = file label, $2 = value
  local found=0 ok
  if [ -z "$2" ]; then
    err "$1 no tiene línea 'Estado:'"
    return
  fi
  for ok in $STATUSES; do [ "$2" = "$ok" ] && found=1; done
  [ "$found" -eq 1 ] || err "$1 tiene estado '$2', se esperaba uno de: $STATUSES"
}

check_placeholders() {
  local f="$1" ph
  ph="$(grep -c '<[a-z][^>]*>\|<PLACEHOLDER\|<TICKET-ID\|<YYYY-MM-DD>\|<feature name>\|<feature-slug>' "$f" 2>/dev/null || true)"
  [ "${ph:-0}" -gt 0 ] && err "$(basename "$f"): $ph placeholder(s) de plantilla sin rellenar"
}

lint_feature() {
  local dir="$1" slug; slug="$(basename "$dir")"
  printf '\n%s%s%s\n' "$B" "$slug" "$Z"

  local spec="$dir/spec.md" plan="$dir/plan.md" tasks="$dir/tasks.md" journal="$dir/journal.md"

  if [ ! -f "$spec" ]; then
    err "falta spec.md"
    return 0
  fi

  if ! grep -qE '^[-*][[:space:]]*Estado:' "$spec" && grep -qE 'Scenario \[AC-' "$spec"; then
    note "spec de sdd-flow 0.1 (Gherkin) — se omite"
    return 0
  fi

  [ -f "$plan" ] || { err "falta plan.md"; return 0; }
  [ -f "$journal" ] || warn "falta journal.md — los hallazgos y los resultados de converge no tienen dónde ir"

  local s_spec s_plan s_tasks=""
  s_spec="$(status_of "$spec")"; s_plan="$(status_of "$plan")"
  check_status "spec.md" "$s_spec"
  check_status "plan.md" "$s_plan"

  check_budget "$spec" "$MAX_SPEC" "spec.md"
  check_budget "$plan" "$MAX_PLAN" "plan.md"

  if ! grep -q '^## Criterios de aceptación' "$spec"; then
    err "spec.md no tiene la sección '## Criterios de aceptación'"
  elif ! awk '/^## Criterios de aceptación/{f=1;next} /^## /{f=0} f && /^- \[[ x]\]/{n++} END{exit !(n>0)}' "$spec"; then
    err "spec.md no tiene casillas de criterios de aceptación"
  fi

  check_placeholders "$spec"
  check_placeholders "$plan"
  grep -q "specs/$slug/spec.md" "$plan" || warn "plan.md no referencia su spec"
  check_bug_spec "$spec"
  check_design_budget "$plan"

  local n_tasks=0
  if [ ! -f "$tasks" ]; then
    case "$s_spec" in
      borrador|aprobado) note "tasks.md todavía no existe — lo crea el paso tasks" ;;
      *) err "falta tasks.md y el spec está en '$s_spec'" ;;
    esac
  else
    s_tasks="$(status_of "$tasks")"
    check_status "tasks.md" "$s_tasks"
    check_budget "$tasks" "$MAX_TASKS" "tasks.md"
    check_placeholders "$tasks"
    grep -q "specs/$slug/plan.md" "$tasks" || warn "tasks.md no referencia su plan"
    case "$s_tasks" in
      implementado|hecho)
        if [ "$s_spec" = "borrador" ] || [ "$s_plan" = "borrador" ]; then
          err "las tareas están en '$s_tasks' pero spec/plan siguen en 'borrador' — los documentos ya no describen la realidad"
        fi
        ;;
    esac
    n_tasks="$(grep -c '^- \[[ x]\]' "$tasks" 2>/dev/null || true)"
    [ "${n_tasks:-0}" -eq 0 ] && warn "tasks.md no tiene tareas"
    check_traceability "$spec" "$plan" "$tasks"
  fi

  printf '  %sok%s    %s tarea(s), spec %s / plan %s / tasks %s\n' \
    "$G" "$Z" "${n_tasks:-0}" "${s_spec:-?}" "${s_plan:-?}" "${s_tasks:--}"
}

check_branch() {
  local branch ticket slug_hit lower candidate
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$branch" ] || return 0
  ticket="$(printf '%s' "$branch" | grep -oE "$TICKET_RE" | head -1 || true)"
  [ -n "$ticket" ] || return 0

  lower="$(printf '%s' "$ticket" | tr '[:upper:]' '[:lower:]')"
  slug_hit=""
  for candidate in "$SPECS/$lower"-* "$SPECS/$lower"; do
    [ -d "$candidate" ] && { slug_hit="$candidate"; break; }
  done
  printf '\n%srama%s %s\n' "$B" "$Z" "$branch"
  if [ -z "$slug_hit" ]; then
    warn "la rama nombra $ticket pero no hay specs/$lower-* — vale para un cambio del lane rápido; si no, el trabajo empezó sin spec"
  else
    printf '  %sok%s    coincide con %s\n' "$G" "$Z" "specs/$(basename "$slug_hit")"
  fi
}

[ -d "$SPECS" ] || { echo "no hay directorio specs/ en $ROOT"; exit 0; }

printf '%sspec-lint%s  %s\n' "$B" "$Z" "$SPECS"

if [ "$#" -gt 0 ]; then
  for slug in "$@"; do
    if [ -d "$SPECS/$slug" ]; then lint_feature "$SPECS/$slug"; else err "no existe la feature: $slug"; fi
  done
else
  found=0
  for d in "$SPECS"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in _templates|example-*) continue ;; esac
    found=1
    lint_feature "$d"
  done
  [ "$found" -eq 1 ] || printf '\n  %sno hay features que revisar%s\n' "$D" "$Z"
  check_branch
fi

printf '\n%s────────────────%s\n' "$B" "$Z"
if [ "$ERRORS" -eq 0 ]; then
  printf '%sspec-lint ok%s (%s aviso(s))\n' "$G" "$Z" "$WARNINGS"
  exit 0
else
  printf '%sspec-lint falló%s: %s error(es), %s aviso(s)\n' "$R" "$Z" "$ERRORS" "$WARNINGS"
  exit 1
fi
