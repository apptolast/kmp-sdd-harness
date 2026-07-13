# Spec NNN: <título de la feature>

> Rama: `feature/NNN-slug` · Proyecto: `<repo>` · Estado: draft
> El spec es el mecanismo anti-deriva: debe ser autosuficiente (releíble al inicio de cada fase).

## Contexto y objetivo
Qué problema resuelve y por qué ahora.

## Alcance
- **Dentro:** …
- **Fuera:** …

## Conocimiento reutilizable
Recetas/aprendizajes relevantes encontrados en **engram** + **kmp-recipes** (con refs: skill / observación #id / repo).
- Qué se reutiliza tal cual: …
- Qué se adapta: …

## Criterios de aceptación (Gherkin)
```gherkin
Scenario [AC-01]: <nombre>
  Given <estado inicial>
  When  <acción>
  Then  <resultado observable>

Scenario [AC-02]: <nombre>
  Given …
  When  …
  Then  …
```

## Desglose de tareas (ligero)
- [ ] T1 …
- [ ] T2 …

## Notas no funcionales
Plataformas afectadas (Android / iOS / web admin), i18n, Firebase, rendimiento, accesibilidad.
**Testabilidad:** si toca plataforma (RevenueCat/Firebase/WebView…), port/interfaz en `commonMain` para testear con fake en `commonTest`.

## Trazabilidad
| AC | Test(s) que lo cubren | ¿Rojo antes de implementar? |
|----|-----------------------|------------------------------|
| AC-01 | `…` | sí/no |
| AC-02 | `…` | sí/no |
