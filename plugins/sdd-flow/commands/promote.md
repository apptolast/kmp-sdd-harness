---
description: "SDD 7/7 (opcional, tras merge) — destila aprendizajes a engram y, si procede, a una skill de kmp-recipes."
argument-hint: "(usa el spec recién mergeado)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash", "mcp__engram"]
---

# /promote — Destilar receta

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase done
```

1. Revisa lo aprendido en esta feature: `spec.md` / `plan.md`, los diffs, y las observaciones `[auto]` que el hook guardó en **engram** (`mcp__engram` → mem_search por el número de spec).
2. **Captura viva (engram):** guarda decisiones/gotchas/errores+solución relevantes (**sin secretos**, solo referencias). Scope `project` para lo específico; `apptolast-kmp` + `global` para lo transversal a la flota KMP.
3. **Promoción canónica (revisada):** si un patrón está probado y es reutilizable, propón crear/actualizar una skill en **kmp-recipes** (`plugins/kmp-recipes/skills/<categoría>/<receta>/SKILL.md`). **No promuevas ruido** — pide OK al usuario antes de canonizar (D6, captura híbrida).
4. Resume qué se capturó (engram) y qué se promovió (skill).
