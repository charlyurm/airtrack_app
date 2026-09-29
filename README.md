# AirTrack

Trackpad virtual para macOS: la cámara del Mac detecta tu mano y la convierte en
cursor, click, doble click, drag y scroll. Todo se procesa en local, sin internet.

## Estado

| Fase | Estado |
|---|---|
| PHASE 0: Core + Architecture | **COMPLETE** |
| PHASE 1: macOS Foundation + Camera + Vision Hand Tracking | Validada en el Mac real (PHASE 1.1, [resultado](PHASE1_1_RESULT.md)) |
| PHASE 2: Cursor Control | Validada en el Mac (G, H, J, L parciales → PHASE 2.1) ([resultado](PHASE2_RESULT.md)) |
| PHASE 2.1: Adaptive Cursor & Peripheral Tracking | Validada en el Mac (confirmado por el usuario) ([resultado](PHASE2_1_RESULT.md)) |
| PHASE 3A-1: Gesture Engine Foundation (modo sombra) | **IMPLEMENTED — PHYSICAL VALIDATION PENDING** ([resultado](PHASE3A1_RESULT.md)) |
| PHASE 3A-2: Scroll (2 dedos / mano abierta) | **IMPLEMENTED — PHYSICAL VALIDATION PENDING** ([resultado](PHASE3A2_RESULT.md)) |
| PHASE 3B–3G, 4–7+ | NOT STARTED |

Lo que hace la app hoy: abre la cámara, detecta hasta dos manos con Vision, dibuja sus 21
landmarks sobre el preview y, **si activas "Cursor Control"** (y das permiso de
Accesibilidad), el índice de la mano primaria mueve el cursor del Mac, con suavizado que se
adapta a la velocidad y seguimiento del índice cerca de los bordes de la imagen (PHASE 2.1).
PHASE 3A añade el scroll vertical con ☝️🖕 o 🖐️ (con el cursor congelado mientras dura e
inercia acotada). **Todavía no hace click, drag, zoom ni swipe** (PHASE 3B+).

## Estructura

| Ruta | Contenido |
|---|---|
| `AirTrackCore/` | Swift Package: modelos, geometría, conversión de coordenadas, mapeo del cursor, smoothing, pinch, máquina de estados de gestos y calibración. Solo importa Foundation. |
| `AirTrack/` | App macOS (SwiftUI): cámara (AVFoundation), Vision, permisos, preview y overlay de debug. |
| `Documentation/` | Arquitectura, gestos, permisos, testing, roadmap y setup en Mac. |
| `AIRTRACK_PROJECT_STRUCTURE.md` | Documento maestro de arquitectura, con las enmiendas aprobadas. |
| `PHASE1_PROMPT.md`, `PHASE1_1_PROMPT.md` | Especificaciones de PHASE 1 y 1.1. |
| `PHASE1_1_RESULT.md` | Diagnóstico y correcciones de PHASE 1.1. |
| `PHASE2_PROMPT.md`, `PHASE2_RESULT.md` | Especificación y resultado de PHASE 2 (cursor). |
| `PHASE2_1_PROMPT.md`, `PHASE2_1_RESULT.md` | Especificación y resultado de PHASE 2.1 (cursor adaptativo, tracking periférico). |
| `PHASE3_MASTER_SPEC.md` | Especificación de producto de PHASE 3 (gestos tipo trackpad). |
| `PHASE3A1_IMPLEMENTATION_SPEC.md`, `PHASE3A1_RESULT.md` | Motor de interacción en modo sombra. |
| `PHASE3A2_IMPLEMENTATION_SPEC.md`, `PHASE3A2_RESULT.md` | Scroll. |

## Pipeline

```text
AVCaptureSession → CameraFrame → Vision → HandStateMapper → [HandState] candidatos
      → PointerTracker (Core: HandPresenceFilter estricto + continuidad FULL/PARTIAL/INDEX/HOLD/LOST)
      → CursorController (Core: dead zone, sensibilidad, smoothing adaptativo)
      → MacOSEventController → CGEvent .mouseMoved → cursor
   (3A) PointerTracker.trackedHand → HandFeatures → FeatureHistory → PoseClassifier
      → ScrollRecognizer → IntentArbiter → InteractionEngine → ScrollController
      → InteractionAction.scroll → MacOSEventController → CGEvent scroll-wheel
      (cursorPolicy FROZEN congela el cursor por encima de CursorController, sin tocarlo)
      → Debug UI (preview + overlay + panel)
```

## Empezar en un Mac

Requiere Xcode 16+ y macOS 14+.

```bash
git checkout claude/gifted-carson-iyjqxg && git pull
cd AirTrackCore && swift test && cd ..        # 353 tests, 0 failures
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
