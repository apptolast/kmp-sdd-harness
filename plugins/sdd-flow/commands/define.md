---
description: Paso SDD 1. Convierte una petición de feature o un bug en una especificación y un plan técnico en specs/<slug>/spec.md y plan.md, con una evaluación de diseño del código que toca. Úsalo para empezar cualquier cambio no trivial, o cuando pidan especificar, definir o planificar una feature o un arreglo. Se detiene para aprobación humana. No escribe código de producción.
argument-hint: <JIRA-ID | slug> [descripción]
allowed-tools: Agent, Task, Read, Grep, Glob, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

Ejecuta el paso SDD **define** para `$ARGUMENTS`.

1. **Ticket.** Si el primer token es una clave de Jira (`ABC-123`) y hay un MCP de Atlassian disponible,
   lee la issue (resumen, descripción, criterios de aceptación) y quédate con un resumen de 10 líneas o
   menos para pasárselo al subagente. Si no hay MCP, sigue sin él.
2. **Slug.** Si `$ARGUMENTS` coincide con un `specs/<slug>/` existente, úsalo. Si no, crea la feature
   con `./scripts/sdd/new-feature.sh [--bug] <JIRA-ID-o-nombre-corto> "<Nombre>"` (usa `--bug` si es un
   bug). Si `scripts/sdd/` no existe, para y pide ejecutar `/sdd-flow:init`.
3. **Rama.** Si estás en `develop` (o en `main` sin `develop`), crea `feature/<JIRA-ID>-<descripción>`
   (o `fix/…` para un bug) desde ella. Si ya estás en una rama de trabajo, no la cambies.
4. Pásale al subagente `sdd-flow:define` el slug, la petición y el resumen del ticket. No leas los documentos en
   esta conversación: el subagente carga lo que necesita.
5. Ejecuta `./scripts/sdd/spec-lint.sh <slug>`, transmite el resumen de gate del subagente y detente.
6. Cuando el usuario apruebe, pon `Estado: aprobado` en `spec.md` y `plan.md` y commitea `specs/<slug>/`
   (`docs(specs): define <slug>`). Si pide cambios por número, vuelve a pasárselos al subagente.
