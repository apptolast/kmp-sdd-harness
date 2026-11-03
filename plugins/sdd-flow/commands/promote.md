---
description: "SDD (opcional, tras el merge) — destila los aprendizajes de una feature a engram y, si procede, a una skill de kmp-recipes."
argument-hint: "<JIRA-ID | slug>"
allowed-tools: Read, Grep, Glob, Bash, mcp__engram__mem_search, mcp__engram__mem_save, mcp__engram__mem_get_observation
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

# /sdd-flow:promote — Destilar aprendizajes de `$ARGUMENTS`

Se ejecuta después del merge. No es una fase obligatoria.

1. Resuelve `specs/<slug>/`. Lee de `journal.md` solo `## Hallazgos`, `## Deuda de diseño` y
   `## Hallazgos de converge`, y la línea `Candidatos a promote` del último informe de converge.
2. Busca en **engram** (`mem_search`) las observaciones `[auto]` de esta rama o slug, que guardó el hook
   de fallos de build.
3. **Capa viva (engram):** guarda con `mem_save` las decisiones, gotchas y errores con su solución que
   valgan para el futuro. Sin secretos, solo referencias (`path:line`, slug). Scope `project` para lo
   específico; para lo transversal a la flota KMP, usa además el proyecto `apptolast-kmp`.
4. **Capa canónica (kmp-recipes):** si un patrón está probado en código mergeado y es reutilizable en
   otros proyectos, propón crear o actualizar `plugins/kmp-recipes/skills/<categoría>/<receta>/SKILL.md`
   en el repo del harness: nombre, descripción (cuándo usarla) y un borrador de 30 líneas o menos.
   **No canonices ruido**: pide un OK explícito antes de escribirla, y escríbela solo si el repo del
   harness está accesible en local.
5. Resume qué se guardó en engram y qué se propuso o promovió como receta. Pon el `Estado:` de los tres
   documentos en `hecho`.
