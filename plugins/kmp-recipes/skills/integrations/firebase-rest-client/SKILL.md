---
name: firebase-rest-client
description: Úsala al integrar Firebase (Auth + Firestore + Storage) en un proyecto KMP/CMP de AppToLast SIN el SDK GitLive — cuando montes la capa `data/remote/firebase` en `:shared`, necesites autenticar por REST (Identity Toolkit), leer/escribir Firestore por REST, subir a Storage, o construir repos Firestore. Define el patrón canónico: Firebase-por-REST-sobre-Ktor con el ID token de Firebase como única credencial, funcionando en TODOS los targets (Android, iOS, JS, wasmJs).
version: 0.1.0
---

# Receta: Firebase por REST sobre Ktor (Auth + Firestore + Storage)

Patrón **canónico** de la flota para hablar con Firebase sin el SDK oficial (GitLive). Todo es Ktor puro en `commonMain`, así que corre en **todos** los targets, incluido **wasmJs** (donde GitLive no existe). El ID token de Firebase es la **única credencial**. Fuente: `apptolast/AllergenGuard` (gemelo estructural de inemsellar).

## Cuándo usarla
- Al montar la capa `data/remote/firebase` en `:shared` de un proyecto nuevo.
- Al necesitar login/registro (email, Google, Apple), lectura/escritura Firestore o subida a Storage sin SDK nativo.
- Al escribir un `Firestore<Feature>Repository` sobre `FirestoreClient`.
- Cuando el target incluye Web/wasmJs y GitLive queda descartado.

## Arquitectura (modelo ID-token-como-única-credencial)
```
FirebaseConfig            # apiKey, projectId, databaseId + endpoints REST (constantes)
FirebaseAuthService       # Identity Toolkit + Secure Token → devuelve idToken/refreshToken
TokenManager              # persiste idToken(access)+refreshToken+expiry (multiplatform-settings)
createFirestoreHttpClient # HttpClient que adjunta "Bearer <idToken>" y lo refresca (proactivo + 401)
FirestoreClient           # data-plane REST: list/get/patch/delete documentos
FirestoreCodec            # encode/decode de los valores tipados de Firestore REST
FirebaseStorageClient     # subida de bytes → URL pública de descarga
FirestoreIdToken          # lee claims del JWT en cliente (sin verificar firma)
```
El `idToken` que devuelve Auth es lo que `createFirestoreHttpClient` adjunta como `Bearer` en cada llamada a Firestore/Storage. Las **reglas** de Firestore/Storage (server-side) verifican ese token: no hay sesión de backend propio.

## Cómo se hace

### 1. `FirebaseConfig` — endpoints y base de datos activa
Constantes de los 4 hosts REST y derivación de la ruta de documentos. `databaseId` es **mutable** y se fija en el arranque (antes de cualquier llamada) según el build.
```kotlin
object FirebaseConfig {
    val apiKey: String = BuildKonfig.FIREBASE_API_KEY
    val projectId: String = BuildKonfig.FIREBASE_PROJECT_ID
    // Se sobrescribe en el entry point de cada plataforma (debug → "debug", release → "(default)").
    var databaseId: String = BuildKonfig.FIRESTORE_DATABASE_ID

    const val IDENTITY_TOOLKIT = "https://identitytoolkit.googleapis.com/v1"
    const val SECURE_TOKEN = "https://securetoken.googleapis.com/v1"
    const val FIRESTORE = "https://firestore.googleapis.com/v1"
    const val STORAGE = "https://firebasestorage.googleapis.com"

    val firestoreDocuments: String
        get() = "$FIRESTORE/projects/$projectId/databases/$databaseId/documents"
    val storageBucket: String
        get() = "$projectId.firebasestorage.app"
}
```
Todas las llamadas Auth llevan `?key=<apiKey>` (no Bearer). Firestore/Storage llevan `Bearer <idToken>`.

### 2. `FirebaseAuthService` — Identity Toolkit + Secure Token (REST, sin Bearer)
Cada método es un `POST` con `?key=apiKey`. Cuerpos `@Serializable` **sin defaults** (kotlinx-serialization omite lo igual al default; Identity Toolkit exige `returnSecureToken` para devolver `refreshToken`).
```kotlin
class FirebaseAuthService(private val client: HttpClient) {
    suspend fun signInWithPassword(email: String, password: String): FirebaseSignInResponse =
        client.post("${FirebaseConfig.IDENTITY_TOOLKIT}/accounts:signInWithPassword") {
            url { parameters.append("key", FirebaseConfig.apiKey) }
            contentType(ContentType.Application.Json)
            setBody(FirebaseSignInRequest(email, password, returnSecureToken = true))
        }.body()

    // Social: canjea el idToken OIDC nativo (Google/Apple) por sesión Firebase.
    // providerId = "google.com" | "apple.com"; rawNonce solo Apple (Identity Toolkit re-hashea sha256).
    suspend fun signInWithIdp(providerId: String, idToken: String, rawNonce: String? = null): FirebaseSignInResponse {
        val postBody = buildString {
            append("id_token=").append(idToken)
            append("&providerId=").append(providerId)
            if (!rawNonce.isNullOrBlank()) append("&nonce=").append(rawNonce)
        }
        return client.post("${FirebaseConfig.IDENTITY_TOOLKIT}/accounts:signInWithIdp") {
            url { parameters.append("key", FirebaseConfig.apiKey) }
            contentType(ContentType.Application.Json)
            setBody(FirebaseSignInWithIdpRequest(postBody, "http://localhost", true, true))
        }.body()
    }

    // Refresco: endpoint distinto (Secure Token) y form-urlencoded, respuesta en snake_case.
    suspend fun refreshIdToken(refreshToken: String): FirebaseRefreshResponse =
        client.submitForm(
            url = "${FirebaseConfig.SECURE_TOKEN}/token",
            formParameters = Parameters.build {
                append("grant_type", "refresh_token")
                append("refresh_token", refreshToken)
            },
        ) { url { parameters.append("key", FirebaseConfig.apiKey) } }.body()
    // + signUp / updateProfile (accounts:update) / deleteAccount (accounts:delete)
}
```
DTOs clave: `FirebaseSignInResponse(idToken, refreshToken, expiresIn:String="3600", localId, email, displayName)` y `FirebaseRefreshResponse` con `@SerialName("id_token")` / `refresh_token` / `expires_in` / `user_id` (snake_case).

### 3. `TokenManager` — persiste la única credencial
`multiplatform-settings`. `accessToken` = el ID token de Firebase. Marca expiración con 30 s de margen.
```kotlin
class TokenManager(private val settings: Settings = Settings()) {
    var accessToken: String? // = Firebase ID token
    var refreshToken: String?
    fun isAccessTokenExpired(): Boolean { /* now >= expiresAt - 30s */ }
    fun saveTokens(access: String, refresh: String, expires: Long) { /* guarda + calcula expiresAt */ }
    fun clearTokens() { /* logout */ }
}
```

### 4. `createFirestoreHttpClient` — adjunta y refresca el Bearer
Interceptor `HttpSend`: refresca **proactivamente** si el token expiró, adjunta `Bearer`, y **reintenta una vez** si Firestore responde `401`. `expectSuccess = false` para inspeccionar status.
```kotlin
fun createFirestoreHttpClient(tokenManager: TokenManager, authService: FirebaseAuthService, json: Json): HttpClient {
    val client = HttpClient {
        install(ContentNegotiation) { json(json) }
        expectSuccess = false
    }
    client.plugin(HttpSend).intercept { request ->
        if (tokenManager.isAccessTokenExpired() && tokenManager.refreshToken != null) {
            refreshFirebaseToken(tokenManager, authService)
        }
        tokenManager.accessToken?.let { token ->
            request.headers { remove(HttpHeaders.Authorization); append(HttpHeaders.Authorization, "Bearer $token") }
        }
        val call = execute(request)
        if (call.response.status == HttpStatusCode.Unauthorized && tokenManager.refreshToken != null) {
            if (refreshFirebaseToken(tokenManager, authService)) {
                tokenManager.accessToken?.let { token ->
                    request.headers { remove(HttpHeaders.Authorization); append(HttpHeaders.Authorization, "Bearer $token") }
                }
                execute(request)
            } else call
        } else call
    }
    return client
}
// refreshFirebaseToken: authService.refreshIdToken(refresh) → saveTokens(...); en error → clearTokens() (fuerza re-login).
```

### 5. `FirestoreClient` — data-plane REST (thin)
Rutas relativas a `firestoreDocuments` (`"ingredients"`, `"accounts/{id}/recipes"`, `"ingredients/{id}"`). `patchDocument` es upsert idempotente; con `updateMask` escribe solo esos campos (deja intactos los que gestiona el servidor, p. ej. contadores).
```kotlin
class FirestoreClient(private val client: HttpClient) {
    private val base = FirebaseConfig.firestoreDocuments

    suspend fun listDocuments(collectionPath: String): List<FirestoreDocument> { /* pagina con pageSize=300 + nextPageToken */ }
    suspend fun getDocument(path: String): FirestoreDocument?            // 404 → null
    suspend fun patchDocument(path: String, fields: Map<String, Any?>, updateMask: List<String>? = null): FirestoreDocument {
        val resp = client.patch("$base/$path") {
            updateMask?.forEach { parameter("updateMask.fieldPaths", it) }
            contentType(ContentType.Application.Json)
            setBody(buildJsonObject { put("fields", FirestoreCodec.encodeFields(fields)) })
        }
        if (!resp.status.isSuccess()) throw FirestoreException(resp.status.value, resp.bodyAsText())
        return parseDoc(resp.body())
    }
    suspend fun deleteDocument(path: String)                            // 404 se ignora
}
// FirestoreDocument(id, fields: Map<String,Any?>, createTime: Instant?, updateTime: Instant?)  ← timestamps del servidor
```

### 6. `FirestoreCodec` — valores tipados de Firestore REST ↔ Kotlin plano
Firestore REST usa `{"stringValue":...}`, `{"integerValue":"…"}` (¡string!), `{"arrayValue":{"values":[...]}}`, `{"mapValue":{"fields":{...}}}`. El codec traduce a/desde `String/Long/Double/Boolean/List/Map/null`.
```kotlin
object FirestoreCodec {
    fun decodeFields(fields: JsonObject): Map<String, Any?> = fields.mapValues { decode(it.value) }
    fun encodeFields(map: Map<String, Any?>): JsonObject = buildJsonObject { map.forEach { (k, v) -> put(k, encode(v)) } }
    fun encode(v: Any?): JsonObject = when (v) {
        null -> buildJsonObject { put("nullValue", JsonNull) }
        is String -> buildJsonObject { put("stringValue", v) }
        is Boolean -> buildJsonObject { put("booleanValue", v) }
        is Int, is Long -> buildJsonObject { put("integerValue", v.toString()) } // enteros como STRING
        is Double -> buildJsonObject { put("doubleValue", v) }
        is Map<*, *> -> /* mapValue.fields */
        is List<*> -> /* arrayValue.values (omite "values" si vacío) */
        else -> buildJsonObject { put("stringValue", v.toString()) }
    }
}
```

### 7. `FirebaseStorageClient` — subida por REST → URL de descarga
Endpoint `v0`, mismo `Bearer`. Devuelve una URL `?alt=media&token=` (idéntica a la del SDK/consola).
```kotlin
class FirebaseStorageClient(private val client: HttpClient) {
    private val base = "${FirebaseConfig.STORAGE}/v0/b/${FirebaseConfig.storageBucket}/o"
    suspend fun uploadBytes(path: String, bytes: ByteArray, contentType: String): String {
        val resp = client.post(base) { parameter("name", path); contentType(ContentType.parse(contentType)); setBody(bytes) }
        val token = resp.body<JsonObject>()["downloadTokens"]?.jsonPrimitive?.contentOrNull?.substringBefore(",")
        return "$base/${path.encodeURLParameter()}?alt=media" + (token?.let { "&token=$it" } ?: "")
    }
}
```

### 8. `FirebaseIdToken` — leer claims en cliente (sin verificar firma)
Decodifica el payload del JWT para recuperar claims que el cliente necesita reenviar (p. ej. `accountId` para las reglas). La seguridad la imponen las reglas server-side sobre el token verificado.
```kotlin
object FirebaseIdToken {
    fun claim(idToken: String?, name: String): String? {
        val payload = idToken?.split('.')?.getOrNull(1) ?: return null
        // Base64.UrlSafe (con padding manual %4) → JsonObject[name]
    }
}
```

### 9. Repos Firestore encima del cliente
Un `Firestore<Feature>Repository` implementa la interfaz de dominio, recibe `FirestoreClient` inyectado, mapea `FirestoreDocument ↔ dominio` con extensiones `toX()` / `toFields()`, y cachea con `MutableStateFlow` + carga perezosa.
```kotlin
class FirestoreIngredientRepository(
    private val firestore: FirestoreClient,
    private val accountHolder: CurrentAccountHolder,
) : IngredientRepository {
    private val _ingredients = MutableStateFlow<List<Ingredient>>(emptyList())
    private fun collection() = "accounts/${accountHolder.requireAccountId()}/ingredients"

    override fun getAllIngredients(): Flow<List<Ingredient>> = flow { /* refresh si toca */; emitAll(_ingredients) }
    override suspend fun addIngredient(i: Ingredient): Ingredient {
        val id = i.id.ifEmpty { Uuid.random().toString() }
        firestore.patchDocument("${collection()}/$id", i.toFields()); refresh(); /* … */
    }
    private fun FirestoreDocument.toIngredient(): Ingredient = /* lee fields["name"] as? String, etc. */
    private fun Ingredient.toFields(): Map<String, Any?> = mapOf("name" to name, /* … */)
}
```

## Gotchas
- **Enteros como String**: Firestore REST codifica `integerValue` como texto (`"3600"`); `expiresIn` de Auth también. El codec/DTOs ya lo contemplan — no asumas números JSON.
- **Dos `HttpClient` distintos**: el de Auth (`named("auth")`, sin Bearer, para Identity Toolkit) y el de Firestore/Storage (`named("firestore")`, con interceptor de Bearer). No los mezcles: mandar Bearer a `accounts:signInWithPassword` o `?key=` a Firestore falla.
- **`databaseId` antes de todo**: fíjalo en el entry point de cada plataforma (`FirebaseConfig.databaseId = if (BuildConfig.DEBUG) "debug" else "(default)"`) **antes** de `initKoin`/primera llamada. El literal `(default)` va tal cual en la ruta.
- **`returnSecureToken` sin default**: si el DTO de request lo omite (por default), Identity Toolkit devuelve solo `idToken` (sin `refreshToken`/`expiresIn`) y el refresco se rompe. Mantén los DTOs de request **sin valores por defecto**.
- **`expectSuccess = false`**: obligatorio en el cliente Firestore para poder inspeccionar `401`/`404` (retry / null) en vez de que Ktor lance. `FirestoreClient` mapea el resto a `FirestoreException(status, body)`.
- **Refresco proactivo + reactivo**: el interceptor refresca por expiración *y* reintenta una vez en `401`. Si el refresco falla, `clearTokens()` fuerza re-login; no entres en bucle de reintentos.
- **Firma NO verificada** en `FirebaseIdToken.claim`: úsalo solo para claims que el cliente reenvía; nunca como control de seguridad. Las reglas de Firestore son la autoridad.
- **`updateMask`**: sin él, `patchDocument` **reemplaza** todos los campos del documento (borra los que no envíes, p. ej. contadores de Cloud Functions). Usa `updateMask` para escrituras parciales.
- **Variante inemsellar**: AllergenGuard conserva el flag `USE_FIRESTORE` (dual Firestore/backend). inemsellar **lo eliminó** junto al backend Rust: Firestore siempre, `FirebaseConfig` sin `useFirestore` y `DataModule` cablea los repos Firestore incondicionalmente.

## Fuente
- Repo: `apptolast/AllergenGuard` (gemelo estructural de inemsellar; Firebase-por-REST idéntico).
- Rutas (`shared/src/commonMain/kotlin/org/apptolast/menuadmin/data/`):
  - `remote/firebase/FirebaseConfig.kt`, `FirebaseAuthService.kt`, `FirebaseAuthDto.kt`, `FirebaseHttpClient.kt` (`createFirestoreHttpClient`), `FirebaseIdToken.kt`, `FirestoreClient.kt`, `FirestoreCodec.kt`, `FirebaseStorageClient.kt`
  - `remote/auth/TokenManager.kt`
  - `repository/FirestoreIngredientRepository.kt` (patrón repo Firestore)
- Acceso: `gh api repos/apptolast/AllergenGuard/contents/<ruta> -q .content | base64 -d`
