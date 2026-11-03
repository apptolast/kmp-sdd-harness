---
name: kmp-platform-code
description: Reglas para código específico de plataforma en KMP — expect/actual, source sets intermedios, interop con iOS (Swift/ObjC, cinterop, frameworks), módulo de plataforma de Koin y código generado. Úsala al tocar androidMain, iosMain, jvmMain, wasmJsMain, expect/actual o el proyecto iosApp.
---

# Código de plataforma en KMP

Trátalo como zona de alto riesgo: un error aquí suele fallar en ejecución en un target que no estabas
probando, no en compilación en el que sí.

- **Primero el común.** Antes de escribir en un source set de plataforma, comprueba si cabe en
  `commonMain` con una librería multiplataforma (kotlinx-datetime, Ktor, multiplatform-settings, Room
  KMP, Coil 3…). La lógica de negocio nunca vive en `androidMain`/`iosMain`.
- **Interfaz o expect/actual.** Para inyectar una dependencia de plataforma, prefiere una interfaz en
  `commonMain` con implementaciones por plataforma registradas en `platformModule` de Koin (`expect val
  platformModule: Module`). Reserva `expect fun`/`expect class` para lo que no encaja en DI. Ambas
  opciones dejan una costura testeable con un fake en `commonTest`.
- **Ficheros**: declaración en `Foo.kt` en `commonMain` (o en el intermedio, p. ej. `mobileMain`); actuals
  en `Foo.android.kt`, `Foo.ios.kt`, `Foo.jvm.kt`, `Foo.wasmJs.kt`. Un `expect` nuevo necesita su `actual`
  en **todos** los targets: compílalos todos.
- **iOS**: lo que se expone a Swift debe ser simple (sin genéricos complejos, sin `suspend` sin envolver
  si el proyecto no usa SKIE/KMP-NativeCoroutines). Cambios en el proyecto `iosApp` de Xcode, en
  `cinterop` o en el framework exportado se validan compilando el framework
  (`link…FrameworkIosSimulatorArm64` o lo que digan los guardarraíles) y se señalan como riesgo en el PR.
- **Código generado**: nunca a mano —KSP (Room, Koin annotations), BuildKonfig, el `Res` de Compose
  Resources, frameworks de iOS—. Cambia la fuente y regenera.
- **Secretos**: nunca en código. BuildKonfig desde `local.properties` (receta `buildkonfig-secrets`); no
  leas `local.properties`, keystores ni `google-services.json`/`GoogleService-Info.plist`.
- **Verificación**: compilar todos los targets afectados es el check rápido. Lo que necesite un
  dispositivo se propone con el comando exacto y se ejecuta solo con aprobación (skill
  `verify-on-device`).
