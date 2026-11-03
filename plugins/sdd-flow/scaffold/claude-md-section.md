## SDD (sdd-flow)

@.claude/sdd/reglas.md

Specs en `specs/<slug>/`, decisiones en `docs/decisions/`. Scripts en `scripts/sdd/`.

## Guardarraíles KMP (build · test · convenciones)

> Rellena cada `<…>` con los valores **reales** de este proyecto (auditados, no genéricos) y borra lo que
> no aplique. Los agentes de sdd-flow leen esta sección en vez de adivinar comandos: una tabla incorrecta
> es peor que una vacía. `/sdd-flow:init` lista los placeholders que quedan.

### Qué es este proyecto

<Una o dos líneas, solo lo que un agente no puede deducir del código: módulos inusuales, targets, zonas
legacy, backend.>

### Stack (hechos)

- Módulos: `<:composeApp, :shared, …>`. Targets: `<android, iosArm64, iosSimulatorArm64, jvm, wasmJs>`.
- Kotlin `<x>`, Compose Multiplatform `<x>`, AGP `<x>`; Android `minSdk <x>` / `targetSdk <x>`.
- `<DI (Koin BOM x) · navegación · red (Ktor) · persistencia (Room KMP / settings) · imágenes (Coil 3)>`.
- Source set intermedio: `<mobileMain para android+ios — o "ninguno">`.

### Comandos (usa los reales — nunca inventes uno)

Los agentes ejecutan Gradle con `./scripts/sdd/gradle-signal.sh <tarea>`: mismas tareas, mismo código de
salida, pero imprime solo los errores, los tests fallidos y la ruta al log completo.

**Checks rápidos — se ejecutan libremente, de más barato a más caro:**

| Propósito | Comando |
|---|---|
| Compilar común + Android | `<./gradlew :composeApp:compileDebugKotlinAndroid>` |
| Compilar iOS (si cambió commonMain) | `<./gradlew :composeApp:compileKotlinIosSimulatorArm64>` |
| Tests rápidos (host JVM/Android) | `<./gradlew :composeApp:testDebugUnitTest>` |
| Tests de todos los targets | `<./gradlew :composeApp:allTests>` |
| Tests del módulo compartido | `<./gradlew :shared:allTests — o borrar>` |
| Lint | `<./gradlew ktlintCheck>` · autoformato `<./gradlew ktlintFormat>` |
| Análisis estático | `<./gradlew detekt — o "no configurado">` |

**Checks caros — pregunta al usuario antes, cada vez** (regla de oro 8):

- Tests instrumentados: `<./gradlew :composeApp:connectedDebugAndroidTest>`
- Emulador/simulador, instalar o manejar la app: `adb`, `emulator`, `xcrun simctl`, `xcodebuild … test`,
  `./gradlew install*`
- Builds de release (paridad con CI, lentos): `<./gradlew :composeApp:bundleRelease>` · `<fastlane …>`

CI: `<qué corre el CI y si ejecuta tests y lint — o "sin quality gate">`.

### Aviso multi-target

El código de `commonMain` compila en todos los targets. Compilar solo Android no demuestra nada sobre
iOS ni web: un API de JVM (`java.*`, `String.format`, `System.currentTimeMillis`) en `commonMain` rompe
iOS sin que Android se queje.

- Si un cambio toca `commonMain` o un source set intermedio, compila **todos** los targets antes de
  darlo por hecho.
- Un `expect` nuevo necesita su `actual` en cada target, incluidos los que no estás probando.
- Si el comportamiento esperado difiere por plataforma y no está documentado, pregunta en vez de adivinar.

### Stack de test

- `<kotlin.test>` + `<Turbine>` + `<kotlinx-coroutines-test>` + `<ktor-client-mock — o borrar>`. Fakes
  `<escritos a mano>`, sin MockK ni Kotest.
- Los tests viven en `<:composeApp/src/commonTest>`. `<Nota: p. ej. :shared no tiene tests de host
  Android; corren en iosSimulatorArm64Test/wasmJsTest — o borrar>`.
- Cada `AC#` del spec tiene al menos un test cuyo nombre (en backticks) lo cita.

### expect/actual y arquitectura

- Declaración común en `Foo.kt`; actuals en `Foo.<target>.kt` en cada source set. Flag
  `<-Xexpect-actual-classes — o "no">`.
- Clean Architecture por capas (domain/data/presentation), state hoisting, `StateFlow` en el ViewModel.
  Sin `runBlocking`/`GlobalScope` en producción.
- Koin `<versión del BOM>`: módulos `<dataModule, presentationModule, platformModule>`. Constructor
  injection.
- `@Preview` de `<org.jetbrains.compose.ui:ui-tooling-preview / AndroidX>` en commonMain, envueltas en
  `<NombreTheme>`.
- Diseños de Pencil (`.pen`) en `<ruta — o "no se usa Pencil">`.

### Depuración (verifica barato primero)

No uses por defecto la reproducción en dispositivo para responder una pregunta sobre la UI. En orden:
leer el composable, el ViewModel y el estado entre ellos → un test en `commonTest` que reproduce la
lógica → una `@Preview` para una duda puramente visual → preguntar al usuario, que tiene la app abierta →
solo entonces, **con su aprobación para esa ejecución**, manejar el dispositivo (skill
`verify-on-device`).
