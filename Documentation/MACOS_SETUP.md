# Setup en macOS (para PHASE 1)

> Aún **no ejecutado.** Este es el plan para crear la capa macOS en tu Mac.
> Todo es REQUIRES MACOS.

## 0. Verificar el entorno

```bash
uname -m            # esperado: arm64
sw_vers
xcodebuild -version
swift --version
cd AirTrackCore && swift test
```

## 1. Crear el proyecto

1. Xcode → File → New → Project → macOS → App.
2. Product Name `AirTrack`, Interface SwiftUI, Language Swift.
3. Guardarlo en la raíz de este repo (junto a `AirTrackCore/`).
4. File → Add Package Dependencies → Add Local… → seleccionar `AirTrackCore/`
   y enlazar la librería al target `AirTrack`.

## 2. Configurar el target

| Ajuste | Valor |
|---|---|
| Signing & Capabilities → App Sandbox | **Eliminar** |
| Info → `NSCameraUsageDescription` | "AirTrack usa la cámara para detectar tu mano. Las imágenes se procesan solo en este Mac." |
| Info → `LSUIElement` | `YES` (app de barra de menú, sin Dock) — PHASE 6 |
| Architectures | Standard (arm64 en Apple Silicon) |
| Deployment target | macOS 13 o superior |

## 3. Verificación de PHASE 0 en el Mac

- [ ] `swift test` en `AirTrackCore/` → todos los tests pasan
- [ ] `xcodebuild -scheme AirTrack build` → `BUILD SUCCEEDED`

Después de eso empieza PHASE 1 (Camera).
