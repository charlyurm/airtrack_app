# Arquitectura

## Principio

Toda la lógica que no toca hardware vive en **AirTrackCore** y es determinista:
recibe datos más un timestamp y devuelve comandos. La app de macOS solo traduce
entre el hardware y AirTrackCore.

## Frontera AirTrackCore ↔ macOS

| AIRTRACKCORE (Swift Package, EXISTE) | MACOS APP (`AirTrack/`, NO EXISTE todavía) |
|---|---|
| Modelos (`HandState`, `InteractionAction`, settings) | Cámara (AVFoundation) |
| Geometría (`Point2D`, `Rect2D`) | Vision (detección de mano) |
| Matemática del cursor (`CursorMapper`, `ScreenMapper`) | CGEvent (eventos de ratón) |
| Smoothing (`CursorSmoother`) | Accesibilidad (permiso + comprobación) |
| Reconocimiento de pinch (`PinchRecognizer`, `HandScale`) | Atajo global de emergencia |
| Máquina de estados de gestos (`GestureStateMachine`, `GestureEngine`) | Menu bar y SwiftUI |
| Matemática de calibración (`ActiveAreaCalibration`) | Persistencia (UserDefaults) |
| Tests (sin hardware; macOS y Linux) | Permisos, logging, lectura de NSScreen |

**Regla:** AirTrackCore solo importa `Foundation`. Nunca AVFoundation, Vision,
AppKit, CoreGraphics ni SwiftUI. El CI en Linux falla si alguien rompe esta regla.

### Flujo de datos

```text
                macOS APP                         │        AIRTRACKCORE
                                                  │
AVFoundation (AVCaptureSession)                   │
      │ CMSampleBuffer                            │
      ▼                                           │
CameraManager ── CameraFrame (CVPixelBuffer + t) │
      │                                           │
      ▼                                           │
HandTrackingEngine (Vision: hand pose request)    │
      │ convierte: joints, y = 1 − y, aspect      │
      ▼                                           │
   HandState ─────────────────────────────────────┼──▶ GestureEngine.process(hand, isPaused)
                                                  │      CursorMapper → CursorSmoother
                                                  │      → PinchRecognizer → GestureStateMachine
   [InteractionAction] ◀──────────────────────────┼──── (coordenadas de display normalizadas)
      │                                           │
      ▼                                           │
CursorController ── ScreenMapper.map(_:to:) ──────┼──▶ (función pura de Core)
      │ puntos globales                           │
      ▼                                           │
MacOSEventController (CGEvent) → macOS            │
```

Los únicos tipos que cruzan la frontera son `HandState` (entrada) e
`InteractionAction` (salida), además de `AirTrackSettings` para la configuración.

### Threading previsto

- `GestureEngine` es un value type sin locks: lo posee **una sola** cola serie, la de
  captura de la cámara, y se llama una vez por frame.
- La UI (main thread) solo recibe copias del estado (fase, estado de la cámara, FPS).
- Los eventos CGEvent se publican desde la misma cola, para mantener el orden
  down → drag → up.

## Contratos previstos para PHASE 1+ (NO IMPLEMENTADOS)

Son bocetos de diseño. Las firmas de las APIs de Apple se verificarán al
implementarlas en un Mac real.

### CameraManager (PHASE 1): `AirTrack/Camera/`

Responsabilidades: descubrir cámaras, pedir permiso, iniciar y detener, entregar
frames, manejar errores y detectar la pérdida de la cámara. **No contiene** hand
tracking, gestos ni lógica de cursor.

```swift
enum CameraStatus: Equatable {
    case notDetermined
    case permissionRequired      // denegado o restringido
    case starting
    case connected(deviceName: String)
    case disconnected            // la cámara desapareció o fue interrumpida
    case error(String)
}

struct CameraFrame {
    let pixelBuffer: CVPixelBuffer   // no se copia ni se guarda; vive solo durante el procesamiento
    let timestamp: TimeInterval      // presentation time de CMSampleBuffer, en segundos (monótono)
    let width: Int
    let height: Int
}

protocol CameraManaging: AnyObject {
    var status: CameraStatus { get }
    var onStatusChange: ((CameraStatus) -> Void)? { get set }
    var onFrame: ((CameraFrame) -> Void)? { get set }   // se llama en la cola serie de captura
    func availableCameras() -> [String]                  // discovery
    func requestPermission() async -> Bool
    func start() throws
    func stop()
}
```

Notas de implementación (verificar en PHASE 1):
`AVCaptureDevice.DiscoverySession` para descubrir cámaras;
`AVCaptureVideoDataOutput` con `alwaysDiscardsLateVideoFrames = true` (se prefiere
perder un frame antes que acumular latencia); y notificaciones de
error/interrupción de la sesión y de desconexión del dispositivo para `disconnected`.

### HandTrackingEngine (PHASE 2): `AirTrack/Vision/`

```swift
protocol HandTracking {
    func process(_ frame: CameraFrame) -> HandState   // HandState de AirTrackCore
}
```

- Vision: hand pose request con máximo 1 mano.
- Mapeo de joints: wrist, thumbTip, indexMCP/PIP/DIP/Tip, middleTip, ringTip,
  `littleTip → pinkyTip`.
- Conversión: `y = 1 − y` (Vision tiene el origen abajo), `confidence` por joint y
  `imageAspectRatio = width / height`.
- Sin mano → `HandState.untracked(at:)`. Nunca se inventan landmarks.

### MacOSEventController (PHASE 3/4): `AirTrack/Events/`

- Consume `[InteractionAction]`, convierte cada posición con
  `ScreenMapper.map(_:to:)` al display objetivo (frame obtenido de NSScreen y
  convertido con `ScreenMapper.globalFrame(fromAppKitFrame:primaryDisplayHeight:)`).
- Un CGEvent por acción; `clickCount` → `mouseEventClickState`.
- Si el permiso de Accesibilidad no está concedido, **no publica nada** y lo informa
  a la UI.

## Sistemas de coordenadas

| Espacio | Origen | Eje Y | Unidades | Dónde |
|---|---|---|---|---|
| Vision | abajo-izquierda | arriba | 0…1 | Solo dentro de HandTrackingEngine |
| `HandState` | arriba-izquierda | abajo | 0…1, **sin espejo** | Salida de HandTrackingEngine |
| Cámara espejada | arriba-izquierda | abajo | 0…1 | `CursorMapper.activeArea`, calibración |
| Display normalizado | arriba-izquierda | abajo | 0…1 | `InteractionAction` |
| Global macOS (CG) | arriba-izquierda del display principal | abajo | puntos (no píxeles) | CGEvent, `ScreenMapper` |
| AppKit (NSScreen) | abajo-izquierda del principal | arriba | puntos | Convertir con `ScreenMapper.globalFrame(fromAppKitFrame:)` |

- **Retina:** CGEvent trabaja en puntos, así que no se aplica ningún `backingScaleFactor`.
- **Aspect ratio:** en una imagen 16:9, 0.1 en x no mide lo mismo que 0.1 en y. Las
  distancias de la mano se corrigen con `HandState.imageAspectRatio`.
- **Multi-monitor:** el MVP mapea a un solo display objetivo.

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
- Una pérdida de tracking mayor a 150 ms durante un drag envía `mouseUp`, para que
  el botón no quede pegado.
- Al pausar, se envía un `mouseUp` inmediato si había drag; después, silencio total.
- Tras una pérdida o una pausa, la mano debe abrirse antes de aceptar otro pinch.
- Entrar en un drag nunca mueve el cursor (offset cursor–dedo), y salir tampoco
  (el offset se desvanece).
- Si la entrada es NaN o infinita, no se genera ningún evento.

## Decisiones

| Decisión | Motivo | Estado |
|---|---|---|
| AirTrackCore sin frameworks de Apple | Tests rápidos sin cámara, también en Linux o CI | Definitiva |
| `mouseDown` diferido hasta resolver el gesto | Un pinch cancelado (pérdida o pausa) nunca llega al sistema | Definitiva |
| Drag con offset `cursor = dedo + (ancla − dedo al iniciar)` | Sin salto al entrar en drag | Definitiva |
| Offset residual que decae en 200 ms tras soltar | Sin salto al salir del drag | Valor provisional |
| Pinch confirmado en 2 frames (~33 ms a 30 fps) | Evitar falsos positivos antes que reducir latencia | **Provisional**, revisar con mediciones reales |
| EMA por frame | Simple y suficiente para empezar | **Provisional**: pasar a smoothing por tiempo |
| Sin App Sandbox | Publicar CGEvent desde sandbox no es viable | MVP |
| Timestamps inyectados | Tests deterministas sin depender del reloj | Definitiva |
