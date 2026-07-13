---
name: webview-expect-actual
description: Úsala al necesitar mostrar una URL DENTRO de la app (no abrir el navegador externo) en proyectos KMP/CMP de AppToLast — política de privacidad, blog, IA SEPE, cualquier página web embebida. Define el patrón canónico `WebViewComposable` expect/actual: expect en commonMain, `WebView`+`AndroidView` en androidMain, `WKWebView`+`UIKitView` en iosMain. Cubre carga de URL, JavaScript, estado de carga y navegación atrás. Resuelve el TODO de inemsellar "WebView específico de plataforma".
version: 0.1.0
---

# Receta: WebView multiplataforma (expect/actual)

Patrón **canónico** para embeber páginas web en apps KMP/CMP de AppToLast. Fuente: `LifetimeJournal` feature `privacypolicy` (`WebViewComposable` expect/actual + `PrivacyPolicyScreen`). Un solo composable `expect` en `commonMain`, `actual` mínimo por plataforma. **No hay librería multiplatform de WebView**: se usa el widget nativo de cada plataforma envuelto en interop de Compose.

## Cuándo usarla
- Mostrar una URL **dentro** de la app en vez de lanzar el navegador externo (el TODO pendiente de inemsellar: IA SEPE, blog, guías).
- Páginas legales/estáticas (política de privacidad, términos) con TopBar propia.
- Cualquier pantalla que renderice HTML remoto embebido.

## Cómo se hace

### 1. `commonMain` — declara el `expect` y envuélvelo en la pantalla
El `expect` recibe solo `url` + `Modifier`. La pantalla pone TopBar/Scaffold alrededor.

```kotlin
// commonMain — WebViewComposable.kt (o al final de la Screen)
@Composable
expect fun WebViewComposable(url: String, modifier: Modifier = Modifier)

@Composable
fun PrivacyPolicyScreen(url: String, modifier: Modifier = Modifier, onBack: () -> Unit = {}) {
    Scaffold(
        topBar = { BasicTopBar(title = stringResource(Res.string.settings_privacy_policy), onBack = onBack) },
        modifier = modifier,
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            WebViewComposable(url = url, modifier = Modifier.fillMaxSize())
        }
    }
}
```

### 2. `androidMain` — `AndroidView` + `WebView`
JavaScript se activa en `settings.javaScriptEnabled` (requiere `@SuppressLint("SetJavaScriptEnabled")`). El `WebViewClient` por defecto mantiene la navegación dentro del WebView (no la delega al navegador).

```kotlin
// androidMain — WebViewComposable.android.kt
@SuppressLint("SetJavaScriptEnabled")
@Composable
actual fun WebViewComposable(url: String, modifier: Modifier) {
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                webViewClient = WebViewClient()
                settings.javaScriptEnabled = true
                loadUrl(url)
            }
        },
        modifier = modifier,
    )
}
```
Añade `<uses-permission android:name="android.permission.INTERNET"/>` en el manifest de `androidMain`.

### 3. `iosMain` — `UIKitView` + `WKWebView`
`WKWebView` trae JavaScript activado por defecto. Convierte el `String` a `NSURL` (puede ser `null`) y carga vía `NSURLRequest`.

```kotlin
// iosMain — WebViewComposable.ios.kt
@OptIn(ExperimentalForeignApi::class)
@Composable
actual fun WebViewComposable(url: String, modifier: Modifier) {
    UIKitView(
        factory = {
            WKWebView().apply {
                NSURL.URLWithString(url)?.let { loadRequest(NSURLRequest.requestWithURL(it)) }
            }
        },
        modifier = modifier,
    )
}
```

### 4. Estado de carga (extensión sobre la base canónica)
La base de LifetimeJournal no expone loading; añádelo con un `MutableState` y los callbacks nativos.
- **Android**: sobrescribe `WebViewClient.onPageFinished` (y `onPageStarted`) para actualizar el estado; muestra un `CircularProgressIndicator` encima mientras carga.
- **iOS**: implementa `WKNavigationDelegate` (`didFinishNavigation` / `didStartProvisionalNavigation`) asignado a `navigationDelegate`.

Mantén el `expect` estable; pasa el estado a la pantalla vía un callback opcional (`onLoadingChanged: (Boolean) -> Unit`) para no romper firmas existentes.

### 5. Navegación atrás dentro del WebView
Si el usuario navegó a subpáginas, el "atrás" debería retroceder en el historial del WebView antes de salir de la pantalla.
- **Android**: guarda la referencia al `WebView` (p.ej. en un `remember`); en un `BackHandler`, si `webView.canGoBack()` llama `webView.goBack()`, si no ejecuta `onBack()`.
- **iOS**: `WKWebView` expone `canGoBack` / `goBack()`; cablea el botón de la TopBar para retroceder primero en el historial.

## Gotchas
- **JavaScript**: en Android está **desactivado por defecto** (hay que poner `javaScriptEnabled = true` + `@SuppressLint`); en iOS `WKWebView` lo trae **activado**. No asumas paridad.
- **`NSURL` puede ser `null`**: `NSURL.URLWithString(url)` devuelve `null` con URLs malformadas o sin esquema. Usa `?.let { … }` (como el snippet) o la carga se ignora en silencio.
- **`ExperimentalForeignApi`**: el `actual` de iOS necesita `@OptIn(ExperimentalForeignApi::class)` por el interop con `platform.WebKit`/`Foundation`.
- **Permiso INTERNET**: sin `<uses-permission android:name="android.permission.INTERNET"/>` el WebView de Android carga en blanco sin error visible.
- **No recrear en cada recomposición**: la `factory` de `AndroidView`/`UIKitView` solo se ejecuta una vez. Si `url` cambia dinámicamente, usa el bloque `update = { … }` para volver a llamar `loadUrl`/`loadRequest`; no dependas solo de `factory`.
- **Reemplaza el navegador externo**: donde hoy haya un `uriHandler.openUri(...)` / `Intent(ACTION_VIEW)` para URLs propias de la app, sustitúyelo por esta pantalla — ese es exactamente el TODO de inemsellar.

## Fuente
- `apptolast/LifetimeJournal` — `composeApp/src/commonMain/.../features/privacypolicy/presentation/PrivacyPolicyScreen.kt` (expect), `.../androidMain/.../WebViewComposable.android.kt`, `.../iosMain/.../WebViewComposable.ios.kt`.
- Los pasos 4 y 5 (estado de carga y back) son extensiones estándar con APIs nativas reales (`WebViewClient`/`BackHandler`, `WKNavigationDelegate`/`canGoBack`), no presentes en el snippet mínimo de LifetimeJournal.
