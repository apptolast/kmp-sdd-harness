## Detente en el 🚦 gate con este resumen

Si puedes ejecutar comandos, corre primero `./scripts/sdd/spec-lint.sh <slug>` y arregla lo que
reporte. Después termina con este resumen y nada más. Menos de 20 líneas; quien revisa responde por
número.

```text
Gate: <paso> — <slug>
Resumen: <una o dos líneas: qué y cómo>
Decidir:
  1. D1 <pregunta> → recomiendo <opción>, porque <razón>   (o "nada que decidir")
Supuestos: A1 <supuesto>   (o "ninguno")
Cambios desde la aprobación: +AC7 añadido · ~AC3 reescrito · −T5 tachado   (solo en re-gates)
Autocomprobación: cada AC observable y testeable · cada AC y R tiene tarea · spec-lint <resultado>
No comprobado: <una línea> · Riesgos: <una línea>
Responde "apruebo", o los números que quieres cambiar.
```
