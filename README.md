# kmp-sdd-harness

Marketplace de plugins privado con el **harness SDD reutilizable** de AppToLast para proyectos KMP / Compose Multiplatform.

Es la capa 1 del sistema (lo estático y reutilizable). Mejora una vez → se propaga a todos los proyectos vía `claude plugin marketplace update`.

## Plugins

| Plugin | Qué aporta |
|---|---|
| **sdd-flow** | El flujo SDD: 7 slash commands (`/spec` `/plan` `/design-check` `/test` `/implement` `/validate` `/promote`), 5 subagentes en contexto aislado, y hooks (lock TDD de tests durante `/implement` + captura automática de fallos a engram). |
| **kmp-recipes** | Recetario canónico de integraciones KMP (RevenueCat, Firebase-REST, auth Google/Apple, fastlane, navegación, i18n, WebView, testing…), sembrado desde proyectos existentes. |

## Flujo (7 pasos, 4 gates humanos)

`/spec` (🚦spec) → `/plan` (🚦plan) → `/design-check` (🚦diseño) → `/test` (rojo) → `/implement` (verde, no toca tests) → `/validate` (🚦PR a develop) → `/promote`

## Memoria (2 capas)

- **engram** (capa viva): auto-captura + FTS de decisiones/gotchas/errores. Cross-proyecto. Setup: ver `docs/harness/engram-setup.md` en el proyecto consumidor.
- **kmp-recipes** (capa canónica): recetas versionadas y prescriptivas. Se acumulan vía `/promote`.

## Instalación en un proyecto

```bash
# Desde ruta local (desarrollo del harness):
claude plugin marketplace add /ruta/a/kmp-sdd-harness
# O desde GitHub (privado):
claude plugin marketplace add https://github.com/apptolast/kmp-sdd-harness.git

claude plugin install sdd-flow@kmp-sdd-harness
claude plugin install kmp-recipes@kmp-sdd-harness
```

## Requisitos del proyecto consumidor

- `CLAUDE.md` con la sección **Guardarraíles KMP** (comandos build/test reales, stack de test, expect/actual). Plantilla: `fragments/kmp-guardrails.md`.
- **engram** instalado y su MCP cableado (`claude mcp add engram --scope user -- engram mcp --tools=agent`).
