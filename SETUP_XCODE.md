# Setup en Xcode

## 1. Crear el proyecto

- Xcode → File → New → Project
- Template: **App** (iOS)
- Product Name: `RadioApp`
- Interface: **SwiftUI**
- Language: **Swift**
- Minimum Deployment: **iOS 16.0**

## 2. Añadir los archivos

Arrastra la carpeta `RadioApp/` entera al navigator de Xcode.
Marca "Copy items if needed" y "Create groups".
**Elimina** el `ContentView.swift` que crea Xcode por defecto (ya está en Views/).

## 3. Capabilities (Signing & Capabilities)

Añadir:
- **Background Modes** → marcar "Audio, AirPlay, and Picture in Picture"
- **CarPlay** → aparece cuando Apple aprueba el entitlement (ver más abajo)

## 4. Info.plist

Añadir estas claves:

| Clave | Valor |
|-------|-------|
| `NSAppTransportSecurity > NSAllowsArbitraryLoads` | YES |
| `NSMicrophoneUsageDescription` | "Necesario para identificar canciones con Shazam" |
| `UIBackgroundModes` | `audio` (ya lo añade Background Modes automáticamente) |

Para CarPlay, añadir también:
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>Default</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

## 5. Assets

El icono de la app va en `Assets.xcassets/AppIcon.appiconset/`.
Solo necesitas un PNG de **1024×1024 px** llamado `AppIcon-1024.png`.
Xcode lo escala a todos los tamaños automáticamente (iOS 16+).

Para el artwork de la pantalla de bloqueo (`NowPlayingArtwork.png`),
cualquier imagen cuadrada ≥ 600×600 px sirve.

Los logos de emisoras se cargan por URL desde internet (campo en Settings).
Si una emisora no tiene logo, se muestra un icono con sus iniciales.

## 6. Entitlement CarPlay

Solicitar en: https://developer.apple.com/contact/carplay/
Categoría: **Audio**
Tiempo de respuesta: ~1-2 semanas.

Una vez aprobado, Xcode añade automáticamente `com.apple.developer.carplay-audio`
al archivo `.entitlements`.

## 7. Identificación de canciones (Shazam)

ShazamKit está incluido en el SDK de iOS, no requiere dependencias externas.
El botón "Identificar" aparece en la barra inferior mientras hay reproducción activa.
Flujo:
1. Pulsa "Identificar" → pide permiso de micrófono la primera vez
2. Escucha 5 segundos
3. Muestra título, artista, carátula y enlace a Apple Music

**Nota:** ShazamKit identifica el audio del entorno (micrófono).
La identificación por metadata de stream (ICY) es automática y no
requiere ninguna acción — si la emisora la incluye, aparece
directamente bajo el nombre de la emisora.

## 8. CarPlayBridge

`CarPlaySceneDelegate` usa `CarPlayBridge.shared` para acceder al mismo
`RadioPlayer` y `StationsStore` que la UI principal.

## 9. Localización

En Xcode, los archivos `.lproj` deben estar referenciados en el proyecto:

1. Selecciona el proyecto en el Navigator → pestaña **Info** → sección **Localizations**
2. Pulsa **+** y añade: Spanish, English, French, German, Portuguese
3. Arrastra la carpeta `Localization/` al proyecto o añade los archivos
   `Localizable.strings` de cada `.lproj` manualmente
4. Xcode selecciona automáticamente el idioma del sistema del usuario

Idiomas incluidos: 🇪🇸 ES · 🇬🇧 EN · 🇫🇷 FR · 🇩🇪 DE · 🇵🇹 PT

## 10. Buscador de emisoras (Radio Browser)

- No requiere API key ni registro
- Base de datos: >30.000 emisoras de todo el mundo
- Filtros por país incluidos: ES · UK · US · FR · DE · IT · PT · MX · AR
- El botón **lupa** en la barra principal abre el buscador
- Desde cada resultado: botón ▶ para escuchar directamente, **+** para añadir a mis emisoras
- Si la emisora ya está añadida, el **+** se convierte en ✓

## 11. Build & Run

Compilar en un iPhone real para probar audio en background.
CarPlay se puede simular con **Xcode → I/O → CarPlay**.
