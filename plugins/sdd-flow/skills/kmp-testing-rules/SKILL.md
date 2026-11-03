---
name: kmp-testing-rules
description: Reglas de testing en los proyectos KMP de AppToLast — TDD, dónde viven los tests (commonTest y source sets de plataforma), cómo se nombran y trazan a los AC del spec, determinismo y qué tests necesitan aprobación. Úsala al escribir, ejecutar o revisar tests.
---

# Reglas de testing KMP

El patrón de código (kotlin.test + Turbine + coroutines-test + fakes a mano, con ejemplos) está en la
receta `kotlin-test-turbine-fakes` de kmp-recipes. Esto son las reglas.

- **TDD**: primero el test que falla, ejecutado y visto en rojo por la razón correcta (falta
  implementación, no un error de compilación del test); luego el código mínimo; luego refactor. Nunca
  debilites, borres ni ajustes un test para conseguir el verde.
- **Dónde**: por defecto en `commonTest` del módulo que contiene el código. Tests de plataforma
  (`androidUnitTest`, `iosTest`, …) solo para código de `actual` o integraciones que no se pueden aislar
  tras un port. Usa el source set que digan los *Guardarraíles KMP* del `CLAUDE.md`.
- **Trazabilidad**: el nombre del test cita el criterio del spec:
  `` fun `AC1 cuando el login falla el estado pasa a Error`() = runTest { … } ``, con secciones
  Given/When/Then comentadas dentro.
- **Qué testear**: ViewModels, casos de uso, repositorios (con fakes de sus fuentes), mappers y lógica
  pura. Lo de plataforma (Firebase, RevenueCat, WebView, sensores) va detrás de una interfaz en
  `commonMain` con un fake en el test.
- **Coroutines**: `runTest` + `StandardTestDispatcher`; `Dispatchers.setMain` en `@BeforeTest` y
  `resetMain` en `@AfterTest`. Flows con Turbine (`test { awaitItem() }`). HTTP con `ktor-client-mock`.
- **Deterministas**: sin red real, sin `delay` real ni `sleep`, sin estado mutable compartido entre tests,
  sin depender del locale ni del reloj salvo que sea lo que se prueba (inyecta un `Clock`).
- **Ejecutar**: siempre con `./scripts/sdd/gradle-signal.sh <tarea>` y los comandos reales de los
  guardarraíles. Si cambiaste `commonMain`, ejecuta también los tests de los demás targets (p. ej.
  `iosSimulatorArm64Test`), no solo los de Android.
- **Instrumentados** (`androidInstrumentedTest`, `connected*AndroidTest`) y UI tests en simulador
  manejado a mano: escribirlos está bien; ejecutarlos necesita la aprobación explícita del usuario para
  esa ejecución (regla de oro 8). Lo que no necesita un dispositivo real va en `commonTest`.
