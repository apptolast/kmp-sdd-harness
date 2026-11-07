# kmp-sdd-harness

Marketplace de plugins privado con el **harness SDD reutilizable** de AppToLast para proyectos KMP /
Compose Multiplatform. Se mejora una vez y llega a todos los proyectos con
`claude plugin marketplace update`.

```
define 🚦  →  tasks 🚦  →  implement (TDD)  →  converge  →  PR 🚦 (contra develop)
                            │   ↑                 │
                            │   ├─ tareas nuevas ←┘   huecos que encuentra converge
                            ↓   │
                         change─┘                     la intención o el diseño cambiaron (🚦 si es material)

lane rápido:  plan en el chat 🚦  →  implement (TDD)  →  PR 🚦
después del merge (opcional):  promote → engram / kmp-recipes
```

El proceso se ajusta al cambio: un cambio de un fichero va por el lane rápido (plan de cinco líneas en
el chat, sin documentos), un bug usa el spec de bug y todo lo demás va por el flujo estándar.

El flujo viene de android-sdd-harness, adaptado a KMP: source sets y
expect/actual, todos los targets compilando, tests en `commonTest`, i18n en/es, diseños de Pencil,
engram, kmp-recipes y Jira.

## Plugins

| Plugin | Qué aporta |
|---|---|
| **sdd-flow** | 5 subagentes y sus comandos (`/sdd-flow:define`, `tasks`, `implement`, `change`, `converge`), `/sdd-flow:promote` y `/sdd-flow:init`; un hook que bloquea el trabajo con dispositivo sin aprobación, otro que captura fallos de build en engram, y las skills `verify-on-device`, `kmp-compose-rules`, `kmp-testing-rules` y `kmp-platform-code`. |
| **kmp-recipes** | Recetario canónico de integraciones KMP (RevenueCat, Firebase-REST, auth Google/Apple, fastlane, navegación, i18n, WebView, testing…), sembrado desde proyectos existentes. |
| **android-skills** | Las skills oficiales de Google para Android ([android/skills](https://github.com/android/skills), Apache-2.0), fijadas a una versión revisada. Se instala como dependencia de sdd-flow. |

## Qué se obtiene

- **Evaluación de diseño** en `define`: antes de planificar, el agente mira el código que toca el cambio,
  señala los indicios de un parche en camino (incluida lógica de negocio en `androidMain`/`iosMain` o
  código que no se puede testear en `commonTest`) y propone un refactor preparatorio (`R#`) cuando el
  cambio iría encima de un problema de diseño.
- **Gates revisables**: cada elemento de los documentos tiene ID (`AC1`, `R1`, `D1`, `T1`) y cada gate
  termina con el mismo resumen corto (decisiones numeradas con recomendación, y solo el delta en un
  re-gate).
- **Cuatro documentos por feature** (`spec.md`, `plan.md`, `tasks.md` y el `journal.md` de solo-añadir),
  con presupuestos de tamaño y trazabilidad AC/R ↔ tarea comprobados por `scripts/sdd/spec-lint.sh`.
- **TDD por tarea**: test en rojo, código mínimo, refactor, check rápido y commit.
- **`gradle-signal.sh`**: ejecuta Gradle y solo imprime errores, tests fallidos (de todos los targets
  KMP) e infracciones de ktlint/detekt, para que un build no inunde el contexto del agente.
- **Aprobación para dispositivos**: un hook bloquea `adb`, emulador, `xcrun simctl`, `xcodebuild test`,
  `install*`/`uninstall*` y los tests instrumentados hasta que el usuario aprueba esa ejecución. Funciona
  también con `--dangerously-skip-permissions`.
- **Memoria en dos capas**: **engram** (viva; `define` la consulta, `converge` y un hook escriben en
  ella) y **kmp-recipes** (canónica; crece con `/sdd-flow:promote`).
- **ADRs** en `docs/decisions/` (`scripts/sdd/new-adr.sh`) y plantilla de PR con la checklist SDD.

## Instalación en un proyecto

```bash
# Desde ruta local (desarrollo del harness):
claude plugin marketplace add /ruta/a/kmp-sdd-harness
# O desde GitHub (privado):
claude plugin marketplace add https://github.com/apptolast/kmp-sdd-harness.git

claude plugin install sdd-flow@kmp-sdd-harness
claude plugin install kmp-recipes@kmp-sdd-harness
```

`sdd-flow` instala `android-skills` como dependencia. Si vienes de sdd-flow 0.2.x y actualizas desde la
shell (`claude plugin update`), instala la dependencia una vez con
`claude plugin install android-skills@kmp-sdd-harness`; si no, sdd-flow no carga.

Después, en el repo del proyecto:

```
/sdd-flow:init            # crea o actualiza scripts/sdd/, .claude/sdd/reglas.md, specs/_templates/,
                          # docs/decisions/, la plantilla de PR y la sección del CLAUDE.md
```

`init` es idempotente: siempre actualiza lo que gestiona el harness (`scripts/sdd/*`,
`.claude/sdd/reglas.md`, las guías) y nunca sobrescribe lo que es del proyecto (plantillas
personalizadas, la sección *Guardarraíles KMP* del `CLAUDE.md`). Al final lista los placeholders sin
rellenar y se ofrece a rellenarlos auditando el proyecto. Ejecútalo otra vez después de cada
`claude plugin marketplace update`.

## Requisitos del proyecto consumidor

- La sección **Guardarraíles KMP** del `CLAUDE.md` rellena con los comandos reales, separados en checks
  rápidos y checks caros. `/sdd-flow:init` la crea.
- **engram** instalado y su MCP conectado (`claude mcp add engram --scope user -- engram mcp
  --tools=agent`). Sin engram el flujo funciona, pero sin memoria viva.
- `python3` (hooks), `bash`, `git` y `gh` (para el PR).
- Opcional: MCP de Atlassian (para leer el ticket de Jira en `define`) y Pencil (diseños `.pen`).

Las skills oficiales de Android de Google llegan con el plugin **android-skills**: el marketplace lo
referencia en github.com/android/skills, fijado a un tag y un sha, y sdd-flow lo declara como dependencia,
así que se instala solo con sdd-flow (`android-skills:edge-to-edge`, `android-skills:r8-analyzer`…). Las
pautas para aplicarlas en KMP están en la skill `sdd-flow:kmp-platform-code`. El workflow
`bump-android-skills` abre cada semana un PR si Google publica una versión nueva
(`./scripts/bump-android-skills.sh --check` lo comprueba en local). Si tenías copias en `~/.claude/skills`,
bórralas: quedarían duplicadas y desfasadas.

## Desarrollar el harness

```bash
./scripts/render.sh            # regenera plugins/sdd-flow/{agents,commands} desde src/
./scripts/render.sh --check    # falla si lo commiteado está desactualizado
./tests/run-tests.sh           # suite de tests, sin dependencias
```

Los cuerpos de los agentes están en `src/agents/` y los bloques que comparten varios agentes en
`src/partials/`. **Nunca edites `plugins/sdd-flow/agents/` ni `plugins/sdd-flow/commands/` a mano**: se
generan, y el CI lo comprueba. Lo que se copia a los proyectos está en `plugins/sdd-flow/scaffold/`.

El CI (`.github/workflows/harness-ci.yml`) ejecuta shellcheck, el render check y los tests en cada push
y en cada pull request.
