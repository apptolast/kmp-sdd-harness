---
name: push-fcm
description: Úsala al añadir notificaciones push (Firebase Cloud Messaging) a proyectos KMP/CMP de AppToLast — suscripción a topics, token FCM, permiso de notificaciones (Android 13+ / iOS APNs) y deep-link al pulsar la notificación. Define el patrón canónico con KMPNotifier (`io.github.mirzemehdi:kmpnotifier`): `NotificationInitializer` común + `DeepLinkManager` (StateFlow) + init por plataforma (Application Android / AppDelegate iOS). Incluye las diferencias Android vs iOS (google-services vs APNs).
version: 0.1.0
---

# Receta: push notifications con FCM (KMPNotifier)

Patrón **canónico** de push en apps KMP/CMP de AppToLast. Fuente: `SpainDecides` (`notification/NotificationInitializer`, `navigation/DeepLinkManager`, `NotificationDeepLinkHandler`, `docs/PUSH_NOTIFICATIONS_SETUP.md`). Librería: **KMPNotifier `io.github.mirzemehdi:kmpnotifier` 1.6.1** (envuelve FCM en Android y APNs+FCM en iOS). El envío se hace por **topic** desde una Cloud Function; la app se **suscribe** al topic y **reacciona** al tap con un deep link.

## Cuándo usarla
- Enviar avisos a todos los dispositivos (broadcast por topic), no push dirigido por device-token.
- Abrir una pantalla concreta al pulsar la notificación (deep link a detalle).
- Cablear permiso de notificaciones (Android 13+ runtime, iOS APNs) y el token FCM.

## Cómo se hace

### 0. Dependencia + config Firebase
- `gradle/libs.versions.toml`: `kmpnotifier = "1.6.1"` → `io.github.mirzemehdi:kmpnotifier`. En Android requiere el plugin `google-services` + `google-services.json` en `composeApp/src/androidMain/`. En iOS, `GoogleService-Info.plist` en `iosApp/iosApp/` + Firebase iOS SDK (`FirebaseMessaging`) por SPM.

### 1. `commonMain` — `NotificationInitializer` (suscripción + listener)
Objeto común que suscribe a un topic por entorno y registra el listener de KMPNotifier (`onNewToken`, `onPayloadData`, `onPushNotification`).

```kotlin
// commonMain — notification/NotificationInitializer.kt
object NotificationInitializer {
    private val scope = CoroutineScope(Dispatchers.Default)

    fun subscribeToNewProposalsTopic() {
        val topic = Environment.FCM_TOPIC_NEW_PROPOSALS // "new_proposals_dev" / "..._prod"
        scope.launch {
            runCatching { NotifierManager.getPushNotifier().subscribeToTopic(topic) }
        }
    }

    fun setNotificationListener(onReceived: (title: String?, body: String?) -> Unit) {
        NotifierManager.addListener(object : NotifierManager.Listener {
            override fun onNewToken(token: String) { /* log / registrar token */ }
            override fun onPayloadData(data: PayloadData) { /* datos crudos */ }
            override fun onPushNotification(title: String?, body: String?) {
                super.onPushNotification(title, body)
                onReceived(title, body)
            }
        })
    }
}
```

### 2. `commonMain` — `DeepLinkManager` (puente tap → navegación)
El tap de la notificación (código de plataforma) **empuja** un deep link a un `StateFlow`; el `App` composable lo **observa** y navega, luego lo consume. `StateFlow` es thread-safe: se puede llamar `setDeepLink` desde cualquier hilo.

```kotlin
// commonMain — navigation/DeepLinkManager.kt
sealed class DeepLink {
    data class ProposalDetail(val proposalId: String, val categoryId: String) : DeepLink()
}

object DeepLinkManager {
    private val _pending = MutableStateFlow<DeepLink?>(null)
    val pendingDeepLink: StateFlow<DeepLink?> = _pending.asStateFlow()
    fun setDeepLink(dl: DeepLink) { _pending.value = dl }
    fun consumeDeepLink() { _pending.value = null } // llamar TRAS navegar
}
```

En `App.kt`: `val pending by DeepLinkManager.pendingDeepLink.collectAsState()` + `LaunchedEffect(pending, hasReachedHome) { … navController.navigate(...); DeepLinkManager.consumeDeepLink() }`. Espera a que el usuario esté autenticado/en Home antes de navegar; si no, guarda el deep link pendiente.

### 3. Android — init en `Application` + permiso/intent en `MainActivity`
Inicializa KMPNotifier en `Application.onCreate` (tras Koin) y suscribe al topic. El permiso y el tap se manejan en la Activity.

```kotlin
// androidMain — Application.onCreate()
NotifierManager.initialize(
    NotificationPlatformConfiguration.Android(
        notificationIconResId = R.drawable.ic_notification,
        showPushNotification = true,
    )
)
NotificationInitializer.subscribeToNewProposalsTopic()
NotificationInitializer.setNotificationListener { title, body -> /* ... */ }
```

```kotlin
// androidMain — MainActivity: permiso runtime (Android 13+, POST_NOTIFICATIONS)
private val requestPermissionLauncher =
    registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> }

private fun askNotificationPermission() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
    ) requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```
El tap se lee del `Intent`: en `onCreate` (cold start) **y** `onNewIntent` (warm start) extrae `extras.getString("type"/"proposalId"/"categoryId")` y llama `DeepLinkManager.setDeepLink(...)`.

### 4. iOS — `AppDelegate` (APNs + FCM token + tap)
En Swift: `FirebaseApp.configure()`, delegados de `UNUserNotificationCenter`/`Messaging`, permiso APNs y `registerForRemoteNotifications`. **`askNotificationPermissionOnStart = false`** en KMPNotifier porque el permiso se pide manualmente.

```swift
// iOSApp.swift — AppDelegate.didFinishLaunchingWithOptions
FirebaseApp.configure()
UNUserNotificationCenter.current().delegate = self
Messaging.messaging().delegate = self
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
    if granted { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
}
NotifierManager.shared.initialize(
    configuration: NotificationPlatformConfigurationIos(
        showPushNotification: true,
        askNotificationPermissionOnStart: false,
        notificationSoundName: nil))
```
- `didRegisterForRemoteNotificationsWithDeviceToken` → `Messaging.messaging().apnsToken = deviceToken`.
- `messaging(_:didReceiveRegistrationToken:)` → suscribe al topic (`Messaging.messaging().subscribe(toTopic:)`).
- El tap (`userNotificationCenter(_:didReceive:)`) extrae `userInfo["type"/"proposalId"/"categoryId"]` y llama al puente Kotlin.

### 5. Puente Kotlin llamable desde Swift (`iosMain`)
Función top-level (Swift la ve como `…Kt.handleNotificationTap(...)`) que empuja el deep link al manager común.

```kotlin
// iosMain — NotificationDeepLinkHandler.kt
fun handleNotificationTap(proposalId: String, categoryId: String) {
    DeepLinkManager.setDeepLink(DeepLink.ProposalDetail(proposalId, categoryId))
}
```

## Gotchas
- **Android vs iOS permiso**: Android 13+ (`TIRAMISU`) exige `POST_NOTIFICATIONS` en runtime; en versiones previas es implícito. iOS pide autorización APNs y **`registerForRemoteNotifications` debe llamarse en el hilo principal** tras conceder el permiso.
- **iOS necesa dispositivo real**: el simulador **no** recibe push APNs. Prueba token/entrega en device físico.
- **APNs `.p8` obligatorio**: sin subir la clave de autenticación APNs (`.p8` + Team ID + Key ID) en Firebase Console → Cloud Messaging, iOS no recibe nada aunque Android funcione. Habilita también las capabilities "Push Notifications" y "Background Modes → Remote notifications" en Xcode.
- **Doble init evitado en iOS**: pon `askNotificationPermissionOnStart = false` si ya pides el permiso manualmente en el `AppDelegate`, o compites con KMPNotifier por el prompt.
- **Payload consistente**: el deep link depende de claves `data` idénticas (`type`, `proposalId`, `categoryId`) en Android (`intent.extras`) e iOS (`userInfo`). Si la Cloud Function las manda en `notification` en vez de `data`, el tap en background puede no traerlas — mándalas en `data`.
- **Consumir el deep link**: llama `consumeDeepLink()` **después** de navegar; si no, el `LaunchedEffect` re-navega en cada recomposición. Y espera a estar autenticado/en Home antes de procesarlo (guarda el pendiente).
- **`google-services.json`/`plist` gitignored**: cada dev/CI los aporta; sin ellos Android crashea al arrancar (plugin `google-services`) e iOS no genera token.

## Fuente
- `apptolast/SpainDecides` — `composeApp/src/commonMain/.../notification/NotificationInitializer.kt`, `.../navigation/DeepLinkManager.kt`, `.../iosMain/.../NotificationDeepLinkHandler.kt`, `androidMain/.../SpainDecidesApplication.kt` + `MainActivity.kt`, `iosApp/iosApp/iOSApp.swift`, y la guía completa `docs/PUSH_NOTIFICATIONS_SETUP.md` (setup Firebase/APNs/Cloud Function paso a paso).
