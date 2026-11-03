# Plan — <feature name>

- Spec: `specs/<slug>/spec.md`
- Estado: `borrador` | `aprobado` | `en-curso` | `implementado` | `hecho` | `bloqueado`

Resumen: <una línea: el enfoque, y el refactor que incluye, si lo hay>

## Enfoque

<El enfoque técnico en pocas frases. Qué componentes existentes se reutilizan, y qué es nuevo y por qué
no se pudo reutilizar.>

## Conocimiento reutilizable

- <skill de kmp-recipes u observación de engram #id> — <qué se reutiliza tal cual / qué se adapta>   (o "ninguno")

## Evaluación de diseño

- Causa raíz / punto de inserción: <fichero y símbolo — una línea>
- Señales: <caso especial · duplicación · capa o source set equivocados · parches repetidos · pelea con el diseño · no testeable en commonTest — o "ninguna">
- Opciones:
  - A — in situ: <cambio> · coste <S/M/L> · deja <qué>
  - B — refactor primero: <refactor>, luego <cambio> · coste <S/M/L> · riesgo <riesgo>
  - C — aplazar: A ahora, B registrado en `Deuda de diseño` de `journal.md`
- Recomendación: <A, B o C>, porque <una línea>
- Refactors aprobados: R1 <refactor que preserva el comportamiento>   (o "ninguno")

## Decisiones

- D1 <decisión> — elegida: <opción>; descartada: <opción>, porque <razón>   (o "ninguna")

## Áreas afectadas

- Módulos y paquetes: <...>
- Source sets: <commonMain · androidMain · iosMain · jvmMain · wasmJsMain — qué va en cada uno>
- expect/actual y ports: <declaraciones nuevas y sus actuals, o interfaces con fake en test — o "ninguno">
- Capas: <domain (modelos, interfaces de repositorio) · data (local/remote/repository) · presentation (ViewModel, UiState, pantallas)>
- DI (Koin): <módulo y bindings nuevos>
- Navegación: <rutas @Serializable nuevas o cambiadas, o "ninguna">
- UI y diseño: <pantallas y su `.pen` de Pencil (existe / falta → D#), o "sin UI">
- i18n: <strings nuevas en `values/` y `values-es/`, o "ninguna">
- Targets: <cuáles hay que compilar y probar>

## Estrategia de test

- `commonTest`: <qué cubre: ViewModels, casos de uso, repositorios con fakes, mappers>
- Tests de plataforma: <androidUnitTest / iosTest / … o "ninguno">
- Dispositivo (instrumentados, simulador manejado a mano): <qué, o "ninguno"> — solo con aprobación
- Checks rápidos: los comandos declarados en los *Guardarraíles KMP* del `CLAUDE.md`

## Riesgos

- <riesgo> → <mitigación>

---
Presupuesto: 150 líneas, de las que la evaluación de diseño 15 o menos. Notas de descubrimiento,
sondeos, inventarios de ficheros y callejones sin salida van a `journal.md`.
