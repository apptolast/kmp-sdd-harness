---
name: ktlint-exclude-generated-sources
description: Úsala cuando ktlint (org.jlleitschuh.gradle.ktlint) falle sobre CÓDIGO GENERADO en un proyecto KMP/CMP de AppToLast — el Res.kt/accessors de Compose Resources o los *_Impl de KSP/Room, con violaciones de indent/class-naming/wrapping que no puede autocorregir y que rompen ktlintCheck/ktlintFormat. Explica por qué los excludes por glob y por path del KtlintExtension no bastan en ktlint-gradle 14.x y da el fix canónico por .editorconfig.
version: 0.1.0
---

# Receta: excluir código generado de ktlint (KMP/CMP)

Patrón **canónico** para que ktlint deje de lintar el código generado (Compose Resources `Res.kt`, KSP/Room `*_Impl`) en la flota AppToLast. Plugin `org.jlleitschuh.gradle.ktlint` **14.x**. Fuente: inemsellar.

## Cuándo usarla
- `./gradlew ktlintCheck`/`ktlintFormat` falla con violaciones en ficheros bajo `build/generated/…` (p. ej. `Res.kt`, `Drawable0.commonMain.kt`, `FavoriteDao_Impl.kt`).
- Reglas que ktlint **no puede autocorregir** en generados: `standard:class-naming`, `standard:indent`, `standard:wrapping`, `standard:binary-expression-wrapping`.

## El problema (por qué los excludes obvios NO funcionan)
Las fuentes generadas se añaden a los **Kotlin source sets** (Compose Resources y KSP hacen `kotlin.srcDir(build/generated/…)`), así que ktlint las descubre como código fuente. Y en ktlint-gradle 14.x:

- **Los globs no valen**: `filter { exclude("**/build/**"); exclude("**/generated/**") }` NO excluye una fuente generada que es la **raíz de su propio source set** — su path *relativo* al source dir no contiene `build/`/`generated/`.
- **El exclude por path solo lo respeta `ktlintCheck`, no `ktlintFormat`**: `filter { exclude { it.file.path.contains("/build/") } }` hace pasar el *check* pero `ktlintFormat` sigue tropezando con los generados (quirk del plugin 14.x).
- **`setSource(source.filter{…})` a nivel de task ⇒ `StackOverflowError`** (el getter `source` se auto-referencia). NO lo uses.
- `exclude { }` a nivel de task tampoco lo respeta el format.

## El fix canónico: `.editorconfig`
ktlint **lee `.editorconfig` directamente** (no vía el filtro del plugin), así que desactivarlo ahí arregla **check Y format** de una vez:

```ini
# .editorconfig (raíz del repo)
[**/build/**]
ktlint = disabled

[**/generated/**]
ktlint = disabled
```

Con eso, `ktlintCheck` y `ktlintFormat` saltan todo lo generado. Opcionalmente, deja también el `filter { exclude { it.file.path.contains("/build/") } }` en el `configure<KtlintExtension>` como cinturón-y-tirantes para el check.

## Regla de CI/gate
El gate de calidad (CI, `/validate`) debe correr **`ktlintCheck`**, nunca `ktlintFormat` — `check` es idempotente y no reescribe ficheros. Con el `.editorconfig` de arriba, `ktlintFormat` también queda usable en local.

## Gotcha adyacente: conflicto `androidx.concurrent:concurrent-futures`
En algunos proyectos las tareas de ktlint/androidTest fallan al resolver `debugAndroidTestCompileClasspath` por un conflicto `androidx.concurrent:concurrent-futures` (1.1.0 estricta vs 1.2.0 transitiva vía `androidx.test.ext:junit:1.3.0`). Fuerza la versión:
```kotlin
// consumerApp/build.gradle.kts
configurations.all { resolutionStrategy { force("androidx.concurrent:concurrent-futures:1.2.0") } }
```

---
Fuente: inemsellar — `.editorconfig`, `consumerApp/build.gradle.kts` + `shared/build.gradle.kts` (`configure<KtlintExtension>`), `adminApp/build.gradle.kts`. Verificado con ktlint-gradle 14.2.0.
