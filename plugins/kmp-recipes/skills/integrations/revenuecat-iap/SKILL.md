---
name: revenuecat-iap
description: Úsala al integrar compras in-app (IAP) en un proyecto KMP de AppToLast con RevenueCat KMP 3.1.0 — cuando implementes "quitar publicidad"/remove_ads, un entitlement que desbloquee funciones premium, restaurar compras, o cablear el flag ads_removed. Cubre el source-set mobileMain (solo Android+iOS, sin wasmJs), el expect/actual de la API key, la config de Purchases, comprar/restaurar y las keys públicas por BuildKonfig.
version: 0.1.0
---

# Receta: IAP con RevenueCat KMP (remove_ads)

Patrón **canónico** de compras in-app de la flota AppToLast. RevenueCat KMP **3.1.0**. La lógica vive en un source-set intermedio **`mobileMain`** (Android + iOS); web/wasmJs usa un `NoOpIapService`. Fuente: inemsellar `consumerApp`.

## Cuándo usarla
- Al implementar el IAP de "Quitar Publicidad" (`remove_ads`) o cualquier compra que active un entitlement.
- Al gatear una función (ads, premium) según un entitlement activo de RevenueCat.
- Al añadir "Restaurar compras" o sincronizar el estado de compra al arrancar.

## Cómo se hace

### 1. Dependencia solo en `mobileMain` (RevenueCat no soporta wasmJs/desktop)
Extiende la jerarquía por defecto para crear el grupo `mobile` compartido por Android + iOS, y ata `iosMain` a `mobileMain` a mano (el template no cablea el grupo intermedio `iosMain`):

```kotlin
// consumerApp/build.gradle.kts
applyDefaultHierarchyTemplate {
    common {
        group("mobile") {
            withAndroidTarget(); withIosArm64(); withIosSimulatorArm64()
        }
    }
}
sourceSets {
    val mobileMain by getting {
        dependencies { implementation(libs.revenuecat.kmp.core) } // purchases-kmp-core 3.1.0
    }
    iosMain.get().dependsOn(mobileMain)   // para que PlatformModule.ios/MainViewController vean los tipos RC
}
```
```toml
# gradle/libs.versions.toml
revenuecatKmp = "3.1.0"
revenuecat-kmp-core = { module = "com.revenuecat.purchases:purchases-kmp-core", version.ref = "revenuecatKmp" }
```

### 2. API key pública por plataforma (expect/actual, leída de BuildKonfig)
RevenueCat usa una **key distinta por store** (Google Play vs App Store), así que va con expect/actual. Las keys **públicas** (`goog_…` / `appl_…`) se pueden shippar en el cliente.

```kotlin
// mobileMain/…/data/local/RevenueCatConfig.kt
expect val revenueCatApiKey: String
// androidMain/…/RevenueCatConfig.android.kt
actual val revenueCatApiKey: String = BuildKonfig.REVENUECAT_ANDROID_API_KEY
// iosMain/…/RevenueCatConfig.ios.kt
actual val revenueCatApiKey: String = BuildKonfig.REVENUECAT_IOS_API_KEY
```
Ver la receta `buildkonfig-secrets` para el bloque `buildConfigField` que las expone.

### 3. Inicializador idempotente (una vez por proceso)
Llámalo desde `MainActivity.onCreate` (Android) y `MainViewController` (iOS). Si la key está en blanco (dev sin secreto), **no crashea**: se salta el configure y la app funciona sin IAP.

```kotlin
// mobileMain/…/RevenueCatInitializer.kt
fun initializeRevenueCat() {
    if (Purchases.isConfigured) return
    if (revenueCatApiKey.isBlank()) { log.w { "RevenueCat API key blank — skipping configure()" }; return }
    Purchases.logLevel = if (BuildKonfig.IS_RELEASE) LogLevel.WARN else LogLevel.DEBUG
    Purchases.logHandler = RcLogHandler // rutea los logs internos a Kermit → Crashlytics
    runCatching { Purchases.configure(PurchasesConfiguration(apiKey = revenueCatApiKey)) }
        .onFailure { log.e(it) { "Purchases.configure threw — IAP disabled this session" } }
}
```
No se pasa `appUserId`: el SDK crea un `$RCAnonymousID` anónimo. Al habilitar login, llamar `Purchases.sharedInstance.logIn(firebaseUid)` desde el orquestador de auth y `logOut()` al cerrar sesión.

### 4. El servicio IAP: comprar, restaurar, sincronizar (`IapService` en commonMain)
`RevenueCatIapService(settingsStorage, analytics)` implementa `IapService` y vive en `mobileMain`. Constantes: entitlement `"InemSellar Pro"`, producto `"remove_ads"`. Usa las extensiones ktx suspend (`awaitOfferings`, `awaitPurchase`, `awaitRestore`, `awaitCustomerInfo`).

```kotlin
private const val ENTITLEMENT_ID = "InemSellar Pro"
private const val REMOVE_ADS_PRODUCT_ID = "remove_ads"

override suspend fun buyRemoveAds() {
    val offerings = Purchases.sharedInstance.awaitOfferings()
    val pkg = findRemoveAdsPackage(offerings.current, offerings.all.values) ?: run {
        _events.emit(IapEvent.PurchaseError("product_not_in_offering")); return
    }
    val result = Purchases.sharedInstance.awaitPurchase(packageToPurchase = pkg)
    applyEntitlement(result.customerInfo)               // escribe ads_removed
    if (result.customerInfo.entitlements[ENTITLEMENT_ID]?.isActive == true)
        _events.emit(IapEvent.PurchaseSuccess)
}

override suspend fun restorePurchases() {
    val info = Purchases.sharedInstance.awaitRestore()
    applyEntitlement(info)
    val active = info.entitlements[ENTITLEMENT_ID]?.isActive == true
    _events.emit(if (active) IapEvent.RestoreSuccess else IapEvent.RestoreNoPurchases)
}

private fun applyEntitlement(info: CustomerInfo) {
    settingsStorage.setAdsRemoved(info.entitlements[ENTITLEMENT_ID]?.isActive == true)
}
```
`buyRemoveAds` distingue **cancelación de usuario** de error real: captura `PurchasesTransactionException` y comprueba `e.userCancelled` → emite `IapEvent.PurchaseCancelled` (no es un fallo). No busques el paquete solo en `current.lifetime`: recórrelo por `storeProduct.id` (y `id.startsWith("$REMOVE_ADS_PRODUCT_ID:")` para subs con base-plan) sobre `availablePackages`, con fallback a otras offerings.

### 5. Gatear la función con el flag `ads_removed`
El entitlement se persiste como un booleano en `SettingsStorage` (multiplatform-settings, clave `"ads_removed"`), compartido con iOS por UserDefaults. La UI observa el `Flow` y no renderiza el banner si está activo:

```kotlin
fun setAdsRemoved(removed: Boolean) { settings.putBoolean("ads_removed", removed); _adsRemoved.value = removed }
fun isAdsRemoved(): Flow<Boolean>   // observado por AdBannerWrapper
fun isAdsRemovedSync(): Boolean      // leído por el app-open ad service
```

### 6. Cableado Koin (por plataforma)
```kotlin
// PlatformModule.android.kt / .ios.kt
single<IapService> { RevenueCatIapService(get(), get()) }
// PlatformModule.wasmJs.kt
single<IapService> { NoOpIapService() }   // web: no hay store
```

## Gotchas
- **`product_not_in_offering`**: la causa nº1. En el dashboard de RevenueCat el producto `remove_ads` debe estar **adjunto a un Package dentro de la Offering *current***, o `awaitOfferings()` no lo encuentra. No basta con crear el producto.
- **Solo `mobileMain`**: nunca importes tipos `com.revenuecat.purchases.kmp.*` desde `commonMain`/`wasmJsMain` — no compila. La interfaz `IapService` va en commonMain; el impl RC en mobileMain; web recibe `NoOpIapService`.
- **Keys en blanco no crashean**: si falta la key en `local.properties`, `initializeRevenueCat()` hace no-op. Bien para devs, pero significa que un release sin la key envía la app **sin IAP** silenciosamente — verifica `REVENUECAT_ANDROID_API_KEY`/`REVENUECAT_IOS_API_KEY` en CI.
- **DEVELOPER_ERROR en Android**: el keystore de firma debe coincidir con la upload key de Play Console; con otra, el AAB rechaza los flujos de IAP/license-tester. Prueba compras en un track interno/cerrado + license tester (Android) o TestFlight + sandbox (iOS).
- **Cancelar ≠ error**: comprueba `PurchasesTransactionException.userCancelled` antes de tratar la excepción como fallo, o mostrarás un error cuando el usuario simplemente cerró la hoja de compra.
- **`amountMicros`**: el precio para analytics viene en micros (1_000_000 micros = 1 unidad); divide antes de loguear el evento `purchase`.

---
Fuente: inemsellar — `consumerApp/src/mobileMain/.../data/local/{RevenueCatConfig.kt,RevenueCatInitializer.kt,RevenueCatIapService.kt}`, `consumerApp/src/{androidMain,iosMain}/.../data/local/RevenueCatConfig.{android,ios}.kt`, `shared/src/commonMain/.../data/local/SettingsStorage.kt`, `consumerApp/build.gradle.kts` (mobileMain), `consumerApp/src/{androidMain,iosMain,wasmJsMain}/.../di/PlatformModule.*.kt`.
