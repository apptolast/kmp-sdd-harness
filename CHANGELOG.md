# Changelog

Cambios notables del harness. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/);
versiones SemVer. `/sdd-flow:init` escribe la versión del plugin en `.claude/sdd/VERSION` del proyecto.

## [0.2.0] — 2026-11-03

El flujo se rehace siguiendo android-sdd-harness (revisado tras uso real) y se adapta a KMP.

### Añadido
- Flujo `define 🚦 → tasks 🚦 → implement → converge → PR 🚦`, con `change` para cambios posteriores a la
  aprobación, y lanes rápido / bug / estándar.
- **Evaluación de diseño** en `define`, con opciones A/B/C y refactors aprobados `R#`. Incluye señales
  propias de KMP: lógica en un source set de plataforma, o falta de costura para testear en `commonTest`.
- Cuatro documentos por feature: `spec.md`, `plan.md`, `tasks.md` y `journal.md` (solo-añadir), con IDs,
  presupuestos, una línea `Resumen:` y plantilla de spec de bug.
- Resumen de gate fijo, con decisiones numeradas y solo el delta en los re-gates. Informe de `converge`
  agrupado en Debe / Debería / Estaría bien.
- `/sdd-flow:init` y `scripts/sdd-init.sh`: instalan o actualizan en el proyecto `scripts/sdd/`,
  `.claude/sdd/reglas.md`, las plantillas, los ADR, la plantilla de PR y la sección del `CLAUDE.md`, y
  listan los placeholders sin rellenar.
- `scripts/sdd/spec-lint.sh` (presupuestos, estados, trazabilidad AC/R ↔ T, specs de bug, coherencia
  con la rama), `gradle-signal.sh` (con fallos de Kotlin/Native, de link de iOS y de ktlint/detekt),
  `new-feature.sh` y `new-adr.sh`.
- Hook `require-device-approval.py`: bloquea el trabajo con dispositivo, emulador o simulador hasta que
  el usuario lo aprueba (`SDD_DEVICE_APPROVED=1`). Cubre también las tareas `install*`/`uninstall*` de
  Gradle, el hueco que el harness Android tenía abierto.
- Skills `verify-on-device` (adb y simctl), `kmp-compose-rules`, `kmp-testing-rules` y
  `kmp-platform-code`.
- Fuente única en `src/` con parciales, `scripts/render.sh --check`, `tests/run-tests.sh` y CI.

### Cambiado
- Todo el texto del flujo en español. El código y los comentarios de código siguen en inglés.
- Criterios de aceptación `- [ ] AC1 CUANDO … ENTONCES …` en lugar de Gherkin `Scenario [AC-01]`.
- TDD por tarea dentro de `implement` (rojo → verde → refactor → commit), en lugar de una fase de tests
  por lotes.
- El diseño en Pencil pasa de ser un gate propio a una decisión `D#` de `define` y una tarea con gate.
- `capture-to-engram.py` identifica la feature por la rama de git y reconoce `gradle-signal`.
- Se quitan las referencias fijas a `consumerApp` y a «detekt no configurado» que venían de un proyecto
  concreto: todo sale de los *Guardarraíles KMP*.
- Las recetas `kotlin-test-turbine-fakes`, `ci-cd-github-actions` y `ktlint-exclude-generated-sources`
  usan los términos del flujo nuevo.

### Eliminado
- Comandos `/spec`, `/plan`, `/design-check`, `/test` y `/validate`; agentes `leader`, `spec-author`,
  `tdd-test-writer`, `implementer` y `reviewer`.
- `sdd-state.sh` y `.claude/.sdd-state.json`: el estado vive en `specs/<slug>/`.
- Hook `block-test-edits.py`: con TDD por tarea no hay fase de tests congelados; la regla pasa a ser
  «nunca debilites un test», y la comprueba la revisión de `converge`.
- `fragments/kmp-guardrails.md`, sustituido por `plugins/sdd-flow/scaffold/claude-md-section.md`.

### Actualizar un proyecto
- `claude plugin marketplace update kmp-sdd-harness`, y después `/sdd-flow:init` en el repo.
- Si el `CLAUDE.md` ya tenía «Guardarraíles KMP» de la 0.1, `init` no la toca: añade solo la sección SDD.
  Compárala con `claude-md-section.md` y divide los comandos en checks rápidos y caros.
- Borra `.claude/.sdd-state.json`.
- Los specs escritos con la 0.1 (Gherkin) siguen pasando `spec-lint`, que los marca como legacy. Una
  feature a medias se puede terminar con el flujo nuevo creando `tasks.md` a mano o pasando por
  `/sdd-flow:change`.

## [0.1.0]

Harness inicial: 7 fases (`/spec` → `/plan` → `/design-check` → `/test` → `/implement` → `/validate` →
`/promote`), 5 subagentes, lock de tests en `/implement`, captura a engram y 15 recetas en kmp-recipes.
