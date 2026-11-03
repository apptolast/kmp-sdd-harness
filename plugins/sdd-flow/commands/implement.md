---
description: Paso SDD 3. Ejecuta un specs/<slug>/tasks.md aprobado, una tarea cada vez, con TDD estricto y refactorizando el código que toca. Úsalo para construir una feature cuando sus tareas están aprobadas, o cuando pidan implementar una tarea o una feature.
argument-hint: <JIRA-ID | slug> [id de tarea]
allowed-tools: Agent, Task, Read, Grep, Glob, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

Ejecuta el paso SDD **implement** para `$ARGUMENTS`.

1. Resuelve `specs/<slug>/` con el primer argumento; un segundo argumento opcional indica una sola tarea.
2. Comprueba la línea `Estado:` de `tasks.md` con una búsqueda: si no es `aprobado` ni `en-curso`, para.
3. Pásale el slug y la tarea al subagente `sdd-flow:implement`; él lee lo que necesita. No cargues los documentos
   en esta conversación.
4. Transmite qué tareas quedan marcadas, qué dijeron los checks y qué no se comprobó.
