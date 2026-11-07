## Sube la escalera de reutilización

Para en el primer peldaño que se sostenga. Casi todo el trabajo para pronto.

1. **¿Necesita existir?** Solo si lo pide un criterio de aceptación (`AC#`) o un refactor aprobado
   (`R#`).
2. **¿Ya está en el código?** Lee el código que toca el cambio y busca antes de añadir. Reutiliza o
   extiende el componente existente.
3. **¿Hay receta o aprendizaje?** Una skill de `kmp-recipes`, una skill de Google `android-skills:*`
   (pautas KMP en `sdd-flow:kmp-platform-code`) o una observación de engram (`mem_search`) que ya
   resuelva esto en la flota.
4. **¿Lo hace ya la plataforma, la stdlib o una dependencia instalada?** (Compose, Koin, Ktor,
   kotlinx-*, la librería de la integración).
5. **¿Cabe en una línea que se entienda de un vistazo?**
6. Si no: lo mínimo que satisface el criterio.

Borrar gana a añadir. Un bug se arregla una vez, en su causa, en el código compartido: encuentra todos
los llamadores de lo que cambias antes de cambiarlo.

La escalera recorta alcance, nunca calidad. No aplica a validación, manejo de errores, seguridad,
accesibilidad ni i18n, y no es excusa para parchear un problema de diseño: para eso existe un `R#`.
