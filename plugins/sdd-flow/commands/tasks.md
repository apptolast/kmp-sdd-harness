---
description: Paso SDD 2. Genera una lista de tareas ordenada por dependencias y con los tests primero en specs/<slug>/tasks.md a partir de un spec y un plan aprobados, incluido cualquier refactor preparatorio aprobado. Úsalo cuando se aprueba el gate de define, o cuando pidan desglosar una feature en tareas. Se detiene para aprobación humana.
argument-hint: <JIRA-ID | slug>
allowed-tools: Agent, Task, Read, Grep, Glob, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

Ejecuta el paso SDD **tasks** para `$ARGUMENTS`.

1. Resuelve `specs/<slug>/` a partir de `$ARGUMENTS`. Comprueba las líneas `Estado:` de `spec.md` y
   `plan.md` con una búsqueda, no con una lectura completa: si no están en `aprobado`, para y dilo. No
   generes tareas de un plan sin aprobar.
2. Pásale el slug al subagente `sdd-flow:tasks`; él lee los documentos.
3. Ejecuta `./scripts/sdd/spec-lint.sh <slug>`, transmite el resumen de gate y detente.
4. Cuando el usuario apruebe, pon `Estado: aprobado` en `tasks.md` y commitea (`docs(specs): tasks <slug>`).
