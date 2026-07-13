---
name: ci-cd-github-actions
description: Úsala al tocar el CI/CD de los proyectos KMP de AppToLast (GitHub Actions). Cuando configures o depures el release de Android (Play internal vía fastlane), iOS (TestFlight vía fastlane+match), el web de consumer/admin (Firebase Hosting, wasmJs) o el deploy de Cloud Functions; cuando inyectes secrets en `local.properties` en tiempo de build; o cuando te preguntes por qué el CI no corre tests. Define el patrón de release por tag `v*` y documenta el hueco de calidad (no hay CI gate).
version: 0.1.0
---

# Receta: CI/CD con GitHub Actions (release por tags)

Setup **canónico** de release de la flota KMP: pipelines por plataforma, disparados por tags `v*`, con secrets inyectados en `local.properties` en tiempo de build. Fuente: inemsellar `.github/workflows/*.yml`.

## Cuándo usarla
- Al crear/depurar el release de Android, iOS, web (consumer/admin) o Cloud Functions.
- Al añadir un secret nuevo (AdMob, RevenueCat, Firebase, signing) al pipeline.
- Al preguntarte qué dispara cada workflow o por qué el CI no valida nada.

## Mapa de workflows
| Workflow | Runner | JDK | Trigger real | Qué hace |
|----------|--------|-----|--------------|----------|
| `deploy-android.yml` | ubuntu | 17 | `v*` + dispatch | fastlane `android release_from_tag` → AAB firmado → Play **internal** (draft) |
| `deploy-ios.yml` | macos-15 | 17 | `v*` + dispatch | fastlane `ios release_from_tag` + **match** → `.ipa` → **TestFlight** |
| `firebase-hosting-consumer.yml` | ubuntu | **21** | dispatch (push comentado) | `:consumerApp:wasmJsBrowserDistribution` → Firebase Hosting (target `consumer`) |
| `firebase-hosting-admin.yml` | ubuntu | **21** | dispatch (push comentado) | `:adminApp:wasmJsBrowserDistribution` → Firebase Hosting (target `admin`) |
| `deploy-functions.yml` | ubuntu | — (Node 20) | dispatch (push comentado) | `firebase deploy --only functions:‹contadores›` (ambos entornos) |
| `deploy.yml` | ubuntu | 17 | dispatch | Legacy: `assembleRelease bundleRelease` + sign + `upload-google-play` |

> **JDK: 17 para Android/iOS, 21 para web (wasmJs).** No mezclar.

## Cómo se hace

### 1. Release móvil disparado por tag `v*`
El patrón: se empuja un tag `vX.Y.Z` en cualquier rama → fastlane lee `$GITHUB_REF_NAME`, calcula el `versionCode`/`CFBundleVersion` consultando la store, construye y sube. `workflow_dispatch` con `inputs.tag` permite re-lanzar un tag existente si un run falló:

```yaml
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      tag: { description: "Existing tag to (re)release, e.g. v224.0.1", required: true, type: string }

concurrency:
  group: android-release-${{ inputs.tag || github.ref_name }}
  cancel-in-progress: false
```

El checkout usa `ref: ${{ inputs.tag || github.ref }}` con `fetch-depth: 0` (fastlane necesita el historial de tags).

### 2. Inyección de secrets en `local.properties` (BuildKonfig)
Todos los pipelines materializan `local.properties` en runtime, justo antes del build, con un heredoc. BuildKonfig lee de ahí. Android release añade además el bloque `signing.*` que apunta al keystore decodificado:

```yaml
- name: Render local.properties
  run: |
    cat > local.properties <<EOF
    sdk.dir=$ANDROID_HOME
    signing.storeFile=$RUNNER_TEMP/secrets/keystore.jks
    signing.storePassword=${{ secrets.SIGNING_KEY_STORE_PASSWORD }}
    signing.keyAlias=${{ secrets.SIGNING_ALIAS }}
    signing.keyPassword=${{ secrets.SIGNING_KEY_PASSWORD }}
    ADMOB_APP_ID=${{ secrets.ADMOB_APP_ID }}
    REVENUECAT_ANDROID_API_KEY=${{ secrets.REVENUECAT_ANDROID_API_KEY }}
    FIREBASE_API_KEY=${{ secrets.FIREBASE_API_KEY }}
    FIREBASE_PROJECT_ID=${{ secrets.FIREBASE_PROJECT_ID }}
    APP_ENV=release
    EOF
```

`APP_ENV=release` ⇒ Firestore base `(default)`. `google-services.json` NO va en `local.properties`: se decodifica de `GOOGLE_SERVICES_JSON_B64` (base64, una sola línea) a `consumerApp/google-services.json`, con validación de que es JSON válido antes de seguir.

### 3. iOS: signing por `match` (read-only en CI)
El runner no tiene certificados: `match` clona el repo privado de certs por **HTTPS** y lo descifra con `MATCH_PASSWORD`. Secrets clave: `APP_STORE_CONNECT_API_KEY_*` (auth con App Store Connect), `MATCH_GIT_URL`, `MATCH_PASSWORD` y `MATCH_GIT_BASIC_AUTHORIZATION` (base64 de `user:PAT`, obligatorio para clonar por HTTPS — SSH falla sin clave en el runner).

### 4. Web (wasmJs) → Firebase Hosting
JDK 21, build de la distribución y deploy con la action oficial. `firebase.json` mapea los targets `consumer`/`admin` a `‹modulo›/build/dist/wasmJs/productionExecutable`:

```yaml
- run: ./gradlew :consumerApp:wasmJsBrowserDistribution --no-daemon
- uses: FirebaseExtended/action-hosting-deploy@v0
  with:
    firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    projectId: inemsellar-app
    target: consumer   # o admin
    channelId: live
```

### 5. Cloud Functions
Node 20, `npm ci --prefix functions`, escribe `functions/.env` (`ADMIN_EMAILS`) y la SA en `$RUNNER_TEMP`, luego despliega **solo los contadores** (los dos entornos), nunca las blocking-auth:

```yaml
- run: |
    firebase deploy --project inemsellar-app --non-interactive --force \
      --only functions:consejosVoteCounter,functions:onReportCreate,functions:consejosVoteCounterDebug,functions:onReportCreateDebug
```

## Gotchas
- **NO hay quality gate en CI.** Ningún workflow corre `test`, `ktlintFormat` ni `check`. La calidad se valida **localmente** (el `/validate` del harness lo compensa); no confíes en el CI para atrapar tests rojos o lint.
- **Casi todos los triggers `push` están comentados.** Web y functions son `workflow_dispatch`-only (los bloques `push:` están en comentarios); solo Android/iOS reaccionan de verdad a tags `v*`. Un merge a `develop`/`main` **no despliega nada** por sí solo.
- **`GOOGLE_SERVICES_JSON_B64` debe ser base64 de una sola línea.** Recréalo con `base64 -i consumerApp/google-services.json | tr -d '\n' | gh secret set GOOGLE_SERVICES_JSON_B64`; el pipeline hace `tr -d '[:space:]'` y valida el JSON, y aborta si no parsea.
- **Keystore = upload key de Play.** `SIGNING_*` debe coincidir con la upload key del Play Console; si no, la AAB se rechaza con `DEVELOPER_ERROR` (rompe IAP/license-tester).
- **JDK equivocado.** Web necesita 21; usar 17 (como Android/iOS) puede fallar el build wasmJs. Cada workflow fija su versión con `setup-java`.
- **`concurrency` no cancela.** `cancel-in-progress: false`: dos runs del mismo tag se serializan, no se matan — evita subir dos veces a la store.
- **iOS match por HTTPS, no SSH.** Sin `MATCH_GIT_BASIC_AUTHORIZATION` el clone del repo de certs falla en CI (no hay clave SSH en el runner).

Fuente: `.github/workflows/{deploy-android,deploy-ios,firebase-hosting-consumer,firebase-hosting-admin,deploy-functions,deploy}.yml` y `firebase.json` (proyecto inemsellar).
