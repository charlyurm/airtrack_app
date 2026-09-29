# AirTrack

Trackpad virtual para macOS: la cámara del Mac detecta tu mano y la convierte en
cursor, click, doble click, drag y scroll. Todo se procesa en local, sin internet.

## Estado

| Fase | Estado |
|---|---|
| PHASE 0: Core + Architecture | **COMPLETE** |
| PHASE 1: Camera | **NOT STARTED** |
| PHASE 2–8 | NOT STARTED |

Todavía **no existe una app ejecutable**: no hay proyecto de Xcode. Lo que existe es
`AirTrackCore`, la lógica pura, probada en macOS y Linux mediante CI. La app de macOS
se crea al inicio de PHASE 1 siguiendo `Documentation/MACOS_SETUP.md`.

## Estructura

| Ruta | Contenido |
|---|---|
| `AirTrackCore/` | Swift Package: modelos, geometría, mapeo del cursor, smoothing, pinch, máquina de estados de gestos y calibración. Solo importa Foundation. |
| `AirTrack/` | App macOS: cámara, Vision, CGEvent, accesibilidad, menu bar, UserDefaults. **No existe todavía.** |
| `Documentation/` | Arquitectura, gestos, permisos, testing, roadmap y setup en Mac. |
| `AIRTRACK_PROJECT_STRUCTURE.md` | Documento maestro de arquitectura (v0.2, con las enmiendas aprobadas). |

## Frontera AirTrackCore ↔ macOS

```text
Vision hand observation → HandState → AirTrackCore → [InteractionAction] → MacOSEventController
```

`HandState` e `InteractionAction` son los únicos tipos que cruzan la frontera.
Detalles en `Documentation/ARCHITECTURE.md`.

## Probar AirTrackCore

Requiere Swift 5.9+ (Xcode 15+ en Mac, o el toolchain de swift.org en Linux):

```bash
cd AirTrackCore
swift test
```

El workflow `.github/workflows/airtrackcore-tests.yml` ejecuta los mismos tests en
macOS y Linux en cada push que toque `AirTrackCore/`.

## Documentación

- [Arquitectura y frontera Core/macOS](Documentation/ARCHITECTURE.md)
- [Gestos](Documentation/GESTURES.md)
- [Permisos](Documentation/PERMISSIONS.md)
- [Testing](Documentation/TESTING.md)
- [Roadmap](Documentation/ROADMAP.md)
- [Setup en macOS](Documentation/MACOS_SETUP.md): cómo continuar en un Mac real

Nada se marca como terminado sin haberlo probado en un Mac real.
