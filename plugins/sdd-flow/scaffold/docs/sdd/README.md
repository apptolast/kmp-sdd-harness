# Spec-Driven Development — guía práctica

Las reglas completas están en `../../.claude/sdd/reglas.md` (reglas de oro y flujo) y en la sección
*Guardarraíles KMP* del `CLAUDE.md` (hechos del proyecto y comandos). Esta es la versión corta.

## Por qué

Que los cambios hechos con IA sean controlados, trazables y testeables: la intención se commitea, una
persona aprueba en los gates y cada cambio va respaldado por TDD. Cuando algo falle dentro de seis
semanas, el razonamiento estará en el repositorio y no en un chat que nadie encuentra.

## El flujo

```
define 🚦  →  tasks 🚦  →  implement (TDD)  →  converge  →  PR 🚦
                            │   ↑                 │
                            │   ├─ tareas nuevas ←┘   huecos que encuentra converge
                            ↓   │
                         change─┘                     la intención o el diseño cambiaron (🚦 si es material)

lane rápido:  plan en el chat 🚦  →  implement (TDD)  →  PR 🚦
```

Ajusta el proceso al cambio: un cambio **rápido** (un fichero, sin ambigüedad, sin código compartido
entre targets) lleva un plan de cinco líneas en el chat en vez de documentos; un **bug** usa
`spec-bug.md`; todo lo demás va por el camino estándar. Ante la duda, el estándar.

## Ejecutarlo

```
/sdd-flow:define    LJ-15            # lee el ticket de Jira si hay MCP, crea specs/ y la rama
/sdd-flow:tasks     lj-15-room-setup
/sdd-flow:implement lj-15-room-setup
/sdd-flow:change    lj-15-room-setup — el filtro ahora aplica a productos, no a categorías
/sdd-flow:converge  lj-15-room-setup # informe + ofrece el PR contra develop
/sdd-flow:promote   lj-15-room-setup # tras el merge: aprendizajes a engram / kmp-recipes
```

Cada comando resuelve `specs/<slug>/` y se lo pasa a un subagente, que carga solo lo que necesita.

## Mirar más allá del ticket

`define` incluye una **evaluación de diseño**: antes de planificar, el agente lee el código que toca el
cambio y busca señales de que el arreglo obvio sería un parche más —un flag nuevo junto a otros
parecidos, lógica duplicada entre pantallas, un síntoma arreglado lejos de su causa, lógica de negocio
en `androidMain`/`iosMain`, código que no se puede testear en `commonTest`—. Entonces propone:

- **A** — cambiarlo in situ;
- **B** — refactorizar primero para que el cambio sea sencillo;
- **C** — hacer A ahora y registrar el refactor como deuda de diseño.

Decides tú en el gate. Un refactor aprobado se convierte en `R1`, `R2`…, en alcance como un criterio de
aceptación, y `tasks` lo programa primero, detrás de tests de caracterización y en sus propios commits.

## Revisar en un gate

Cada gate termina con el mismo resumen corto: qué se propone, las decisiones que tienes que tomar
(numeradas, cada una con una recomendación), los supuestos, qué cambió desde la última aprobación y qué
no se comprobó. Responde por número: *«apruebo, pero D2 → B»*.

## Los checks caros necesitan tu sí

El agente lee código, luego escribe un test o una preview, luego te pregunta. Nunca arranca un emulador
o un simulador, maneja la app ni ejecuta tests instrumentados sin tu aprobación para esa ejecución, y el
hook del plugin bloquea esos comandos hasta que la das.

## Los cuatro documentos, y por qué existe `journal.md`

`spec.md`, `plan.md` y `tasks.md` se releen en cada iteración, así que son cortos y con presupuesto. Todo
lo demás —notas de descubrimiento, mediciones, sondeos, deuda de diseño, resultados de converge, cambios
tras la aprobación— va a `journal.md`, que no tiene presupuesto porque nada lo relee entero.

## Cuando la intención cambia después de un gate

Usa `change`, no una corrección improvisada. Aplicar el arreglo directamente al código deja los
documentos aprobados describiendo una feature que ya nadie construye, y `converge` valida contra ficción.
El re-gate muestra solo el delta: `+AC7 · ~AC3 · −T5`.

## Memoria en dos capas

- **engram** (viva): `define` la consulta, `converge` guarda gotchas, y un hook captura los fallos de
  build y test.
- **kmp-recipes** (canónica): recetas versionadas en el plugin. Crecen con `/sdd-flow:promote`.

## Comprobar tu trabajo

```bash
./scripts/sdd/spec-lint.sh            # todas las features: documentos, estado, presupuestos, trazabilidad
./scripts/sdd/spec-lint.sh <slug>     # solo una
./scripts/sdd/new-adr.sh "Título"     # siguiente ADR en docs/decisions/
```
