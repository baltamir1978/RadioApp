# Revisión de código — RadioApp

Revisión general del estado del proyecto y recomendaciones antes de publicar en GitHub / TestFlight.

## Resumen

App SwiftUI bien estructurada por responsabilidades (player, stores, servicios, vistas). El reconocimiento de canciones y la pantalla de bloqueo se consolidaron en commits recientes. Hay **cambios sin commitear** en el árbol de trabajo que conviene revisar y consolidar.

## Estado de Git

- Rama: `main` → `origin` (`github.com/baltamir1978/RadioApp.git`).
- ⚠️ Hay múltiples archivos modificados sin commitear (`project.pbxproj`, `ContentView.swift`, `HistoryStore.swift`, `CarPlayBridge.swift`, iconos…). Recomendación: revisar el diff, agrupar en commits con mensaje claro y subir antes de etiquetar una versión.

## Puntos fuertes

- ✅ Separación limpia de capas: `RadioPlayer`, `StationsStore`, `HistoryStore`, servicios (`RadioBrowserService`, `ShazamService`).
- ✅ Reproducción en segundo plano + Now Playing correctamente declarados en `Info.plist`.
- ✅ Localización completa en 5 idiomas.
- ✅ Código compartido app↔widget aislado en `Shared/`.

## Recomendaciones

### Seguridad / configuración
- `NSAllowsArbitraryLoads = true` permite tráfico HTTP sin cifrar. Es habitual en apps de radio (muchos streams son HTTP), pero documenta el motivo y, si es posible, restríngelo por dominio con `NSExceptionDomains` para pasar mejor la revisión de App Store.

### Calidad
- Verifica que no queden *logs* de diagnóstico (el commit `2b875b9` ya retiró los de Shazam — confirmar que no se reintrodujeron en los cambios pendientes).
- Añade manejo de errores visible al usuario cuando un stream falla o caduca (reintentos / mensaje).
- Considera mover la persistencia de emisoras/historial a un contenedor de **App Group** si el widget necesita leer el estado actual.

### Mantenimiento
- Añadir un `.gitignore` que excluya `xcuserdata/`, `*.xcuserstate` y `DerivedData/` (revisar que no se estén versionando archivos de usuario de Xcode).
- Documentar en el README los *capabilities* exactos que hay que activar (App Groups, SiriKit) para que otro desarrollador pueda compilar a la primera.

### Pruebas
- No se observan tests. Para la lógica pura (parseo de Radio Browser, `Station.initials`, parseo de deep links) unos *unit tests* serían baratos y útiles.

## Checklist previo a release

- [ ] Consolidar cambios pendientes en commits.
- [ ] Probar en dispositivo real: Shazam, CarPlay, widget, deep link `radioapp://`.
- [ ] Revisar textos localizados en los 5 idiomas.
- [ ] Verificar icono 1024px y assets de App Store.
- [ ] Confirmar `ITSAppUsesNonExemptEncryption` y cuestionario de cifrado.
