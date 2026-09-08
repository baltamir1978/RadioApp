# Revisión de código — RadioApp

Estado del proyecto y trabajo pendiente. Actualizado el 08/09/2026, tras la ronda de arreglos de audio en marcha (v1.2).

## Resumen

App SwiftUI bien estructurada por responsabilidades (player, stores, servicios, vistas). La reproducción, el reconocimiento de canciones y la pantalla de bloqueo están consolidados y publicados en la release v1.0.

## Estado de Git

- Rama `main` → `origin` (`github.com/baltamir1978/RadioApp.git`), al día con el árbol de trabajo.
- Primera versión etiquetada: **`v1.0`**, con release publicada en GitHub.
- `MARKETING_VERSION` = `1.0` y `CURRENT_PROJECT_VERSION` = `1`. Este último hay que incrementarlo en cada envío a TestFlight, aunque la versión de cara al usuario no cambie.

## Resuelto desde la revisión anterior

- ✅ **Errores de stream visibles y recuperables**: reconexión automática con reintentos escalonados, vigilante de conexión caída y aviso en pantalla; `LocalStreamProxy` rescata las emisoras cuyo servidor describe mal el stream.
- ✅ **Trazabilidad**: la reproducción emite trazas con `os.Logger` bajo `com.radioapp.playback`, que es lo único que distingue las causas de un fallo de stream (todas se ven igual desde la interfaz). No son *logs* de depuración sueltos: están puestos a propósito y documentados en el README.
- ✅ **App Group** en uso para compartir el estado de reproducción con el widget (`Shared/WidgetShared.swift`).
- ✅ **`.gitignore`** presente; no hay `xcuserdata/` ni `*.xcuserstate` versionados.
- ✅ **Capabilities documentadas** en el README (Background Modes, App Groups, SiriKit).
- ✅ **Cuelgue silencioso** (08/09/2026): `handleTimeControl(.paused)` solo desarmaba el vigilante, así que un `AVPlayer` que se pausaba solo dejaba `isPlaying == true` sin audio y había que pulsar play dos veces. Ahora `scheduleUnexpectedPauseRecovery()` reintenta de forma escalonada y reconstruye el stream si reanudar no basta.
- ✅ **Salto al altavoz del móvil** (08/09/2026): al desaparecer el Bluetooth del coche, la reconexión reanudaba sobre la ruta nueva y la radio empezaba a sonar por el teléfono. Se observa `routeChangeNotification`, y `.oldDeviceUnavailable` pausa en vez de reintentar. Retirado además `.allowBluetoothHFP` de la sesión `.playback`.
- ✅ **Carátulas que no llegaban** (08/09/2026): un solo fallo de red condenaba a la canción entera a quedarse con el logo, porque la clave se marcaba como buscada antes de conocer el resultado. Ahora se distingue "sin carátula" de "falló la red", con reintentos y caché por canción.

## Puntos fuertes

- Separación limpia de capas: `RadioPlayer`, `StationsStore`, `HistoryStore`, servicios (`RadioBrowserService`, `ShazamService`).
- Reproducción en segundo plano + Now Playing correctamente declarados en `Info.plist`.
- Localización completa en 5 idiomas.
- Código compartido app↔widget aislado en `Shared/`.

## Pendiente

### Seguridad / configuración
- `NSAllowsArbitraryLoads = true` permite tráfico HTTP sin cifrar. Es habitual en apps de radio (muchos streams siguen siendo HTTP), pero conviene restringirlo por dominio con `NSExceptionDomains` para pasar mejor la revisión de App Store, o al menos dejar por escrito el motivo en la ficha de revisión.

### Pruebas
- **No hay tests.** Para la lógica pura serían baratos y útiles: parseo de la respuesta de Radio Browser, `Station.initials`, el parseo de deep links, `IgnoredTitle.key(station:title:)` y la reescritura de cabeceras de `LocalStreamProxy`.

### Verificación en dispositivo
Lo que el simulador no cubre y sólo se puede comprobar en el coche o en el iPhone:
- Kiss FM arrancando con 5G (su fallo dependía de la latencia de la red móvil).
- Que la pantalla de bloqueo y CarPlay ya no repiten el nombre de la emisora entre canciones.
- Reconocimiento con Shazam en CarPlay, widget y deep link `radioapp://`.
- **Los tres arreglos del 08/09/2026**, que por definición sólo se dan en marcha: que la app no
  se quede muda tras una llamada, que al perder el Bluetooth calle en vez de pasar al altavoz, y
  que Los 40 muestre la carátula del disco. Las trazas de `com.radioapp.playback` (tabla en el
  README) dicen por cuál de los caminos ha ido cada caso.
