#!/usr/bin/env bash
# sdd-flow — gestionado por el plugin; /sdd-flow:init lo sobrescribe. No lo edites aquí.
#
# Runs Gradle and prints only what an agent needs to act on: the result, the "What went wrong" block,
# compiler errors (JVM, Android, Kotlin/Native), failed tests (all KMP targets), ktlint/detekt
# violations and the lint summary. The full log stays on disk.
#
#   ./scripts/sdd/gradle-signal.sh <task> [<task> ...] [gradle options]
#
# The exit code is Gradle's own, so this can stand in for ./gradlew in any guardrail command.
# Full output: .artifacts/gradle-last.log (add .artifacts/ to .gitignore; /sdd-flow:init does).
# GRADLE_SIGNAL_MAX_LINES caps each section of the summary (default 40).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/.artifacts"
LOG="$LOG_DIR/gradle-last.log"
MAX="${GRADLE_SIGNAL_MAX_LINES:-40}"

[ "$#" -gt 0 ] || { echo "usage: $0 <gradle task> [<task> ...] [gradle options]" >&2; exit 2; }
[ -x "$ROOT/gradlew" ] || { echo "error: no executable gradlew in $ROOT" >&2; exit 2; }

mkdir -p "$LOG_DIR"
(cd "$ROOT" && ./gradlew --console=plain "$@") > "$LOG" 2>&1
rc=$?

section() {
  # $1 = title. Prints stdin under the title, capped at $MAX lines; prints nothing for empty input.
  awk -v title="$1" -v max="$MAX" '
    { n++; if (n <= max) line[n] = $0 }
    END {
      if (n == 0) exit
      print title
      for (i = 1; i <= n && i <= max; i++) print "  " line[i]
      if (n > max) printf "  ... %d more in the full log\n", n - max
    }'
}

result="$(grep -E '^BUILD (SUCCESSFUL|FAILED)' "$LOG" | tail -n 1)"

if [ "$rc" -eq 0 ]; then
  printf 'gradle-signal: OK — %s%s\n' "$*" "${result:+ ($result)}"
  warnings="$(grep -c '^w: ' "$LOG" || true)"
  if [ "${warnings:-0}" -gt 0 ]; then
    printf '  %s compiler warning(s), see the full log\n' "$warnings"
  fi
else
  printf 'gradle-signal: FAILED (exit %s) — %s\n' "$rc" "$*"

  # Gradle's own explanation, minus the boilerplate that follows it.
  awk '/^\* What went wrong:/ { f = 1; next }
       /^\* (Try|Exception is|Get more help):/ { f = 0 }
       f && NF' "$LOG" | section "What went wrong:"

  # Kotlin (`e: file:///...`, also Kotlin/Native), javac (`File.java:12: error:`) and native linker
  # errors (`ld: ...`, `Undefined symbols`) from iOS framework links.
  grep -E '^e: |:[0-9]+: error: |^(error: )?ld: |Undefined symbols for architecture|error: Compilation finished with errors' "$LOG" \
    | section "Compiler errors:"

  # JVM/Android: `com.example.FooTest > someTest FAILED` + the exception line.
  # Kotlin/Native and JS/Wasm: `FooTest[iosSimulatorArm64] > someTest[iosSimulatorArm64] FAILED`.
  grep -E -A1 ' > .+ FAILED$' "$LOG" | grep -v '^--$' | section "Failed tests:"
  grep -E '[0-9]+ tests? completed, [0-9]+ failed' "$LOG" | tail -n 5 | section "Test summary:"

  # ktlint (`File.kt:12:5 Lint error > ...` or `File.kt:12:5 <message> (standard:rule)`) and detekt.
  grep -E 'Lint error >|\((standard|ktlint|compose):[a-z-]+\)$|^.+\.kt:[0-9]+:[0-9]+: .+ \[[A-Za-z]+\]$' "$LOG" \
    | sort -u | section "Lint / style:"

  grep -E 'Lint found|Wrote (HTML|XML|text|SARIF) report' "$LOG" | sort -u | section "Android lint:"
fi

printf 'Full log: .artifacts/gradle-last.log (%s lines)\n' "$(wc -l < "$LOG" | tr -d ' ')"
exit "$rc"
