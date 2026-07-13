---
description: "SDD 6/7 — validación completa (ktlint + tests + trazabilidad) y abre el PR contra develop. Gate humano."
argument-hint: "(usa el spec activo)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash", "mcp__engram"]
---

# /validate — Validación + PR (🚦 Gate 4)

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase validate
```

1. Lanza el subagente **reviewer** (Task) para:
   - Correr `./gradlew ktlintCheck` y la suite de tests del proyecto (Guardarraíles KMP). detekt N/A (no configurado en el proyecto).
   - Verificar **trazabilidad**: cada `Scenario [AC-xx]` del spec tiene ≥1 test que lo cubre **y que estuvo en rojo antes** de implementar. **Bloquea** si hay implementación sin test rojo previo.
   - Verificar el resultado contra el spec (alcance dentro/fuera; notas no funcionales).
2. Si todo pasa, abre el **PR contra `develop`** con `gh` (título `NNN Descripción`; cuerpo: resumen + AC + tabla de trazabilidad + plataformas afectadas). La automatización **se detiene en "PR abierto"**.
3. Señala candidatos a `/promote` (aprendizajes/recetas nuevas), sin promover aún.
4. **🚦 GATE 4 (humano):** el usuario revisa y aprueba el PR; él gestiona `main`, releases estables y el bump **SemVer**.
