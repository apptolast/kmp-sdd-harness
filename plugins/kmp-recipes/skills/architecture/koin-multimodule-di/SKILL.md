---
name: koin-multimodule-di
description: Úsala al cablear la inyección de dependencias con Koin en un monorepo KMP de AppToLast con `:shared` + `:consumerApp` + `:adminApp` — cuando montes los módulos Koin (Data/Presentation/Platform) de una app, definas `expect/actual platformModule`, arranques Koin (`initKoin()`) por plataforma (Android/iOS/Web), enlaces implementaciones a interfaces (`singleOf(::X) bind Y::class`) o registres ViewModels (`viewModelOf`). Define el reparto de módulos canónico de la flota.
version: 0.1.0
---

# Receta: Koin en monorepo multi-módulo (`:shared` + `:consumerApp` + `:adminApp`)

Patrón **canónico** de DI de la flota. Cada **app** (`:consumerApp`, `:adminApp`) declara sus propios módulos Koin y arranca su propio `initKoin()`; `:shared` **no** declara módulos Koin — solo expone clases (services, repos, `TokenManager`, `FirestoreClient`…) que las apps cablean. Fuente: `apptolast/AllergenGuard` (gemelo estructural de inemsellar).

## Cuándo usarla
- Al montar el DI de una app nueva en el monorepo (o añadir un módulo `:adminApp`).
- Al repartir bindings entre Data / Presentation / Platform.
- Al definir un binding específico de plataforma (`expect/actual platformModule`).
- Al enganchar el arranque de Koin en el entry point de Android / iOS / Web.

## Principios
- **`:shared` sin Koin**: expone clases planas (constructor injection). Cada app las registra en su propio grafo. Así consumer y admin comparten `FirestoreClient`/`TokenManager` pero con ViewModels y platform bindings distintos.
- **Constructor injection siempre** (`get()` / `singleOf` / `viewModelOf`). Nunca field injection ni service locator.
- **Reparto por responsabilidad**: `dataModule` (red + repos + storage), `presentationModule` (ViewModels + controllers de UI), `platformModule` (`expect/actual`, bindings de SDK nativo).

## Cómo se hace

### 1. Data module — infra de red + repos, con qualifiers y `bind`
Dos `HttpClient` distintos van con `named(...)`. Cada repo Firestore se enlaza a su interfaz de dominio con `singleOf(::Impl) bind Interface::class`.
```kotlin
val dataModule = module {
    single { Json { ignoreUnknownKeys = true; prettyPrint = true } }

    // Red: cliente de Auth (sin Bearer) vs cliente de Firestore (con Bearer) — qualifiers distintos.
    single { TokenManager() }
    single(named("auth")) { createAuthHttpClient(get()) }
    single { FirebaseAuthService(get(named("auth"))) }
    single(named("firestore")) { createFirestoreHttpClient(get(), get(), get()) }
    single { FirestoreClient(get(named("firestore"))) }
    single { FirebaseStorageClient(get(named("firestore"))) }

    // Repos Firestore → interfaz de dominio.
    singleOf(::FirestoreIngredientRepository) bind IngredientRepository::class
    singleOf(::FirestoreRestaurantRepository) bind RestaurantRepository::class
    singleOf(::FirebaseAuthRepository) bind AuthRepository::class
    // …

    // Estado compartido / preferencias locales.
    single { CurrentAccountHolder() }
    single { ThemePreferences() }
}
```
`get(named("auth"))` resuelve el cliente correcto por qualifier. `singleOf(::X)` infiere el constructor; `bind Y::class` publica la interfaz para que los consumidores dependan del dominio, no de la impl.

### 2. Presentation module — ViewModels
`viewModelOf(::VM)` para constructores sin parámetros de runtime; `viewModel { (arg) -> VM(get(), …, arg) }` cuando el ViewModel recibe un id de navegación.
```kotlin
val presentationModule = module {
    single { SnackbarController() }
    viewModelOf(::DashboardViewModel)
    viewModelOf(::IngredientsViewModel)
    // ViewModel parametrizado con un id de ruta:
    viewModel { (restaurantId: String) -> RecipesViewModel(get(), get(), get(), restaurantId) }
}
```
En Compose se resuelven con `koinViewModel()` (y `parametersOf(id)` para los parametrizados).

### 3. Platform module — `expect/actual`
Un `platformModule` por app para bindings solo-plataforma (SDK nativo: social auth, file handlers, PDF…). Hay **dos formas** en uso; elige una y sé consistente dentro de la app:

**Forma `val`** (consumer):
```kotlin
// commonMain
expect val platformModule: Module

// androidMain
actual val platformModule: Module = module {
    single<SocialAuthClient> { AndroidSocialAuthClient(androidContext()) }
}
// iosMain
actual val platformModule: Module = module {
    single<SocialAuthClient> { IosSocialAuthClient() }
}
```

**Forma `fun`** (admin — útil si el `actual` necesita lógica/argumentos):
```kotlin
// commonMain
expect fun platformModule(): Module
// webMain
actual fun platformModule(): Module = module {
    single<FileHandler> { WebFileHandler() }
    single<EmailSender> { WebEmailSender() }
}
```

### 4. `initKoin()` — punto de arranque común
Función en `commonMain` que agrupa los módulos. Acepta un `KoinAppDeclaration` opcional para que cada plataforma inyecte lo suyo (p. ej. `androidContext`).
```kotlin
// consumerApp/commonMain/di/AppModule.kt
fun initKoin(config: KoinAppDeclaration? = null) {
    startKoin {
        config?.invoke(this)
        modules(platformModule, firebaseModule, repositoryModule, viewModelModule)
    }
}
```
```kotlin
// adminApp/commonMain/di/KoinInitializer.kt
fun initKoin(appDeclaration: (KoinApplication.() -> Unit)? = null) {
    startKoin {
        appDeclaration?.invoke(this)
        modules(dataModule, presentationModule, platformModule()) // platformModule() = forma fun
    }
}
```

### 5. Llamar a `initKoin()` en cada entry point
**Android** — desde `Application.onCreate()`, pasando `androidContext` + `androidLogger`:
```kotlin
class MenuFrontendApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseConfig.databaseId = if (BuildConfig.DEBUG) "debug" else "(default)" // antes de initKoin
        initKoin {
            androidLogger()
            androidContext(this@MenuFrontendApplication)
        }
    }
}
```
**iOS** — función `initKoinIos()` invocada desde Swift antes de crear el `ComposeUIViewController`:
```kotlin
fun initKoinIos() {
    FirebaseConfig.databaseId = if (Platform.isDebugBinary) "debug" else "(default)"
    initKoin()
}
fun MainViewController() = ComposeUIViewController { App() }
```
**Web (js/wasmJs)** — desde `main()`, con guarda de idempotencia:
```kotlin
fun main() {
    if (GlobalContext.getOrNull() == null) initKoin()
    ComposeViewport(document.body!!) { App() }
}
```

## Gotchas
- **`androidContext` obligatorio**: bindings Android que lo usan (`AndroidSocialAuthClient(androidContext())`, prefs) fallan si `initKoin` no recibió `androidContext(this@App)` desde el `Application`. Regístralo en el bloque `config`, no en el módulo común.
- **Guarda en Web**: hot-reload/re-render puede reentrar `main()`; sin `if (GlobalContext.getOrNull() == null)` obtienes `KoinApplicationAlreadyStartedException`.
- **Orden `databaseId` → `initKoin`**: fija `FirebaseConfig.databaseId` **antes** de `initKoin` (antes de crear el `FirestoreClient`), o el primer acceso pega a la base equivocada.
- **`single` vs `singleOf`**: usa `singleOf(::X)` solo si todas las deps se resuelven por tipo. Si hay qualifier (`named`) o parámetro, usa `single { X(get(named("…")), get()) }` explícito.
- **`bind` para publicar la interfaz**: sin `bind Interface::class`, `singleOf(::Impl)` registra solo el tipo concreto; los consumidores que piden la interfaz de dominio no la encuentran.
- **`:shared` no arranca Koin**: no metas `startKoin`/módulos en `:shared`. Cada app dueña de su grafo; duplicar el arranque provoca `AlreadyStarted` o grafos en conflicto.
- **Dos formas de `platformModule`**: `val` y `fun` no son intercambiables entre `expect`/`actual`. Mantén la misma forma en todas las plataformas de una misma app.
- **ViewModels parametrizados**: para VMs con id de ruta usa `viewModel { (id: String) -> VM(get(), id) }` + `koinViewModel { parametersOf(id) }`; `viewModelOf` no admite el argumento de runtime.

## Fuente
- Repo: `apptolast/AllergenGuard` (gemelo estructural de inemsellar).
- Rutas:
  - Consumer: `consumerApp/src/commonMain/kotlin/com/apptolast/menufrontend/di/AppModule.kt` (módulos + `initKoin`), `di/PlatformModule.kt` (`expect val`), `androidMain/di/PlatformModule.android.kt`, `iosMain/di/PlatformModule.ios.kt`; entry points `androidMain/MenuFrontendApplication.kt`, `iosMain/MainViewController.kt`.
  - Admin: `adminApp/src/commonMain/kotlin/org/apptolast/menuadmin/di/{DataModule,PresentationModule,PlatformModule,KoinInitializer}.kt`, `webMain/di/PlatformModule.web.kt` (`actual fun`), `webMain/main.kt`.
- Acceso: `gh api repos/apptolast/AllergenGuard/contents/<ruta> -q .content | base64 -d`
