---
name: buildkonfig-secrets
description: Úsala al configurar secretos, ad-unit-ids, URLs o el entorno de build en un proyecto KMP de AppToLast con BuildKonfig — cuando necesites exponer un valor de local.properties al código común, resolver el entorno con la variable única APP_ENV (debug/release), derivar FIRESTORE_DATABASE_ID, o inyectar secretos en CI (GitHub Actions). Cubre el bloque buildkonfig de build.gradle.kts, el orden de resolución de APP_ENV y la inyección en local.properties desde GitHub Secrets.
version: 0.1.0
---

# Receta: secretos y entorno con BuildKonfig

Patrón **canónico** de config por build de AppToLast. BuildKonfig **0.22.x** lee de `local.properties` (gitignored) y genera un objeto `BuildKonfig` accesible desde `commonMain`. El entorno se gobierna con **una sola variable, `APP_ENV`** (`debug`/`release`). Fuente: inemsellar (`:shared` + `:consumerApp`).

## Cuándo usarla
- Al añadir un secreto/URL/ad-unit-id que el código común debe leer (RevenueCat, AdMob, Firebase, URLs).
- Al resolver el entorno de build (`APP_ENV`) o derivar valores de él (`FIRESTORE_DATABASE_ID`, `IS_RELEASE`).
- Al inyectar secretos en CI (GitHub Actions) sin commitearlos.

## Cómo se hace

### 1. Plugin + carga perezosa de `local.properties`
```kotlin
// build.gradle.kts (cada módulo que necesite BuildKonfig)
plugins { alias(libs.plugins.buildkonfig) }   // id "com.codingfeline.buildkonfig", version 0.22.0

val localProperties: Properties by lazy {
    Properties().apply {
        val file = rootProject.file("local.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
}
```

### 2. `APP_ENV` se resuelve UNA vez en el `build.gradle.kts` raíz
Prioridad estricta: **`-PAPP_ENV` > `local.properties` > heurística por tarea (`release` si alguna tarea contiene "release") > `debug`**. Se publica en `extra["appEnv"]` para que todos los módulos lo consuman.

```kotlin
// build.gradle.kts (raíz)
val appEnv: String = run {
    val fromProp  = (findProperty("APP_ENV") as String?)?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
    val fromLocal = Properties().apply {
        val f = rootProject.file("local.properties"); if (f.exists()) f.inputStream().use { load(it) }
    }.getProperty("APP_ENV")?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
    val fromTasks = if (gradle.startParameter.taskNames.any { it.lowercase().contains("release") }) "release" else "debug"
    (fromProp ?: fromLocal ?: fromTasks).also {
        require(it == "debug" || it == "release") { "APP_ENV inválido: '$it' (usa 'debug' o 'release')" }
    }
}
extra["appEnv"] = appEnv
logger.lifecycle("APP_ENV = $appEnv")
```

### 3. El bloque `buildkonfig` (leer `local.properties` con default)
Cada `buildConfigField(TYPE, "NAME", value)` se vuelve `BuildKonfig.NAME`. **Siempre** da un default a `getProperty` para que el build no rompa cuando falta el secreto en la máquina del dev.

```kotlin
// consumerApp/build.gradle.kts
import com.codingfeline.buildkonfig.compiler.FieldSpec.Type.STRING
import com.codingfeline.buildkonfig.compiler.FieldSpec.Type.BOOLEAN

val appEnv = rootProject.extra["appEnv"] as String   // consume el valor del raíz

buildkonfig {
    packageName = "com.mobincube.android.sc_WRTRG.app_72671"
    defaultConfigs {
        buildConfigField(STRING, "ADMOB_BANNER_ANDROID", localProperties.getProperty("ADMOB_BANNER_ANDROID", ""))
        buildConfigField(STRING, "ADMOB_APP_OPEN_ANDROID", localProperties.getProperty("ADMOB_APP_OPEN_ANDROID", ""))
        buildConfigField(STRING, "REVENUECAT_ANDROID_API_KEY", localProperties.getProperty("REVENUECAT_ANDROID_API_KEY", ""))
        buildConfigField(STRING, "REVENUECAT_IOS_API_KEY", localProperties.getProperty("REVENUECAT_IOS_API_KEY", ""))
        buildConfigField(STRING, "SEPE_IA_URL", localProperties.getProperty("SEPE_IA_URL", "https://…"))
        // Derivados de APP_ENV — no van en local.properties:
        buildConfigField(STRING,  "APP_ENV",    appEnv)
        buildConfigField(BOOLEAN, "IS_RELEASE", (appEnv == "release").toString())
    }
}
```

### 4. Derivar `FIRESTORE_DATABASE_ID` de `APP_ENV` (BuildKonfig de `:shared`)
`debug` → base Firestore `"debug"`; `release` → `"(default)"`. Se admite un override puntual con `-PFIRESTORE_DATABASE_ID=…` (p. ej. migraciones):

```kotlin
// shared/build.gradle.kts
val appEnv = rootProject.extra["appEnv"] as String
val firestoreDatabaseId = (project.findProperty("FIRESTORE_DATABASE_ID") as String?)
    ?: if (appEnv == "release") "(default)" else "debug"

buildkonfig {
    packageName = "com.mobincube.android.sc_WRTRG.app_72671.shared"
    defaultConfigs {
        buildConfigField(STRING, "APP_ENV", appEnv)
        buildConfigField(STRING, "FIREBASE_API_KEY", localProperties.getProperty("FIREBASE_API_KEY", ""))
        buildConfigField(STRING, "FIREBASE_PROJECT_ID", localProperties.getProperty("FIREBASE_PROJECT_ID", "inemsellar-app"))
        buildConfigField(STRING, "FIRESTORE_DATABASE_ID", firestoreDatabaseId)
    }
}
```

### 5. Consumir desde código común
```kotlin
import com.mobincube.android.sc_WRTRG.app_72671.BuildKonfig          // :consumerApp
import com.mobincube.android.sc_WRTRG.app_72671.shared.BuildKonfig   // :shared (packageName distinto)

actual val revenueCatApiKey: String = BuildKonfig.REVENUECAT_ANDROID_API_KEY
if (BuildKonfig.IS_RELEASE) LogLevel.WARN else LogLevel.DEBUG
```

### 6. CI: inyectar secretos en `local.properties` (GitHub Actions)
El pipeline **no** commitea `local.properties`; lo escribe en runtime desde GitHub Secrets antes de `assembleRelease`, forzando `APP_ENV=release`:
```yaml
# .github/workflows/deploy.yml — step "Create local.properties"
run: |
  echo "ADMOB_BANNER_ANDROID=${{ secrets.ADMOB_BANNER_ANDROID }}" >> local.properties
  echo "REVENUECAT_ANDROID_API_KEY=${{ secrets.REVENUECAT_ANDROID_API_KEY }}" >> local.properties
  echo "FIREBASE_API_KEY=${{ secrets.FIREBASE_API_KEY }}" >> local.properties
  echo "APP_ENV=release" >> local.properties
```
`google-services.json` va aparte: se decodifica de `GOOGLE_SERVICES_JSON_B64` a `consumerApp/google-services.json` (no cabe en BuildKonfig).

## Gotchas
- **`packageName` por módulo**: el import de `BuildKonfig` cambia según el módulo (`…app_72671` en `:consumerApp`, `…app_72671.shared` en `:shared`). Importa el correcto o leerás campos que no existen.
- **`APP_ENV` se resuelve solo en el raíz**: cada módulo hace `rootProject.extra["appEnv"] as String`; no re-implementes la heurística por módulo (se desincronizaría). El raíz loguea `APP_ENV = …` — míralo para confirmar el entorno.
- **Heurística de tarea traicionera**: cualquier tarea cuyo nombre contenga "release" fuerza `APP_ENV=release` (p. ej. `assembleRelease`), lo que en release apunta a Firestore `(default)`. Para un build de debug que toque tareas "release", pasa `-PAPP_ENV=debug` explícito.
- **Siempre da default a `getProperty`**: `localProperties.getProperty("KEY", "")`. Sin el default, un dev sin ese secreto rompe el build en vez de degradar (las keys en blanco se manejan en runtime, p. ej. RevenueCat hace no-op).
- **Las keys de BuildKonfig acaban en el binario**: solo mete valores **públicos/cliente** (SDK keys públicas de RevenueCat `goog_`/`appl_`, ad-unit-ids, API key de Firebase). Nunca secretos de servidor ni service-accounts.
- **`local.properties` está gitignored**: los secretos viven ahí en local y en GitHub Secrets para CI; no los commitees. Cada dev baja `google-services.json` / `GoogleService-Info.plist` de Firebase Console a mano.

---
Fuente: inemsellar — `build.gradle.kts` (raíz, resolución de `APP_ENV`), `shared/build.gradle.kts` (bloque buildkonfig + `FIRESTORE_DATABASE_ID`), `consumerApp/build.gradle.kts` (buildkonfig con ADMOB/REVENUECAT/`IS_RELEASE`), `.github/workflows/deploy.yml` (inyección de secretos), y la sección "Secrets (BuildKonfig via local.properties)" de `CLAUDE.md`.
