# PHASE 1.1 RESULT — Tracking, coordenadas, identidad de landmarks y estabilidad

**Estado:** implementado y verificado por CI. **Validación física en el Mac pendiente.**
PHASE 1 sigue **IN PROGRESS**. No se implementó nada de PHASE 2 (ni cursor, ni click, ni
drag, ni scroll, ni CGEvent, ni Accesibilidad).

Entorno de desarrollo: Claude Code Cloud (Linux x86_64, sin Xcode ni cámara). Todo lo que
aquí figura como "verificado" es por tests automatizados, compilación en CI o análisis de
código. **Nada se probó con la cámara física.**

---

## 1. Problema

Validación en el Mac real (PHASE 1):

| Observación | Resultado |
|---|---|
| Cámara, permiso, preview, tracking LOST y recovery, movimiento horizontal | OK |
| Movimiento vertical | **Invertido** |
| Cadena `wrist → indexMCP → indexPIP → indexDIP → indexTip` | **Termina en la zona del dedo medio** |
| Alejar la mano | **Los puntos se desplazan** |
| ~20 cm | Menos fiable, **falsos positivos** |
| Dos manos | **`Hands = 1`** |
| Rendimiento | 30 FPS, Vision 11.6–30 ms, Capture → HandState ~45 ms, Dropped frames 22–23 |

## 2. Causa raíz

### 2.1 Vertical invertida + cadena en otro dedo + desplazamiento con la distancia → un solo bug, en el overlay

Auditoría del pipeline:

| Paso | Estado | Evidencia |
|---|---|---|
| Buffer de cámara → Vision (`.up`) | Correcto | Mac: buffer horizontal y derecho |
| Vision → `HandJoint` | **Correcto**: por identificador (`recognizedPoints(.all)[.indexTip]`), nunca por orden | Revisión del código de PHASE 1 |
| Vision (origen abajo-izq.) → `HandState` (`y = 1 − y`) | Correcto | Tests de PHASE 1 y 1.1 |
| `HandState` → overlay | **Incorrecto** | Ver abajo |

El overlay de PHASE 1 convertía cada punto con
`AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)` y lo dibujaba en
un `CALayer` alojado en un `NSView` sin invertir. Esa función devuelve puntos con **Y hacia
abajo**, pero en macOS el espacio de ese layer tiene **Y hacia arriba**. Resultado: cada
landmark se reflejaba verticalmente respecto al centro del preview, mientras la X (y el
espejo horizontal) quedaba bien.

Ese único error explica los tres síntomas:
- **Vertical invertida:** es el reflejo.
- **Cadena del índice en el dedo medio:** una cadena reflejada verticalmente aterriza sobre
  otra parte de la mano. Las confianzas eran altas porque Vision sí detectaba bien.
- **Desplazamiento al alejar la mano:** el error es `2·(y − 0.5)·alto`, así que depende de
  dónde queda la mano y cambia al moverla o alejarla.

`HandState` (lo que usará PHASE 2) **sí era correcto**; el fallo era solo visual.

> Límite honesto: no pude ejecutar la API de Apple desde Linux para confirmar su convención
> de salida en macOS. La explicación encaja con todos los síntomas, y el arreglo no depende
> de ella: elimina esa API del camino.

### 2.2 Dos manos

`VNDetectHumanHandPoseRequest.maximumHandCount = 1` (configuración de PHASE 1): Vision
descartaba la segunda mano.

### 2.3 Falsos positivos cerca de la cámara

PHASE 1 aceptaba cualquier observación con al menos un joint de confianza > 0. No
comprobaba la confianza de la mano, los joints requeridos, el número de joints ni el
tamaño, y una detección espuria de un solo frame se mostraba como mano. (No había reuso de
landmarks viejos: cada frame se reemplazaba entero; ahora además está garantizado por tests.)

### 2.4 Dropped frames

- El contador (22–23) era **acumulado desde el arranque** y mezclaba los frames descartados
  por AVFoundation con los descartados por estar Vision ocupado. Sobre ~30 fps durante
  minutos, es menos del 1 %; es probable que se concentren al arrancar, cuando la primera
  petición de Vision es lenta. No era un problema de rendimiento.
- Sí había un problema menor de latencia: con Vision ocupado se tiraba el frame recién
  llegado y, al terminar, se esperaba al siguiente de la cámara (hasta 33 ms extra).

## 3. Arreglos

| # | Arreglo | Dónde |
|---|---|---|
| 1 | Overlay reescrito en SwiftUI `Canvas`: origen arriba-izquierda documentado, igual que `HandState`. Transformación pura y probada: `PreviewGeometry` (rect letterbox de `.resizeAspect` + espejo en X). Sin `layerPointConverted` | `UI/HandDebugOverlay.swift`, `UI/CameraPreviewView.swift`, Core `Geometry/PreviewGeometry.swift` |
| 2 | 21 joints en `HandJoint` + `HandSkeleton` (cadenas por dedo); mapeo Vision → `HandJoint` en un `switch` exhaustivo; comprobación uno a uno al arrancar | Core `Models/HandJoint.swift`, `Vision/HandStateMapper.swift`, `Vision/VisionHandTrackingEngine.swift` |
| 3 | Overlay con un color por dedo (pulgar naranja, índice verde, medio azul, anular morado, meñique rosa), para que un error de identidad se vea a simple vista | `UI/HandDebugOverlay.swift` |
| 4 | Hasta 2 manos (`maximumHandCount = 2`); orden determinista (`HandOrdering`); la mano 1 es la primaria; `chirality` y confianza en `HandState` | Core `Tracking/HandOrdering.swift`, `Models/HandState.swift` |
| 5 | `HandPresenceFilter`: validación (confianza de la mano y de los joints, joints requeridos, ≥10/21, tamaño mínimo, dentro de la imagen), gate de adquisición de 2 frames, pérdida inmediata y salida construida solo con el frame actual | Core `Tracking/HandPresenceFilter.swift`, `Vision/HandTrackingPipeline.swift` |
| 6 | Latest-frame-wins: buzón de 1 plaza. El frame nuevo sustituye al que esperaba y, al terminar Vision, se procesa el más reciente sin esperar | `Vision/HandTrackingPipeline.swift` |
| 7 | Métricas separadas: `Superseded frames` y `Camera drops` | `Vision/HandTrackingPipeline.swift`, `UI/TrackingStatusView.swift` |
| 8 | Panel: manos con L/R y confianza, `Index tip (x, y)` para validar la vertical sin depender del overlay, motivos de rechazo, landmarks por dedo | `UI/TrackingStatusView.swift` |

Umbrales nuevos (sin calibrar): confianza de mano ≥ 0.3, joint ≥ 0.3, joints requeridos
`wrist/thumbTip/indexMCP/indexTip`, ≥ 10 joints, `wrist→indexMCP` ≥ 0.02, tolerancia de
bordes 0.05 y 2 frames para adquirir. **No se bajó ningún umbral**; solo se añadieron
comprobaciones.

## 4. Archivos cambiados

**Core (lógica pura, solo Foundation):**
- `Models/HandJoint.swift`: 21 joints, `Finger`, `HandSkeleton`, `HandChirality`
- `Models/HandState.swift`: `chirality`, `confidence` (con valores por defecto; compatible)
- `Models/LandmarkCoordinateConversion.swift`: pasa `chirality` y `confidence`
- **Nuevos:** `Geometry/PreviewGeometry.swift`, `Tracking/HandPresenceFilter.swift`, `Tracking/HandOrdering.swift`

**App macOS:**
- `Vision/HandStateMapper.swift`, `Vision/VisionHandTrackingEngine.swift`, `Vision/HandTrackingPipeline.swift`
- `App/AppModel.swift`
- `UI/CameraPreviewView.swift`, `UI/HandDebugOverlay.swift`, `UI/ContentView.swift`, `UI/TrackingStatusView.swift`

**Tests (nuevos):** `HandJointIdentityTests`, `PreviewGeometryTests`,
`HandPresenceFilterTests`, `HandOrderingTests`; `TestSupport` con una mano sintética de 21 joints.

**Documentación:** `ARCHITECTURE.md`, `MACOS_SETUP.md`, `TESTING.md`, `ROADMAP.md`,
`GESTURES.md`, `README.md`, `AIRTRACK_PROJECT_STRUCTURE.md`, este archivo.

## 5. Tests añadidos (47)

| Requisito | Tests |
|---|---|
| Identidad de landmarks | `testThereAreExactly21DistinctJoints`, `testFingertipsKeepTheirIdentity`, `testEveryOneOf21JointsKeepsItsIdentity`, `testIndexTipIsNotTheMiddleTip` |
| Cadenas índice / medio / anular / meñique / pulgar | `testIndexChainFollowsTheIndexFinger`, `testMiddleChain…`, `testRingChain…`, `testPinkyChain…`, `testThumbChain…`, `testEveryChainStartsAtTheWristAndEndsAtItsOwnTip`, `testEveryNonWristJointBelongsToExactlyOneFinger` |
| Conversión / orientación vertical | `testTopOfImageIsTopOfViewAndBottomIsBottom`, `testMovingTheHandUpMovesTheOverlayUp` (pipeline Vision → HandState → pantalla) |
| Orientación horizontal y espejo | `testUnmirroredHorizontalMatchesTheImage`, `testMirroringFlipsHorizontalOnly`, `testMovingRightInTheImageMovesLeftInAMirroredPreview` |
| Aspect ratio / letterbox | `testWideViewGetsSideBars`, `testTallViewGetsTopAndBottomBars` |
| Bordes y esquinas | `testCornersAndEdgesLandOnTheContentRect`, `testDegenerateInputsProduceNoPoint` |
| Estabilidad con la distancia | `testHandSizeDoesNotShiftItsAnchor`, `testMappingIsAffineSoHandShapeIsPreserved` |
| 0 / 1 / 2 manos, orden determinista | `testZeroHands` ×2, `testOneHand` ×2, `testTwoHandsAreBothReportedInDeterministicOrder`, `testAtMostTwoHands`, `testTwoHandsAreOrderedLeftToRightInTheRawImage`, `testSameColumnIsOrderedTopFirst`, `testHandWithoutWristIsPlacedByItsCentroid`, `testUntrackedHandsAreDropped` |
| Baja confianza | `testLowHandConfidenceIsNotAHand`, `testLowConfidenceJointsAreRemovedNotKept`, `testRequiredJointWithLowConfidenceRejectsTheHand` |
| Falsos positivos | `testSingleFrameFalsePositiveIsNeverReported`, `testPartialDetectionWithTooFewJointsIsRejected`, `testTinySpuriousHandIsRejected`, `testMissingRequiredJointRejectsTheHand`, `testJointsFarOutsideTheImageAreRemoved`, `testRejectionReasonsAreReported` |
| Resultado inválido de Vision | `testInvalidProviderValuesNeverBecomeAHand` |
| Tracking loss / recovery | `testTrackingLossIsImmediate`, `testRecoveryAfterLossNeedsReacquisition`, `testAcquisitionNeedsConsecutiveFrames` |
| Sin landmarks obsoletos | `testFailedObservationNeverReusesTheLastHand`, `testOutputAlwaysComesFromTheCurrentFrame` |

Todos son deterministas: datos sintéticos, sin reloj ni aleatoriedad. Comprueban
comportamiento (dónde acaba un punto, qué mano sale y cuándo), no detalles internos.

## 6. Resultados de los tests

GitHub Actions, run `36535906360`, commit `4b117fc`:

| Job | Resultado |
|---|---|
| `swift test` macOS 15 (arm64) | **132/132**, 0 failures, 0 unexpected |
| `swift test` Ubuntu 24.04 (x86_64) | **132/132**, 0 failures, 0 unexpected |
| `xcodebuild` AirTrack.app (Debug) | **OK**; único warning: "Metadata extraction skipped. No AppIntents.framework dependency found." (benigno) |

- Los 85 tests existentes siguen pasando; hay 47 nuevos.
- El target de la app no tiene tests unitarios. Su lógica comprobable sin cámara está en
  Core; la integración con AVFoundation y Vision solo se valida ejecutando la app.

## 7. Riesgos pendientes

1. **La corrección vertical solo se confirma en pantalla.** Si `.resizeAspect` coloca el video
   distinto de `PreviewGeometry` (lo que no debería ocurrir), habría un desfase. En ese caso
   hay que reportar la dirección y la magnitud.
2. **Umbrales sin calibrar.** Si son demasiado estrictos, puede aparecer `LOST` con una mano
   visible (sobre todo parcial o muy cerca). El panel muestra el motivo del rechazo.
3. **Precisión de Vision a distancia.** Con una mano pequeña en la imagen, Vision es menos
   preciso; eso no se arregla con coordenadas.
4. **La `chirality` (L/R) es la que reporta Vision** con la imagen sin espejo; no está validada.
5. **El orden de manos es espacial.** Si las manos se cruzan, la primaria cambia.
6. **El gate de 2 frames** añade unos 33 ms solo al adquirir la mano; perderla sigue siendo inmediato.
7. **El buzón retiene hasta 2 buffers de cámara a la vez.** Si aparecen muchos
   `Camera drops`, podría ser presión sobre el pool de buffers de la cámara.
8. **Cámaras rotadas** (Continuity Camera en vertical): no están contempladas.

## 8. Validación en el Mac (pasos exactos)

```bash
cd ~/ruta/a/airtrack_app
git checkout claude/gifted-carson-iyjqxg && git pull
cd AirTrackCore && swift test && cd ..      # esperado: Executed 132 tests, with 0 failures
open AirTrack/AirTrack.xcodeproj            # ⌘R
```

Colores del overlay: **pulgar naranja · índice verde · medio azul · anular morado · meñique rosa**.

| # | Qué hacer | Resultado esperado |
|---|---|---|
| **A — Movimiento vertical** | Mano de abajo arriba y de arriba abajo, despacio | Los puntos siguen la mano en la misma dirección. Panel "Index tip (x, y)": **subir la mano BAJA y** |
| **B — Identidad** | Mano abierta, dedos separados | Punta verde en el índice, azul en el medio, morada en el anular, rosa en el meñique, naranja en el pulgar; cada cadena recorre su dedo |
| **C — Distancia corta (~20 cm)** | Acercar la mano | Colores correctos si se detecta. `LOST` con "Rechazadas: …" es aceptable; un esqueleto sobre algo que no es tu mano **no** lo es |
| **D — Distancia normal/lejana** | Alejar poco a poco | Los puntos siguen pegados a la mano; no hay deriva que crezca con la distancia |
| **E — Dos manos** | Ambas en cuadro | `Hands: 2`, esqueletos "1" y "2"; la 1 es la más a la derecha del preview espejado |
| **F — Tracking LOST** | Sacar las manos | `LOST`, `Hands: 0`, el overlay desaparece al instante (sin esqueletos congelados) |
| **G — Recovery** | Volver a meter la mano | `HAND DETECTED` en ~2 frames, con los colores correctos |
| **H — Rendimiento** | ~1 minuto con la mano en cuadro | Anotar Camera FPS, Vision FPS, Vision processing, Capture → HandState, Superseded frames y Camera drops |

Qué reportar: OK/falla por fila, una captura con la mano abierta y los números de H. Si
algo falla, indica la dirección exacta (por ejemplo, "la punta verde cae en el medio" o "al
subir la mano, y sube").
