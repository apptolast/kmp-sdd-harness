---
name: navigation-type-safe-routes
description: Úsala al montar navegación en un proyecto KMP/CMP de AppToLast con Navigation Compose Multiplatform — cuando definas rutas type-safe con @Serializable, grafos anidados (RootNavGraph/authRoutesFlow), transiciones compartidas (NavTransitions), el DSL composable<Route>, lectura de argumentos con toRoute, o un NavType custom para objetos complejos.
version: 0.1.0
---

# Receta: navegación type-safe (Navigation Compose Multiplatform)

Patrón **canónico** de navegación: rutas `@Serializable`, grafos anidados como extensiones de `NavGraphBuilder`, y transiciones compartidas. Fuente: `apptolast/BaseLogin` (`:custom-login` + `:composeApp`, `presentation/navigation/`). Requiere `navigation-compose` 2.9.x + plugin `kotlinx-serialization`.

## Cuándo usarla
- Al crear `Routes.kt` y el `NavHost` de una feature/app KMP.
- Al organizar grafos anidados (p.ej. flujo de auth vs. flujo principal) y navegar entre ellos.
- Al pasar argumentos entre destinos (primitivos, o un objeto complejo vía NavType custom).

## Cómo se hace

### 1. `Routes.kt`: rutas como `@Serializable`
`data object` para destinos sin argumentos; `data class` cuando lleva parámetros. El **grafo anidado** es también una ruta (`data object`):

```kotlin
// presentation/navigation/Routes.kt
import kotlinx.serialization.Serializable

@Serializable data object AuthRoutesFlow          // grafo anidado
@Serializable data object WelcomeRoute
@Serializable data object LoginRoute
@Serializable data class ResetPasswordRoute(val resetCode: String)  // con argumento
```

### 2. Grafo anidado como extensión de `NavGraphBuilder`
Encapsula cada flujo en una función `NavGraphBuilder.xxxFlow(...)` con `navigation<Grafo>(startDestination) { composable<Route> { … } }`:

```kotlin
fun NavGraphBuilder.authRoutesFlow(
    navController: NavHostController,
    startDestination: Any = WelcomeRoute,
    onNavigateToHome: () -> Unit = {},
) {
    navigation<AuthRoutesFlow>(startDestination = startDestination) {
        composable<WelcomeRoute> { WelcomeScreen(onNavigateToLogin = {
            navController.navigate(LoginRoute) { launchSingleTop = true }
        }) }
        composable<LoginRoute> { LoginScreen(onNavigateToHome = onNavigateToHome) }
    }
}
```

### 3. Leer argumentos con `toRoute<Route>()`
Reconstruye la ruta tipada desde el `backStackEntry`:

```kotlin
composable<ResetPasswordRoute> { backStackEntry ->
    val route = backStackEntry.toRoute<ResetPasswordRoute>()
    ResetPasswordScreen(resetCode = route.resetCode)
}
```

### 4. `NavHost` + transiciones compartidas
Centraliza las animaciones en un `object NavTransitions` (slide + fade) y aplícalas en el `NavHost`:

```kotlin
NavHost(
    navController = navController,
    startDestination = AuthRoutesFlow,
    enterTransition = { NavTransitions.enter },
    exitTransition = { NavTransitions.exit },
    popEnterTransition = { NavTransitions.popEnter },
    popExitTransition = { NavTransitions.popExit },
) {
    authRoutesFlow(navController, startDestination = LoginRoute)
    mainRoutesFlow()   // otro grafo anidado
}
```

`NavTransitions` (`slideInHorizontally + fadeIn`, etc.) también se reutiliza en `AnimatedContent` para conmutar grafos según `AuthState` (auth vs. app principal) con un feel consistente.

### 5. Navegar: `popUpTo` / `launchSingleTop` / `inclusive`
Controla el back-stack de forma type-safe (pasando la **instancia** de ruta, no strings):

```kotlin
navController.navigate(LoginRoute) {
    popUpTo(AuthRoutesFlow) { inclusive = true }  // limpia todo el grafo anidado
    launchSingleTop = true
}
```

### 6. Objetos complejos: NavType custom (escape hatch)
BaseLogin solo pasa **primitivos** (`String resetCode`), así que no necesita NavType custom. Para un objeto complejo, decláralo `@Serializable`, define un `NavType` que serialice/parsee a JSON y pásalo en `typeMap`:

```kotlin
val ItemNavType = object : NavType<Item>(isNullableAllowed = false) {
    override fun get(bundle: Bundle, key: String) = Json.decodeFromString<Item>(bundle.getString(key)!!)
    override fun parseValue(value: String) = Json.decodeFromString<Item>(value)
    override fun serializeAsValue(value: Item) = Json.encodeToString(value)
    override fun put(bundle: Bundle, key: String, value: Item) = bundle.putString(key, Json.encodeToString(value))
}
// composable<DetailRoute>(typeMap = mapOf(typeOf<Item>() to ItemNavType)) { … }
```

Prefiere pasar un **id** primitivo y recargar desde el repo antes que serializar objetos grandes en la ruta.

## Gotchas
- **Falta el plugin de serialización = no compila.** Toda ruta debe ser `@Serializable`; aplica `kotlinx-serialization` en el módulo o `composable<Route>`/`toRoute` fallan.
- **`startDestination` es una instancia, no una `KClass`.** Pasa `LoginRoute` (el objeto), no `LoginRoute::class`. El grafo anidado (`AuthRoutesFlow`) es a la vez una ruta y el ancla para `popUpTo`.
- **Grafos anidados = funciones de extensión**, no clases: `fun NavGraphBuilder.xxxFlow()`. Mantiene `Routes.kt` fino y cada flujo autocontenido y testeable.
- **Transiciones en un solo sitio.** Define `NavTransitions` una vez y reúsalo en `NavHost` y en `AnimatedContent`; evita animaciones divergentes entre pantallas.
- **`popUpTo(Grafo){inclusive=true}`** limpia el flujo completo (p.ej. al pasar de auth a app tras login); no basta con `popUpTo(pantalla)`.

Fuente: `apptolast/BaseLogin` → `custom-login/src/commonMain/.../presentation/navigation/` (`Routes.kt`, `RootNavGraph.kt`, `NavTransitions.kt`) y `composeApp/src/commonMain/.../App.kt` + `presentation/navigation/`.
