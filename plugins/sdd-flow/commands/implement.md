---
description: "SDD 5/7 — hace pasar los tests a verde. NO puede tocar los tests (un hook lo bloquea)."
argument-hint: "(usa el spec activo)"
allowed-tools: ["Task", "Read", "Grep", "Glob", "Bash"]
---

# /implement — A verde

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-state.sh" set-phase implement
```

> A partir de aquí el hook **bloquea** cualquier edición de ficheros de test (lock TDD, fase 1 sin mutabilidad).

1. Lanza el subagente **implementer** (Task) para implementar el código de **producción** hasta que **todos los tests pasen a verde**, siguiendo `specs/<NNN-slug>/plan.md` y los Guardarraíles KMP (clean architecture, Koin, expect/actual, state hoisting, sin `runBlocking`/`GlobalScope`).
2. **No modifica tests.** Si un test parece incorrecto, **para y avisa** (no lo cambies): se resuelve volviendo a `/test`.
3. Ejecuta los tests hasta verde y deja el árbol compilando en todas las plataformas afectadas. El usuario continúa con `/validate`.
