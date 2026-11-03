# Tareas — <feature name>

- Spec: `specs/<slug>/spec.md` · Plan: `specs/<slug>/plan.md` · Log: `specs/<slug>/journal.md`
- Estado: `borrador` | `aprobado` | `en-curso` | `implementado` | `hecho` | `bloqueado`

Ordenadas por dependencia. Los tests van antes del código que especifican. Toda tarea salvo las de
preparación y validación termina con los IDs a los que traza (`→ AC1`, `→ R1`). Marca las casillas al
avanzar.

## Fase 1 — Preparación

- [ ] T1 <p. ej. diseñar la pantalla X en el .pen (gate), o añadir dependencias de commonTest si faltan>

## Fase 2 — Refactor preparatorio (preserva el comportamiento; solo para un R# aprobado)

- [ ] T2 <test de caracterización que fija el comportamiento de hoy, si no existe> → R1
- [ ] T3 <refactor; los tests siguen en verde; commit propio> → R1

## Fase 3 — Tests (rojo)

- [ ] T4 <test en commonTest que falla para el comportamiento X> → AC1

## Fase 4 — Implementación (verde, luego refactor)

- [ ] T5 <código mínimo para pasar T4, luego limpiar lo tocado> → AC1

## Fase 5 — Validación

- [ ] T6 Checks rápidos en verde: tests, ktlint; todos los targets compilan si cambió commonMain
- [ ] T7 Strings en values/ y values-es/, y @Preview para cada composable nuevo, si hay UI
- [ ] T8 Checks de dispositivo del plan, si los hay (necesita aprobación)
- [ ] T9 ADR en `docs/decisions/` si se tomó una decisión de arquitectura

---
Presupuesto: 60 líneas, una línea por tarea. Esto es una checklist, no un log: la narrativa va a
`journal.md`.
