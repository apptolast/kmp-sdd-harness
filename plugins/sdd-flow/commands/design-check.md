---
description: "SDD 3/7 — comprueba/crea el diseño (.pen de Pencil) de las pantallas de la feature. Gate humano (N/A si no toca UI)."
argument-hint: "(usa el spec activo)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash", "mcp__pencil"]
---

# /design-check — Diseño (🚦 Gate 3)

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase design
```

1. **¿Toca UI?** Si la feature es lógica/infra pura (p. ej. el piloto *IAP identity linking*), anótalo en el spec ("sin impacto de UI → gate de diseño N/A") y **salta** el gate hacia `/test`.
2. Si toca UI: comprueba en el repo si existe el/los `.pen` de la(s) pantalla(s) — es una **comprobación del repo** (Git), no requiere Pencil abierto. Si faltan y Pencil está corriendo, propón/crea el diseño vía `mcp__pencil` (full read/write). Trata el `.pen` como **especificación visual**: el Compose Multiplatform se genera en `/implement` a partir de ella (no dependas del export web de Pencil).
3. **🚦 GATE 3 (humano):** presenta el diseño (o la justificación de N/A) y **detente** hasta aprobación.
