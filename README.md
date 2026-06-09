# RadioApp

App de iOS para escuchar radio por internet con reconocimiento de canciones (Shazam), widgets, CarPlay y atajos de Siri.

## Características

- 🎵 **Reproducción de radio por streaming** sobre `AVPlayer`, con audio en segundo plano (`UIBackgroundModes: audio`) y controles en la pantalla de bloqueo (Now Playing + artwork).
- 🔎 **Búsqueda de emisoras** mediante la API pública de [Radio Browser](https://www.radio-browser.info/).
- ➕ **Emisoras propias**: añadir, editar y eliminar estaciones con URL de stream y logo.
- 🎼 **Reconocimiento de canciones** con [ShazamKit](https://developer.apple.com/shazamkit/), capturando el audio del stream en directo (`AudioStreamTap`).
- 🕑 **Historial** de canciones escuchadas, con favoritos.
- 📱 **Widgets** (WidgetKit): emisora en reproducción y acceso rápido a emisoras.
- 🚗 **CarPlay** mediante `CarPlaySceneDelegate`.
- 🗣️ **Atajos de Siri** (`SiriIntents`).
- 🌍 **Localización en 5 idiomas**: español, inglés, alemán, francés y portugués.

## Requisitos

- Xcode 15 o superior
- iOS 17.0+
- Cuenta de desarrollador de Apple (para ShazamKit, CarPlay y widgets en dispositivo real)

## Estructura del proyecto

```
RadioApp/
├── RadioApp/                  # Target principal (app iOS)
│   ├── RadioAppApp.swift      # Punto de entrada + deep links (radioapp://play?u=…)
│   ├── ContentView.swift      # Navegación principal
│   ├── RadioPlayer.swift      # Motor de reproducción (AVPlayer + Now Playing)
│   ├── AudioStreamTap.swift   # Captura de audio del stream para Shazam
│   ├── ShazamService.swift    # Reconocimiento de canciones (ShazamKit)
│   ├── RadioBrowserService.swift  # Cliente de la API Radio Browser
│   ├── Station.swift / StationsStore.swift  # Modelo y persistencia de emisoras
│   ├── HistoryStore.swift / ListenedSong.swift  # Historial de canciones
│   ├── CarPlay*.swift         # Integración CarPlay
│   ├── SiriIntents.swift      # Atajos de Siri
│   ├── *View.swift            # Vistas SwiftUI
│   └── Localization/          # de, en, es, fr, pt
├── RadioWidget/               # Extensión de widgets (WidgetKit)
├── Shared/                    # Código compartido app ↔ widget
└── Tools/                     # Scripts auxiliares (icono, target de widget)
```

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

## Privacidad

- `NSMicrophoneUsageDescription`: necesario para identificar canciones con Shazam.
- `ITSAppUsesNonExemptEncryption = false`: la app no usa cifrado no exento.

## Licencia

Proyecto personal de Bruno Altamirano. Todos los derechos reservados salvo indicación contraria.
