---
name: kotlin-test-turbine-fakes
description: Úsala al escribir tests en proyectos KMP/CMP de AppToLast — cuando traduzcas criterios Gherkin a tests, testees ViewModels o Flows/StateFlow, o necesites fakes. Define el patrón de test estándar de la flota: kotlin.test puro + Turbine + kotlinx-coroutines-test + fakes escritos a mano (sin Kotest, sin MockK), con la estructura Given/When/Then.
version: 0.1.0
---

# Receta: testing con kotlin.test + Turbine + fakes

Patrón de test **canónico** de los proyectos KMP de AppToLast. Fuente: `BaseLogin :custom-login` (suite más completa de la org) e inemsellar `consumerApp/commonTest`.

## Cuándo usarla
- Al traducir `Scenario [AC-xx]` (Gherkin del spec) a tests (`tdd-test-writer`).
- Al testear ViewModels, casos de uso, mappers o `Flow`/`StateFlow`.
- Al necesitar dobles de test (repos, servicios, ports de plataforma).

## Stack (no desviarse salvo que el proyecto diga otra cosa)
- **`kotlin.test`** — `@Test`, `assertEquals`, `assertIs`, `assertTrue`, `@BeforeTest`/`@AfterTest`. **Nada de Kotest.**
- **Turbine** — testear `Flow`/`StateFlow` (`test { awaitItem() … }`).
- **kotlinx-coroutines-test** — `runTest`, `StandardTestDispatcher`, `Dispatchers.setMain(dispatcher)` en `@BeforeTest` + `Dispatchers.resetMain()` en `@AfterTest`.
- **ktor-client-mock** — si hay HTTP.
- **Fakes escritos a mano** — implementan la interfaz de dominio; **nada de MockK/mockmp**.

## Ubicación
- Por defecto **`consumerApp/commonTest`** (camino rápido: corre como Android unit test con `./gradlew :consumerApp:testDebugUnitTest`, y en iOS/wasmJs con `:consumerApp:allTests`).
- `:shared:commonTest` solo si la lógica vive en `:shared` (recuerda: no hay unit-test Android host para `:shared`; corre en iOS sim / wasmJs).

## Esqueleto (ViewModel + StateFlow con Turbine)

```kotlin
class FeatureViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest fun setUp() { Dispatchers.setMain(dispatcher) }
    @AfterTest fun tearDown() { Dispatchers.resetMain() }

    @Test
    fun `AC-01 al ocurrir X el estado pasa a Success`() = runTest {
        // Given
        val repo = FakeFeatureRepository(items = listOf(sampleItem()))
        val vm = FeatureViewModel(repo)

        // When / Then
        vm.uiState.test {
            assertIs<FeatureUiState.Loading>(awaitItem())
            vm.load()
            val success = awaitItem()
            assertIs<FeatureUiState.Success>(success)
            assertEquals(1, success.items.size)
            cancelAndIgnoreRemainingEvents()
        }
    }
}

private class FakeFeatureRepository(
    private val items: List<Item> = emptyList(),
) : FeatureRepository {
    override fun observe(): Flow<List<Item>> = flowOf(items)
    override suspend fun refresh(): Result<Unit> = Result.success(Unit)
}
```

## Ports de plataforma (para testear lógica que toca SDK nativo)
Si la feature usa un SDK solo-plataforma (RevenueCat, Firebase, WebView), **define un port/interfaz en `commonMain`** y testea la lógica con un fake en `commonTest`; el actual real vive en `mobileMain`/`androidMain`/`iosMain`.

```kotlin
// commonMain
interface IapIdentity { suspend fun logIn(uid: String); suspend fun logOut() }

// commonTest
class FakeIapIdentity : IapIdentity {
    val loggedIn = mutableListOf<String>(); var loggedOut = 0
    override suspend fun logIn(uid: String) { loggedIn += uid }
    override suspend fun logOut() { loggedOut++ }
}
```

## Reglas TDD del harness
- Un test (o pocos) **por `AC-xx`**, con el AC en el nombre backtick.
- El test se escribe **en rojo** en `/test` y es **inmutable** en `/implement` (fase 1). El `implementer` no lo toca.
- Estructura **Given/When/Then** visible dentro de cada test.
