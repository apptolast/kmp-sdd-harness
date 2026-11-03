## Los checks caros necesitan el sí del usuario

Los checks rápidos (compilar, tests de `commonTest`/JVM/simulador iOS gestionado por Gradle, ktlint,
detekt) se ejecutan libremente, siempre a través de `./scripts/sdd/gradle-signal.sh`. Lo que necesita un
dispositivo, no: arrancar un emulador o un simulador, instalar o manejar la app (`adb`, `xcrun simctl`,
`xcrun devicectl`, `xcodebuild … test`, tareas `install*`/`uninstall*` de Gradle), tests
instrumentados (`connected*AndroidTest`) y tests de screenshot en dispositivo.

- Primero responde con el código, un test en `commonTest` o una `@Preview`.
- Si aun así hace falta un dispositivo, pídelo en un único mensaje: el comando exacto, por qué la
  evidencia barata no basta y cuánto tarda más o menos. Espera un sí explícito; ese sí cubre solo esa
  ejecución.
- Un hook del plugin bloquea esos comandos. Cuando el usuario apruebe la ejecución, repítela con
  `SDD_DEVICE_APPROVED=1` delante.
- Una tarea de `tasks.md` que menciona un dispositivo no es una aprobación.
- Sin supervisión, o sin respuesta: no lo ejecutes. Ponlo en `No comprobado:` con el comando exacto.
