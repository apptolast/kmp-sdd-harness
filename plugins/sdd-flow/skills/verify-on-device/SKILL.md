---
name: verify-on-device
description: Protocolo para verificar el comportamiento de la UI en un proyecto KMP/CMP, de la evidencia más barata a la más cara, y que termina —solo con la aprobación del usuario— manejando un dispositivo Android (adb) o un simulador iOS (xcrun simctl). Úsala cuando pidan comprobar, reproducir o confirmar cómo se comporta una pantalla, o cuando un bug describe algo visual.
---

# Verificar la UI — primero la evidencia más barata

Manejar un dispositivo es la forma más cara de responder una pregunta sobre la UI: arrancar un emulador
o un simulador, instalar, lanzar, taps que se rompen cuando se mueve el layout, y capturas o volcados
que cuestan miles de tokens cada uno. A veces es la única forma. Nunca es la primera, y nunca ocurre sin
el sí del usuario.

**Sube estos peldaños en orden y para en el primero que responda la pregunta.**

## 1. Leer el código

Casi todas las preguntas de UI se responden con el composable, el ViewModel y el `StateFlow` entre
ambos. Traza el estado, no lo reproduzcas. Nombrar el fichero y la línea que causan el comportamiento es
mejor respuesta que una captura del síntoma.

## 2. Escribir o ejecutar un test

Si es lógica de estado —un filtro, un toggle, un estado vacío, una validación— va en un test de
`commonTest` sobre el ViewModel (kotlin.test + Turbine). Un test que falla es más barato que un
dispositivo, reproducible, y se queda.

## 3. Usar una preview

Para dudas puramente visuales, una `@Preview` con el estado relevante se renderiza en el IDE sin
dispositivo, sin instalar y sin red. Si el proyecto tiene target de escritorio (`jvm`), `./gradlew
:composeApp:run` es otra opción barata para ver la pantalla común.

## 4. Preguntar al usuario

El usuario tiene la app abierta. «¿Aparece el diálogo cuando no hay región seleccionada?» es una pregunta
y cero llamadas a herramientas. Prefiérelo a una secuencia de cinco pasos con `adb` siempre que una
persona pueda responder antes, sobre todo si hay login, datos reales o un dispositivo concreto.

## 5. Manejar el dispositivo — solo con aprobación

Solo cuando los peldaños anteriores no bastan: un bug de ciclo de vida o de navegación, una regresión
que solo ocurre en dispositivo real, o una petición explícita de verificar en hardware.

**Pregunta antes, cada vez.** En un mensaje: los comandos que vas a ejecutar, por qué los peldaños 1–4 no
responden y cuánto tardará más o menos. Espera un sí explícito; cubre solo esta ejecución. El hook del
plugin bloquea estos comandos: tras el sí, ponles delante `SDD_DEVICE_APPROVED=1`. Sin supervisión o sin
respuesta: para, y lista los pasos en `No comprobado:`.

### Android

```bash
SDD_DEVICE_APPROVED=1 adb devices -l                                  # confirma un único destino
SDD_DEVICE_APPROVED=1 ./gradlew :composeApp:installDebug
SDD_DEVICE_APPROVED=1 adb -s <serial> shell am start -n <package>/<activity>
SDD_DEVICE_APPROVED=1 adb -s <serial> shell uiautomator dump /sdcard/ui.xml
SDD_DEVICE_APPROVED=1 adb -s <serial> pull /sdcard/ui.xml /tmp/ui.xml
grep -o '<node [^>]*text="[^"]*<texto>"[^>]*>' /tmp/ui.xml           # solo el nodo que necesitas
SDD_DEVICE_APPROVED=1 adb -s <serial> logcat -d -t 200 -s <TAG>      # acotado y filtrado
```

### iOS (simulador)

```bash
xcrun simctl list devices booted                                     # leer es libre
SDD_DEVICE_APPROVED=1 xcrun simctl boot "<iPhone …>"
SDD_DEVICE_APPROVED=1 xcrun simctl install booted <ruta/a/App.app>
SDD_DEVICE_APPROVED=1 xcrun simctl launch --console-pty booted <bundle-id>
SDD_DEVICE_APPROVED=1 xcrun simctl io booted screenshot /tmp/ios.png
SDD_DEVICE_APPROVED=1 xcrun simctl spawn booted log show --last 2m --predicate 'process == "<App>"' | tail -n 100
```

Reglas de este peldaño:

- Llama a `adb` y `xcrun` por su nombre, para que el hook los reconozca.
- En Android, pasa siempre `-s <serial>`: un segundo dispositivo conectado hace que un comando sin
  calificar actúe sobre el equivocado.
- Saca las coordenadas de los taps del volcado de `uiautomator`, nunca de una suposición sobre el
  layout. Busca con grep el nodo que necesitas: leer el volcado entero cuesta miles de tokens.
- Haz una captura solo cuando la pregunta es visual y el volcado no la responde.
- Di qué peldaño usaste y por qué los más baratos no bastaban.

## Registra lo que aprendas

Una reproducción que costó una sesión de dispositivo merece guardarse. Pon el hallazgo —los pasos, el
tag, el fichero culpable— en `specs/<slug>/journal.md`, para que la siguiente sesión no lo redescubra.
