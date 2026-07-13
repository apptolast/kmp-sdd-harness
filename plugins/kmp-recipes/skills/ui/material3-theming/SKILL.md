---
name: material3-theming
description: Úsala al montar el tema Material 3 en proyectos KMP/CMP de AppToLast — cuando definas paleta (light+dark), tipografía con fuentes propias, un tema que conmuta por `isSystemInDarkTheme()` o preferencia persistida, colores semánticos fuera de `ColorScheme` (ExtendedColors/DomainColors), o cuando vayas a poner un color/tamaño. Regla de oro: siempre `MaterialTheme.colorScheme`/`typography`, nada hardcodeado, spacing en múltiplos de 4dp.
version: 0.1.0
---

# Receta: theming Material 3 (Color / Theme / Type + colores extendidos)

Patrón **canónico** de theming de la flota. Tres archivos en `presentation/theme` (o `core/theme`):
`Color.kt` (paleta light+dark), `Theme.kt` (`<Proyecto>Theme` que conmuta por `isSystemInDarkTheme()`),
`Type.kt` (tipografía con fuentes de `composeResources/font`). Colores semánticos que no caben en
`ColorScheme` van en un `ExtendedColors`/`DomainColors` provisto por `CompositionLocal`.

Fuente: `apptolast/AllergenGuard` (`consumerApp` + `adminApp` + `:shared` para la preferencia persistida).

## Cuándo usarla
- Al crear el tema de una app nueva o revisar uno existente.
- Cuando necesites colores semánticos propios (estados safe/danger, chips…) adaptados a dark mode.
- Al añadir un toggle de modo oscuro persistido, en vez de solo seguir al sistema.
- **Siempre que vayas a poner un color o un tamaño**: úsalos desde el tema, no como literales.

## Cómo se hace

### 1. `Color.kt` — tokens crudos (constantes `Color`), light y dark
```kotlin
val Blue500 = Color(0xFF3B82F6)
val White = Color(0xFFFFFFFF)
val TextPrimary = Color(0xFF1A1A2E)
// Canvas vs surface: las cards (surface) van sobre un canvas (background) distinto para que resalten.
val CanvasLight = Color(0xFFF1F5F9)
val SurfaceVariantLight = Color(0xFFEDF1F6)
val CanvasDark = Color(0xFF12121E)
val SurfaceDark = Color(0xFF20203A)
```
Solo constantes; el mapeo a roles Material vive en `Theme.kt`.

### 2. `Theme.kt` — `lightColorScheme`/`darkColorScheme` + composable del tema
```kotlin
private val LightColorScheme = lightColorScheme(
    primary = Blue500, onPrimary = White,
    background = CanvasLight, onBackground = TextPrimary,
    surface = White, onSurface = TextPrimary,
    surfaceVariant = SurfaceVariantLight, onSurfaceVariant = TextSecondary,
    error = DangerRed, errorContainer = DangerRedContainer, /* … */
)
private val DarkColorScheme = darkColorScheme(
    primary = Blue500, onPrimary = White,
    background = CanvasDark, onBackground = White,
    surface = SurfaceDark, onSurface = White, /* … */
)

@Composable
fun AllergenGuardTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),   // sobre-escribible por preferencia persistida
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    val extendedColors = if (darkTheme) DarkExtendedColors else LightExtendedColors
    CompositionLocalProvider(LocalExtendedColors provides extendedColors) {
        MaterialTheme(colorScheme = colorScheme, typography = DmSansTypography(), content = content)
    }
}
```

### 3. `Type.kt` — tipografía con fuente propia desde `composeResources/font`
```kotlin
@Composable
fun DmSansFontFamily(): FontFamily = FontFamily(
    Font(Res.font.dm_sans_regular, FontWeight.Normal),
    Font(Res.font.dm_sans_medium, FontWeight.Medium),
    Font(Res.font.dm_sans_semibold, FontWeight.SemiBold),
    Font(Res.font.dm_sans_bold, FontWeight.Bold),
)

@Composable
fun DmSansTypography(): Typography {
    val fontFamily = DmSansFontFamily()
    val default = Typography()
    return Typography(
        titleLarge = default.titleLarge.copy(fontFamily = fontFamily),
        bodyMedium = default.bodyMedium.copy(fontFamily = fontFamily),
        labelSmall = default.labelSmall.copy(fontFamily = fontFamily),
        /* … copia fontFamily en todos los estilos … */
    )
}
```
Parte de `Typography()` y sobre-escribe `fontFamily` conservando tamaños/pesos Material.

### 4. Colores extendidos — lo que no cabe en `ColorScheme`
Colores semánticos propios (safe/danger, chips) por tema, en un `@Immutable data class` provisto por
`staticCompositionLocalOf`, para que **también se adapten a dark mode** en vez de un literal fijo.
```kotlin
@Immutable
data class ExtendedColors(
    val safe: Color, val safeContainer: Color, val onSafeContainer: Color,
    val danger: Color, val dangerContainer: Color, val warning: Color, /* … */
)
val LightExtendedColors = ExtendedColors(safe = Color(0xFF16A34A), /* … */)
val DarkExtendedColors  = ExtendedColors(safe = Color(0xFF4ADE80), /* pops en dark … */)

val LocalExtendedColors = staticCompositionLocalOf { LightExtendedColors }

/** Accesor: `MaterialTheme.extendedColors.safeContainer`. */
val MaterialTheme.extendedColors: ExtendedColors
    @Composable @ReadOnlyComposable get() = LocalExtendedColors.current
```
**Variante `DomainColors`** (colores derivados de enums de dominio): mantenlos **fuera** del módulo
`:shared` (domain+data no debe depender de Compose). El dominio lleva un `Long` ARGB (`colorArgb`) y la
extensión Compose vive en `presentation/theme`:
```kotlin
val AllergenType.color: Color get() = Color(colorArgb)  // en adminApp/presentation/theme, no en :shared
```

### 5. Preferencia de dark mode persistida (opcional) — `ThemePreferences`
`multiplatform-settings` + `StateFlow`; se colecta y se pasa al `darkTheme` del tema.
```kotlin
class ThemePreferences(private val settings: Settings = Settings()) {
    private val _isDarkTheme = MutableStateFlow(settings.getBoolean(KEY_DARK_THEME, false))
    val isDarkThemeFlow: StateFlow<Boolean> = _isDarkTheme.asStateFlow()
    var isDarkTheme: Boolean
        get() = _isDarkTheme.value
        set(value) { settings.putBoolean(KEY_DARK_THEME, value); _isDarkTheme.value = value }
    private companion object { const val KEY_DARK_THEME = "dark_theme" }
}
// AllergenGuardTheme(darkTheme = themePrefs.isDarkThemeFlow.collectAsState().value) { App() }
```

## Gotchas
- **Nunca hardcodees color ni tamaño en composables.** Usa `MaterialTheme.colorScheme.*`,
  `MaterialTheme.typography.*` y `MaterialTheme.extendedColors.*`. Los literales `Color(0x…)` solo viven
  en `Color.kt`/`ExtendedColors.kt`.
- **`ExtendedColors` debe existir para light Y dark** y proveerse dentro del `if (darkTheme)`; si dejas
  un solo set, los colores semánticos no cambian en modo oscuro.
- **`staticCompositionLocalOf` (no `compositionLocalOf`)** para los extended colors: cambian en bloque al
  reprovisionarse, no necesitan lectura reactiva granular.
- **`DomainColors` fuera de `:shared`.** El domain lleva `colorArgb: Long`; la conversión a `Color` es
  una extensión en `presentation/theme`, así `:shared` no arrastra Compose (importante para wasmJs).
- **Fuentes vía `composeResources/font` + `org.jetbrains.compose.resources.Font`**, no `androidx…Font`;
  y `DmSansTypography()`/`DmSansFontFamily()` son `@Composable` porque `Res.font.*` lo requiere.
- **Spacing en múltiplos de 4dp** (4/8/12/16/24/32) y radios Small 8 / Medium 12 / Large 16-24dp.
- **Preferencia persistida** conmuta el tema pasando `darkTheme` explícito; no dependas solo de
  `isSystemInDarkTheme()` si ofreces toggle in-app.

Fuente: `apptolast/AllergenGuard` — `consumerApp/.../core/theme/{Color,Theme,Type,ExtendedColors}.kt`,
`adminApp/.../presentation/theme/DomainColors.kt`, `shared/.../data/local/ThemePreferences.kt`.
