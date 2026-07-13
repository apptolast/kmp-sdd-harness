---
name: social-auth-rest
description: Úsala al implementar login social (Google + Apple) en apps KMP/CMP de AppToLast sin GitLive — cuando necesites que Google (Android) o Sign in with Apple (iOS) desemboquen en una sesión Firebase. Define el patrón canónico: bridge nativo obtiene el idToken del proveedor → canje REST contra Identity Toolkit `signInWithIdp` → misma `TokenManager` que email/password. Vale para proyectos con `:shared` que compila a wasmJs (donde GitLive no existe).
version: 0.1.0
---

# Receta: login social (Google + Apple) por REST, sin GitLive

Patrón **canónico** de auth social de la flota. El código nativo (Credential Manager en Android,
`ASAuthorizationController` en iOS) **solo obtiene el idToken del proveedor**; el canje por sesión
Firebase lo hace un servicio REST en `:shared` (`signInWithIdp`), de modo que Google, Apple y
email/password acaban en la **misma `TokenManager`** (única fuente de verdad de sesión).

Fuente: `apptolast/AllergenGuard` (`consumerApp` + `:shared` + `iosApp`), `docs/auth-google-apple-setup.md`.

## Cuándo usarla
- Al añadir "Continuar con Google" / "Continuar con Apple" a una app KMP.
- Cuando `:shared` compila a **wasmJs** (panel admin) y no puedes usar `dev.gitlive:firebase-auth`.
- Cuando ya tienes email/password por REST (Identity Toolkit + `TokenManager`) y quieres que el login
  social reutilice esa misma sesión.

## Reparto por plataforma (alcance de producto)
- **Google → solo Android.** **Apple → solo iOS.** Cada botón se muestra según `isGoogleAvailable` /
  `isAppleAvailable`; la plataforma que no soporta un proveedor reporta `false` (botón oculto) y lanza
  si se invoca. Apple es iOS-only: gatea el botón con `isAppleSignInAvailable`.

## Cómo se hace

### 1. `commonMain` — contrato `SocialAuthClient` (expect/actual vía `platformModule`)
El idToken (+ nonce/name) que devuelve la UI nativa; el canje Firebase se hace en el repo.

```kotlin
data class SocialSignInResult(
    val providerId: String,          // "google.com" o "apple.com"
    val idToken: String,
    val rawNonce: String? = null,    // Raw (sin hashear) — solo Apple. null en Google.
    val displayName: String? = null, // Apple solo lo da en el PRIMER login. null si no.
)

interface SocialAuthClient {
    val isGoogleAvailable: Boolean
    val isAppleAvailable: Boolean
    suspend fun signInWithGoogle(): SocialSignInResult
    suspend fun signInWithApple(): SocialSignInResult
}

class SocialAuthUnavailableException(message: String) : IllegalStateException(message)
class SocialAuthCancelledException : Exception("Social sign-in cancelled by the user")
```

### 2. `:shared` — canje REST `signInWithIdp` (Identity Toolkit, puro Ktor → sirve en wasmJs)

```kotlin
suspend fun signInWithIdp(
    providerId: String,
    idToken: String,
    rawNonce: String? = null,
): FirebaseSignInResponse {
    val postBody = buildString {
        append("id_token=").append(idToken)
        append("&providerId=").append(providerId)
        if (!rawNonce.isNullOrBlank()) append("&nonce=").append(rawNonce)
    }
    return client.post("${FirebaseConfig.IDENTITY_TOOLKIT}/accounts:signInWithIdp") {
        url { parameters.append("key", FirebaseConfig.apiKey) }
        contentType(ContentType.Application.Json)
        setBody(FirebaseSignInWithIdpRequest(
            postBody = postBody,
            requestUri = "http://localhost",
            returnSecureToken = true,
            returnIdpCredential = true,
        ))
    }.body()
}
```

### 3. `commonMain` — `FirebaseAuthRepository`: native → REST → `TokenManager`

```kotlin
override suspend fun loginWithGoogle(): Result<User> = runCatching { exchangeIdp(socialAuthClient.signInWithGoogle()) }
override suspend fun loginWithApple(): Result<User>  = runCatching { exchangeIdp(socialAuthClient.signInWithApple()) }

override val isGoogleSignInAvailable: Boolean get() = socialAuthClient.isGoogleAvailable
override val isAppleSignInAvailable: Boolean  get() = socialAuthClient.isAppleAvailable

private suspend fun exchangeIdp(social: SocialSignInResult): User {
    val r = authService.signInWithIdp(social.providerId, social.idToken, social.rawNonce)
    tokenManager.saveTokens(r.idToken, r.refreshToken, r.expiresIn.toLongOrNull() ?: 3600L)
    val email = r.email.ifEmpty { FirebaseIdToken.claim(r.idToken, "email").orEmpty() }
    // Apple solo da el nombre la 1ª vez → prioriza social.displayName, luego el de Firebase, luego el email.
    val name = social.displayName?.takeIf { it.isNotBlank() }
        ?: r.displayName.takeIf { it.isNotBlank() }
        ?: email.substringBefore("@").ifBlank { "Usuario" }
    return User(id = r.localId, name = name, email = email).also { _currentUser.value = it }
}
```

### 4. `androidMain` — Google con Credential Manager (`GetSignInWithGoogleOption`)
Devuelve **solo el ID token**. `serverClientId` = cliente **Web** (`client_type 3` del
`google-services.json`), inyectado por `BuildConfig.GOOGLE_WEB_CLIENT_ID`.

```kotlin
override val isGoogleAvailable = webClientId.isNotBlank()
override val isAppleAvailable = false

override suspend fun signInWithGoogle(): SocialSignInResult {
    val activity = SocialAuthActivityHolder.requireActivity() // WeakReference set/clear en MainActivity
    val option = GetSignInWithGoogleOption.Builder(webClientId).build()
    val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
    val response = try {
        credentialManager.getCredential(context = activity, request = request)
    } catch (_: GetCredentialCancellationException) { throw SocialAuthCancelledException() }
      catch (e: GetCredentialException) { throw SocialAuthUnavailableException(e.message ?: "…") }
    val credential = response.credential
    if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
        val google = GoogleIdTokenCredential.createFrom(credential.data)
        return SocialSignInResult("google.com", google.idToken, displayName = google.displayName)
    }
    throw SocialAuthUnavailableException("No se obtuvo una credencial de Google válida.")
}
```

### 5. `iosMain` — bridge a Swift (Apple). Swift instala el handler al arrancar.

```kotlin
typealias IosAppleCompletion = (String?) -> Unit // "idToken|||rawNonce|||displayName" o null (cancel/error)

object IosAppleAuthBridge { var signInHandler: ((IosAppleCompletion) -> Unit)? = null }

class IosSocialAuthClient : SocialAuthClient {
    override val isGoogleAvailable = false
    override val isAppleAvailable get() = IosAppleAuthBridge.signInHandler != null

    override suspend fun signInWithApple(): SocialSignInResult {
        val handler = IosAppleAuthBridge.signInHandler ?: throw SocialAuthUnavailableException("…")
        val payload = suspendCancellableCoroutine<String?> { cont ->
            handler { result -> cont.resume(result) }
        } ?: throw SocialAuthCancelledException()
        val (idToken, rawNonce, displayName) = payload.split("|||").let {
            Triple(it.getOrNull(0).orEmpty(), it.getOrNull(1).orEmpty(), it.getOrNull(2)?.takeIf(String::isNotBlank))
        }
        if (idToken.isBlank() || rawNonce.isBlank()) throw SocialAuthUnavailableException("…")
        return SocialSignInResult("apple.com", idToken, rawNonce, displayName)
    }
}
```

### 6. Swift — `SocialAuthCoordinator`: `ASAuthorizationController` + nonce
Solo usa `AuthenticationServices` + `CryptoKit` (sin SPM de Firebase/GoogleSignIn). Registra el bridge
en `iOSApp.init` con `SocialAuthCoordinator.shared.registerBridges()`.

```swift
func registerBridges() {
    IosAppleAuthBridge.shared.signInHandler = { [weak self] completion in
        self?.signInWithApple { payload in completion(payload) }
    }
}
// ...
let nonce = Self.randomNonceString()
request.requestedScopes = [.fullName, .email]
request.nonce = Self.sha256(nonce)   // Apple firma con SHA256(nonce); el RAW va a Firebase (anti-replay)
// delegate → didCompleteWithAuthorization:
finish("\(idToken)|||\(rawNonce)|||\(name)")  // cancel/error → finish(nil)
```

## Gotchas
- **Android: `serverClientId` = cliente Web (`client_type 3`), NUNCA el de Android.** Con el de Android,
  Credential Manager devuelve un idToken pero Firebase lo **rechaza**.
- **SHA-1 y SHA-256 de cada keystore** (debug, release, CI) en Firebase Console; si faltan, Google
  falla con `DEVELOPER_ERROR` o no devuelve idToken. Reexporta `google-services.json` tras añadirlas.
- **Apple: manda el nonce RAW (sin hashear) a `signInWithIdp`.** La request se firma con `sha256(nonce)`
  pero Identity Toolkit re-hashea el raw y lo compara con la claim `nonce` del token. Mandar el hash falla.
- **Apple solo entrega el nombre en el PRIMER login.** Persístelo al recibirlo (p. ej. `updateProfile` +
  refresh del token); en logins posteriores `fullName` viene vacío.
- **Habilita Apple como proveedor** en Firebase Console → Authentication → Sign-in method, con Services
  ID + Team ID + Key ID + `.p8`. Si no, `signInWithIdp("apple.com")` devuelve `OPERATION_NOT_ALLOWED`.
- **Cancelación = no-op silencioso.** Traduce el cancel nativo a `SocialAuthCancelledException` y no
  muestres error; cualquier otro fallo va a `SocialAuthUnavailableException`.
- **No metas Firebase en Swift.** El coordinator solo consigue el idToken; el canje vive en `:shared`
  (así también funciona en wasmJs). Retén el `ASAuthorizationController` mientras dura el flujo o iOS
  suelta el delegate antes de tiempo.

Fuente: `apptolast/AllergenGuard` — `SocialAuthClient.kt`, `AndroidSocialAuthClient.kt`,
`IosSocialAuthClient.kt`, `FirebaseAuthRepository.kt`, `FirebaseAuthService.kt`,
`iosApp/iosApp/SocialAuthCoordinator.swift`, `docs/auth-google-apple-setup.md`.
