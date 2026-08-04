# RadioApp

App de iOS para escuchar radio por internet con reconocimiento de canciones (Shazam), widgets, CarPlay y atajos de Siri.

**Versión actual: 1.2**

## Características

- 🎵 **Reproducción de radio por streaming** sobre `AVPlayer`, con audio en segundo plano (`UIBackgroundModes: audio`) y controles en la pantalla de bloqueo (Now Playing + carátula).
- 🔎 **Búsqueda de emisoras** mediante la API pública de [Radio Browser](https://www.radio-browser.info/).
- ➕ **Emisoras propias**: añadir, editar y eliminar estaciones con URL de stream y logo.
- 🎼 **Reconocimiento de canciones** con [ShazamKit](https://developer.apple.com/shazamkit/), capturando el audio del stream en directo (`AudioStreamTap`) o descodificándolo por separado (`StreamDecoder`) en las emisoras que no admiten la captura pasiva.
- 🖼️ **Carátulas**: portada del tema en la pantalla de reproducción y en el historial, vía ShazamKit o búsqueda en la API de iTunes para las emisoras que sólo emiten texto.
- 📝 **Letras**: enlace directo a la canción en Apple Music.
- 🔄 **Resistencia a cortes de red**: reconexión automática de streams caídos (pensada para 5G en movimiento) y un proxy local (`LocalStreamProxy`) que rescata emisoras cuyo servidor describe mal el stream.
- 🕑 **Historial** de canciones escuchadas, con favoritos y una lista de títulos ignorados que mantiene fuera los eslóganes de la emisora.
- 📱 **Widgets** (WidgetKit): emisora en reproducción y acceso rápido a emisoras. El de accesos directos es **configurable**: mantén pulsado el widget → *Editar* y elige qué emisora va en cada uno de los cuatro huecos.
- 🚗 **CarPlay** mediante `CarPlaySceneDelegate`, con panel en el salpicadero (`CarPlayDashboardSceneDelegate`).
- 🗣️ **Atajos de Siri** (`SiriIntents`).
- 🌗 **Modo claro y oscuro** con colores adaptativos.
- ♿️ **Accesibilidad**: etiquetas de VoiceOver en toda la interfaz, tipografía que escala con Dynamic Type, contraste verificado contra WCAG AA y respeto por *Reducir movimiento*.
- 🌍 **Localización en 5 idiomas**: español, inglés, alemán, francés y portugués — incluidos los widgets, las frases de Siri y los avisos de permisos.

## Requisitos

- Xcode 26 o superior
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
│   ├── Lyrics.swift           # Acceso a la letra (enlace a Apple Music)
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
4. Compila y ejecuta en un dispositivo real (ShazamKit y CarPlay no funcionan en simulador).

> Consulta también `SETUP_XCODE.md` para los pasos detallados de configuración del proyecto en Xcode.

## Deep links

El widget abre la app con:

```
radioapp://play?u=<URL_del_stream>
```

`RadioAppApp.handleURL` busca la emisora con ese stream y comienza la reproducción.

## Diagnóstico de reproducción

Cuando una emisora no arranca o se corta, el síntoma visible es siempre el mismo (el botón alterna entre play y pausa sin sonido), así que la reproducción emite trazas con `os.Logger` bajo el subsistema `com.radioapp.playback`:

- En dispositivo: **Console.app**, filtrando por ese subsistema.
- En simulador: `xcrun simctl spawn <udid> log stream --level debug --predicate 'subsystem == "com.radioapp.playback"'`.

Las trazas distinguen las dos causas que producen ese mismo síntoma: una conexión que nunca llega a sonar (el vigilante la reconstruye tras `connectGrace`) y una que sonaba y se cortó (`stallGrace`).

## Privacidad

La app **no recoge datos**: no hay backend propio, ni analítica, ni SDK de terceros (solo
frameworks de Apple). Las emisoras, el historial y la lista de ignorados se guardan en el
dispositivo. El tráfico de red se limita al stream y la carátula que pide el usuario, más las
consultas a Radio Browser e iTunes Search, sin identificador ni cuenta asociada.

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
