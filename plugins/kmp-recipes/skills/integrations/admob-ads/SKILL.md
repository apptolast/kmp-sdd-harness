---
name: admob-ads
description: Úsala al integrar AdMob (Google Mobile Ads) en un proyecto KMP de AppToLast — cuando añadas un banner adaptativo sobre la bottom nav, un app-open ad al volver de background, o necesites gatear anuncios con el flag ads_removed. Cubre el expect/actual BannerAdView + getBannerAdUnitId, AdBannerWrapper (commonMain), Android AndroidView+AdView, iOS UIKitView+BannerAdBridge→Swift, y el app-open (ProcessLifecycleOwner en Android, AppOpenAdManager.swift en iOS).
version: 0.1.0
---

# Receta: AdMob en KMP (banner adaptativo + app-open)

Patrón **canónico** de anuncios de AppToLast. Dos formatos: **banner adaptativo** (sobre la bottom nav) y **app-open ad** (al volver de background). El SDK nativo (Google Mobile Ads) solo existe en Android/iOS; se aísla tras expect/actual y un bridge Kotlin→Swift. Fuente: inemsellar `consumerApp`.

## Cuándo usarla
- Al añadir un banner adaptativo a la UI Compose (común Android + iOS).
- Al implementar un app-open ad que se muestra al volver de background.
- Al gatear cualquier anuncio con la compra `remove_ads` (flag `ads_removed`).

## Cómo se hace

### 1. Wrapper común que gatea por `ads_removed` (commonMain)
Toda la UI de banner pasa por `AdBannerWrapper`. Corta el render si el usuario compró remove_ads o si no hay ad unit id:

```kotlin
// commonMain/…/presentation/components/AdBannerWrapper.kt
@Composable
fun AdBannerWrapper(modifier: Modifier = Modifier) {
    val settingsRepository: SettingsRepository = koinInject()
    val adsRemoved by settingsRepository.isAdsRemoved().collectAsState(initial = false)
    if (adsRemoved) return
    val adUnitId = remember { getBannerAdUnitId() }
    if (adUnitId.isBlank()) return
    BannerAdView(adUnitId = adUnitId, modifier = modifier)
}
```

### 2. expect/actual del banner y del ad unit id (commonMain)
```kotlin
@Composable expect fun BannerAdView(adUnitId: String, modifier: Modifier = Modifier)
expect fun getBannerAdUnitId(): String
```
Los ids salen de BuildKonfig por plataforma (ver receta `buildkonfig-secrets`):
```kotlin
// androidMain
actual fun getBannerAdUnitId(): String = BuildKonfig.ADMOB_BANNER_ANDROID
// iosMain
actual fun getBannerAdUnitId(): String = BuildKonfig.ADMOB_BANNER_IOS
// wasmJsMain
actual fun getBannerAdUnitId(): String = ""      // web no tiene AdMob → wrapper corta
```

### 3. Banner Android — `AndroidView` + `AdView` directo
El SDK Google Mobile Ads es accesible desde Kotlin en Android. Usa banner **adaptativo anclado** y reenvía el lifecycle (pause/resume/destroy) para no filtrar:

```kotlin
// androidMain/…/BannerAdView.android.kt
@Composable actual fun BannerAdView(adUnitId: String, modifier: Modifier) {
    val activity = LocalActivity.current ?: return
    val screenWidthDp = LocalConfiguration.current.screenWidthDp
    val adView = remember(adUnitId, screenWidthDp) {
        AdView(activity).apply {
            setAdSize(AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(activity, screenWidthDp))
            this.adUnitId = adUnitId
            loadAd(AdRequest.Builder().build())
        }
    }
    DisposableEffect(adView, lifecycleOwner) {
        val observer = LifecycleEventObserver { _, e -> when (e) {
            Lifecycle.Event.ON_PAUSE -> adView.pause(); Lifecycle.Event.ON_RESUME -> adView.resume(); else -> Unit } }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer); adView.destroy() }
    }
    AndroidView(modifier = modifier.fillMaxWidth().wrapContentHeight(), factory = { adView })
}
```
Dependencia: `implementation(libs.play.services.ads)` en `androidMain`.

### 4. Banner iOS — `UIKitView` + bridge Kotlin→Swift
En iOS el SDK GoogleMobileAds (SPM, v13) solo se ve desde Swift. Kotlin define una interfaz-bridge y Swift la implementa; el bridge se inyecta en `iOSApp.swift`.

```kotlin
// iosMain/…/BannerAdBridge.kt
interface BannerAdViewFactory {
    fun createBannerView(adUnitId: String, width: Double): UIView
    fun getBannerHeight(width: Double): Double
}
object BannerAdBridge { var factory: BannerAdViewFactory? = null }

// iosMain/…/BannerAdView.ios.kt
@Composable actual fun BannerAdView(adUnitId: String, modifier: Modifier) {
    val factory = BannerAdBridge.factory ?: return
    val screenWidth = UIScreen.mainScreen.bounds.useContents { size.width }
    val bannerHeight = remember(screenWidth) { runCatching { factory.getBannerHeight(screenWidth) }.getOrDefault(0.0) }
    if (bannerHeight <= 0.0) return
    UIKitView(modifier = modifier.fillMaxWidth().height(bannerHeight.dp),
        factory = { runCatching { factory.createBannerView(adUnitId, screenWidth) }.getOrElse { UIView() } })
}
```
```swift
// iosApp/BannerAdViewFactory.swift — implementa la interfaz Kotlin
class IOSBannerAdViewFactory: NSObject, BannerAdViewFactory {
    func createBannerView(adUnitId: String, width: Double) -> UIView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: CGFloat(width)))
        banner.adUnitID = adUnitId
        banner.rootViewController = Self.getRootViewController()
        banner.load(Request())
        return banner
    }
    func getBannerHeight(width: Double) -> Double { … }
}
// iOSApp.swift: BannerAdBridge.shared.factory = IOSBannerAdViewFactory()
```

### 5. App-open ad
**Interfaz común** `AppOpenAdService { loadAd(); showAdIfAvailable(); notifyAppBackgrounded() }`.

Android (`AndroidAppOpenAdService`): observa `ProcessLifecycleOwner` en `MainActivity` tras `MobileAds.initialize`:
```kotlin
private fun setupAppOpenAd() {
    val svc: AppOpenAdService = getKoin().get()
    svc.loadAd()
    ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
        override fun onStart(owner: LifecycleOwner) { svc.showAdIfAvailable() }   // vuelta de background
        override fun onStop(owner: LifecycleOwner)  { svc.notifyAppBackgrounded() }
    })
}
```
El id sale de `BuildKonfig.ADMOB_APP_OPEN_ANDROID`. Reglas de Google que implementa el servicio: **no** mostrar en cold launch (`hasBeenBackgrounded`), saltar el primer open (`app_open_count < 2`), y caducar el ad cacheado a las **4 horas**. Requiere `implementation(libs.androidx.lifecycle.process)`.

iOS (`AppOpenAdManager.swift`, singleton): todo en Swift vía `didEnterBackgroundNotification`/`didBecomeActiveNotification`. `IosAppOpenAdService.kt` es un **no-op** solo para satisfacer la interfaz en Koin.

### 6. Cableado Koin e init del SDK
```kotlin
// PlatformModule
single<AppOpenAdService> { AndroidAppOpenAdService(get()) }   // ios: IosAppOpenAdService · web: NoOpAppOpenAdService
```
En `MainActivity`: `MobileAds.setRequestConfiguration(...test devices...)` → `MobileAds.initialize(this) {}` → `setupAppOpenAd()`, disparado tras recoger el consentimiento (`ConsentManager.gatherConsent { initializeMobileAdsSdk() }`). El `ADMOB_APP_ID` va en el manifest Android como `manifestPlaceholders["ADMOB_APP_ID"]`.

## Gotchas
- **App-open id iOS hardcodeado**: `AppOpenAdManager.swift` tiene el ad unit id en una constante Swift (`ca-app-pub-…`), **no** viene de BuildKonfig. Si cambias `ADMOB_APP_OPEN_IOS` en `local.properties`, actualiza también el `.swift` a mano o se desincroniza.
- **El bridge iOS debe inyectarse o el banner no aparece**: `BannerAdView.ios.kt` hace `BannerAdBridge.factory ?: return`. Si olvidas `BannerAdBridge.shared.factory = IOSBannerAdViewFactory()` en `iOSApp.swift`, el banner sale vacío sin error.
- **No mostrar app-open en cold launch**: guía oficial de Google. El servicio preloadea silenciosamente la primera vez y solo muestra al volver de background (flag `hasBeenBackgrounded`); Android e iOS además saltan el primer open (`app_open_count < 2`).
- **Gating en dos sitios**: el banner corta en `AdBannerWrapper` (Flow `isAdsRemoved()`); el app-open corta con `isAdsRemovedSync()` / `UserDefaults.bool("ads_removed")`. Comparten la misma clave `ads_removed` que escribe RevenueCat (ver receta `revenuecat-iap`).
- **Fugas de AdView Android**: cachea el `AdView` con `remember(adUnitId, screenWidthDp)` y **destrúyelo en `onDispose`**; sin eso, la rotación filtra vistas.
- **wasmJs es no-op**: `getBannerAdUnitId()` devuelve `""` y `BannerAdView` no hace nada en web; el gating por id-en-blanco del wrapper hace el resto.
- **Test devices**: registra tus dispositivos en `RequestConfiguration.setTestDeviceIds(...)` para que sirvan ads de test aunque uses ad units reales; nunca hagas clics en ads reales durante desarrollo.

---
Fuente: inemsellar — `consumerApp/src/commonMain/.../presentation/components/{AdBannerWrapper,BannerAdView,BannerAdUnitId}.kt`, `.../{androidMain,iosMain,wasmJsMain}/.../presentation/components/BannerAd*.{android,ios,wasmJs}.kt` + `BannerAdBridge.kt`, `.../data/local/AppOpenAdService*.kt`, `consumerApp/.../MainActivity.kt`, `iosApp/iosApp/{BannerAdViewFactory,AppOpenAdManager}.swift`, y la sección "AdMob Architecture" de `CLAUDE.md`.
