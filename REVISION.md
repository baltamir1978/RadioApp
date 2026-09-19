# Revisión de código — RadioApp

Estado del proyecto y trabajo pendiente. Actualizado el 19/09/2026.

## Resumen

App SwiftUI bien estructurada por responsabilidades (player, stores, servicios, vistas). La reproducción, el reconocimiento de canciones y la pantalla de bloqueo están consolidados y publicados en la release v1.0.

## Estado de Git

- Rama `main` → `origin` (`github.com/baltamir1978/RadioApp.git`), al día con el árbol de trabajo.
- Primera versión etiquetada: **`v1.0`**, con release publicada en GitHub.
- `MARKETING_VERSION` = `1.2` y `CURRENT_PROJECT_VERSION` = `3` (subido el 19/09/2026 para el envío con la letra). Este último hay que incrementarlo en cada envío a TestFlight, aunque la versión de cara al usuario no cambie; está también en `Tools/add_widget_target.rb`, que lo aplica al widget.

## Resuelto desde la revisión anterior

- ✅ **Errores de stream visibles y recuperables**: reconexión automática con reintentos escalonados, vigilante de conexión caída y aviso en pantalla; `LocalStreamProxy` rescata las emisoras cuyo servidor describe mal el stream.
- ✅ **Trazabilidad**: la reproducción emite trazas con `os.Logger` bajo `com.radioapp.playback`, que es lo único que distingue las causas de un fallo de stream (todas se ven igual desde la interfaz). No son *logs* de depuración sueltos: están puestos a propósito y documentados en el README.
- ✅ **App Group** en uso para compartir el estado de reproducción con el widget (`Shared/WidgetShared.swift`).
- ✅ **`.gitignore`** presente; no hay `xcuserdata/` ni `*.xcuserstate` versionados.
- ✅ **Capabilities documentadas** en el README (Background Modes, App Groups, SiriKit).
- ✅ **Cuelgue silencioso** (08/09/2026): `handleTimeControl(.paused)` solo desarmaba el vigilante, así que un `AVPlayer` que se pausaba solo dejaba `isPlaying == true` sin audio y había que pulsar play dos veces. Ahora `scheduleUnexpectedPauseRecovery()` reintenta de forma escalonada y reconstruye el stream si reanudar no basta.
- ✅ **Salto al altavoz del móvil** (08/09/2026): al desaparecer el Bluetooth del coche, la reconexión reanudaba sobre la ruta nueva y la radio empezaba a sonar por el teléfono. Se observa `routeChangeNotification`, y `.oldDeviceUnavailable` pausa en vez de reintentar. Retirado además `.allowBluetoothHFP` de la sesión `.playback`.
- ✅ **Carátulas que no llegaban** (08/09/2026): un solo fallo de red condenaba a la canción entera a quedarse con el logo, porque la clave se marcaba como buscada antes de conocer el resultado. Ahora se distingue "sin carátula" de "falló la red", con reintentos y caché por canción.
- ✅ **Migración a Swift 6** (16/09/2026): `SWIFT_VERSION = 6.0` en todos los targets, compila sin avisos con Xcode 27. Lo que destapó:
  - `LocalStreamProxy` y su `Relay` estaban aislados en el actor principal por el aislamiento por defecto del proyecto, pero los llaman las colas de Network y URLSession; en Swift 6 eso cierra la app en cuanto llega tráfico. Ahora son `actor` con su propia `DispatchSerialQueue` como ejecutor, y cada callback entra con `assumeIsolated`, sin saltos ni reordenación. `NWListener` exige `newConnectionHandler` **antes** de `start`. Probado con el stream de Cassette FM: sondeo `Range: bytes=0-1` → `200` con cabeceras ICY, dos conexiones a la vez y `stop()` repetido.
  - `StreamSinkBox` pasa a `Sendable` con `OSAllocatedUnfairLock`, y los tres callbacks C de `StreamDecoder` dejan de necesitar `nonisolated(unsafe)`. Quedan dos `@unchecked Sendable`, justificados: `StreamMatcher` (guarda un `SHSession`, que no es `Sendable`) y `StreamDecoder` (estado C de AudioToolbox confinado a la cola de URLSession).
  - El delegado de metadatos ICY es ahora `@preconcurrency` y aislado en el actor principal, que es donde ya se entregaba (`queue: .main`).
- ✅ **Cierre inmediato al elegir emisora** (18/09/2026): secuela de la migración a Swift 6. El `requestHandler` de `MPMediaItemArtwork` se construía dentro de un `MainActor.run`, así que heredaba el aislamiento del actor principal; pero `MPNowPlayingInfoCenter` lo llama desde su propia cola, y en Swift 6 el compilador mete ahí una comprobación de ejecutor que aborta el proceso (`BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on queue [com.apple.main-thread]`, `EXC_BREAKPOINT`). Como la carátula se carga nada más arrancar una emisora, la app se cerraba siempre. La carátula se construye ahora antes de volver al actor principal, en contexto no aislado. Comprobado en el simulador con iOS 26.5: cuatro emisoras encadenadas (Cassette FM, Kiss FM, Cadena 100, La Indie), audio en las cuatro y ningún informe de cierre.

- ✅ **Letra sincronizada, portada de MacRadio** (19/09/2026). La app no es pública, así que la letra de LRCLIB va dentro (`LYRICS_EMBEDDED` activado en el target de la app). Lo que llegó con ella:
  - `ShazamService` es ahora uno solo (`shared`) para la pantalla, CarPlay y el reproductor, que aplica los resultados (título, carátula, historial) y guarda la posición en la canción. El historial ya no se escribe desde las vistas, que duplicaban entradas en cuanto el reproductor ponía títulos.
  - Inicio de canción por el cambio de título (marca de tiempo del bloque de metadatos, menos el retraso aprendido de la emisora) y por Shazam a los ~20 s; ajuste − / + / ↺ por emisora y toque en la línea que suena; títulos caducados y emisoras sin títulos nombrados por Shazam; búsqueda de letras de colaboraciones.
  - `StreamDecoder` no pasa a Shazam la ráfaga inicial de audio atrasado (en MacRadio dejaba la letra ~1 s tarde).
  - Las identificaciones automáticas solo con la app en pantalla (cada una abre una segunda conexión); al volver se ponen al día.
  - Reproductor y letra lado a lado en pantallas anchas (plegable abierto, iPad), con la hoja a tamaño de página; en el iPhone, «Ver letra». Widget «Sonando ahora» en tamaño grande y extragrande con la letra por líneas; al tocarlo abre el reproductor (`radioapp://nowplaying`).
  - Comprobado en el simulador (iPhone 18 Pro y iPad mini, iOS 27): Cadena 100 con Shazam por la segunda conexión (6 s de ráfaga descartados), letra sincronizada y dos columnas en el iPad. De paso: la etiqueta «EN DIRECTO» salía cortada («E…») y `Tools/add_widget_target.rb` seguía en Swift 5.0.

## Puntos fuertes

- Separación limpia de capas: `RadioPlayer`, `StationsStore`, `HistoryStore`, servicios (`RadioBrowserService`, `ShazamService`).
- Reproducción en segundo plano + Now Playing correctamente declarados en `Info.plist`.
- Localización completa en 5 idiomas.
- Código compartido app↔widget aislado en `Shared/`.

## Pendiente

### Seguridad / configuración
- `NSAllowsArbitraryLoads = true` permite tráfico HTTP sin cifrar. Es habitual en apps de radio (muchos streams siguen siendo HTTP), pero conviene restringirlo por dominio con `NSExceptionDomains` para pasar mejor la revisión de App Store, o al menos dejar por escrito el motivo en la ficha de revisión.

### Pruebas
- **No hay tests.** Para la lógica pura serían baratos y útiles: parseo de la respuesta de Radio Browser, `Station.initials`, el parseo de deep links, `IgnoredTitle.key(station:title:)` y la reescritura de cabeceras de `LocalStreamProxy` (ya es una función pura: `Relay.responseHead(for:)`).

### Verificación en dispositivo
Lo que el simulador no cubre y sólo se puede comprobar en el coche o en el iPhone:
- **La letra en el iPhone** (build 3): que vaya a tiempo sin tocar − / +, «Ver letra» en el iPhone, el widget grande con la letra avanzando (no se ha podido ver en el simulador: no deja añadir widgets desde la línea de comandos) y que en CarPlay o con la app en segundo plano no se hagan identificaciones solas.
- Kiss FM arrancando con 5G (su fallo dependía de la latencia de la red móvil).
- Que la pantalla de bloqueo y CarPlay ya no repiten el nombre de la emisora entre canciones.
- Reconocimiento con Shazam en CarPlay, widget y deep link `radioapp://`.
- **Los tres arreglos del 08/09/2026**, que por definición sólo se dan en marcha: que la app no
  se quede muda tras una llamada, que al perder el Bluetooth calle en vez de pasar al altavoz, y
  que Los 40 muestre la carátula del disco. Las trazas de `com.radioapp.playback` (tabla en el
  README) dicen por cuál de los caminos ha ido cada caso.
- **La migración a Swift 6** en el iPhone y en el coche: reproducción a través del proxy, reconexiones
  y metadatos ICY. Un fallo de aislamiento aquí no da error, cierra la app.
