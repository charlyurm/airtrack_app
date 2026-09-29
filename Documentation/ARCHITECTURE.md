# Arquitectura

## Principio

Toda la lógica que no toca hardware vive en **AirTrackCore** y es determinista:
recibe datos más un timestamp y devuelve comandos. La app de macOS solo traduce
entre el hardware y AirTrackCore.

```text
┌──────────────────────── macOS app (AirTrack/) ────────────────────────┐
│ CameraManager ──frames──▶ HandTrackingEngine (Vision adapter)         │
│                                  │ HandState                           │
└──────────────────────────────────┼─────────────────────────────────────┘
                                   ▼
┌──────────────────────── AirTrackCore (Swift Package) ─────────────────┐
│ GestureEngine.process(hand, isPaused)                                  │
│   CursorMapper ─▶ CursorSmoother ─▶ PinchRecognizer ─▶ GestureStateMachine
│   (mirror, zona activa,  (EMA)        (ratio vs tamaño   (click / double
│    sensibilidad)                       de mano, histéresis) click / drag)
│                                   │ [InteractionAction] (coords normalizadas)
└───────────────────────────────────┼────────────────────────────────────┘
                                    ▼
┌──────────────────────── macOS app ────────────────────────────────────┐
│ CursorController ─▶ ScreenMapper (Core) ─▶ MacOSEventController (CGEvent)
└────────────────────────────────────────────────────────────────────────┘
```

## Sistemas de coordenadas

| Espacio | Origen | Eje Y | Unidades | Dónde |
|---|---|---|---|---|
| Vision | abajo-izquierda | arriba | 0…1 | Solo dentro del adapter de Vision |
| `HandState` | arriba-izquierda | abajo | 0…1, **sin espejo** | Salida de HandTrackingEngine (adapter: `y = 1 - y`) |
| Cámara espejada | arriba-izquierda | abajo | 0…1 | `CursorMapper.activeArea`, calibración |
| Display normalizado | arriba-izquierda | abajo | 0…1 | `InteractionAction` |
| Global macOS (CG) | arriba-izquierda del display principal | abajo | puntos (no píxeles) | CGEvent, `ScreenMapper` |
| AppKit (NSScreen) | abajo-izquierda del principal | arriba | puntos | Convertir con `ScreenMapper.globalFrame(fromAppKitFrame:)` |

- **Retina:** CGEvent trabaja en puntos, así que no se aplica ningún `backingScaleFactor`.
- **Aspect ratio:** en una imagen 16:9, 0.1 en x no mide lo mismo que 0.1 en y.
  Las distancias de la mano se corrigen con `HandState.imageAspectRatio`.
- **Multi-monitor:** el MVP mapea a un solo display objetivo. Mapear sobre la unión
  de displays con formas irregulares queda fuera del MVP.

## Módulos de AirTrackCore

| Carpeta | Tipos | Responsabilidad |
|---|---|---|
| `Models/` | `HandJoint`, `HandState`, `InteractionAction`, `AirTrackSettings`, `KeyboardShortcut` | Modelos independientes del proveedor de tracking |
| `Geometry/` | `Point2D`, `Rect2D` | Geometría propia (sin CGPoint, para compilar en Linux) |
| `Cursor/` | `CursorMapper`, `CursorSmoother`, `ScreenMapper` | Cámara → pantalla |
| `Gestures/` | `HandScale`, `PinchRecognizer`, `GestureStateMachine`, `GestureEngine` | Gestos |
| `Calibration/` | `ActiveAreaCalibration` | Matemática de calibración (la UI es PHASE 6) |

## Reglas de seguridad (garantizadas por tests)

- Si se pierde el tracking, el cursor no se mueve.
- Una pérdida de tracking mayor a 150 ms durante un drag envía `mouseUp`,
  para que el botón no quede pegado.
- Al pausar, se envía un `mouseUp` inmediato si había drag; después, silencio total.
- Tras una pérdida o una pausa, la mano debe abrirse antes de aceptar otro pinch.
- Si la entrada es NaN o infinita, no se genera ningún evento.

## Decisiones

| Decisión | Motivo |
|---|---|
| AirTrackCore sin frameworks de Apple | Tests rápidos sin cámara, también en Linux o CI |
| `mouseDown` diferido hasta resolver el gesto | Un pinch cancelado (pérdida o pausa) nunca llega al sistema |
| Sin App Sandbox | Publicar CGEvent desde sandbox no es viable; el MVP es solo para uso local |
| Timestamps inyectados | Tests deterministas sin depender del reloj |
