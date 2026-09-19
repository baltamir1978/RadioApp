# RadioApp

App de iOS para escuchar radio por internet con reconocimiento de canciones (Shazam), widgets, CarPlay y atajos de Siri.

**Versión actual: 1.2**

## Características

- 🎵 **Reproducción de radio por streaming** sobre `AVPlayer`, con audio en segundo plano (`UIBackgroundModes: audio`) y controles en la pantalla de bloqueo (Now Playing + carátula).
- 🔎 **Búsqueda de emisoras** mediante la API pública de [Radio Browser](https://www.radio-browser.info/).
- ➕ **Emisoras propias**: añadir, editar y eliminar estaciones con URL de stream y logo.
- 🎼 **Reconocimiento de canciones** con [ShazamKit](https://developer.apple.com/shazamkit/), capturando el audio del stream en directo (`AudioStreamTap`) o descodificándolo por separado (`StreamDecoder`) en las emisoras que no admiten la captura pasiva.
- 🖼️ **Carátulas**: portada del tema en la pantalla de reproducción y en el historial, vía ShazamKit o búsqueda en la API de iTunes para las emisoras que sólo emiten texto, con caché por canción y reintentos cuando falla la red.
- 📝 **Letra sincronizada** ([LRCLIB](https://lrclib.net)) que sigue la canción línea a línea: la línea que suena se resalta y se mantiene a la vista; tocarla sincroniza la letra, y − / + / ↺ la ajustan por emisora. Como en MacRadio, el inicio de la canción sale del cambio de título (descontando lo tarde que lo cambia cada emisora) o de Shazam, y cuando una emisora deja un título ya acabado, Shazam dice qué suena. Ver «Letra».
- 📐 **Pantallas anchas** (iPhone plegable abierto, iPad): reproductor y letra lado a lado. En el iPhone, «Ver letra» cambia la carátula por la letra.
- 🔄 **Resistencia a cortes de red**: reconexión automática de streams caídos (pensada para 5G en movimiento) y un proxy local (`LocalStreamProxy`) que rescata emisoras cuyo servidor describe mal el stream.
- 🎧 **Cuidado con la ruta de audio**: si el equipo del coche o los auriculares desaparecen, la app calla en vez de seguir sonando por el altavoz del móvil; y una pausa que el usuario no ha pedido (una llamada, Siri) se recupera sola.
- 🕑 **Historial** de canciones escuchadas, con favoritos y una lista de títulos ignorados que mantiene fuera los eslóganes de la emisora.
- 📱 **Widgets** (WidgetKit): emisora en reproducción —en tamaño grande y extragrande, con la carátula y la letra avanzando línea a línea; al tocarlo se abre el reproductor—, **Letra** en tamaño pequeño y mediano (la canción arriba y la línea que suena con las siguientes debajo) y acceso rápido a emisoras. El de accesos directos es **configurable**: mantén pulsado el widget → *Editar* y elige qué emisora va en cada uno de los cuatro huecos.
- 🚗 **CarPlay** mediante `CarPlaySceneDelegate`, con panel en el salpicadero (`CarPlayDashboardSceneDelegate`).
- 🗣️ **Atajos de Siri** (`SiriIntents`).
- 🌗 **Modo claro y oscuro** con colores adaptativos.
- ♿️ **Accesibilidad**: etiquetas de VoiceOver en toda la interfaz, tipografía que escala con Dynamic Type, contraste verificado contra WCAG AA y respeto por *Reducir movimiento*.
- 🌍 **Localización en 5 idiomas**: español, inglés, alemán, francés y portugués — incluidos los widgets, las frases de Siri y los avisos de permisos.

## Requisitos

- Xcode 26 o superior (modo de lenguaje Swift 6; probado con Xcode 27)
- iOS 26.5+
- Cuenta de desarrollador de Apple (para ShazamKit, CarPlay y widgets en dispositivo real)

## Estructura del proyecto

```
RadioApp/
├── RadioApp/                  # Target principal (app iOS)
│   ├── RadioAppApp.swift      # Punto de entrada + deep links (radioapp://play?u=…)
│   ├── ContentView.swift      # Navegación principal
│   ├── RadioPlayer.swift      # Motor de reproducción (AVPlayer + Now Playing + reconexión)
│   ├── LocalStreamProxy.swift # Proxy en loopback para streams mal descritos por el servidor
│   ├── AudioStreamTap.swift   # Captura de audio del stream para Shazam
│   ├── StreamDecoder.swift    # Descodificación propia para emisoras sin captura pasiva
│   ├── ShazamService.swift    # Reconocimiento de canciones (ShazamKit)
│   ├── RadioBrowserService.swift  # Cliente de la API Radio Browser
│   ├── Station.swift / StationsStore.swift  # Modelo y persistencia de emisoras
│   ├── HistoryStore.swift / ListenedSong.swift  # Historial de canciones
│   ├── Lyrics.swift           # Panel de letra sincronizada (o enlace a Apple Music)
│   ├── LyricsService.swift    # Búsqueda en LRCLIB (colaboraciones incluidas)
│   ├── Theme.swift            # Colores adaptativos (claro / oscuro)
│   ├── CarPlay*.swift         # Integración CarPlay (lista + salpicadero)
│   ├── SiriIntents.swift      # Atajos de Siri
│   ├── *View.swift            # Vistas SwiftUI
│   ├── PrivacyInfo.xcprivacy  # Manifiesto de privacidad (App Store)
│   └── Localization/          # de, en, es, fr, pt
├── RadioWidget/               # Extensión de widgets (WidgetKit) + su propio manifiesto
├── Shared/                    # Código compartido app ↔ widget
└── Tools/                     # Scripts auxiliares (icono, target de widget)
```

> El target `RadioWidget` **se genera con `ruby Tools/add_widget_target.rb`**, no editando el
> proyecto a mano: sus fuentes, recursos y versiones están declarados ahí. Si añades un fichero
> a `RadioWidget/`, regístralo en el script — al volver a ejecutarlo recrea el target entero.

## Localización

Tres ficheros por idioma bajo `RadioApp/Localization/<idioma>.lproj/`, cada uno con su cometido:

| Fichero | Contenido |
|---|---|
| `Localizable.strings` | La interfaz. Todas las claves deben existir en los 5 idiomas. |
| `AppShortcuts.strings` | Las frases de Siri, y solo eso. Las claves son las frases tal cual están escritas en `RadioShortcuts` (en español), con los marcadores `${applicationName}` y `${station}`. |
| `InfoPlist.strings` | Los textos de permisos (`NSMicrophoneUsageDescription`). El literal del `Info.plist` es solo el respaldo. |

Dos detalles que no son evidentes:

- **La extensión de widgets tiene su propio bundle** y no puede leer los textos de la app. Los mismos `.lproj` se copian también dentro de `RadioWidget.appex` (lo hace el script del target).
- **Los App Intents se traducen por clave**: `LocalizedStringResource("intent_play_title")` y
  `@Parameter(title: "intent_slot_1")` se resuelven contra `Localizable.strings`. No pongas ahí
  el texto visible o quedará sin traducir.

Comprobar que los idiomas siguen alineados:

```sh
for l in en es fr de pt; do plutil -lint RadioApp/Localization/$l.lproj/Localizable.strings; done
```

## Accesibilidad

Criterios que conviene no romper al tocar la interfaz:

- **El acento no admite blanco encima.** `Color.brand` es verde oscuro en claro pero menta claro
  en oscuro; el blanco sobre esa variante se queda en 1,8:1. Para glifos sobre el acento se usa
  `Color.appBackground`, que se invierte con él y aguanta por encima de 5:1 en ambos modos.
- **`WidgetTheme.swift` debe reflejar a `Theme.swift`**, valores oscuros incluidos. Son dos
  ficheros distintos por fuerza (módulos separados) y se mantienen a mano.
- **`.system(size:)` no escala** con Dynamic Type. La app usa estilos semánticos (`.callout`,
  `.footnote`…); los tamaños fijos quedan solo donde el glifo vive en una caja de tamaño fijo.

## Puesta en marcha

1. Clona el repositorio y abre `RadioApp.xcodeproj` en Xcode.
2. Selecciona tu **Team** de firma en *Signing & Capabilities* para los targets `RadioApp` y `RadioWidget`.
3. Asegúrate de que están activadas las *capabilities*: **Background Modes → Audio**, **App Groups** (compartido con el widget) y **SiriKit**.
4. Compila y ejecuta. CarPlay y el micrófono necesitan un dispositivo real; Shazam sobre el
   stream y la letra sincronizada sí funcionan en el simulador (ver «Deep links»).

> Consulta también `SETUP_XCODE.md` para los pasos detallados de configuración del proyecto en Xcode.

## Letra

La letra (LRCLIB, gratuita y sin clave) se muestra dentro de la app porque RadioApp no es
pública: se instala desde Xcode o TestFlight. Mostrar letras en una app de la App Store exige
licencia, así que todo va tras la condición de compilación `LYRICS_EMBEDDED`, activada en el
target de la app; sin ella queda el enlace a Apple Music y ni una línea del código de letras.

Las marcas de LRCLIB cuentan desde el inicio de la canción, y la emisora solo dice *qué* suena.
El inicio se da por bueno si viene de:

1. **Ver cambiar el título mientras se escucha**, con la marca de tiempo del bloque de metadatos
   dentro del audio, menos lo tarde que esa emisora cambia sus títulos (`title_lag.<stream>`,
   aprendido con Shazam y promediado).
2. **Shazam** (`predictedCurrentMatchOffset`), a los ~20 s de cada canción con letra
   sincronizada. Escucha por una segunda conexión (`StreamDecoder`), que abre con una ráfaga de
   audio atrasado (Cadena 100: 6 s); esa ráfaga no se le pasa, y a su posición se le suma lo
   que el reproductor tiene en el búfer.

Encima, la letra se adelanta 1 s (se lee justo antes de cantarse) y se ajusta a mano por emisora.
Si la duración de la canción pasa (+20 s) y el título no cambia, Shazam dice qué suena y nombra
las canciones hasta que la emisora cambie el título; si no reconoce nada, se vuelve al logo. En
las emisoras sin títulos (Kiss FM), Shazam identifica cada minuto.

**Solo con la app en pantalla.** Cada identificación abre una segunda conexión al stream, así
que las automáticas (sincronizar, títulos caducados, emisoras sin títulos) solo se hacen con la
app delante, que es cuando se lee la letra; al volver a ella se ponen al día. En segundo plano o
en CarPlay no gastan datos, y una canción que nombró Shazam vuelve a la emisora al minuto.

**CarPlay no muestra la letra**: las apps de audio solo pueden usar las plantillas de Apple
(listas, cuadrícula, «Ahora suena»), ninguna admite texto largo, y no hay acceso a las pantallas
de los pasajeros. Para ellos está la app en el iPhone.

## Deep links

Los widgets abren la app con:

```
radioapp://play?u=<URL_del_stream>   # empieza esa emisora
radioapp://nowplaying                # abre el reproductor (con la letra) de lo que suena
```

`RadioAppApp.handleURL` los atiende. En compilaciones de depuración, `-open <enlace>` al
arrancar hace lo mismo (en el simulador, `simctl openurl` pide confirmación en pantalla) y
`-muted` deja el reproductor sin volumen para probar sin que suene por el Mac:

```
xcrun simctl launch <udid> Altamirano.RadioApp -muted -open "radioapp://play?u=<stream>" -open radioapp://nowplaying
```

## Diagnóstico de reproducción

Cuando una emisora no arranca o se corta, el síntoma visible es siempre el mismo (el botón alterna entre play y pausa sin sonido), así que la reproducción emite trazas con `os.Logger` bajo el subsistema `com.radioapp.playback`:

- En dispositivo: **Console.app**, filtrando por ese subsistema.
- En simulador: `xcrun simctl spawn <udid> log show --last 5m --style compact | grep com.radioapp.playback`
  (con Xcode 27, `--predicate` dentro del simulador no devuelve nada; filtrar con `grep` sí).

Las trazas distinguen las causas que producen ese mismo síntoma:

| Traza | Qué ha pasado |
|---|---|
| `watchdog fired after 25.0s (hasPlayed=false)` | La conexión nunca llegó a sonar; se reconstruye tras `connectGrace`. |
| `watchdog fired after 5.0s (hasPlayed=true)` | Sonaba y se cortó; se reconstruye tras `stallGrace`. |
| `player paused itself — resuming` | El reproductor se pausó solo (interrupción, ruta) y se está reanudando. |
| `output device went away` | Se perdió el coche o los auriculares: se pausa a propósito, no se reintenta. |
| `skipping reconnect — output fell back to the built-in speaker` | Se ha evitado que la radio vuelva a sonar por el altavoz del móvil. |
| `cover lookup failed … retrying` | La búsqueda de carátula en iTunes falló por red; se reintenta. |
| `title timestamp is …s from playback` | Distancia entre el título en el audio y lo que suena. |
| `identifying automatically` | Shazam, pedido por la app (sincronizar letra, título caducado, emisora sin títulos). |
| `second connection: …s of opening burst held back` | Audio atrasado de la ráfaga inicial que no se pasa a Shazam. |
| `player is …s behind the air` | Lo que el reproductor tiene en el búfer, sumado a la posición de Shazam. |
| `lyrics synced by ShazamKit at …s` | Shazam ha fijado la posición exacta de la canción. |
| `… changes its titles …s late` | Retraso medido entre el inicio real de la canción y su título. |
| `title unchanged past the song's end` | La canción debería haber acabado y el título sigue: se pregunta a Shazam. |
| `station title is stale — …` | Suena otra cosa: Shazam nombra las canciones hasta el próximo título. |

## Audio en el coche

Tres reglas que conviene no romper al tocar `RadioPlayer`, porque las tres nacen de fallos reales
en marcha y ninguna se reproduce en el simulador:

- **Perder el aparato de salida es motivo para callarse, no para reintentar.** Cuando el
  Bluetooth o CarPlay desaparecen, iOS mueve la ruta al altavoz y pausa. Si la lógica de
  reconexión lee esa pausa como un stream muerto y llama a `play()`, la radio empieza a sonar a
  todo volumen por el móvil. De ahí el observador de `routeChangeNotification` y el guardia
  `fellBackToBuiltInSpeaker()`, consultado antes de reconectar, de reanudar una pausa y de
  reanudar una interrupción.
- **Una pausa que el usuario no ha pedido hay que recuperarla.** `AVPlayer` se queda en
  `.paused` cuando una interrupción manda `.began` y nunca `.ended` — habitual con las llamadas
  atendidas desde la pantalla del coche. La prueba fiable de que la interrupción terminó no es
  la notificación, sino conseguir `setActive(true)` sobre la sesión.
- **`.playback` no lleva `.allowBluetoothHFP`.** HFP es el perfil de manos libres, mono y de
  calidad telefónica; declararlo hace que algunos equipos de coche lo prefieran sobre
  A2DP/CarPlay. La sesión usa `.allowBluetoothA2DP`, y `ShazamService.restoreAudioSession` tiene
  que declarar exactamente lo mismo o devolverá la reproducción por una ruta mono.

## Privacidad

La app **no recoge datos**: no hay backend propio, ni analítica, ni SDK de terceros (solo
frameworks de Apple). Las emisoras, el historial y la lista de ignorados se guardan en el
dispositivo. El tráfico de red se limita al stream y la carátula que pide el usuario, más las
consultas a Radio Browser, iTunes Search y LRCLIB (letras), sin identificador ni cuenta asociada.

- `PrivacyInfo.xcprivacy` (uno por bundle: app y widget — Apple evalúa cada uno por separado).
  Declara `NSPrivacyTracking = false`, sin dominios de seguimiento, sin datos recogidos, y una
  única API de motivo requerido: `UserDefaults` con el motivo **CA92.1** (acceso restringido a
  los datos de la propia app y su *app group*).
- `NSMicrophoneUsageDescription`: necesario para identificar canciones con Shazam.
- `ITSAppUsesNonExemptEncryption = false`: la app no usa cifrado no exento.

> Al subir a App Store Connect, el formulario de privacidad tiene que decir lo mismo que el
> manifiesto. Una incoherencia entre ambos es motivo de rechazo.

## Licencia

Proyecto personal de Bruno Altamirano. Todos los derechos reservados salvo indicación contraria.
