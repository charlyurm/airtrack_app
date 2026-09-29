# AirTrack

Trackpad virtual para macOS: la cámara del Mac detecta tu mano y la convierte en
cursor, click, doble click, drag y scroll. Todo se procesa en local, sin internet.

> **Estado: PHASE 0 (bootstrap + arquitectura).** Todavía NO existe una app que
> se pueda ejecutar. Solo existe la lógica pura (`AirTrackCore`) con sus tests.

## Estructura

| Ruta | Contenido |
|---|---|
| `AirTrackCore/` | Swift Package con toda la lógica independiente del hardware: mapeo de coordenadas, smoothing, pinch y máquina de estados de gestos. No importa AppKit, AVFoundation, Vision ni CoreGraphics. |
| `AirTrack/` | Capa macOS (cámara, Vision, CGEvent, UI). **Todavía no creada** (PHASE 1+). |
| `Documentation/` | Arquitectura, gestos, permisos, testing, roadmap y setup en Mac. |
| `AIRTRACK_PROJECT_STRUCTURE.md` | Documento maestro de arquitectura (v0.2, con las enmiendas aprobadas). |

## Probar AirTrackCore

Requiere Swift 5.9+ (Xcode 15+ en Mac, o el toolchain de swift.org en Linux):

```bash
cd AirTrackCore
swift test
```

Además, el workflow de CI `.github/workflows/airtrackcore-tests.yml` ejecuta los
tests en macOS y Linux en cada push que toque `AirTrackCore/`.

## Estado del MVP

Ver `Documentation/ROADMAP.md`. Nada se marca como terminado sin haberlo probado
en un Mac real.

## Documentación

- [Arquitectura](Documentation/ARCHITECTURE.md)
- [Gestos](Documentation/GESTURES.md)
- [Permisos](Documentation/PERMISSIONS.md)
- [Testing](Documentation/TESTING.md)
- [Roadmap](Documentation/ROADMAP.md)
- [Setup en macOS](Documentation/MACOS_SETUP.md)
