---
description: "SDD 4/7 — escribe los tests en ROJO en commonTest traduciendo cada scenario Gherkin. Sin mutabilidad."
argument-hint: "(usa el spec activo)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash"]
---

# /test — Tests en rojo (TDD)

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase test
```

Lee el spec activo (`specs/<NNN-slug>/spec.md`).

1. Lanza el subagente **tdd-test-writer** (Task) para traducir **cada `Scenario [AC-xx]`** a una función `@Test` (kotlin.test, nombre backtick, estructura Given/When/Then) en el source-set de test correcto (`consumerApp/commonTest` salvo que el spec diga otra cosa). Fakes escritos a mano + Turbine para Flows + `runTest` para coroutines.
2. Debe **ejecutar los tests y confirmar que están en ROJO** — fallan por falta de implementación de producción, **no** por errores de compilación del test — con el comando de test del proyecto (Guardarraíles KMP del `CLAUDE.md`).
3. Actualiza la sección **Trazabilidad** del spec (`AC-xx → test(s)`).
4. Deja los tests en rojo listos para commit. **No implementes producción.** El usuario continúa con `/implement`.
