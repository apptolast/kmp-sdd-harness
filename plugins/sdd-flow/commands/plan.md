---
description: "SDD 2/7 — desglosa el plan técnico y de tareas a partir del spec aprobado. Gate humano."
argument-hint: "(usa el spec activo)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash", "mcp__engram"]
---

# /plan — Plan técnico y de tareas (🚦 Gate 2)

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase plan
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" get
```

Lee el spec activo (`specs/<NNN-slug>/spec.md`) según el estado de arriba.

1. Produce `specs/<NNN-slug>/plan.md` con:
   - **Enfoque técnico** y decisiones de arquitectura (dónde vive cada pieza).
   - **Ficheros a tocar por source-set** (`commonMain` / `mobileMain` / `androidMain` / `iosMain` / `wasmJsMain`) y puntos **expect/actual**.
   - **Wiring de DI (Koin)** y contratos/interfaces (ports) necesarios para testear en `commonTest`.
   - **Impacto en plataformas** (Android/iOS/web) e i18n si aplica.
   - **Desglose de tareas ordenado**, cada tarea mapeada a los `AC-xx` del spec.
2. Consulta **engram** + **kmp-recipes** para reutilizar enfoques probados (anótalos).
3. **🚦 GATE 2 (humano):** presenta el plan y **detente** hasta aprobación. No sigas a `/design-check`.
