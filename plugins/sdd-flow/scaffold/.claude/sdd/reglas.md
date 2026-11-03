<!-- sdd-flow — gestionado por el plugin; /sdd-flow:init lo sobrescribe. No lo edites aquí: los
     hechos del proyecto van en la sección «Guardarraíles KMP» del CLAUDE.md. -->
# Reglas SDD (sdd-flow)

Cómo se trabaja en este repositorio. Los hechos del proyecto y los comandos están en la sección
*Guardarraíles KMP* del `CLAUDE.md`.

## Reglas de oro (no se rompen)

1. **Idiomas.** Documentos SDD (`specs/`, `docs/decisions/`) y PRs en español. Código, identificadores y
   comentarios de código en inglés. Strings de UI externalizadas, con inglés por defecto y español en
   `values-es/`.
2. **TDD.** Primero el test que falla, luego el código mínimo, luego refactor. Nunca debilites, borres ni
   ajustes un test para conseguir el verde.
3. **Gates humanos.** Para y pide aprobación después de `define`, después de `tasks` y cada vez que el
   spec se mueva.
4. **Solo comandos reales**, los de los *Guardarraíles KMP*. Nunca inventes una tarea de Gradle.
5. **Nunca edites a mano código generado** (KSP, Room, BuildKonfig, el `Res` de Compose Resources,
   frameworks de iOS). Regenéralo.
6. **Arregla causas, no síntomas.** No apiles parches. Un cambio estructural pasa por el gate de `define`
   como refactor aprobado (`R#`) o por `change`; nunca en silencio.
7. **Reutiliza antes de construir.** ¿Necesita existir → ya está aquí → hay receta en kmp-recipes o
   aprendizaje en engram → lo hace la plataforma o una dependencia → cabe en una línea → si no, lo
   mínimo? Solo recorta alcance: nunca validación, manejo de errores, seguridad, accesibilidad ni i18n.
8. **Primero la evidencia barata; el dispositivo necesita un sí.** Código, luego un test en
   `commonTest` o una `@Preview`, luego preguntar. Nunca arranques un emulador o un simulador, instales
   o manejes la app, ni ejecutes tests instrumentados sin la aprobación explícita del usuario para esa
   ejecución. Que una tarea lo mencione no es aprobación. Un hook del plugin bloquea esos comandos:
   cuando el usuario apruebe una ejecución, ponle delante `SDD_DEVICE_APPROVED=1`.

## El flujo SDD

```
define 🚦  →  tasks 🚦  →  implement (TDD)  →  converge  →  PR 🚦 (contra develop)
                            │   ↑                 │
                            │   ├─ tareas nuevas ←┘   huecos que encuentra converge
                            ↓   │
                         change─┘                     la intención o el diseño cambiaron (🚦 si es material)

después del merge (opcional):  promote → engram / kmp-recipes
```

| Paso | Comando | Resultado | Gate |
|---|---|---|---|
| define | `/sdd-flow:define <JIRA-ID \| slug>` | `spec.md` (qué, por qué) + `plan.md` (cómo, con evaluación de diseño) | 🚦 |
| tasks | `/sdd-flow:tasks <slug>` | `tasks.md`: checklist ordenada, tests primero | 🚦 |
| implement | `/sdd-flow:implement <slug> [T#]` | código y tests, una tarea cada vez | — |
| change | `/sdd-flow:change <slug> — <qué cambió>` | spec/plan/tasks actualizados | 🚦 si es material |
| converge | `/sdd-flow:converge <slug>` | informe de validación; añade tareas si quedan huecos; ofrece el PR | 🚦 revisión del PR |
| promote | `/sdd-flow:promote <slug>` | aprendizajes a engram; recetas propuestas a kmp-recipes | opcional |

**Lanes.** *Rápido*: un fichero, sin ambigüedad, sin tocar `commonMain` compartido por varios targets ni
`expect`/`actual`, sin dependencias nuevas. Sin documentos: un plan de cinco líneas o menos en el chat
(causa, cambio, test, riesgo), un OK, y TDD. *Bug*: el flujo estándar con `spec-bug.md`. *Estándar*:
todo lo demás, y siempre que haya dudas.

**Git.** `define` crea `feature/<JIRA-ID>-<desc>` (o `fix/…`) desde `develop`. Conventional commits en
minúsculas. El PR va contra `develop` con título `<JIRA-ID> Descripción`, y la automatización se detiene
en «PR abierto»: merge, `main`, releases y versiones son del usuario.

## Los cuatro documentos — `specs/<slug>/`

| Fichero | Papel | Presupuesto |
|---|---|---|
| `spec.md` | Qué y por qué. Los criterios de aceptación (`AC#`) son normativos. | ≤ 60 líneas |
| `plan.md` | Cómo: enfoque, evaluación de diseño, refactors aprobados (`R#`), source sets, tests, riesgos. | ≤ 150 líneas |
| `tasks.md` | Checklist, una línea por tarea, cada una trazada a un `AC#` o `R#`. | ≤ 60 líneas |
| `journal.md` | Log de solo-añadir: descubrimiento, hallazgos, deuda de diseño, cambios, converge. | sin límite |

Se releen en cada paso; lo que quiera crecer va a `journal.md`. `./scripts/sdd/spec-lint.sh` comprueba
presupuestos y trazabilidad.

## Cómo reportar

- Empieza por el resultado o por la decisión que necesitas. Sin preámbulo, sin recapitular, sin
  ofrecimientos al final.
- Mientras trabajas, una línea corta por fase, no una por llamada a herramienta.
- Muestra diffs y `path:line`, no ficheros enteros. Cita solo la línea decisiva de un error.
- Frases completas para preguntas, avisos, acciones irreversibles y todo lo que se commitea.
- Numera tus preguntas y dale a cada una una respuesta recomendada.
- Termina cada paso con `No comprobado:` y `Riesgos:` — una línea cada uno, o `nada`.

## Disciplina de tokens

- Carga solo lo que el paso necesita: busca antes de leer, lee ficheros grandes por rangos, no releas un
  fichero que no ha cambiado. Nunca leas `journal.md` entero.
- Manda la exploración amplia a un subagente de solo lectura y quédate con su resumen.
- Ejecuta Gradle con `./scripts/sdd/gradle-signal.sh <tarea>` y lee los fallos que reporta, no el log.
- Una tarea por sesión o subagente; `specs/<slug>/` lleva el estado entre ellos.

## Hecho significa

Documentos commiteados con un `Estado:` correcto; checks rápidos en verde, y todos los targets
compilando si cambió código compartido; checks de dispositivo ejecutados con aprobación o listados como
no comprobados; strings en `values/` y `values-es/` y `@Preview` si hay UI nueva; un ADR en
`docs/decisions/` para una decisión de arquitectura; un PR abierto contra `develop` para revisión
(`.github/pull_request_template.md`).
