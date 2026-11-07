---
name: kmp-compose-rules
description: Reglas de UI con Compose Multiplatform en los proyectos KMP de AppToLast — state hoisting, StateFlow, previews obligatorias, Material 3, Compose Resources (i18n en/es), insets, listas y accesibilidad. Úsala al escribir o revisar composables, pantallas o componentes en commonMain.
---

# Reglas de Compose Multiplatform

Detalle de theming en la receta `material3-theming` y de i18n en `i18n-compose-resources` (kmp-recipes).
Si la pantalla tiene un `.pen` de Pencil, es la especificación visual: síguelo.

- **Estructura**: `<Feature>Screen` con estado (recoge el ViewModel con `koinViewModel()` y
  `collectAsStateWithLifecycle()`), y `<Feature>Content` sin estado: estado inmutable entra, eventos
  salen (`onClick: () -> Unit`). La lógica de negocio vive en el ViewModel, no en el composable.
- **Estado de UI**: `sealed interface <Feature>UiState` (`Loading` / `Success(data)` / `Error(error)`),
  expuesto como `StateFlow` con `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), …)`.
- `remember`/`rememberSaveable` para estado local de UI y `derivedStateOf` para estado calculado. Nunca
  hagas I/O ni trabajo bloqueante durante la composición: usa `LaunchedEffect` o
  `rememberCoroutineScope`.
- **Material 3 y tema del proyecto**: colores, tipografía y formas desde `MaterialTheme`; nunca valores
  fijos. Espaciado en múltiplos de 4 dp; radios 8/12/16–24 dp.
- **Strings**: ninguna string visible fija en un composable. `stringResource(Res.string.x)` con la
  entrada en `composeResources/values/strings.xml` (inglés) y `values-es/strings.xml` (español).
  Placeholders `%1$s`/`%1$d` para lo dinámico.
- **Previews (obligatorias)**: cada `Content` sin estado y cada componente de `components/` tiene una
  `@Preview` en el mismo fichero, al final, llamada `Preview<Nombre>`, envuelta en el tema del proyecto y
  con datos realistas. Varias previews si hay estados distintos (cargando, vacío, error, con datos). Las
  previews no tocan DI, red ni código de plataforma.
- **Insets y teclado**: `imePadding()` antes de `verticalScroll` en la cadena de modifiers. En Android,
  sigue la skill de Google `android-skills:edge-to-edge` para las barras de sistema.
- **Listas**: `LazyColumn`/`LazyRow` con `key` estables.
- **Accesibilidad**: `contentDescription` (externalizada) en cada icono accionable; áreas táctiles de al
  menos 48 dp.
- **Reutilización**: antes de escribir una pantalla nueva, comprueba si es una variante de una existente.
  Dos pantallas que solo difieren en la fuente de datos comparten implementación.
- **TDD**: la lógica de estado de UI va en el ViewModel, donde se testea en `commonTest`; ajusta el test
  antes de cambiar el comportamiento.
