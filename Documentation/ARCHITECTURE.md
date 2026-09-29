# Arquitectura

## Principio

Toda la lógica que no toca hardware vive en **AirTrackCore** y es determinista:
recibe datos más un timestamp y devuelve comandos. La app de macOS (`AirTrack/`) es un
adaptador entre el hardware y AirTrackCore.

## Frontera AirTrackCore ↔ macOS

| AIRTRACKCORE (Swift Package) | MACOS APP (`AirTrack/AirTrack/`) |
|---|---|
| Modelos (`HandState`, `HandJoint` ×21, `InteractionAction`, settings) | Cámara (AVFoundation): `Camera/` |
| Geometría (`Point2D`, `Rect2D`, `PreviewGeometry`) | Vision (hand pose): `Vision/` |
| Conversión Vision → HandState (`LandmarkCoordinateConversion`) | Permiso de cámara: `Permissions/` |
| Esqueleto de la mano (`HandSkeleton`) | Preview + overlay de debug: `UI/` |
| Validación y orden de manos (`HandPresenceFilter`, `HandOrdering`) | Logging (`os.Logger`): `Utilities/` |
| Cursor, smoothing, pinch, gestos, calibración | *Futuro:* CGEvent, Accesibilidad, atajo global, menu bar, UserDefaults |
| Tests (sin hardware; macOS y Linux) | |

**Regla:** AirTrackCore solo importa `Foundation`. Nunca AVFoundation, Vision, AppKit,
CoreGraphics ni SwiftUI. El job de Linux del CI falla si alguien rompe esta regla.

```text
macOS / Vision  ──HandState──▶  AirTrackCore  ──[InteractionAction]──▶  macOS events (PHASE 2+)
```

## Pipeline de PHASE 1 / 1.1

```text
AVCaptureSession (CameraManager, sessionQueue)
      │ CMSampleBuffer en videoQueue
      ▼
CameraFrame (CVPixelBuffer + timestamp + tamaño)            ← nunca entra en AirTrackCore
      │ HandTrackingPipeline.submit → buzón de 1 plaza (latest-frame-wins)
      ▼
VisionHandTrackingEngine (visionQueue)
      │ VNDetectHumanHandPoseRequest, maximumHandCount = 2, orientación .up
      ▼
[VNHumanHandPoseObservation]  (orden arbitrario de Vision)
      │ HandStateMapper: 21 joints POR IDENTIFICADOR + chirality + confidence
      ▼
LandmarkCoordinateConversion (Core): y → 1 − y, descarta confidence ≤ 0
      ▼
candidatos [HandState]
      │ HandPresenceFilter (Core): validación, orden determinista, máx. 2, gate de adquisición
      ▼
manos válidas [HandState] (solo de ESTE frame; la primera es la primaria)
      ▼
AppModel (main) ──▶ CameraPreviewView (video) + HandDebugOverlay (SwiftUI) + TrackingStatusView
```

En PHASE 1 `HandState` todavía no pasa por `GestureEngine`: no hay cursor ni eventos.

### Componentes

| Archivo | Responsabilidad |
|---|---|
| `Camera/CameraManager.swift` | Discovery, sesión 1280×720 en 420f, start/stop, frames, desconexión y errores |
| `Camera/CameraStatus.swift` | `unknown`, `permissionRequired`, `ready`, `running`, `stopped`, `disconnected`, `error(String)` |
| `Camera/CameraFrame.swift` | Transporte AVFoundation → Vision |
| `Permissions/CameraPermissionManager.swift` | Permiso de cámara |
| `Vision/VisionHandTrackingEngine.swift` | Petición de Vision (hasta 2 manos) → candidatos |
| `Vision/HandStateMapper.swift` | Tabla explícita Vision → `HandJoint` y conversión a `HandState` |
| `Vision/HandTrackingPipeline.swift` | Buzón latest-frame-wins, filtro de presencia, métricas, logs |
| `App/AppModel.swift` | Estado de la UI (`@MainActor @Observable`) |
| `UI/CameraPreviewView.swift` | Solo video (`AVCaptureVideoPreviewLayer`, `.resizeAspect`, espejo) |
| `UI/HandDebugOverlay.swift` | Landmarks en SwiftUI `Canvas`, un color por dedo |
| `UI/TrackingStatusView.swift` | Panel de diagnóstico |

## Identidad de los landmarks (tabla explícita)

Cada joint se busca en el diccionario de `recognizedPoints(.all)` por su **identificador**
de Vision; nunca por posición en un array. En `HandStateMapper.visionJointName(for:)` es un
`switch` exhaustivo: añadir un `HandJoint` sin mapearlo no compila. Al arrancar, el motor
comprueba que el mapeo sea uno a uno (`mappingIsOneToOne`).

| Vision `JointName` | `HandJoint` | Punto anatómico |
|---|---|---|
| `.wrist` | `wrist` | Muñeca |
| `.thumbCMC` / `.thumbMP` / `.thumbIP` / `.thumbTip` | `thumbCMC` / `thumbMP` / `thumbIP` / `thumbTip` | Pulgar: carpometacarpiana → punta |
| `.indexMCP` / `.indexPIP` / `.indexDIP` / `.indexTip` | `indexMCP` / `indexPIP` / `indexDIP` / `indexTip` | Índice: nudillo → punta |
| `.middleMCP` / `.middlePIP` / `.middleDIP` / `.middleTip` | `middleMCP` … `middleTip` | Medio |
| `.ringMCP` / `.ringPIP` / `.ringDIP` / `.ringTip` | `ringMCP` … `ringTip` | Anular |
| `.littleMCP` / `.littlePIP` / `.littleDIP` / `.littleTip` | `pinkyMCP` … `pinkyTip` | Meñique (Vision lo llama "little") |

`HandSkeleton.chain(for:)` define cada dedo como `wrist → MCP/CMC → PIP/MP → DIP/IP → tip`.

## Sistemas de coordenadas (una sola convención)

**Convención de AirTrack:** normalizado 0…1 sobre la imagen completa, **origen
arriba-izquierda, Y hacia abajo, sin espejo**. `HandState` la usa, y el overlay también
(SwiftUI tiene el mismo origen).

| Espacio | Origen / Y | Espejo | Conversión | Dónde |
|---|---|---|---|---|
| Buffer de cámara | arriba-izq / abajo | no (forzado en la salida de datos) | — | `CameraFrame` |
| Vision | **abajo**-izq / **arriba** | no | `y' = 1 − y`, **una sola vez** | `LandmarkCoordinateConversion` (Core) |
| `HandState` | arriba-izq / abajo | **no** | — | frontera con Core |
| Overlay (SwiftUI) | arriba-izq / abajo, en puntos | opcional (`x' = 1 − x`) | rect letterbox + espejo | `PreviewGeometry` (Core) |
| Preview de video | lo gestiona AVFoundation | igual que el overlay | `.resizeAspect` | `CameraPreviewView` |
| Display normalizado / global CG | arriba-izq / abajo | — | — | PHASE 2+ |

- **Letterboxing:** `.resizeAspect` escala la imagen para que quepa y la centra.
  `PreviewGeometry.aspectFitRect` reproduce ese rectángulo a partir del tamaño de la vista
  y de `HandState.imageAspectRatio` (ancho/alto del buffer: 16:9 a 1280×720).
- **Espejo:** solo visual y siempre en el eje X. `HandState` es siempre la imagen real;
  el espejo del cursor lo aplicará `CursorMapper` en PHASE 2.
- **Orientación:** cámaras de Mac en horizontal → Vision `.up`. Una cámara rotada (iPhone
  en vertical con Continuity Camera) no está contemplada.

### Qué estaba mal en PHASE 1 (corregido en 1.1)

El overlay convertía con `AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)`
y dibujaba en un `CALayer` alojado en un `NSView` sin invertir. Esa función entrega puntos
con Y hacia abajo, pero el espacio de ese layer en macOS tiene **Y hacia arriba**. Cada
landmark se reflejaba verticalmente respecto al centro del preview (en X la conversión era
correcta). Explica los tres síntomas del Mac real: la vertical invertida, la cadena del
índice sobre otro dedo y un desplazamiento que depende de la posición y la distancia.
`HandState` sí era correcto. Ahora el overlay es SwiftUI (origen arriba-izquierda,
documentado) y la transformación es una función pura con tests (`PreviewGeometryTests`).

## Manos: validación, orden y datos obsoletos

`HandPresenceFilter` (Core) se aplica a cada frame:

1. **Validación** (`HandValidation`), con valores iniciales NO calibrados:
   - confianza de Vision de la mano ≥ 0.3;
   - se eliminan los joints con confianza < 0.3 o fuera de la imagen (±0.05);
   - deben existir `wrist`, `thumbTip`, `indexMCP` e `indexTip`;
   - ≥ 10 de 21 joints válidos;
   - tamaño `wrist → indexMCP` ≥ 0.02 alturas de imagen.
   Los motivos de rechazo aparecen en el panel ("Rechazadas: …").
2. **Orden determinista** (`HandOrdering`): de izquierda a derecha en la imagen **real**
   por la X de la muñeca (en el preview espejado se ve de derecha a izquierda); si falta la
   muñeca, se usa el centroide. En empate va primero la más alta y luego se ordena por
   chirality. La **mano 1 es la primaria**. Máximo 2.
3. **Gate de adquisición:** el tracking se reporta tras 2 frames seguidos con una mano
   válida (filtra falsos positivos de un solo frame). La pérdida es **inmediata**.
4. **Nunca hay datos obsoletos:** la salida se construye solo con el frame actual. Si
   Vision falla o no hay mano válida, se devuelven 0 manos; jamás las del frame anterior.

`chirality` (L/R) la reporta Vision y AirTrack no la valida.

## Frames: latest-frame-wins

```text
camera (30 fps) ─▶ ¿Vision libre? ── sí ─▶ procesar ya
                         │ no
                         ▼
                  buzón de 1 plaza  (un frame nuevo SUSTITUYE al que esperaba → "superseded")
                         │ al terminar Vision
                         ▼
                  procesar el frame más nuevo del buzón, sin esperar al siguiente de la cámara
```

- Como máximo hay 1 frame en proceso y 1 esperando: la memoria y la latencia están acotadas.
- PHASE 1 descartaba el frame que llegaba con Vision ocupado y luego esperaba al siguiente
  de la cámara (hasta 33 ms extra). Ahora procesa inmediatamente el más reciente.
- Los "dropped frames" de PHASE 1 (22–23) eran un **contador acumulado** desde el arranque
  que mezclaba dos cosas. Ahora están separados: `Superseded frames` (sustituidos en el
  buzón; esperado y sano) y `Camera drops` (los descarta AVFoundation). Con Vision a
  11–30 ms y frames cada 33 ms, lo esperable son pocos superseded, sobre todo al arrancar,
  cuando la primera petición de Vision es lenta. DEFERRED TO LOCAL MAC VALIDATION.

## Threading

```text
MAIN (MainActor)   SwiftUI, AppModel, overlay (Canvas)
sessionQueue       configuración de AVCaptureSession, startRunning/stopRunning (bloqueantes)
videoQueue         callbacks de AVCaptureVideoDataOutput → HandTrackingPipeline.submit
visionQueue        Vision + HandPresenceFilter → TrackingResult
→ main             DispatchQueue.main.async + MainActor.assumeIsolated (conserva el orden)
```

- Vision nunca corre en el main thread. Swift 6 con concurrencia estricta.
- `CameraManager` y `HandTrackingPipeline` son `@unchecked Sendable`, con su estado
  confinado a colas serie o protegido por `NSLock`, y lo documentan en el código.

## Métricas (nombres honestos)

| Métrica | Qué mide | Qué NO mide |
|---|---|---|
| Camera FPS | Frames entregados por AVFoundation (ventana de 1 s) | — |
| Vision FPS | Frames procesados por Vision | — |
| Vision processing | Duración de `perform` (suavizada) | Espera en el buzón |
| Capture → HandState | Timestamp de captura → manos listas (espera + Vision + filtro) | Tiempo de pantalla: **no es end-to-end** |
| Superseded frames | Sustituidos en el buzón por uno más nuevo (acumulado) | — |
| Camera drops | Descartados por AVFoundation (acumulado) | — |

## Módulos de AirTrackCore

| Carpeta | Tipos |
|---|---|
| `Models/` | `HandJoint`, `Finger`, `HandSkeleton`, `HandChirality`, `HandState`, `InteractionAction`, `AirTrackSettings`, `KeyboardShortcut`, `LandmarkCoordinateConversion` |
| `Geometry/` | `Point2D`, `Rect2D`, `PreviewGeometry` |
| `Tracking/` | `HandValidation`, `HandPresenceFilter`, `HandOrdering` |
| `Cursor/` | `CursorMapper`, `CursorSmoother`, `ScreenMapper` |
| `Gestures/` | `HandScale`, `PinchRecognizer`, `GestureStateMachine`, `GestureEngine` |
| `Calibration/` | `ActiveAreaCalibration` |

## Reglas de seguridad

- Nunca se inventan landmarks ni se reutilizan los de un frame anterior.
- Sin permiso de cámara, la app arranca igual y muestra cómo concederlo.
- Una cámara desconectada muestra `DISCONNECTED`, no `ERROR`.
- Cerrar la ventana cierra la app, así que la cámara no queda encendida.
- (Core) Tracking loss o pausa durante un drag → `mouseUp`; el drag no tiene saltos.

## Decisiones

| Decisión | Motivo | Estado |
|---|---|---|
| AirTrackCore sin frameworks de Apple | Tests sin cámara, también en Linux o CI | Definitiva |
| Toda la matemática de coordenadas en Core (`LandmarkCoordinateConversion`, `PreviewGeometry`) | Se prueba en macOS y Linux sin target de tests en Xcode | Definitiva |
| Overlay en SwiftUI en lugar de la conversión de `AVCaptureVideoPreviewLayer` | Una sola convención documentada; elimina la inversión vertical | 1.1, pendiente de confirmación visual |
| 21 joints en `HandJoint` | Validar la identidad de todos los dedos | 1.1 |
| Hasta 2 manos; la primera es la primaria | Vision ya no descarta la segunda mano; los gestos siguen con una | 1.1 |
| Filtro de validación y gate de 2 frames | Falsos positivos y datos obsoletos | 1.1, umbrales sin calibrar |
| Buzón latest-frame-wins de 1 plaza | Latencia acotada, sin colas | 1.1 |
| Vision clásico (`VNDetectHumanHandPoseRequest`) | Compatible con macOS 14 | Revisable |
| Firma ad-hoc + entitlement de cámara, sin sandbox | Ejecución local | MVP |
| Latencia del pinch en 2 frames, EMA por frame | Ver `GESTURES.md` | Provisional |
