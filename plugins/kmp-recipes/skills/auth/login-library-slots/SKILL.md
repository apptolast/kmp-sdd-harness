---
name: login-library-slots
description: Úsala al montar autenticación en un proyecto KMP/CMP de AppToLast reutilizando la librería :custom-login de BaseLogin — cuando necesites pantallas de login/registro/recuperación con multi-proveedor (Google/Apple/GitHub/Microsoft/Twitter/Facebook/Magic-link/Phone), quieras el patrón Slots para personalizar la UI, o el andamiaje MVI+tests. Define cómo consumir la librería y cómo adaptar su wiring (GitLive → REST).
version: 0.1.0
---

# Receta: consumir la librería de login `:custom-login` (patrón Slots)

Librería de auth **canónica** de la org: módulo Gradle standalone, UI Compose Multiplatform, 8 proveedores, MVI por pantalla y la suite de tests más completa. Fuente: `apptolast/BaseLogin`, módulo `:custom-login` (`com.apptolast.customlogin`).

## Cuándo usarla
- Al arrancar una app KMP que necesita flujo de auth (login → registro → recuperar/reset → phone OTP → magic link → reauth → welcome) y quieres reutilizar UI/UX + tests en vez de reescribirlos.
- Al personalizar cualquier pieza visual del flujo sin bifurcar la librería (**patrón Slots**).
- **NO** la copies tal cual si tu proyecto retiró GitLive por REST (estilo inemsellar): consume la riqueza de UI/UX y el andamiaje de tests, pero **reescribe el wiring de auth a REST** (ver receta `social-auth-rest`). Ver Gotchas.

## Cómo se hace

### 1. Incluir el módulo
Es un **módulo Gradle standalone** (no un paquete dentro de tu app). En `settings.gradle.kts`:

```kotlin
// settings.gradle.kts
include(":custom-login")

// Repos GitLive requeridos por la lib (Firebase-kotlin-sdk) — ver Gotchas
dependencyResolutionManagement {
    repositories {
        maven("https://gitlive.github.io/firebase-kotlin-sdk/maven/")
    }
}
```

```kotlin
// build.gradle.kts de tu app
dependencies { implementation(project(":custom-login")) }
```

(También se publica como artefacto Maven: `com.github.apptolast:baselogin` vía JitPack.)

### 2. Activar proveedores con `LoginLibraryConfig`
Toggle-API única. Cada proveedor se activa pasando su config (o `true`); si es `null`/`false`, no aparece:

```kotlin
val config = LoginLibraryConfig(
    googleSignInConfig = GoogleSignInConfig(serverClientId = "…"), // null = oculto
    appleSignInConfig = AppleSignInConfig(…),   // iOS nativo; web-OAuth en Android
    githubEnabled = true,     // web-OAuth vía Firebase en ambas plataformas
    microsoftEnabled = false,
    magicLinkConfig = MagicLinkConfig(…),        // null = deshabilitado
    phoneEnabled = true,      // SMS OTP (por defecto true)
    twitterEnabled = false,
    facebookEnabled = false,
)
```

### 3. Arrancar Koin con `initLoginKoin`
La librería trae su propio inicializador (registra `configModule` + `dataModule` + `presentationModule`):

```kotlin
// entry point de cada plataforma
initLoginKoin(config = config) {
    // appDeclaration opcional: modules(tusModulos), androidContext(...), etc.
}
```

### 4. Montar el flujo en tu NavHost
La librería expone la extensión `authRoutesFlow` (grafo anidado type-safe). Enchúfala en tu `NavHost`:

```kotlin
NavHost(navController, startDestination = AuthRoutesFlow) {
    authRoutesFlow(
        navController = navController,
        startDestination = LoginRoute,   // o WelcomeRoute
        slots = AuthScreenSlots(),        // ver paso 5
        onNavigateToHome = { /* auth OK → tu app; normalmente lo dispara AuthState */ },
    )
}
```

### 5. Personalizar con Slots
Cada pantalla define un `*ScreenSlots` (data class) donde cada campo es un `@Composable` con **default**. Sobrescribe solo lo que quieras; el resto usa `DefaultXxx` de `presentation/slots/defaultslots/`:

```kotlin
val slots = AuthScreenSlots(
    login = LoginScreenSlots(
        header = { MiLogo() },
        submitButton = { onClick, isLoading, enabled, text ->
            MiBotonPrimario(onClick, isLoading, enabled, text)
        },
        // emailField, passwordField, socialProviders, forgotPasswordLink… quedan por defecto
    ),
)
```

`AuthScreenSlots` agrupa `login/register/forgotPassword/resetPassword/phoneAuth/magicLink/reauth`.

### 6. Estructura MVI por pantalla (lo que heredas)
Cada pantalla (login, register, forgotpassword, resetpassword, magiclink, phone, reauth, welcome) sigue el mismo contrato en `presentation/screens/<screen>/`: **`<Screen>Action`** (eventos de UI, `sealed interface`), **`<Screen>Effect`** (efectos one-shot: navegación/errores), **`<Screen>UiState`** (`data class` inmutable), **`<Screen>ViewModel`** (`viewModelOf(::…)` en `presentationModule`) y **`<Screen>Screen`** (composable stateless que recibe `slots`). Replica este molde si añades pantallas.

## Gotchas
- **GitLive es el gran acoplamiento.** `:custom-login` depende de `firebase-kotlin-sdk` de GitLive (`implementation(libs.firebase.auth)`) y **exige el repo maven `gitlive.github.io`** en `settings.gradle.kts`. Proyectos estilo inemsellar **retiraron GitLive por REST**: consume la UI/Slots/MVI/tests, pero re-implementa `AuthProvider`/`AuthRepositoryImpl` sobre Identity Toolkit REST (receta `social-auth-rest`) y **no arrastres** `libs.firebase.auth` ni los repos GitLive.
- **El README está desactualizado.** Muestra una API aspiracional (`CustomLogin.AuthFlow`, `LoginConfig`, `registerProvider`) que **no existe** en el código. La API real es `initLoginKoin(config)` + `LoginLibraryConfig` + `authRoutesFlow(...)` + `AuthScreenSlots`. Guíate por el código, no por el README.
- **Paquete propio.** El código vive bajo `com.apptolast.customlogin` y los recursos generados bajo `login.custom_login.generated.resources` (`publicResClass = true`) — no bajo el paquete de tu app.
- **Apple es solo-iOS nativo** (en Android cae a web-OAuth); oculta el botón fuera de iOS. Cada proveedor se muestra solo si está activo en `LoginLibraryConfig`.
- **Sincroniza versiones.** La lib fija Koin/Nav/Compose propias (Koin 4.1.1, Nav 2.9.1, Compose 1.9.3 en BaseLogin); alinea con las de tu app vía BOM/catálogo para evitar choques de clases duplicadas.

Fuente: `apptolast/BaseLogin` → `custom-login/` (`build.gradle.kts`, `settings.gradle.kts`, `di/LoginLibraryConfig.kt`, `di/KoinInitializer.kt`, `di/PresentationModule.kt`, `presentation/slots/AuthSlots.kt`, `presentation/navigation/RootNavGraph.kt`).
