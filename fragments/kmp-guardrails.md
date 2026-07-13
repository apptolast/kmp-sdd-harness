# Fragmento reutilizable — Guardarraíles KMP para `CLAUDE.md`

> Copia esta sección en el `CLAUDE.md` de cada proyecto KMP y **rellena los `<…>` con los valores REALES**
> del proyecto (auditados, no genéricos). El harness SDD (subagentes `tdd-test-writer` / `implementer` /
> `reviewer`) lee estos valores. Las skills no siempre se auto-invocan → lo crítico va aquí, sí o sí.

## Guardarraíles KMP (build · test · convenciones)

### Comandos build/test (valores reales)
| Propósito | Comando |
|---|---|
| Tests del módulo compartido | `<./gradlew :shared:allTests>` |
| Tests de la app (todos) | `<./gradlew :app:allTests>` |
| Test unit rápido (Android host) | `<./gradlew :app:testDebugUnitTest>` |
| Test iOS / wasmJs | `<:app:iosSimulatorArm64Test>` / `<:app:wasmJsBrowserTest>` |
| Lint | `<./gradlew ktlintCheck>` · autoformat `<ktlintFormat>` |
| Todo | `<./gradlew check>` |

- ¿detekt configurado? `<sí/no>` → si no, el gate de `/validate` = **ktlint + tests**.
- CI: `<qué gate de calidad corre, si alguno>`.

### Stack de test
- `<kotlin.test / Kotest>` + `<Turbine>` + `<kotlinx-coroutines-test>` + `<ktor-client-mock>`. Fakes `<a mano / MockK>`.
- Los tests viven en `<módulo/source-set>`.
- Gherkin→test: cada `Scenario [AC-xx]` → función `@Test` (nombre backtick, Given/When/Then).

### expect/actual
- Común en `Foo.kt`; actuals en `Foo.<target>.kt` (`.android`/`.ios`/`.wasmJs`/`.web`). Flag `<-Xexpect-actual-classes?>`.
- Nombres lowercase-camelCase; en `commonMain` (o intermedio `<mobileMain?>`).

### Arquitectura / DI / UI
- Clean Architecture por capas (domain/data/presentation), state hoisting, `StateFlow` en el root. Sin `runBlocking`/`GlobalScope` en producción.
- Koin `<versión BOM>`: módulos `<Data/Presentation/Platform>`. Constructor injection.
- Previews `@Preview` de `<JetBrains / AndroidX>` en commonMain.
