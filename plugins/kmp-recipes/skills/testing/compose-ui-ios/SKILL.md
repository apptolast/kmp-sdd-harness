---
name: compose-ui-ios
description: Úsala al escribir tests de UI de Compose Multiplatform sin dispositivo en un proyecto KMP/CMP de AppToLast (semántica y accesibilidad, áreas táctiles de 48 dp, texto que no se corta con la fuente al 200 %, móvil y tableta, navegación con los ViewModels reales) o al sacar capturas PNG de los composables con el tema real para un PR. Corren en `iosSimulatorArm64Test` con `org.jetbrains.compose.ui:ui-test` (API v2). Incluye los gotchas del Keychain en los tests de iOS y del APK de tests instrumentados con AGP 9.
version: 0.1.0
---

# Receta: tests de UI de Compose en `iosTest`, sin dispositivo

Patrón **canónico** de la flota para probar lo que pinta Compose sin emulador ni simulador manejado: los tests
de semántica (`runComposeUiTest`) viven en `iosTest` y corren en `iosSimulatorArm64Test`, con el tema, las
fuentes y los Compose Resources reales. El mismo arnés dibuja los composables a PNG para la revisión de un PR.

Fuente: una app KMP de la flota (CMP 1.12, AGP 9, Android + iOS) con tests de componentes, pantallas y
navegación en `iosTest`; engram `testing/kmp-ios-android-test-gotchas`.

## Cuándo usarla
- Probar un componente o un `XContent` sin estado: textos, roles, encabezados, `contentDescription`, regiones
  vivas, clics y estados habilitado o deshabilitado.
- Comprobar las áreas táctiles de 48 dp, el texto con la fuente al 200 % y la disposición en móvil y en tableta
  (`sdd-flow:kmp-compose-rules`, «Pantallas adaptativas»).
- Probar la raíz y la navegación con los ViewModels reales sobre un Koin de fakes.
- Sacar capturas de cada estado, en claro y en oscuro, para un PR.

## Por qué en `iosTest` y no en `commonTest`
- En Android, `runComposeUiTest` necesita un test instrumentado o Robolectric. En `commonTest` también se
  compila para el host de Android, y `testAndroidHostTest` falla.
- `iosSimulatorArm64Test` lo ejecuta con Skia y sin pantalla: es un check rápido de los guardarraíles, no
  maneja un simulador y no necesita aprobación.
- La lógica sigue en `commonTest` (ViewModels, funciones puras como la elección de disposición); `iosTest` solo
  prueba lo que pinta Compose.

## Cómo se hace

### 1. La dependencia, solo en `iosTest`

```toml
# gradle/libs.versions.toml: the version of Compose Multiplatform
compose-uiTest = { module = "org.jetbrains.compose.ui:ui-test", version.ref = "composeMultiplatform" }
```

```kotlin
// shared/build.gradle.kts
sourceSets {
    iosTest.dependencies {
        // runComposeUiTest only runs on iOS: the Android host has no Robolectric.
        implementation(libs.compose.uiTest)
    }
}
```

### 2. Un test de semántica

```kotlin
import androidx.compose.ui.test.assert // .assert(matcher) needs this explicit import
import androidx.compose.ui.test.v2.runComposeUiTest // the v1 one is deprecated in CMP 1.12

@OptIn(ExperimentalTestApi::class)
class AppButtonTest {
    @Test
    fun `AC6 while loading it shows its text ignores taps and is announced politely`() =
        runComposeUiTest {
            var clicks = 0
            setContent { AppTheme { AppButton(text = LOADING, onClick = { clicks++ }, loading = true) } }

            onNodeWithText(LOADING)
                .assertIsNotEnabled()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
                .performClick()

            assertEquals(0, clicks)
        }

    private companion object {
        const val LOADING = "Signing in…"
    }
}
```

- Un componente recibe sus textos: el test le pasa los suyos. Una pantalla los saca de los Compose Resources:
  el cuerpo de `runComposeUiTest` es `suspend`, así que búscalos con `getString(Res.string.x)` y no con el
  literal, y el test vale en cualquier idioma. El simulador corre en inglés (`values/`).
- La v2 usa `StandardTestDispatcher`: los efectos se encolan, no corren al momento. Las aserciones esperan al
  reposo; si cambias un estado desde fuera de Compose (un fake), la siguiente aserción ya lo ve.
- La escena ya da `ViewModelStoreOwner` y `LifecycleOwner`: `NavHost`, `koinViewModel()` y
  `collectAsStateWithLifecycle()` funcionan. Para la raíz, `startKoin` con el `presentationModule` real y fakes
  en `@BeforeTest`, `Dispatchers.setMain(UnconfinedTestDispatcher())` para que corra `viewModelScope`, y
  `stopKoin()` y `resetMain()` en `@AfterTest`.

### 3. 48 dp, medidos sobre el nodo

```kotlin
// TouchTarget.min: the 48 dp token of the theme.
onNodeWithText("Ok").assertHeightIsAtLeast(TouchTarget.min).assertWidthIsAtLeast(TouchTarget.min)
```

No midas con `touchBoundsInRoot`: Compose estira hasta 48 dp el área táctil de **cualquier** nodo pulsable, y
un texto pulsable de 29 dp pasaría. El `Button` de Material 3 dibuja 40 dp y solo cumple por esa área táctil:
un componente propio que lo envuelve necesita `heightIn(min = …)` con el token, o el test del nodo falla.

### 4. Texto que no se corta con la fuente al 200 %

```kotlin
setContent {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
        AppTheme {
            // The width the field gets on a phone: the screen minus its gutters.
            Box(Modifier.width(360.dp).padding(horizontal = Spacing.screen)) {
                AppTextField(state = rememberTextFieldState(), label = LABEL, placeholder = PLACEHOLDER)
            }
        }
    }
}

val layouts = mutableListOf<TextLayoutResult>()
onNodeWithText(PLACEHOLDER, useUnmergedTree = true)
    .fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
assertFalse(layouts.first().hasVisualOverflow, "The placeholder is cut: ${layouts.first().lineCount} line(s)")
```

Un placeholder o una etiqueta con `maxLines = 1` se corta al 200 %: deja que parta en líneas, con el control
creciendo (`heightIn(min = …)`), y deja la línea única solo para lo que escribe el usuario, que se desplaza.

### 5. Móvil y tableta
- La ventana de `runComposeUiTest` mide 1024 × 768 dp a densidad 1: una tableta en horizontal.
- Lo que decide `BoxWithConstraints` se prueba con un marco: `Box(Modifier.size(360.dp, 640.dp)) { … }`.
- Lo que decide `currentWindowAdaptiveInfo()` mira la ventana (`LocalWindowInfo.containerSize`), no el marco:
  cambia la ventana con `v2.runSkikoComposeUiTest(size = Size(360f, 800f))`. El tamaño va en píxeles (dp ×
  densidad).
- Un test por anchura y por disposición; la función pura que elige la disposición, en `commonTest`.

### 6. Capturas PNG para un PR
Un test **desechable** en `iosTest`, que no se commitea, dibuja cada estado y lo guarda en el disco del Mac (el
proceso del simulador escribe en rutas del host). Las capturas no las compara ningún test: la referencia sigue
siendo el código, las previews y los tests de semántica.

```kotlin
@OptIn(ExperimentalTestApi::class, ExperimentalForeignApi::class, BetaInteropApi::class)
class CaptureTmpTest {
    @Test
    fun capture() =
        // 390 × 844 dp at density 2; the size is in px. fontScale = 2f for the 200 % capture.
        runSkikoComposeUiTest(size = Size(390f * 2, 844f * 2), density = Density(2f, fontScale = 1f)) {
            // Compose Resources picks the language from NSLocale.preferredLanguages on every call.
            NSUserDefaults.standardUserDefaults.setObject(listOf("es-ES"), forKey = "AppleLanguages")
            try {
                setContent { AppTheme(darkTheme = true) { LoginContent(state = previewState, onAction = {}) } }
                savePng(captureToImage(), "$OUT/login-oscuro.png") // OUT: an absolute path in the repo
            } finally {
                NSUserDefaults.standardUserDefaults.removeObjectForKey("AppleLanguages")
            }
        }
}

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
private fun savePng(image: ImageBitmap, path: String) {
    val bytes = checkNotNull(Image.makeFromBitmap(image.asSkiaBitmap()).encodeToData(EncodedImageFormat.PNG)).bytes
    val data = bytes.usePinned { NSData.create(bytes = it.addressOf(0), length = bytes.size.convert()) }
    check(data.writeToFile(path, atomically = true)) { "Could not write $path" }
}
```

- Se lanza con `./gradlew :shared:iosSimulatorArm64Test --tests '<paquete>.CaptureTmpTest'` y se borra después.
- `runSkikoComposeUiTest`, de `androidx.compose.ui.test.v2`; `asSkiaBitmap()`, de `androidx.compose.ui.graphics`;
  `Image` y `EncodedImageFormat`, de `org.jetbrains.skia`.
- Los PNG van a `docs/design/<feature>/`, con un README que diga de dónde salen, a qué tamaño y cómo se
  regeneran. Sin barra de estado ni teclado; una animación infinita (un spinner) sale en el fotograma capturado.

## Gotchas
- **Keychain en `iosSimulatorArm64Test`**: `SecItemAdd` devuelve `errSecNotAvailable` (−25291) aunque enlaces
  entitlements con `-sectcreate`, y firmar el `test.kexe` con ellos lo mata (código 137); es KT-61470. Pon
  `SecItem*` detrás de un port pequeño con un fake (receta `rest-rotating-refresh-session`) y prueba el real
  solo en un simulador arrancado o un dispositivo, con aprobación.
- **AGP 9 con `com.android.kotlin.multiplatform.library`**: `withDeviceTestBuilder { sourceSetTreeName = "test" }`
  mete **todo** `commonTest` en el APK instrumentado, y D8, con `minSdk` < 30, rechaza los nombres de test con
  espacios. Dale al test de dispositivo su propio árbol y su `kotlin-test`:

  ```kotlin
  kotlin {
      android {
          // Own source set tree, without commonTest: D8 rejects spaces in names below minSdk 30.
          withDeviceTestBuilder {}.configure { instrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
      }
      sourceSets {
          getByName("androidDeviceTest").dependencies {
              implementation(libs.kotlin.test) // brings kotlin-test-junit for the runner
              implementation(libs.androidx.testRunner)
          }
      }
  }
  ```

  Los nombres de `androidDeviceTest` van sin espacios. Compruébalo con `assembleAndroidDeviceTest` del módulo,
  que no necesita dispositivo.
- **Nombres con backticks en Kotlin/Native**: sin comas, puntos, dos puntos, punto y coma, barras, corchetes
  ni `<` `>`: «1500 ms», no «1.5 s».
- **`.assert(matcher)`** sobre un nodo necesita su import explícito, `androidx.compose.ui.test.assert`.
- **Android Studio abierto** puede regenerar `shared/build/generated/compose` a medias y romper
  `compileAndroidMain`: borra ese directorio y vuelve a compilar.

## Fuente
Una app KMP de la flota: los tests de componentes, del acceso y de la navegación de `shared/src/iosTest`, su
`build.gradle.kts` (`iosTest`, `androidDeviceTest`) y el README de sus capturas de diseño. Engram:
`testing/kmp-ios-android-test-gotchas`.
