#!/usr/bin/env bash
#
# Dependency-free test suite for the harness: render, spec-lint, init, gradle-signal and hooks.
#
#   ./tests/run-tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$HERE/plugins/sdd-flow"
SCAFFOLD="$PLUGIN/scaffold"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sddtest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export NO_COLOR=1

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }
check() { # $1 = name, rest = command; passes when the command exits 0
  local name="$1"; shift
  local out; if out="$("$@" 2>&1)"; then ok "$name"; else bad "$name" "$out"; fi
}
check_fails() {
  local name="$1"; shift
  local out; if out="$("$@" 2>&1)"; then bad "$name (expected failure)" "$out"; else ok "$name"; fi
}
contains() { # $1 = name, $2 = needle, $3 = haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "expected: $2"$'\n'"got: $3"; fi
}
lacks() {
  if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "unexpected: $2"$'\n'"got: $3"; else ok "$1"; fi
}

# --------------------------------------------------------------------------------------------- render
echo "render"
check "src/ and plugin are in sync" "$HERE/scripts/render.sh" --check
for f in "$PLUGIN"/agents/*.md; do
  n="$(basename "$f" .md)"
  [ -f "$PLUGIN/commands/$n.md" ] && ok "agent $n has a command" || bad "agent $n has a command"
  lacks "agent $n has no unexpanded include" "@include" "$(cat "$f" "$PLUGIN/commands/$n.md")"
done

# ------------------------------------------------------------------------------------------- json
echo "json"
for j in "$HERE/.claude-plugin/marketplace.json" "$PLUGIN/.claude-plugin/plugin.json" \
         "$HERE/plugins/kmp-recipes/.claude-plugin/plugin.json" "$PLUGIN/hooks/hooks.json"; do
  check "valid JSON: ${j#"$HERE"/}" python3 -m json.tool "$j"
done
v_plugin="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"
contains "VERSION matches sdd-flow plugin.json" "$v_plugin" "$(cat "$HERE/VERSION")"

# ------------------------------------------------------------------------------------------- init
echo "init"
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
out="$(bash "$PLUGIN/scripts/sdd-init.sh" "$REPO" --check)"
contains "--check reports" "solo comprobación" "$out"
[ ! -e "$REPO/scripts" ] && ok "--check writes nothing" || bad "--check writes nothing"

out="$(bash "$PLUGIN/scripts/sdd-init.sh" "$REPO")"
contains "first init creates CLAUDE.md" "CLAUDE.md" "$out"
for f in scripts/sdd/spec-lint.sh scripts/sdd/gradle-signal.sh scripts/sdd/new-feature.sh scripts/sdd/new-adr.sh \
         .claude/sdd/reglas.md specs/_templates/spec.md specs/_templates/tasks.md docs/decisions/_template.md \
         .github/pull_request_template.md .claude/sdd/VERSION; do
  [ -f "$REPO/$f" ] && ok "init places $f" || bad "init places $f"
done
[ -x "$REPO/scripts/sdd/spec-lint.sh" ] && ok "scripts are executable" || bad "scripts are executable"
contains "CLAUDE.md imports the rules" "@.claude/sdd/reglas.md" "$(cat "$REPO/CLAUDE.md")"
contains ".gitignore has .artifacts/" ".artifacts/" "$(cat "$REPO/.gitignore")"
contains "init lists unfilled placeholders" "Placeholders sin rellenar" "$out"

printf 'custom\n' >> "$REPO/specs/_templates/plan.md"
printf 'stale\n' >> "$REPO/scripts/sdd/spec-lint.sh"
out="$(bash "$PLUGIN/scripts/sdd-init.sh" "$REPO")"
contains "re-init keeps a customized project template" "specs/_templates/plan.md" "$out"
contains "custom template content survives" "custom" "$(tail -1 "$REPO/specs/_templates/plan.md")"
cmp -s "$SCAFFOLD/scripts/sdd/spec-lint.sh" "$REPO/scripts/sdd/spec-lint.sh" \
  && ok "re-init restores a harness-owned script" || bad "re-init restores a harness-owned script"
n_import="$(grep -c '@\.claude/sdd/reglas\.md' "$REPO/CLAUDE.md")"
[ "$n_import" -eq 1 ] && ok "re-init does not duplicate the CLAUDE.md section" || bad "CLAUDE.md section duplicated ($n_import)"
n_gi="$(grep -cx '\.artifacts/' "$REPO/.gitignore")"
[ "$n_gi" -eq 1 ] && ok "re-init does not duplicate .gitignore entry" || bad ".gitignore duplicated ($n_gi)"

LEGACY="$WORK/legacy"
mkdir -p "$LEGACY/.claude"
printf '# CLAUDE.md\n\n## Guardarraíles KMP (build · test · convenciones)\n\n- tests: ./gradlew :app:allTests\n' > "$LEGACY/CLAUDE.md"
printf '{}' > "$LEGACY/.claude/.sdd-state.json"
out="$(bash "$PLUGIN/scripts/sdd-init.sh" "$LEGACY")"
contains "0.1 install: notes the legacy state file" ".sdd-state.json" "$out"
n_g="$(grep -c '^## Guardarraíles KMP' "$LEGACY/CLAUDE.md")"
[ "$n_g" -eq 1 ] && ok "0.1 install: guardrails section not duplicated" || bad "guardrails duplicated ($n_g)"
contains "0.1 install: rules imported" "@.claude/sdd/reglas.md" "$(cat "$LEGACY/CLAUDE.md")"

# -------------------------------------------------------------------------------------- spec-lint
echo "spec-lint"
LINT="$REPO/scripts/sdd/spec-lint.sh"
NF="$REPO/scripts/sdd/new-feature.sh"

check "empty specs tree passes" "$LINT"
out="$("$NF" ABC-12-Login "Login con Google")"
contains "new-feature lower-cases the slug" "specs/abc-12-login/" "$out"
[ ! -f "$REPO/specs/abc-12-login/tasks.md" ] && ok "new-feature leaves tasks.md to the tasks step" || bad "tasks.md created early"
contains "new-feature fills the ticket" "Ticket: \`ABC-12\`" "$(cat "$REPO/specs/abc-12-login/spec.md")"
check_fails "fresh scaffold fails on placeholders" "$LINT" abc-12-login

write_valid_feature() { # $1 = slug
  local d="$REPO/specs/$1"
  mkdir -p "$d"
  cat > "$d/spec.md" <<EOF
# Spec — Login

- Slug: \`$1\`
- Estado: \`aprobado\`
- Ticket: \`ABC-12\`
- Plataformas: Android · iOS

Resumen: login con Google en Android e iOS.

## Problema

No hay login social.

## Objetivos

- Entrar con un toque.

## Fuera de alcance

- Apple Sign-In.

## Criterios de aceptación

- [ ] AC1 CUANDO el usuario pulsa Google ENTONCES ve su perfil
- [ ] AC2 CUANDO cancela ENTONCES sigue en la pantalla de login

## Preguntas abiertas

- Ninguna
EOF
  cat > "$d/plan.md" <<EOF
# Plan — Login

- Spec: \`specs/$1/spec.md\`
- Estado: \`aprobado\`

Resumen: AuthRepository común con actuals por plataforma.

## Evaluación de diseño

- Recomendación: B
- Refactors aprobados: R1 extraer AuthRepository de LoginViewModel
EOF
  cat > "$d/tasks.md" <<EOF
# Tareas — Login

- Spec: \`specs/$1/spec.md\` · Plan: \`specs/$1/plan.md\` · Log: \`specs/$1/journal.md\`
- Estado: \`aprobado\`

- [ ] T1 test de caracterización → R1
- [ ] T2 extraer AuthRepository → R1
- [ ] T3 test rojo de login → AC1
- [ ] T4 test rojo de cancelación → AC2
EOF
  printf '# Journal — Login\n' > "$d/journal.md"
}

rm -rf "$REPO/specs/abc-12-login"
write_valid_feature abc-12-login
check "valid feature passes" "$LINT" abc-12-login
out="$("$LINT" abc-12-login)"
lacks "valid feature has no warnings" "warn" "$out"

sed -i.bak '/T4 test rojo/d' "$REPO/specs/abc-12-login/tasks.md"
out="$("$LINT" abc-12-login)"
contains "criterion without a task warns" "AC2 no tiene ninguna tarea" "$out"
printf -- '- [ ] T9 algo → AC9\n' >> "$REPO/specs/abc-12-login/tasks.md"
out="$("$LINT" abc-12-login)"
contains "trace to a missing criterion warns" "traza a AC9" "$out"
printf -- '- [ ] ~~T10 tachada → AC8~~\n' >> "$REPO/specs/abc-12-login/tasks.md"
out="$("$LINT" abc-12-login)"
lacks "struck-through task is ignored" "AC8" "$out"

write_valid_feature abc-13-long
for _ in $(seq 1 70); do printf 'relleno\n' >> "$REPO/specs/abc-13-long/spec.md"; done
check_fails "spec over budget fails" "$LINT" abc-13-long

write_valid_feature abc-14-status
sed -i.bak 's/`aprobado`/`approved`/' "$REPO/specs/abc-14-status/plan.md"
check_fails "unknown status fails" "$LINT" abc-14-status

write_valid_feature abc-15-drift
sed -i.bak 's/`aprobado`/`hecho`/' "$REPO/specs/abc-15-drift/tasks.md"
sed -i.bak 's/`aprobado`/`borrador`/' "$REPO/specs/abc-15-drift/spec.md"
check_fails "done tasks with draft spec fails" "$LINT" abc-15-drift

write_valid_feature abc-16-bug
sed -i.bak 's/^- Ticket: .*/&\n- Tipo: bug/' "$REPO/specs/abc-16-bug/spec.md"
out="$("$LINT" abc-16-bug)"
contains "bug spec without unchanged behavior warns" "sin cambios" "$out"

write_valid_feature abc-17-early
rm "$REPO/specs/abc-17-early/tasks.md"
out="$("$LINT" abc-17-early)"
contains "missing tasks.md before the tasks step is fine" "lo crea el paso tasks" "$out"
check "missing tasks.md before the tasks step passes" "$LINT" abc-17-early

mkdir -p "$REPO/specs/001-legacy"
printf '# Spec 001\n\n> Estado: draft\n\nScenario [AC-01]: algo\n' > "$REPO/specs/001-legacy/spec.md"
out="$("$LINT" 001-legacy)"
contains "0.1 Gherkin spec is reported as legacy" "0.1" "$out"
check "0.1 Gherkin spec passes" "$LINT" 001-legacy

# ------------------------------------------------------------------------------------------- adr
echo "new-adr"
out="$("$REPO/scripts/sdd/new-adr.sh" "Usar Room KMP para la caché")"
contains "new-adr creates 0001" "0001-usar-room-kmp-para-la-cache.md" "$out"
contains "new-adr fills the title" "ADR-0001: Usar Room KMP para la caché" "$(cat "$REPO"/docs/decisions/0001-*.md)"
"$REPO/scripts/sdd/new-adr.sh" "Segunda" >/dev/null
[ -f "$REPO/docs/decisions/0002-segunda.md" ] && ok "new-adr numbers sequentially" || bad "new-adr numbers sequentially"
contains "new-adr builds the index" "0002" "$(cat "$REPO/docs/decisions/README.md")"

# ---------------------------------------------------------------------------------- gradle-signal
echo "gradle-signal"
cat > "$REPO/gradlew" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_GRADLE_FAIL:-0}" = 1 ]; then
  echo "> Task :shared:iosSimulatorArm64Test"
  echo "com.app.LoginViewModelTest[iosSimulatorArm64] > AC1 login ok[iosSimulatorArm64] FAILED"
  echo "    kotlin.AssertionError: Expected <Success>, actual <Error>."
  echo "e: file:///repo/shared/src/commonMain/kotlin/Foo.kt:3:5 Unresolved reference 'bar'."
  echo "/repo/app/src/commonMain/kotlin/Bar.kt:12:1 Lint error > [standard:no-wildcard-imports] Wildcard import"
  echo "3 tests completed, 1 failed"
  echo "* What went wrong:"
  echo "Execution failed for task ':shared:iosSimulatorArm64Test'."
  echo "* Try:"
  echo "BUILD FAILED in 3s"
  exit 1
fi
echo "BUILD SUCCESSFUL in 1s"
EOF
chmod +x "$REPO/gradlew"
out="$("$REPO/scripts/sdd/gradle-signal.sh" allTests)"; rc=$?
[ "$rc" -eq 0 ] && ok "gradle-signal keeps exit 0" || bad "gradle-signal keeps exit 0"
contains "gradle-signal reports OK" "gradle-signal: OK" "$out"
out="$(FAKE_GRADLE_FAIL=1 "$REPO/scripts/sdd/gradle-signal.sh" allTests)"; rc=$?
[ "$rc" -eq 1 ] && ok "gradle-signal keeps the failing exit code" || bad "gradle-signal exit code ($rc)"
contains "gradle-signal shows the native test failure" "[iosSimulatorArm64] FAILED" "$out"
contains "gradle-signal shows the assertion" "AssertionError" "$out"
contains "gradle-signal shows compiler errors" "Unresolved reference" "$out"
contains "gradle-signal shows ktlint" "no-wildcard-imports" "$out"
contains "gradle-signal shows what went wrong" "Execution failed" "$out"
[ -f "$REPO/.artifacts/gradle-last.log" ] && ok "gradle-signal keeps the full log" || bad "gradle-signal keeps the full log"

# ------------------------------------------------------------------------------------------ hooks
echo "hooks"
HOOK="$PLUGIN/hooks/require-device-approval.py"
decide() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | python3 "$HOOK"; }
for c in 'adb devices' 'cd app && adb -s emu shell input tap 1 2' '$ANDROID_HOME/platform-tools/adb install x.apk' \
         'emulator -avd Pixel' 'bash -c "emulator -avd P"' 'xcrun simctl boot "iPhone 16"' 'xcrun devicectl list devices' \
         'xcodebuild -scheme iosApp -destination "platform=iOS Simulator" test' \
         './gradlew :composeApp:installDebug' './gradlew :composeApp:connectedDebugAndroidTest' \
         './gradlew pixel6Api34DebugAndroidTest' './gradlew uninstallAll' 'ios-deploy --bundle x.app'; do
  contains "blocks: $c" '"deny"' "$(decide "$c")"
done
for c in 'git commit -m "document adb usage"' 'grep -rn emulator docs/' './gradlew :shared:iosSimulatorArm64Test' \
         './gradlew :composeApp:testDebugUnitTest' './gradlew compileDebugAndroidTestKotlin' 'xcrun simctl list devices' \
         'xcodebuild -scheme iosApp build' 'brew install ktlint' 'pod install' \
         'SDD_DEVICE_APPROVED=1 adb devices' 'SDD_DEVICE_APPROVED=1 ./gradlew installDebug'; do
  contains "allows: $c" '{}' "$(decide "$c")"
done
contains "ignores non-Bash tools" '{}' "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"adb"}}' | python3 "$HOOK")"
contains "survives bad JSON" '{}' "$(printf 'nope' | python3 "$HOOK")"

CAP="$PLUGIN/hooks/capture-to-engram.py"
check "capture hook compiles" python3 -m py_compile "$CAP"
out="$(PATH="/usr/bin:/bin" printf '{"tool_input":{"command":"./gradlew test"},"tool_response":{"stdout":"BUILD FAILED","exit_code":1}}' \
  | PATH="/usr/bin:/bin" python3 "$CAP" 2>&1)"
[ -z "$out" ] && ok "capture hook is silent without engram" || bad "capture hook is silent without engram" "$out"

# ------------------------------------------------------------------------------------------ result
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
