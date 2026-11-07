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

## Skills de Google (`android-skills:*`) en KMP

sdd-flow instala como dependencia el plugin `android-skills` (github.com/android/skills, versión fijada
en el marketplace). Son recetas oficiales y al día para Android: úsalas antes que tu memoria cuando el
trabajo toque `androidMain`, `androidApp` o la UI común, con estos matices:

| Skill | Cómo aplicarla en KMP |
|---|---|
| `agp-9-upgrade` | Pensada para apps Android puras: el módulo KMP usa `com.android.kotlin.multiplatform.library` (source sets `androidMain`/`androidHostTest`/`androidDeviceTest`); aplica sus pasos al módulo de app y a la configuración de Gradle. |
| `navigation-3` | Solo si el proyecto ha adoptado Navigation 3 (mira sus ADR); muchos usan Navigation Compose 2.x con rutas `@Serializable`. |
| `edge-to-edge`, `adaptive`, `jetpack-compose-performance` | `enableEdgeToEdge()` y lo de la `Activity` van en `androidApp`/`androidMain`; antes de llevar un API a `commonMain`, comprueba que existe en Compose Multiplatform. |
| `r8-analyzer`, `play-billing-library-version-upgrade`, `play-policy-insights`, `android-intent-security`, `android-permissions-security`, `anr-audit-and-fix`, `testing-setup` | Solo `androidMain`/`androidApp` y su build; los tests comunes siguen en `commonTest` (skill `kmp-testing-rules`). |
| `android-cli`, `android-profiler` | Lo que toque un dispositivo (los subcomandos `emulator`, `install`, `run`, `screen` y `layout`, o grabar una traza) necesita la aprobación del usuario para esa ejecución (regla de oro 8; el hook lo bloquea). `android docs`, `android describe` y analizar una traza que ya existe, no. |
| Wear, TV, XR, coches, Glance, Ink, cámara, media3, IA en dispositivo | Solo si el proyecto apunta a esa superficie. |
