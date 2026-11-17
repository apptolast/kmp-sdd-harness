---
name: kmp-compose-rules
description: Reglas de UI con Compose Multiplatform en los proyectos KMP de AppToLast — state hoisting, StateFlow, previews obligatorias, Material 3, Compose Resources (i18n en/es), insets, listas, accesibilidad y pantallas adaptativas (móvil y tableta). Úsala al escribir o revisar composables, pantallas o componentes en commonMain.
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

## Pantallas adaptativas (móvil y tableta)

Cada pantalla se diseña, se implementa y se prueba en móvil y en tableta, en vertical y en horizontal,
salvo que un ADR del proyecto diga otra cosa. La guía de Google es `android-skills:adaptive`; sus matices
en KMP, en `kmp-platform-code`.

- **Clases de anchura de Material 3**: compacta < 600 dp, media de 600 a 839 y expandida ≥ 840. Los
  umbrales son tokens del tema (en `theme/`, como el espaciado), nunca un `600.dp` suelto.
- **Quién decide**: una pantalla o una región se adapta al espacio que le dan, con `BoxWithConstraints`
  (`maxWidth` frente al token). Las decisiones de ventana (la navegación principal, uno o varios paneles)
  salen de `currentWindowAdaptiveInfo().windowSizeClass` (`isWidthAtLeastBreakpoint(…)`), de
  `org.jetbrains.compose.material3.adaptive:adaptive`. Tiene numeración propia: usa la versión que las
  notas de Compose Multiplatform emparejan con la del proyecto. Nunca por plataforma, por modelo
  (`isTablet`) ni por orientación.
- **Patrones**:
  - formularios en una columna con ancho máximo (`widthIn(max = …)` con un token);
  - listas que crecen a rejilla con `LazyVerticalGrid(GridCells.Adaptive(…))`;
  - navegación principal con `NavigationSuiteScaffold` (`material3-adaptive-navigation-suite`, con la
    versión de `material3`): barra abajo en compacta y raíl a partir de media;
  - lista-detalle con las *Scenes* de Navigation 3 si el proyecto adoptó Navigation 3
    (`android-skills:adaptive`); con Navigation Compose 2, dentro de una ruta con `ListDetailPaneScaffold`
    (`adaptive-layout`).
- **Estado que sobrevive al giro y al cambio de tamaño**: `rememberSaveable` para el estado de UI y
  `rememberLazyListState()`/`rememberScrollState()` para el desplazamiento; lo demás, en el ViewModel.
  Nunca `android:screenOrientation` ni `android:configChanges`. En iOS, el iPad entra en
  `TARGETED_DEVICE_FAMILY` (`1,2`), con las cuatro orientaciones.
- **Previews y tests**: una preview de móvil (p. ej. `@Preview(widthDp = 360, heightDp = 800)`) y dos de
  tableta, en horizontal (`1280 × 800`) y en vertical (`800 × 1280`), para el estado principal y para cada
  estado que cambie de disposición. La elección de disposición es una función pura (anchura →
  disposición) testeada en `commonTest` en los umbrales; la semántica de la pantalla, en `iosTest` a dos
  anchos (receta `compose-ui-ios`).
