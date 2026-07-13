---
description: "SDD 1/7 — redacta el spec (requisitos + criterios Gherkin + tareas ligeras), consulta engram/recetas y crea la rama. Gate humano."
argument-hint: "<descripción de la feature>  (o  NNN-slug si ya existe)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash", "mcp__engram"]
---

# /spec — Especificación (🚦 Gate 1)

Feature solicitada: **$ARGUMENTS**

Marca la fase:

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase spec
```

Orquesta la fase de especificación:

1. **Numeración:** mira `specs/` y elige el siguiente `NNN` libre (3 dígitos) + un `slug` kebab-case corto. Registra el spec activo con Bash (sustituye el valor real):
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-spec <NNN-slug>`
   y el project key de engram: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-project <nombre-repo>`.
2. **Redacción:** lanza el subagente **spec-author** con el Task tool para que escriba `specs/<NNN-slug>/spec.md` siguiendo la plantilla `${CLAUDE_PLUGIN_ROOT}/templates/spec.md`. Pásale la feature y la ruta del proyecto. Debe:
   - Consultar **engram** (`mcp__engram` → mem_search) y las skills de **kmp-recipes** por recetas/aprendizajes relevantes, y rellenar la sección "Conocimiento reutilizable" (qué se reutiliza tal cual, qué se adapta, con refs).
   - Escribir los criterios de aceptación en **Gherkin** (`Scenario [AC-01] … Given/When/Then`, observables).
   - Respetar los **Guardarraíles KMP** del `CLAUDE.md` del proyecto (source-sets, expect/actual, stack de test).
3. **Rama:** crea `feature/<NNN-slug>` desde `develop` (usa `fix/` o `refactor/` si la feature lo pide) y regístrala:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-branch <rama>`.
4. **🚦 GATE 1 (humano):** presenta el spec al usuario y **detente**. No sigas a `/plan` hasta su aprobación explícita.
