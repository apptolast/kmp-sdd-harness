---
description: "SDD — instala o actualiza en este repo lo que necesita el flujo sdd-flow: reglas, guardarraíles KMP en CLAUDE.md, plantillas de specs, scripts, ADRs y plantilla de PR. Idempotente."
argument-hint: "[--check]"
allowed-tools: Read, Grep, Glob, Edit, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

# /sdd-flow:init — Preparar el repositorio para sdd-flow

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-init.sh" "${CLAUDE_PROJECT_DIR:-$PWD}" $ARGUMENTS
```

La salida de arriba dice qué se creó, qué se actualizó y qué ya existía.

1. Si el script falló, explica el error y para.
2. Si la sección *Guardarraíles KMP* del `CLAUDE.md` tiene `<placeholders>` sin rellenar (los lista la
   salida), ofrece rellenarlos **auditando el proyecto real**: módulos y targets en
   `settings.gradle.kts` y los `build.gradle.kts`, source sets de test existentes, plugins de
   ktlint/detekt, versiones en `gradle/libs.versions.toml` y workflows de CI. Usa solo comandos que
   existan en el proyecto; nunca inventes tareas de Gradle. Pregunta antes de escribir lo que no puedas
   verificar.
3. Si un fichero que es del proyecto ya existía y difiere de la plantilla del plugin, menciónalo en una
   línea; no lo sobrescribas.
4. Recuerda commitear los ficheros nuevos (`build(sdd): …`) y, si existe `.claude/.sdd-state.json` de la
   versión 0.1, que se puede borrar.
