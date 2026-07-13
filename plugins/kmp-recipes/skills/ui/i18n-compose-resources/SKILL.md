---
name: i18n-compose-resources
description: Úsala al internacionalizar UI en proyectos KMP/CMP de AppToLast — cuando externalices strings, añadas un idioma, uses placeholders `%1$s`/`%d`, o necesites cambiar el idioma en runtime independientemente del sistema. Define el patrón canónico: Compose Multiplatform Resources (`composeResources/values*/strings.xml` + `stringResource(Res.string.xxx)`) y el override de locale con `LocalAppLocale`. NADA de moko-resources.
version: 0.1.0
---

# Receta: i18n con Compose Multiplatform Resources

Patrón **canónico** de i18n de la flota. Sistema oficial de JetBrains (`org.jetbrains.compose.resources`),
**sin moko-resources**. Strings en `composeResources/values*/strings.xml`, acceso type-safe por
`stringResource(Res.string.xxx)`, y override de idioma en runtime con `LocalAppLocale` (expect/actual).

Fuente: `apptolast/AllergenGuard` (`consumerApp` móvil + `adminApp` web).

## Cuándo usarla
- Al externalizar cualquier string de UI (regla: **cero strings hardcodeados** en composables).
- Al añadir un idioma nuevo (crear la carpeta `values-<lang>/`).
- Al necesitar un selector de idioma **in-app** que ignore el locale del sistema.

## Cómo se hace

### 1. Estructura de recursos (por módulo: consumer y admin cada uno el suyo)
```
<módulo>/src/commonMain/composeResources/
  values/strings.xml        # idioma por defecto (aquí: español)
  values-en/strings.xml     # inglés (fallback)
  font/…, drawable/…        # otros recursos multiplataforma
```
El idioma de `values/` es el **fallback global**: si una clave falta en `values-en/`, se usa la de
`values/`. Cada módulo (`consumerApp`, `adminApp`) tiene sus propios `composeResources` y su propio
objeto `Res` generado — **no se comparten**.

### 2. `strings.xml` — claves + placeholders
```xml
<!-- values/strings.xml (español, defecto) -->
<resources>
    <string name="app_name" translatable="false">Allergen Guard</string>
    <string name="login_button">Iniciar Sesión</string>
    <string name="login_google_button">Continuar con Google</string>
    <string name="home_dishes_count">%d platos</string>
    <string name="home_reviews_count">%d reseñas</string>
</resources>
```
```xml
<!-- values-en/strings.xml (inglés) -->
<resources>
    <string name="login_button">Sign In</string>
    <string name="login_google_button">Continue with Google</string>
    <string name="home_dishes_count">%d dishes</string>
</resources>
```
- Marca con `translatable="false"` lo que no se traduce (nombre de la app, marcas).
- Placeholders posicionales: `%1$s` / `%2$s` (texto), `%d` (entero). Úsalos siempre para contenido
  dinámico, nunca concatenes strings en el composable.

### 3. Uso en composables — `stringResource(Res.string.xxx)`
```kotlin
import org.jetbrains.compose.resources.stringResource
import com.apptolast.menufrontend.resources.Res       // Res del módulo consumer
import com.apptolast.menufrontend.resources.login_button
import com.apptolast.menufrontend.resources.home_dishes_count

Text(stringResource(Res.string.login_button))
Text(stringResource(Res.string.home_dishes_count, dishCount))  // rellena el %d
```
El `Res` se importa desde el paquete `<...>.resources` del **módulo** en que estás (el admin usa su
propio `Res`). Tras editar `strings.xml`, regenera con un build de Gradle para que aparezcan las claves.

### 4. Override de idioma en runtime — `LocalAppLocale` (expect/actual)
Patrón oficial JetBrains ("manage local resource environment"). Un `CompositionLocal` que fuerza el
idioma con el que resuelven los `stringResource`, independiente del locale del sistema. `null` = seguir
al sistema. **El mismo archivo se replica en cada módulo** (consumer y admin), con actuals por plataforma.

```kotlin
// commonMain — igual en consumer y admin
expect object LocalAppLocale {
    val current: String @Composable get
    @Composable infix fun provides(value: String?): ProvidedValue<*>
}

@Composable
fun AppEnvironment(locale: String?, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppLocale provides locale) {
        key(locale) { content() }   // key(locale) recompone el subárbol al cambiar de idioma
    }
}
```
```kotlin
// androidMain — cambia el Locale de la Configuration
actual object LocalAppLocale {
    private var default: Locale? = null
    actual val current: String @Composable get() = Locale.getDefault().toString()
    @Composable actual infix fun provides(value: String?): ProvidedValue<*> {
        val configuration = LocalConfiguration.current
        if (default == null) default = Locale.getDefault()
        val new = if (value == null) default!! else Locale(value)
        Locale.setDefault(new)
        configuration.setLocale(new)
        val resources = LocalContext.current.resources
        resources.updateConfiguration(configuration, resources.displayMetrics)
        return LocalConfiguration.provides(configuration)
    }
}
```
```kotlin
// webMain (js+wasmJs) — expone el locale a navigator.languages vía window.__customLocale,
// que un locale-override.js (cargado en index.html ANTES de la app) lee.
actual object LocalAppLocale {
    private val delegate = staticCompositionLocalOf { Locale.current }
    actual val current: String @Composable get() = delegate.current.toString()
    @Composable actual infix fun provides(value: String?): ProvidedValue<*> {
        setCustomLocale(value?.replace('_', '-').orEmpty())
        return delegate.provides(Locale.current)
    }
}
private fun setCustomLocale(value: String) =
    js("(function(){ window.__customLocale = value && value.length ? value : null; })()")
```
Envuelve la raíz de la app con `AppEnvironment(locale = userLocale) { … }` para aplicar el idioma
elegido por el usuario.

## Gotchas
- **`values/` es el fallback, no un idioma más.** Pon ahí el idioma primario (español) completo; los
  `values-<lang>/` pueden ser parciales y caen a `values/` para las claves que falten.
- **`Res` es por módulo.** Importa el `Res` del paquete `resources` del módulo actual; no reutilices el
  del admin en el consumer ni viceversa. Cada uno duplica su `strings.xml` y su `LocalAppLocale`.
- **`key(locale)` es imprescindible** en `AppEnvironment`: sin él, los strings ya leídos no se
  re-resuelven al cambiar de idioma y la UI se queda en el idioma anterior.
- **Web necesita `locale-override.js` en `index.html` antes de cargar la app**, o `window.__customLocale`
  no existe cuando Compose lee `navigator.languages`.
- **Placeholders posicionales** (`%1$s`, `%d`) — no concatenes ni interpoles en Kotlin; pásalos como
  args de `stringResource(...)` para respetar el orden por idioma.
- **Regenera tras editar XML**: las claves nuevas no existen en `Res` hasta correr un build de Gradle.

Fuente: `apptolast/AllergenGuard` — `consumerApp/.../composeResources/values{,-en}/strings.xml`,
`core/i18n/LocalAppLocale.kt` (+ `.android.kt`), `adminApp/.../i18n/LocalAppLocale.web.kt`.
