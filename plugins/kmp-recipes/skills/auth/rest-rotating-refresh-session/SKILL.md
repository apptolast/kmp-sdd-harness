---
name: rest-rotating-refresh-session
description: Úsala al montar la sesión de un dispositivo contra un backend REST propio (sin Firebase Auth) en una app KMP/CMP de AppToLast, cuando el backend da un acceso corto y un refresco ROTATORIO con detección de reutilización, de modo que reusar un refresco (también con dos renovaciones a la vez) revoca toda la sesión. Cubre el plugin propio de Ktor en vez de `Auth { bearer }`, la renovación de un solo vuelo, el arranque sin red, el cierre que revoca de verdad, los tokens cifrados (Android Keystore, iOS Keychain) y los tests en tiempo virtual.
version: 0.1.0
---

# Receta: sesión de dispositivo con refresco rotatorio (Ktor, Keystore y Keychain)

Patrón **canónico** para la sesión de una app contra un backend REST sin cookies. Cada dispositivo recibe un
**acceso** corto (minutos) y un **refresco** largo (días) que **rota** en cada renovación. Si el servidor ve
un refresco ya usado, revoca toda la sesión: dos renovaciones a la vez, o una repetida tras perder la
respuesta, cierran la sesión. Por eso la renovación tiene un solo vuelo y sobrevive a quien la pidió.

Fuente: una app KMP de la flota (Android + iOS) con este patrón en producción y su ADR de sesión por token;
engram `architecture/ktor-rotating-refresh-session` y `testing/kmp-ios-android-test-gotchas`.

## Cuándo usarla
- Login con credenciales contra tu propio backend, con tokens opacos y un refresco que rota.
- El backend detecta la reutilización del refresco, o limita los fallos de renovación (429 con `Retry-After`).
- La app debe abrir sin red con la sesión guardada, y una carrera nunca debe cerrar la sesión.
- Con Firebase Auth no: usa `firebase-rest-client` o `social-auth-rest` (su refresco no rota así).

## El contrato que se supone

| Llamada | Qué hace |
|---|---|
| `POST /auth/login` | Devuelve `access`, `refresh`, `accessExpiresAt` (ISO-8601) y el usuario. |
| `POST /auth/refresh` | Cambia el refresco por un par nuevo; el acceso anterior deja de valer. 400/401: refresco desconocido, revocado o reutilizado. 429 o 503, con `Retry-After`. |
| `DELETE /auth/session` | Revoca este dispositivo, **solo con un acceso vigente**: con uno caducado responde 401. |

Si tu backend acepta un acceso caducado en el `DELETE`, simplifica el cierre (paso 7), no lo demás.

## Por qué un plugin propio y no `Auth { bearer }`
El `Auth` de Ktor con un solo proveedor sí renueva aunque el 401 no traiga `WWW-Authenticate`; ese no es el
motivo. Lo son estos tres:
- su `AuthTokenHolder` es una segunda copia de los tokens, que resucita la sesión si no llamas a `clearToken()`;
- no sabe «esperar la renovación en curso sin empezar otra», que es lo que necesita una petición de fondo;
- renueva en la corrutina de quien llama: si se cancela (la pantalla se va, el tope del arranque), la rotación se
  corta a medias y el refresco nuevo se pierde.

## Cómo se hace

### 1. Las piezas
- `domain/session`: `SessionRepository`, la única interfaz de la sesión para la UI: `state:
  StateFlow<SessionState>` (`Checking`, `Active(user)`, `SignedOut(expired)`), `events` (`SessionClosed`),
  `start()`, `login()` y `logout()`.
- `data/session`: `SessionManager`, que la implementa y es el único que lee los tokens; `AuthApi` (login,
  renovar y cerrar); el plugin `SessionAuth`, y `BlobSessionStore` sobre un `SecureBlobStore` por plataforma.

### 2. Dos clientes sobre un motor
El cliente público hace el login, la renovación y el cierre, así que un 401 suyo nunca dispara otra renovación.
El autenticado lleva el plugin. Los dos usan el motor de `platformModule`, que cerrar un cliente no cierra.

```kotlin
val sessionModule = module {
    single<CoroutineScope>(APP_SCOPE) { CoroutineScope(SupervisorJob() + Dispatchers.Default) } onClose { it?.cancel() }
    single(PUBLIC_CLIENT) { HttpClient(get<HttpClientEngine>()) { installCommon() } } onClose { it?.close() }
    single { AuthApi(get(PUBLIC_CLIENT)) }
    single<SessionStore> { BlobSessionStore(get(), json, Dispatchers.IO) } // SecureBlobStore: platformModule
    single<PushDevice> { NoOpPushDevice } // until the app has push
    // Explicit lambda: singleOf would not skip the default values of the constructor.
    single {
        SessionManager(api = get(), store = get(), push = get(), clock = Clock.System, appScope = get(APP_SCOPE))
    } bind SessionRepository::class
    single(AUTH_CLIENT) {
        val manager = get<SessionManager>()
        HttpClient(get<HttpClientEngine>()) {
            installCommon() // base URL, JSON, timeouts, expectSuccess = false, logging without Authorization
            install(SessionAuth) { session = manager }
        }
    } onClose { it?.close() }
}
```

### 3. El plugin
Sin acceso, la petición sale sin cabecera. Con uno, lleva su Bearer; ante un 401 pide la renovación (o se une a
la que esté en curso) y repite la petición **una vez**. Una petición de fondo (`background()`) nunca empieza
una renovación ni cierra la sesión; si el backend distingue la actividad de fondo, aquí va también su cabecera.

```kotlin
/** Work the app sends on its own: a 401 to it never starts a renewal nor ends the session. */
val BackgroundRequest = AttributeKey<Unit>("BackgroundRequest")
fun HttpRequestBuilder.background() = attributes.put(BackgroundRequest, Unit)

class SessionAuthConfig { var session: SessionManager? = null }

val SessionAuth = createClientPlugin("SessionAuth", ::SessionAuthConfig) {
    val session = checkNotNull(pluginConfig.session) { "SessionAuth needs the session" }
    on(Send) { request ->
        val access = session.access() ?: return@on proceed(request)
        val background = BackgroundRequest in request.attributes
        val call = proceed(request.authorizedBy(access))
        if (call.response.status != HttpStatusCode.Unauthorized) return@on call
        val renewed = session.renewAfterRejection(access, mayStart = !background) ?: return@on call
        val repeated = proceed(request.copy().authorizedBy(renewed))
        if (repeated.response.status == HttpStatusCode.Unauthorized && !background) session.closeAfterRejection(renewed)
        repeated
    }
}

// Replaced, never appended: bearerAuth() would add a second Authorization header to the repetition.
private fun HttpRequestBuilder.authorizedBy(access: String) =
    apply { headers[HttpHeaders.Authorization] = "Bearer $access" }

// A new builder in the same execution context, as Ktor's own Auth repeats a request.
@OptIn(InternalAPI::class)
private fun HttpRequestBuilder.copy() = HttpRequestBuilder().takeFromWithExecutionContext(this)
```

### 4. `SessionManager`: el núcleo de un solo vuelo
- Una copia en memoria (`current`) que guarda un `Mutex`. El `Mutex` **nunca** cubre una llamada de red, y no
  es reentrante: lo que se llama con él tomado acaba en `…Locked`.
- Una **época** que sube con cada login, cierre o rechazo: la respuesta tardía de una sesión anterior no la
  resucita.
- Un único `Deferred` de rotación, en el scope de la app (`appScope.async`), al que se unen todos los 401.
  Cancelar a quien espera no lo cancela.
- El resultado se guarda en `NonCancellable`: el servidor ya rotó, así que el par nuevo se guarda aunque el
  scope se esté cerrando.
- **Acceso obsoleto**: si el acceso rechazado ya no es el actual, el 401 llegó tarde y se repite con el
  actual, sin renovar.

```kotlin
suspend fun access(): String? = mutex.withLock { current?.access }

suspend fun renewAfterRejection(rejected: String, mayStart: Boolean): String? {
    val pending = mutex.withLock {
        val session = current ?: return null
        if (session.access != rejected) return session.access // late 401: already rotated
        rotation?.takeIf { it.isActive } ?: run {
            if (!mayStart) return null // background work: wait for one, never start one
            cooldownErrorLocked()?.let { throw RenewalUnavailable(it) } // Retry-After still running
            val startedIn = epoch
            appScope.async { rotate(session, startedIn) }.also { rotation = it }
        }
    }
    // The wait holds no lock, and cancelling it leaves the rotation running.
    return when (val renewal = pending.await()) {
        is Renewal.Renewed -> mutex.withLock { current?.access?.takeIf { it == renewal.tokens.access } }
        Renewal.Rejected -> null
        is Renewal.Unavailable -> throw RenewalUnavailable(renewal.error)
    }
}

private suspend fun rotate(from: StoredSession, startedIn: Long): Renewal {
    val renewal = api.renew(from.refresh)
    withContext(NonCancellable) {
        when (renewal) {
            is Renewal.Renewed -> keep(from, renewal.tokens, startedIn) // ignored if epoch != startedIn
            Renewal.Rejected -> closeWithNotice(startedIn) // idem: SignedOut(expired = true) + one event
            is Renewal.Unavailable -> coolDown(renewal.error) // the limit is per IP: always
        }
    }
    return renewal
}
```

`RenewalUnavailable` es una excepción que el mapeo de errores del proyecto (`apiCall` o similar) entrega como
su error tipado: la petición falla con «sin red» o «demasiadas peticiones», y la sesión sigue.

### 5. Qué cierra la sesión
Solo un 400 o un 401 de `/auth/refresh`, y por el estado HTTP, no por el código del cuerpo: un 401 con
cualquier código es un refresco muerto. Un 429, un 5xx o la falta de red conservan los tokens.

```kotlin
suspend fun renew(refresh: String): Renewal {
    var status = 0
    val result = client.apiCall<TokensDto> { // the project's response → typed result mapping
        post("auth/refresh") {
            contentType(ContentType.Application.Json)
            setBody(RefreshDto(refresh))
        }.also { status = it.status.value }
    }
    return when (result) {
        is AppResult.Success -> Renewal.Renewed(result.value.toTokens())
        is AppResult.Failure -> if (status == 400 || status == 401) Renewal.Rejected else Renewal.Unavailable(result.error)
    }
}
```

Tras un 429 o un 503 con `Retry-After`, no vuelve a salir ninguna renovación hasta que pase, aunque la pidan
otras peticiones o un login nuevo: el límite suele ser por IP, y varios dispositivos pueden compartirla.
Mientras dura, la petición devuelve el error con la espera que queda. El enfriamiento vive en memoria.

### 6. Arranque optimista
`start()` lanza una sola carga (un `Job` `LAZY` en el scope de la app: arrancarlo dos veces no hace nada).

```kotlin
private suspend fun load() {
    val saved = readSavedOrNull() // a store that throws counts as no session: the check always ends
    // No session → SignedOut; access fresh for more than 60 s → Active at once, without network;
    // otherwise → the rotation it needs.
    val renewal = mutex.withLock { openLocked(saved) } ?: return
    withTimeoutOrNull(startupBudget) { renewal.await() } // 1.5 s: cuts the wait, never the rotation
    mutex.withLock {
        // Unless the rotation was rejected, or a login or a logout came first.
        val session = current
        if (_state.value == SessionState.Checking && session != null) _state.value = SessionState.Active(session.user)
    }
}
```

Una caducidad ilegible cuenta como caducada. En Android, la pantalla de arranque se mantiene mientras el
estado sea `Checking` (`setKeepOnScreenCondition`).

### 7. Cierre de sesión
`logout()` deja la sesión cerrada y el almacén vacío **al momento**, en `NonCancellable`; después, en el scope
de la app, busca un acceso vigente y avisa al servidor. Ningún error de esa parte llega a la UI.

```kotlin
override suspend fun logout() {
    val (ended, pendingRotation) = withContext(NonCancellable) {
        mutex.withLock {
            val ending = current?.let { it to rotation?.takeIf { r -> r.isActive } }
            endLocked() // epoch++, current = null, rotation = null, store.clear()
            _state.value = SessionState.SignedOut(expired = false)
            ending
        }
    } ?: return
    appScope.launch { revoke(ended, pendingRotation) }
}
```

`revoke` hace, cada paso con su tope (`withTimeoutOrNull`) y sus errores tragados y registrados sin datos:
1. Con una rotación en curso, la espera (2 s) y usa su acceso, sin renovar otra vez.
2. Si no, usa el acceso guardado si caduca en más de 60 s; si no, renueva con el refresco (5 s) **sin guardar
   el par** ni tocar la sesión, salvo durante el enfriamiento, que esta renovación respeta y también inicia.
3. Si la renovación se rechaza, la sesión ya no existe en el servidor: no llama a nada más. Si no está
   disponible, sigue con el acceso guardado.
4. Da de baja el push (3 s) **antes** del `DELETE`, porque necesita el mismo acceso vigente.
5. `DELETE auth/session` con el Bearer explícito, por el cliente público (5 s).

### 8. Almacén: JSON común sobre un blob cifrado
`BlobSessionStore` (común) guarda la sesión como JSON con versión (`"v": 1`) y borra lo ilegible o de otra
versión. Debajo, cada plataforma solo cifra y guarda un texto:

```kotlin
sealed interface SecureBlob {
    data class Present(val text: String) : SecureBlob
    data object Absent : SecureBlob      // nothing saved, or undecryptable and already deleted
    data object Unavailable : SecureBlob // cannot be read now (iOS before the first unlock): nothing deleted
}

interface SecureBlobStore { // blocking calls: BlobSessionStore runs them on Dispatchers.IO
    fun read(): SecureBlob
    fun write(text: String) // throws if it could not be stored
    fun clear()
}
```

**Android (`KeystoreBlobStore`)**
- AES-256/GCM con una clave del `AndroidKeyStore` sin autenticación de usuario (`KeyGenParameterSpec`,
  `BLOCK_MODE_GCM`, `ENCRYPTION_PADDING_NONE`). El IV lo genera el `Cipher` (`cipher.iv`): el Keystore rechaza
  uno propio.
- Se guarda `[versión][IV][texto cifrado]` en Base64, en unas preferencias privadas propias, con `commit()`
  para saber si se escribió.
- Lo que no se descifra (clave invalidada o dañada, copia de otro dispositivo, datos corruptos) se borra con su
  clave y se lee como `Absent`. Una escritura con la clave inservible borra la clave y cifra con una nueva:

```kotlin
internal fun isUnusableKey(e: Throwable) = e is GeneralSecurityException || e is ProviderException
```

- El fichero de preferencias no viaja en las copias, porque la clave no sale del dispositivo:

```xml
<!-- res/xml/data_extraction_rules.xml (Android 12+); backup_rules.xml repite el exclude (11 y anteriores) -->
<data-extraction-rules>
    <cloud-backup><exclude domain="sharedpref" path="session_store.xml" /></cloud-backup>
    <device-transfer><exclude domain="sharedpref" path="session_store.xml" /></device-transfer>
</data-extraction-rules>
```

**iOS (`KeychainBlobStore`)**
- Una contraseña genérica (`kSecClassGenericPassword` con un `kSecAttrService` propio) con
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: legible tras el primer desbloqueo, sin iCloud ni copia a
  otro dispositivo.
- Las cuatro llamadas `SecItem*` van detrás de un port `Keychain` que devuelve el `OSStatus`, con un fake en
  `iosTest`: el binario de test del simulador no tiene Keychain (gotchas). `SecItemKeychain` es solo el interop.
- Escribir es `SecItemAdd`, y con `errSecDuplicateItem`, `SecItemUpdate`: `SecItemAdd` nunca reemplaza.
- El Keychain sobrevive a la desinstalación: una marca en `NSUserDefaults` (lo único de la sesión ahí) dice si
  esta instalación ya borró lo que dejó la anterior. La primera llamada sin marca borra el item y luego la pone.
- Las llamadas bloquean: un `NSLock` las pone en fila.

```kotlin
when (found.status) {
    errSecSuccess -> found.text?.let(SecureBlob::Present) ?: deleteUnreadable()
    errSecItemNotFound -> SecureBlob.Absent
    errSecInteractionNotAllowed -> SecureBlob.Unavailable // locked: read, delete and mark nothing
    else -> throw KeychainException("read", found.status) // the status only, never data
}
```

### 9. La navegación sigue al estado
La raíz observa `state` y navega con una función pura (`sessionRedirect(state, currentIsLogin)`, testeada en
`commonTest`) que limpia la pila (`popUpTo(graph.id) { inclusive = true }`). Nunca navega por `events`: un
evento con `replay = 0` se pierde si el `NavHost` aún no está compuesto. El evento solo sirve para un aviso.

### 10. Tests en `commonTest`, en tiempo virtual
El `SessionManager` real sobre el `AuthApi` real, con `MockEngine`, un almacén falso y todo en el mismo
planificador de test: los 1,5 s del arranque, los topes del cierre y el `Retry-After` pasan sin esperar.

```kotlin
fun TestScope.mockEngine(handler: MockRequestHandler) = MockEngine(
    MockEngineConfig().apply {
        dispatcher = StandardTestDispatcher(testScheduler) // delays and timeouts in virtual time
        addHandler(handler)
    },
)

val appScope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)) // cancel() it at the end

class TestClock(private val scheduler: TestCoroutineScheduler, private val origin: Instant) : Clock {
    override fun now(): Instant = origin + scheduler.currentTime.milliseconds
}
```

El backend falso lleva el par vivo, como el de verdad: `/auth/refresh` solo acepta el refresco vivo (otro, 401)
y emite un par nuevo, y el `DELETE` da 204 solo con el acceso vivo sin caducar (otro, 401). Sin eso, un cierre
que manda el acceso caducado pasa los tests. Casos mínimos:
- tres 401 a la vez: una sola renovación, y cada petición se repite una vez, con una sola cabecera;
- un 401 tardío con el acceso anterior: se repite con el actual, sin renovar;
- un 400 o un 401 de renovar con varias peticiones esperando: un cierre con aviso y un solo evento;
- un 429, un 5xx o sin red: los tokens siguen y la petición devuelve el error; tras un `Retry-After`, ninguna
  renovación hasta que pase;
- cancelar la petición que espera no para la rotación ni bloquea la siguiente;
- cerrar sesión durante una renovación: sigue cerrada, y se revoca el par más nuevo;
- el arranque: un acceso fresco entra sin red; uno caducado con el backend lento entra a los 1,5 s y la rotación
  sigue;
- un almacén ilegible o de otra versión se borra y se lee como sin sesión.

## Gotchas
- **`bearerAuth()` añade, no reemplaza**: en la repetición habría dos `Authorization`. Asigna `headers[…]`.
- **`proceed()` dos veces** necesita una copia del builder con `takeFromWithExecutionContext`, que es
  `@InternalAPI` (como en el `Auth` de Ktor): revísalo al subir Ktor.
- **`catch (e: Exception)` atrapa la cancelación**: relanza `CancellationException` antes, o el cierre de la app
  sigue trabajando.
- **El refresco perdido tras rotar** (el proceso muere o se pierde la respuesta después de que el servidor rote)
  parece una reutilización, y el servidor revoca la sesión. No tiene arreglo en el cliente: pide al backend una
  ventana de gracia para el par anterior.
- **`EncryptedSharedPreferences` está deprecado** (`security-crypto` 1.1.0); multiplatform-settings y KVault
  no tienen el estado «no disponible» del Keychain bloqueado. El Keystore y Security.framework directos son
  pocas llamadas.
- **Algunos Keystore lanzan `ProviderException`** (una `RuntimeException`) con una clave dañada: trátala como
  una `GeneralSecurityException`, o la app falla en cada arranque.
- **Keychain en tests**: `iosSimulatorArm64Test` no tiene Keychain (`errSecNotAvailable`, receta
  `compose-ui-ios`): el fake del port prueba la lógica, y el `SecItemKeychain` real, un dispositivo con aprobación.
- **CFDictionary en Kotlin/Native**: las constantes `kSec*` entran tal cual; los valores de Kotlin o Foundation
  se puentean con `CFBridgingRetain` y se liberan cuando el diccionario los retiene.
- **Ningún token al registro**: el `Logging` de Ktor con `sanitizeHeader` para `Authorization`, y los mensajes
  de error con el estado HTTP o el `OSStatus`, nunca con datos.
- **El login se guarda en `NonCancellable`**: el servidor ya creó la sesión aunque la pantalla se haya ido.

## Fuente
Una app KMP de la flota (Android + iOS): `SessionManager`, el plugin de sesión, `SessionApi`,
`BlobSessionStore`, `KeystoreBlobStore`, `KeychainBlobStore` y `SecItemKeychain`, con sus tests de
`commonTest`/`iosTest`, y su ADR de sesión por token. Engram: `architecture/ktor-rotating-refresh-session`.
