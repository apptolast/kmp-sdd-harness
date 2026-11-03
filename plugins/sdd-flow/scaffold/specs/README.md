# specs/

Documentos fuente de verdad del flujo Spec-Driven Development (plugin `sdd-flow`). El flujo está en
`.claude/sdd/reglas.md`.

Cada feature vive en `specs/<slug>/`:

| Fichero | Papel | Lo escribe | Presupuesto |
|---|---|---|---|
| `spec.md` | Qué y por qué; los criterios (`AC#`) son normativos | `define` 🚦 | ≤ 60 líneas |
| `plan.md` | Cómo: enfoque, evaluación de diseño y refactors aprobados (`R#`), tests, riesgos | `define` 🚦 | ≤ 150 líneas |
| `tasks.md` | Checklist ejecutable con los tests primero; cada tarea traza a un `AC#` o `R#` | `tasks` 🚦 | ≤ 60 líneas |
| `journal.md` | Log de solo-añadir: descubrimiento, hallazgos, deuda, cambios, converge | todos | — |

Las plantillas están en `specs/_templates/`; un bug usa `spec-bug.md` (comportamiento actual, esperado y
sin cambios) en lugar de `spec.md`. Crea una feature con `./scripts/sdd/new-feature.sh <slug>`, o
`./scripts/sdd/new-feature.sh --bug <slug>` para un bug, y revisa el árbol con
`./scripts/sdd/spec-lint.sh`.

Referencia los specs bajo demanda (`@specs/<slug>/spec.md`) en lugar de pegarlos en el prompt.
