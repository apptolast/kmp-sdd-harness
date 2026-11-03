---
description: Paso SDD 4. Valida la implementación contra specs/<slug>/spec.md, plan.md y tasks.md y los checks rápidos, y revisa el diseño del cambio. Informa Convergido, o añade las tareas que faltan. Úsalo antes de abrir un PR, o cuando pidan validar o verificar una feature.
argument-hint: <JIRA-ID | slug>
allowed-tools: Agent, Task, Read, Grep, Glob, Bash
---
<!-- Generado por scripts/render.sh desde src/. Edita la fuente, no este fichero. -->

Ejecuta el paso SDD **converge** para `$ARGUMENTS`.

1. Resuelve `specs/<slug>/`.
2. Pásaselo al subagente `sdd-flow:converge`; él lee los documentos y ejecuta los checks rápidos.
3. Ejecuta `./scripts/sdd/spec-lint.sh <slug>` y transmite el informe sin cambios.
4. Si el veredicto es ✅ Convergido, ofrece abrir el PR contra `develop` con `gh pr create --base develop`:
   título `<JIRA-ID> <Descripción>`, cuerpo desde `.github/pull_request_template.md` con el resumen, los
   AC con su evidencia y las plataformas afectadas. No lo abras ni hagas push sin un sí explícito. La
   automatización se detiene en «PR abierto»: merge, `main`, releases y versiones son del usuario.
