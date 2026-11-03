## Qué y por qué

<Una o dos frases. Enlaza el ticket de Jira.>

Spec: `specs/<slug>/spec.md`

## Checklist SDD

- [ ] `spec.md`, `plan.md`, `tasks.md` y `journal.md` están commiteados y su `Estado` es correcto
- [ ] Todos los criterios de aceptación se cumplen, o el hueco se lista abajo
- [ ] `converge` dio ✅ (sus hallazgos están en `journal.md`)
- [ ] La lógica nueva o cambiada está cubierta por tests; ningún test se debilitó para conseguir el verde
- [ ] ktlint limpio y tests en verde
- [ ] Si cambió código compartido (`commonMain`), **todos los targets compilan**
- [ ] Strings nuevas en `values/` y `values-es/`; `@Preview` para los composables nuevos
- [ ] Los checks de dispositivo del plan se ejecutaron con aprobación, o se listan en Huecos conocidos
- [ ] Hay un ADR en `docs/decisions/` si se tomó una decisión de arquitectura

## Plataformas afectadas

<Android · iOS · Desktop · Web>

## Huecos conocidos

<Lo que se aplaza a sabiendas, y por qué, incluida la deuda de diseño registrada en `journal.md`.
«Ninguno» es una respuesta válida.>

## Cómo verificarlo

<La forma más barata de que quien revisa confirme que funciona.>
