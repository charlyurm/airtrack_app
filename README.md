# AirTrack

Trackpad virtual para macOS: la cámara del Mac detecta tu mano y la convierte en
cursor, click, doble click, drag y scroll. Todo se procesa en local, sin internet.

## Estado

| Fase | Estado |
|---|---|
| PHASE 0: Core + Architecture | **COMPLETE** |
| PHASE 1: macOS Foundation + Camera + Vision Hand Tracking | **IN PROGRESS**: código implementado y compilando en CI; falta la validación en el Mac |
| PHASE 2: Cursor Control | NOT STARTED |
| PHASE 3–7+ | NOT STARTED |

Lo que hace la app hoy: abre la cámara, detecta una mano con Vision y dibuja sus
landmarks sobre el preview, con el estado del tracking y FPS. **Todavía no mueve el
cursor.**

## Estructura

| Ruta | Contenido |
|---|---|
| `AirTrackCore/` | Swift Package: modelos, geometría, conversión de coordenadas, mapeo del cursor, smoothing, pinch, máquina de estados de gestos y calibración. Solo importa Foundation. |
| `AirTrack/` | App macOS (SwiftUI): cámara (AVFoundation), Vision, permisos, preview y overlay de debug. |
| `Documentation/` | Arquitectura, gestos, permisos, testing, roadmap y setup en Mac. |
| `AIRTRACK_PROJECT_STRUCTURE.md` | Documento maestro de arquitectura, con las enmiendas aprobadas. |
| `PHASE1_PROMPT.md` | Especificación de PHASE 1. |

## Pipeline

```text
AVCaptureSession → CameraFrame → Vision → HandStateMapper → HandState → Debug UI
                                                                 │
                                         (PHASE 2+) AirTrackCore → InteractionAction → eventos macOS
```

## Empezar en un Mac

Requiere Xcode 16+ y macOS 14+.

```bash
git checkout claude/gifted-carson-iyjqxg && git pull
cd AirTrackCore && swift test && cd ..        # 85 tests, 0 failures
open AirTrack/AirTrack.xcodeproj               # luego ⌘R
```

Guía completa y checklist de validación: [Documentation/MACOS_SETUP.md](Documentation/MACOS_SETUP.md).

## CI

`.github/workflows/airtrackcore-tests.yml` ejecuta los tests de AirTrackCore en macOS y
Linux y compila la app con `xcodebuild` en macOS en cada push.

## Documentación

- [Arquitectura, frontera Core/macOS, coordenadas y threading](Documentation/ARCHITECTURE.md)
- [Gestos](Documentation/GESTURES.md)
- [Permisos](Documentation/PERMISSIONS.md)
- [Testing](Documentation/TESTING.md)
- [Roadmap](Documentation/ROADMAP.md)
- [Setup y validación en macOS](Documentation/MACOS_SETUP.md)

Nada se marca como terminado sin haberlo probado en un Mac real.
