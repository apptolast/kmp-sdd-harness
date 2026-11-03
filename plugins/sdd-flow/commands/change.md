---
description: Gestiona un cambio de alcance, comportamiento o diseño que llega después de aprobar un gate. Actualiza spec, plan y tasks para que reflejen la nueva intención y registra el cambio. Úsalo cuando el usuario pide algo que los documentos aprobados no cubren o contradicen, o cuando la implementación descubre que hace falta un cambio estructural.
argument-hint: <JIRA-ID | slug> — <qué cambió>
allowed-tools: Agent, Task, Read, Grep, Glob, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

Registra un cambio posterior a la aprobación para `$ARGUMENTS`.

El primer token es el ticket o el slug; el resto describe qué cambió.

1. Resuelve `specs/<slug>/`.
2. Pásale el slug y la descripción al subagente `sdd-flow:change`; él lee los documentos.
3. Ejecuta `./scripts/sdd/spec-lint.sh <slug>` y transmite la clasificación, el delta y si hace falta
   volver a aprobar.
4. Si hubo re-gate y el usuario aprueba, pon `Estado: aprobado` en los documentos cambiados (`en-curso`
   en `tasks.md` si la implementación ya había empezado) y commitea (`docs(specs): change <slug>`).
