# Arquitectura

## Principio

Toda la lógica que no toca hardware vive en **AirTrackCore** y es determinista:
recibe datos más un timestamp y devuelve comandos. La app de macOS (`AirTrack/`) es un
adaptador entre el hardware y AirTrackCore.

## Frontera AirTrackCore ↔ macOS

| AIRTRACKCORE (Swift Package) | MACOS APP (`AirTrack/AirTrack/`) |
|---|---|
| Modelos (`HandState`, `InteractionAction`, settings) | Cámara (AVFoundation): `Camera/` |
| Geometría (`Point2D`, `Rect2D`) | Vision (hand pose): `Vision/` |
| Conversión de coordenadas de landmarks (`LandmarkCoordinateConversion`) | Permiso de cámara: `Permissions/` |
| Matemática del cursor (`CursorMapper`, `ScreenMapper`) | Preview + overlay de debug: `UI/` |
| Smoothing (`CursorSmoother`) | Logging (`os.Logger`): `Utilities/` |
| Pinch (`PinchRecognizer`, `HandScale`) | *Futuro:* CGEvent, Accesibilidad, atajo global, menu bar, UserDefaults |
| Gestos (`GestureStateMachine`, `GestureEngine`) | |
| Calibración (`ActiveAreaCalibration`) | |
| Tests (sin hardware; macOS y Linux) | |

**Regla:** AirTrackCore solo importa `Foundation`. Nunca AVFoundation, Vision, AppKit,
CoreGraphics ni SwiftUI. El job de Linux del CI falla si alguien rompe esta regla.

```text
macOS / Vision  ──HandState──▶  AirTrackCore  ──[InteractionAction]──▶  macOS events (PHASE 2+)
```

## Pipeline de PHASE 1 (implementado)

```text
AVCaptureSession (CameraManager, sessionQueue)
      │ CMSampleBuffer en videoQueue
      ▼
CameraFrame (CVPixelBuffer + timestamp + tamaño)          ← no entra en AirTrackCore
      │ HandTrackingPipeline.submit: si Vision está ocupado, el frame se descarta
      ▼
VisionHandTrackingEngine (visionQueue)
      │ VNDetectHumanHandPoseRequest, maximumHandCount = 1, orientación .up
      ▼
VNHumanHandPoseObservation
      │ HandStateMapper: extrae 9 joints (x, y, confidence)
      ▼
LandmarkCoordinateConversion (AirTrackCore): y → 1 − y, descarta confidence ≤ 0
      ▼
HandState ──▶ AppModel (main) ──▶ CameraPreviewView + HandDebugOverlay + TrackingStatusView
```

En PHASE 1, `HandState` todavía no pasa por `GestureEngine`: no hay cursor ni eventos.

### Componentes

| Archivo | Responsabilidad |
|---|---|
| `Camera/CameraManager.swift` | Descubrir cámaras (built-in, externa, Continuity), configurar la sesión a 1280×720 en formato 420f, arrancar y parar, entregar frames, detectar desconexión y errores de runtime |
| `Camera/CameraStatus.swift` | `unknown`, `permissionRequired`, `ready`, `running`, `stopped`, `disconnected`, `error(String)` |
| `Camera/CameraFrame.swift` | Transporte del frame desde AVFoundation hasta Vision |
| `Permissions/CameraPermissionManager.swift` | Estado del permiso, solicitud y apertura de Configuración del Sistema |
| `Vision/VisionHandTrackingEngine.swift` | Ejecutar la petición de Vision sobre un frame |
| `Vision/HandStateMapper.swift` | Observación de Vision → `HandState` |
| `Vision/HandTrackingPipeline.swift` | Cola de Vision, backpressure, métricas, log de adquisición y pérdida del tracking |
| `App/AppModel.swift` | Estado de la UI (`@MainActor @Observable`) |
| `UI/CameraPreviewView.swift` | Preview (`AVCaptureVideoPreviewLayer`) + overlay en el mismo layer |
| `UI/HandDebugOverlay.swift` | Dibujo de landmarks |
| `UI/TrackingStatusView.swift` | Panel de diagnóstico |

## Sistemas de coordenadas

| Espacio | Origen | Eje Y | Espejo | Dónde |
|---|---|---|---|---|
| Buffer de cámara | arriba-izquierda | abajo | **no** (se fuerza `isVideoMirrored = false` en la salida de datos) | `CameraFrame` |
| Vision | **abajo**-izquierda | **arriba** | no | Dentro de `HandStateMapper` |
| `HandState` | arriba-izquierda | abajo | **no** | Frontera con AirTrackCore |
| Capture device point (AVFoundation) | arriba-izquierda | abajo | no | Idéntico a `HandState` en una cámara de Mac horizontal |
| Preview layer | el que use el layer | — | **sí**, si "Espejar preview" está activo (por defecto) | Solo visual |
| Cámara espejada (Core) | arriba-izquierda | abajo | sí | `CursorMapper.activeArea` (PHASE 2) |
| Display normalizado | arriba-izquierda | abajo | — | `InteractionAction` (PHASE 2+) |
| Global macOS (CG) | arriba-izquierda del display principal | abajo | — | CGEvent (PHASE 2+) |

- **Normalización:** todas las coordenadas de landmarks van de 0 a 1 respecto a la imagen
  completa. Las distancias se corrigen con `HandState.imageAspectRatio` (ancho/alto del
  buffer, 16:9 a 1280×720).
- **Orientación:** las cámaras de Mac entregan buffers horizontales y derechos, así que
  Vision usa `.up`. Una cámara rotada (p. ej., un iPhone en vertical con Continuity
  Camera) no está contemplada: pendiente de validar en el Mac.
- **Espejo:** solo en el preview. `HandState` es siempre la imagen real. El espejo para
  el cursor lo aplica `CursorMapper` en PHASE 2.
- **Alineación del overlay:** no se invierte X a mano. Cada punto de `HandState` se
  convierte con `AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)`,
  que aplica el `videoGravity` (bandas negras) y el espejo del propio layer, y el overlay
  es un sublayer del mismo layer. **DEFERRED TO LOCAL MAC VALIDATION**: la alineación
  real solo se confirma viendo la mano en pantalla.

## Threading

```text
MAIN (MainActor)   SwiftUI, AppModel, dibujo del overlay
sessionQueue       configuración de AVCaptureSession, startRunning/stopRunning (bloqueantes)
videoQueue         callbacks de AVCaptureVideoDataOutput → HandTrackingPipeline.submit
visionQueue        VNImageRequestHandler.perform → HandState
→ main             DispatchQueue.main.async + MainActor.assumeIsolated (conserva el orden)
```

- Vision nunca corre en el main thread.
- **Backpressure:** hay como máximo un frame en vuelo. Si Vision sigue ocupado, el frame
  nuevo se descarta (se cuenta en `Dropped frames`), así la latencia no se acumula.
  Además, `alwaysDiscardsLateVideoFrames = true`.
- Los frames nunca se guardan: el `CVPixelBuffer` se libera al terminar Vision.
- Swift 6 (`SWIFT_VERSION = 6.0`, concurrencia estricta). `CameraManager` y
  `HandTrackingPipeline` son `@unchecked Sendable` con su estado confinado a colas serie
  o protegido por `NSLock`, y lo documentan en el código.
- El overlay se actualiza por cada resultado de Vision (~30 Hz). Las métricas llegan a la
  UI como máximo 4 veces por segundo.

## Métricas (nombres honestos)

| Métrica | Qué mide | Qué NO mide |
|---|---|---|
| Camera FPS | Frames entregados por AVFoundation (ventana de 1 s) | — |
| Vision FPS | Frames procesados por Vision | — |
| Vision processing | Duración de `perform` (suavizada) | La espera en cola |
| Capture → HandState | Timestamp de captura → `HandState` listo (cola + Vision) | Tiempo de pantalla: **no es latencia end-to-end** |
| Dropped frames | Descartados por backpressure + descartados por AVFoundation | — |

`Capture → HandState` asume que el timestamp de presentación está en el reloj host (lo
habitual en AVCaptureSession). Si el valor no es plausible (fuera de 0–2 s) se muestra
"—". DEFERRED TO LOCAL MAC VALIDATION.

## Módulos de AirTrackCore

| Carpeta | Tipos | Responsabilidad |
|---|---|---|
| `Models/` | `HandJoint`, `HandState`, `InteractionAction`, `AirTrackSettings`, `KeyboardShortcut`, `LandmarkCoordinateConversion` | Modelos independientes del proveedor de tracking |
| `Geometry/` | `Point2D`, `Rect2D` | Geometría propia (sin CGPoint, para compilar en Linux) |
| `Cursor/` | `CursorMapper`, `CursorSmoother`, `ScreenMapper` | Cámara → pantalla |
| `Gestures/` | `HandScale`, `PinchRecognizer`, `GestureStateMachine`, `GestureEngine` | Gestos |
| `Calibration/` | `ActiveAreaCalibration` | Matemática de calibración (la UI es PHASE 5) |

## Reglas de seguridad

- Si se pierde el tracking, `HandState` queda vacío (`isTracked = false`) y el overlay
  desaparece; nunca se inventan landmarks.
- Sin permiso de cámara la app arranca igual y muestra cómo concederlo.
- Una cámara desconectada muestra `DISCONNECTED`, no `ERROR`. Un error de runtime justo
  después de una desconexión se trata como desconexión.
- Cerrar la ventana cierra la app, así que la cámara nunca queda encendida en segundo plano.
- (Core, ya probado) Tracking loss o pausa durante un drag → `mouseUp`; drag sin saltos.

## Decisiones

| Decisión | Motivo | Estado |
|---|---|---|
| AirTrackCore sin frameworks de Apple | Tests sin cámara, también en Linux o CI | Definitiva |
| `LandmarkCoordinateConversion` en Core | La conversión de ejes es lógica pura; en Core se prueba con `swift test` en macOS y Linux sin crear un target de tests en Xcode que enlazaría AirTrackCore dos veces | Definitiva (adición, no cambia nada existente) |
| Vision clásico (`VNDetectHumanHandPoseRequest`) | Disponible desde macOS 11, compatible con el deployment target 14 y conocido. La API Swift nueva de Vision (macOS 15+) queda como opción futura | Revisable |
| Deployment target macOS 14 | `@Observable`, `@Bindable` y los tipos de cámara `.external`/`.continuityCamera` | Revisable |
| Overlay alineado con la conversión del preview layer | Evita reimplementar letterboxing y espejo a mano | Pendiente de confirmación visual |
| Descartar frames en lugar de encolarlos | Latencia acotada | Definitiva |
| Proyecto con grupos sincronizados (objectVersion 77) | `.pbxproj` sin lista de archivos: más pequeño y robusto | Requiere Xcode 16+ |
| Firma "Sign to Run Locally" (ad-hoc) + entitlement de cámara | Ejecución local sin cuenta de desarrollador; sin sandbox. Con firma ad-hoc Xcode desactiva el Hardened Runtime; el entitlement cubre el caso de firmar con un Team | MVP |
| Latencia del pinch en 2 frames, EMA por frame | Ver `GESTURES.md` | Provisional |
