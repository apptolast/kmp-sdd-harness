---
name: fastlane-release
description: Úsala al automatizar releases de una app KMP de AppToLast con fastlane — cuando montes o toques el `fastlane/` de iOS (match/TestFlight) o de Android (Play `supply`), añadas lanes de release, o configures el flujo release-por-tag (`v*`) en CI. Define la convención estándar de la flota: releases tag-driven, firma iOS por `match`, subida Android por `supply`, versión inyectada por Gradle `-P`, secretos inyectados en build-time.
version: 0.1.0
---

# Receta: automatización de releases con fastlane (iOS + Android)

Patrón **canónico** de release de los proyectos KMP de AppToLast. Fuentes: `apptolast/GreenhouseFronts` (mejor `iosApp/fastlane`: match + TestFlight) y `apptolast/AllergenGuard` (mejor `consumerApp/fastlane`: Play `supply` + metadata).

## Cuándo usarla
- Al montar `fastlane/` en un módulo nuevo (iOS `iosApp/` o Android `consumerApp/`).
- Al añadir/editar lanes de build, TestFlight, Internal testing o subida de metadata.
- Al cablear el release **por tag `v*`** en GitHub Actions.
- Al depurar firma (`match` iOS / keystore Android) o credenciales de store.

## Convención compartida (no desviarse)
- **Release tag-driven**: el `versionName` sale del tag Git (`v1.2.3` → `1.2.3`) vía `parse_tag`; el lane de CI es `release_from_tag` y lee `RELEASE_TAG` / `GITHUB_REF_NAME`.
- **Un `fastlane/` por plataforma**: `iosApp/fastlane/` (Appfile, Matchfile, Fastfile, metadata/, screenshots/) y `consumerApp/fastlane/` (Appfile, Fastfile, metadata/android/).
- **Secretos en build-time, nunca commiteados**: local → `fastlane/.env` (gitignored, cargado por fastlane-dotenv); CI → GitHub Secrets exportados como env. Los secretos de app (AdMob, RevenueCat, `google-services.json`, keystore) se inyectan en `local.properties`/`keystore.properties` justo antes de compilar.
- **Identificadores en el Appfile, credenciales en env**: el Appfile queda commiteado; `team_id`, `apple_id`, `SUPPLY_JSON_KEY`, etc. vienen de env.

## Cómo se hace — iOS (`iosApp/fastlane`, GreenhouseFronts)

### 1. `Matchfile` — firma cifrada compartida vía `match`
Un único repo privado de certificados para toda la flota (`apptolast/ios-certificates`); `match` separa por bundle id.
```ruby
git_url(ENV["MATCH_GIT_URL"]) unless ENV["MATCH_GIT_URL"].to_s.empty?
storage_mode("git")
app_identifier(["com.apptolast.greenhousefronts"])
team_id(ENV["FASTLANE_TEAM_ID"]) unless ENV["FASTLANE_TEAM_ID"].to_s.empty?
type("appstore")
```
`.env`: `MATCH_GIT_URL=https://github.com/apptolast/ios-certificates.git`, `MATCH_PASSWORD=…`, y en CI `MATCH_GIT_BASIC_AUTHORIZATION` (base64 de `user:PAT`).

### 2. Lanes (correr desde `iosApp/`)
- `bootstrap_match` — **una vez**: crea/actualiza cert + profile App Store en el repo match (`readonly: false`).
- `match_certificates` — sincroniza cert + profile (`readonly: true`).
- `build` — `.ipa` Release local, sin subir.
- `beta` — build + subida a TestFlight.
- `upload_store_assets` — solo metadata/screenshots.
- `release_from_tag` — CI: tag → TestFlight.

Helpers clave: token ASC API, prebuild del framework Kotlin, y `match` en modo readonly para firmar.
```ruby
def sync_appstore_signing(api_key:, readonly:)
  match(type: "appstore", readonly: readonly, app_identifier: [BUNDLE_ID], api_key: api_key)
end

# El framework KMP debe linkarse ANTES de build_app; configuration-cache off.
def prebuild_kotlin_framework(configuration: RELEASE_CONFIG)
  task = configuration == RELEASE_CONFIG ? "linkReleaseFrameworkIosArm64" : "linkDebugFrameworkIosArm64"
  gradle(task: ":composeApp:#{task}", project_dir: ROOT_DIR, flags: "--no-configuration-cache")
end

# versionCode de TestFlight = último visto en ASC + 1 (sin estado en el repo).
def next_testflight_build_number(api_key)
  latest_testflight_build_number(app_identifier: BUNDLE_ID, api_key: api_key, initial_build_number: 0).to_i + 1
end
```
`build_app` (gym) exporta `app-store` firmando con el profile de match:
```ruby
build_app(
  project: XCODEPROJ, scheme: SCHEME, configuration: RELEASE_CONFIG,
  export_method: "app-store",
  export_options: { provisioningProfiles: { BUNDLE_ID => "match AppStore #{BUNDLE_ID}" } },
  xcargs: "PROVISIONING_PROFILE_SPECIFIER='match AppStore #{BUNDLE_ID}'",
  output_directory: IOS_APP_DIR, output_name: "iosApp.ipa",
  include_bitcode: false, include_symbols: true, clean: true
)
```
El lane de CI incrementa versión desde el tag + build number desde ASC, firma readonly y sube a TestFlight (sin enviar a review):
```ruby
lane :release_from_tag do
  if ENV["CI"] == "true"
    ENV.delete("MATCH_KEYCHAIN_NAME"); ENV.delete("MATCH_KEYCHAIN_PASSWORD")
  end
  setup_ci(keychain_name: "kropia-temp.keychain")   # keychain temporal en CI

  tag = ENV["RELEASE_TAG"].to_s
  tag = ENV["GITHUB_REF_NAME"].to_s if tag.empty?
  version_name = parse_tag(tag)
  api_key = app_store_connect_api_key_token
  next_build = next_testflight_build_number(api_key)

  increment_version_number(version_number: version_name, xcodeproj: XCODEPROJ)
  increment_build_number(build_number: next_build, xcodeproj: XCODEPROJ)
  prebuild_kotlin_framework(configuration: RELEASE_CONFIG)
  sync_appstore_signing(api_key: api_key, readonly: true)
  build_release_ipa
  upload_to_testflight(api_key: api_key, app_identifier: BUNDLE_ID,
    skip_waiting_for_build_processing: true, distribute_external: false, skip_submission: true)
end
```
Autenticación: **App Store Connect API key** (no user/pass). `.env`: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, `ASC_API_KEY_PATH` (local `.p8`) o `APP_STORE_CONNECT_API_KEY_BASE64` (CI).

## Cómo se hace — Android (`consumerApp/fastlane`, AllergenGuard)

### 1. `Appfile` — paquete + service account de Play
```ruby
package_name("com.apptolast.menufrontend")
json_key_file(ENV["SUPPLY_JSON_KEY"]) if ENV["SUPPLY_JSON_KEY"]
```
`.env`: `SUPPLY_JSON_KEY=/ruta/play-service-account.json` (cuenta con rol ≥ *Release manager*); en CI viene del secret `SERVICE_ACCOUNT_GOOGLE_PLAY_CONSOLE_JSON`.

### 2. Modelo de versión — stateless, inyectado por Gradle `-P`
El repo **no guarda estado de versión**: `versionName` sale del tag; `versionCode` = máximo de **todos** los tracks de Play + 1 (Play exige versionCode único global). Ambos entran por propiedades Gradle, así `build.gradle.kts` no lo toca CI.
```ruby
PLAY_TRACKS = %w[production beta alpha internal].freeze

def next_version_code_from_play
  codes = PLAY_TRACKS.flat_map do |track|
    google_play_track_version_codes(track: track)
  rescue StandardError
    []
  end
  (codes.max || 0) + 1
end
```

### 3. Lanes (correr desde `consumerApp/`)
- `version` — imprime versión por defecto de `build.gradle.kts`.
- `validate_play` — comprueba credenciales listando versionCodes por track.
- `build` — AAB firmado local (`bundleRelease`).
- `internal` — build + subida a Internal testing como **DRAFT**.
- `release_from_tag` — CI: tag → Internal testing DRAFT.
- `upload_store_assets` — solo listing + screenshots.

```ruby
lane :build do |options|
  vcode = options[:version_code] || default_version_code
  vname = options[:version_name] || default_version_name
  gradle(task: ":consumerApp:clean", project_dir: ROOT_DIR)
  gradle(
    task: ":consumerApp:bundleRelease", project_dir: ROOT_DIR,
    properties: { "appVersionCode" => vcode, "appVersionName" => vname },
    flags: "--no-configuration-cache",
  )
end

lane :release_from_tag do
  tag = ENV["RELEASE_TAG"] || ENV["GITHUB_REF_NAME"]
  UI.user_error!("RELEASE_TAG/GITHUB_REF_NAME not set") if tag.to_s.empty?
  vname = parse_tag(tag)
  vcode = next_version_code_from_play
  build(version_code: vcode, version_name: vname)
  upload_to_play_store(                    # supply
    track: "internal", aab: AAB_PATH, release_status: "draft",
    skip_upload_apk: true, skip_upload_metadata: true, skip_upload_images: true,
    skip_upload_screenshots: true, skip_upload_changelogs: true,
  )
end
```
`build.gradle.kts` debe leer las propiedades (`appVersionCode`/`appVersionName`) con fallback al default, y la firma release desde `keystore.properties` (restaurado desde secrets en CI). Metadata del listing en `fastlane/metadata/android/es-ES/` (`title.txt`, `full_description.txt`, `short_description.txt`, `changelogs/default.txt`).

## Gotchas
- **`DEVELOPER_ERROR` en Android**: el keystore de subida **debe coincidir con la upload key del Play Console**. Si CI firma con otro keystore, el AAB se rechaza y las compras IAP / license-tester fallan. Verifica `SIGNING_KEY_B64`/alias/passwords contra la clave registrada en Play.
- **`match` necesita la private key de distribución presente** en el repo de certificados. Si falta (p. ej. tras rotar), `match` no puede firmar; ejecuta `bootstrap_match` (readonly false) para regenerar cert + profile. En build/beta/release usa siempre `readonly: true` — un lane de CI **nunca** debe regenerar certificados.
- **En CI, keychain temporal**: `setup_ci(keychain_name: …)` + borra `MATCH_KEYCHAIN_NAME`/`MATCH_KEYCHAIN_PASSWORD` antes, o el desbloqueo del keychain choca con el runner.
- **versionCode Android es único global**: toma el `max` de **todos** los tracks (`production/beta/alpha/internal`), no solo del que subes; si no, Play rechaza el duplicado.
- **Linka el framework KMP antes de `build_app`**: `linkReleaseFrameworkIosArm64` con `--no-configuration-cache`; si no, gym compila sin el binario Kotlin actualizado.
- **Releases se suben como DRAFT / sin review** (`release_status: "draft"`, `skip_submission: true`): un humano promueve/envía a review en la consola. No automatices el submit.
- **Auth por token, no por contraseña**: iOS usa App Store Connect API key (`.p8`), Android usa service-account JSON. No hay Apple ID/password en CI.

---
Fuente: `apptolast/GreenhouseFronts` (`iosApp/fastlane/Fastfile`, `Matchfile`, `Appfile`) y `apptolast/AllergenGuard` (`consumerApp/fastlane/Fastfile`, `Appfile`). Los nombres internos en los comentarios ("Kropia", "MenuAdmin") son code-names de esos repos.
