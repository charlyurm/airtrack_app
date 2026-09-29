# AIRTRACK — PHASE 1
# macOS FOUNDATION + CAMERA + VISION HAND TRACKING

Trabaja directamente sobre el repositorio AirTrack abierto en ESTA SESIÓN.

IMPORTANTE: esta fase DEBE ejecutarse en mi Mac real, no en Linux remoto. Antes de modificar cualquier archivo verifica macOS, arquitectura, Xcode, Swift, SDK, ruta, branch y git status. Si no estás realmente en macOS con Xcode disponible, DETENTE y no modifiques nada.

## ESTADO ACTUAL

PHASE 0 está COMPLETA.
Commit base: `b240157`.

Validación:
- macOS arm64e
- Xcode 27.0
- Swift 6.4
- AirTrackCore compila
- 78 tests
- 0 failures
- 0 unexpected

NO reescribas Phase 0, NO reemplaces AirTrackCore y NO dupliques su lógica.

## ROADMAP OFICIAL

- PHASE 0 — Core + Architecture — COMPLETE
- PHASE 1 — macOS Foundation + Camera + Vision Hand Tracking — IN PROGRESS
- PHASE 2 — Cursor Control — NOT STARTED
- PHASE 3 — Click / Double Click / Drag — NOT STARTED
- PHASE 4 — Scroll — NOT STARTED
- PHASE 5 — Menu Bar / Settings / Calibration — NOT STARTED
- PHASE 6 — Optimization — NOT STARTED
- PHASE 7+ — Advanced Gestures — NOT STARTED

Actualiza ROADMAP.md y documentación para mantener esta numeración. NO implementes Phase 2.

## OBJETIVO

Construir la primera aplicación macOS real de AirTrack con este pipeline:

CAMERA → AVCaptureSession → CameraFrame → Vision → Hand Landmarks → HandState → Debug UI

Al terminar debo poder abrir AirTrack, conceder permiso de cámara, ver el preview, detectar una mano, ver sus landmarks alineados, ver estado de tracking, FPS/latencia y comprobar pérdida/recuperación del tracking.

Esta fase NO implementa control del mouse.

## 1. AUDITORÍA OBLIGATORIA

Antes de escribir código ejecuta:

```bash
pwd
git status
git branch --show-current
git log --oneline -5
uname -m
sw_vers
xcodebuild -version
swift --version
```

Inspecciona estructura, AirTrackCore, Package.swift, Sources, Tests, README, documentación, ROADMAP y cualquier proyecto/código previo de Phase 1. Busca `.xcodeproj`, `.xcworkspace`, target macOS, SwiftUI App, CameraManager, VisionHandTrackingEngine, CameraStatus, permisos, preview y debug overlay.

No dupliques implementaciones ni borres trabajo válido. Si existe trabajo parcial, intégralo.

## 2. ARQUITECTURA

### AirTrackCore
Debe seguir siendo Swift puro y testeable. NO debe importar AppKit, SwiftUI, AVFoundation, Vision, CoreMedia, CGEvent ni APIs de permisos macOS.

Contiene modelos, geometría, cursor mapping, smoothing, pinch recognition, gesture state machine, gesture engine, calibration, lógica pura y tests.

### macOS App
Puede usar SwiftUI, AppKit, AVFoundation, Vision, CoreMedia, CoreGraphics, os y APIs de permisos. Es responsable de cámara, permisos, Vision, preview, debug UI e integración futura con eventos macOS.

## 3. INTEGRACIÓN

Integra AirTrackCore como dependencia local. La app debe poder usar:

```swift
import AirTrackCore
```

No copies ni dupliques `HandState`, `InteractionAction` o `AirTrackSettings`.

## 4. APP MACOS

Si no existe, crea una app nativa macOS llamada `AirTrack`, SwiftUI, Swift. Usa un deployment target compatible con el SDK instalado. Verifica las APIs reales disponibles y evita APIs deprecated cuando haya una alternativa correcta. La app debe arrancar incluso sin permiso de cámara.

Estructura sugerida, adaptándola si ya existe una mejor:

```text
AirTrack/
├── App/
│   ├── AirTrackApp.swift
│   └── AppModel.swift
├── Camera/
│   ├── CameraManager.swift
│   ├── CameraFrame.swift
│   └── CameraStatus.swift
├── Vision/
│   ├── VisionHandTrackingEngine.swift
│   ├── VisionHandObservation.swift
│   └── HandStateMapper.swift
├── Permissions/
│   └── CameraPermissionManager.swift
├── UI/
│   ├── ContentView.swift
│   ├── CameraPreviewView.swift
│   ├── HandDebugOverlay.swift
│   └── TrackingStatusView.swift
└── Utilities/
    └── Logging.swift
```

## 5. CAMERA STATUS

Implementa un estado equivalente a:

```swift
enum CameraStatus {
    case unknown
    case permissionRequired
    case ready
    case running
    case stopped
    case disconnected
    case error
}
```

`disconnected` DEBE ser distinto de `error`.

## 6. CAMERA MANAGER

Implementa `CameraManager` para:
- descubrir cámaras
- seleccionar cámara
- solicitar permiso
- crear/configurar `AVCaptureSession`
- crear input
- configurar `AVCaptureVideoDataOutput`
- entregar frames
- start/stop
- interrupciones
- desconexiones
- errores
- liberar recursos

Debe existir una API equivalente a requestPermission, start, stop, availableCameras, status y entrega de frames, usando los nombres que mejor encajen con la arquitectura.

## 7. PERMISOS

Configura `NSCameraUsageDescription` con una explicación clara de que AirTrack necesita la cámara para detectar movimientos de la mano.

Maneja notDetermined, authorized, denied y restricted si aplica. Si se deniega: no crash, no loops, estado comprensible e instrucciones apropiadas.

## 8. CAMERA FRAME Y PREVIEW

Crea una abstracción `CameraFrame` para transportar desde AVFoundation a Vision, pudiendo contener `CVPixelBuffer`, timestamp, dimensiones y orientación. `CVPixelBuffer` NO debe entrar en AirTrackCore.

Implementa preview real, aspect ratio correcto, sin deformación, orientación correcta y mirror horizontal si corresponde. Documenta y coordina las transformaciones con Vision; no asumas que invertir X siempre es suficiente.

## 9. VISION HAND TRACKING

Implementa `VisionHandTrackingEngine` usando la API de Vision realmente disponible en el SDK instalado. Verifica primero la API de hand pose detection y usa la API moderna compatible.

Todo debe funcionar con la cámara real, localmente. No simules landmarks ni uses servicios externos.

Obtén como mínimo, cuando estén disponibles:
- wrist
- thumb tip
- index MCP
- index PIP
- index DIP
- index tip
- middle tip
- ring tip
- little tip

## 10. VISION → HANDSTATE

Implementa `HandStateMapper`:

Vision Observation → HandStateMapper → AirTrackCore.HandState

Debe manejar transformación de coordenadas, normalización, confidence, timestamps, joints válidos y tracking validity.

Usa el `HandState` existente. No crees otro. Si existe incompatibilidad real, primero intenta resolverla en macOS; modifica Core solamente si es necesario, con tests y documentación.

## 11. COORDENADAS — CRÍTICO

Documenta:
- coordenadas de Vision
- coordenadas del preview
- coordenadas esperadas por HandState
- mirror
- orientación
- normalización

Evita X/Y invertidos, rotación, desplazamiento y desalineación entre preview y landmarks.

Toda transformación que pueda ser lógica pura debe tener tests. Si depende de Vision/AppKit/AVFoundation, mantenla en macOS y prueba lo posible sin contaminar Core.

## 12. THREADING

Vision NO debe bloquear Main Thread.

Objetivo:

```text
MAIN THREAD → SwiftUI / UI
CAMERA QUEUE → AVCaptureVideoDataOutput
VISION QUEUE → Vision processing
RESULT → HandState
MAIN ACTOR → UI update
```

Usa concurrencia compatible con Swift 6. Evita data races, acceso inseguro, trabajo pesado en MainActor y warnings de Sendable que puedan corregirse.

## 13. TRACKING

Distingue:
- Camera running + hand detected
- Camera running + no hand
- Camera disconnected
- Camera error

Cuando desaparezca la mano: no produzcas eventos del sistema, limpia el estado y permite reacquisición.

## 14. DEBUG UI

Construye una UI de debugging con preview y overlay. Debe mostrar algo equivalente a:

```text
AirTrack
Camera: RUNNING
Tracking: HAND DETECTED
Hands: 1
Camera FPS: XX
Vision FPS: XX
Vision processing: XX ms
Vision latency: XX ms
```

Dibuja landmarks y, si es útil, conexiones simples. La UI debe permitir diagnosticar cámara, Vision, tracking y coordenadas.

## 15. VALIDACIÓN VISUAL DE LANDMARKS

Los landmarks deben quedar sobre la mano visible. Prueba mano izquierda/derecha, cerca/lejos, arriba/abajo/izquierda/derecha. Si hay mirror, preview y landmarks deben ser coherentes.

No declares que están correctamente alineados solamente porque compile: debe comprobarse ejecutando la app y, si hace falta, con mi confirmación visual.

## 16. FPS Y LATENCIA

Mide Camera FPS, Vision FPS y Vision processing duration. Mide latencia de forma honesta. Si sólo puedes medir frame → Vision result, llámala `Vision processing latency`; no la presentes como end-to-end latency. No inventes números.

## 17. LOGGING Y ERRORES

Usa logging estructurado. Registra permisos, cámara seleccionada, sesión start/stop, interrupción, desconexión, Vision start/error y tracking acquired/lost. No inundes consola por frame.

No debe haber crashes por cámara no disponible, permiso denegado, desconexión, frame inválido, ausencia de observaciones, landmarks faltantes, error de AVCaptureSession o interrupción temporal.

## 18. NO IMPLEMENTAR TODAVÍA

NO implementes:
- cursor movement
- CGEvent mouse movement
- Accessibility event posting
- click
- double click
- drag
- right click
- scroll
- horizontal swipe
- Spaces
- Mission Control
- zoom
- advanced gestures
- emergency shortcut
- menu bar completo
- settings completos
- calibration UI completa
- analytics
- telemetry
- cloud vision
- API externa
- backend
- sincronización cloud

Phase 1 exclusivamente: CAMERA + VISION + HAND TRACKING + DEBUG UI.

## 19. TESTS

Después de implementar:

```bash
cd AirTrackCore
swift test
```

Debe haber 0 failures y 0 unexpected. Actualmente esperamos 78 tests; el número puede aumentar si agregas tests legítimos.

NO aceptes regresiones.

## 20. BUILD REAL DE MACOS

Es obligatorio compilar la app macOS completa mediante Xcode/xcodebuild y obtener `BUILD SUCCEEDED`. `swift test` por sí solo NO es suficiente.

## 21. EJECUCIÓN REAL

Ejecuta la app y verifica:
1. abre
2. ventana
3. permiso
4. preview
5. frames
6. Vision
7. landmarks
8. tracking loss
9. tracking recovery

Si necesitas mi validación visual, ejecuta la app, deja el overlay visible y dime exactamente qué debo observar; espera mi confirmación.

## 22. PRUEBAS MANUALES

A — cámara: imagen real.
B — permiso: aparece correctamente.
C — mano: `Tracking: HAND DETECTED`, `Hands: 1`.
D — landmarks: aparecen sobre la mano.
E — movimiento: izquierda/derecha/arriba/abajo siguen correctamente.
F — distancia: acercar/alejar.
G — tracking loss: sacar mano → `Tracking: LOST`.
H — recovery: volver a introducir → `Tracking: HAND DETECTED`.
I — si es posible, interrupción/desconexión → `Camera: DISCONNECTED` o estado equivalente.

## 23. DOCUMENTACIÓN

Actualiza README, ROADMAP, arquitectura, cámara, Vision, permisos, coordenadas, threading, ejecución y testing.

Documenta el pipeline:

```text
AVCaptureSession
      ↓
CameraFrame
      ↓
VisionHandTrackingEngine
      ↓
Vision observation
      ↓
HandStateMapper
      ↓
HandState
```

Y la frontera:

```text
macOS / Vision
      ↓
HandState
      ↓
AirTrackCore
```

## 24. GIT

Antes de terminar:

```bash
git status
git diff --stat
git diff
```

Revisa basura, credenciales, builds temporales, archivos enormes, cambios innecesarios y cambios accidentales en Core.

Si todo está correcto:

```bash
git add .
git commit -m "feat: implement macOS camera and vision hand tracking"
git status
```

Mantén la rama actual. No cambies de branch.

## 25. CRITERIOS DE ACEPTACIÓN

Phase 1 sólo puede ser COMPLETE si:

[ ] app macOS existe y abre
[ ] AirTrackCore integrado
[ ] Core con 0 failures
[ ] app macOS compila
[ ] BUILD SUCCEEDED
[ ] permiso de cámara funciona
[ ] preview funciona
[ ] CameraManager funciona
[ ] CameraStatus implementado
[ ] disconnected separado de error
[ ] Vision funciona
[ ] hand tracking funciona
[ ] landmarks visibles
[ ] landmarks correctamente alineados
[ ] HandState generado
[ ] coordenadas verificadas
[ ] tracking loss funciona
[ ] tracking recovery funciona
[ ] Vision no bloquea UI
[ ] Camera FPS medido
[ ] Vision FPS medido
[ ] processing time medido
[ ] latencia correctamente descrita
[ ] logging implementado
[ ] documentación actualizada
[ ] git revisado
[ ] commit realizado

## 26. NO DECLARAR ÉXITO FALSAMENTE

Usa sólo:
- PASS
- PASS WITH ISSUES
- BLOCKED

No declares PASS si no compilaste/ejecutaste la app, no probaste cámara/Vision/landmarks, existe un error importante o hay regresiones.

Si algo no puede probarse automáticamente, dilo explícitamente.

## 27. SI ENCUENTRAS PROBLEMAS

1. identifica causa
2. determina si pertenece a Core/macOS/Camera/Vision/UI/concurrency
3. aplica solución mínima
4. ejecuta tests
5. vuelve a compilar
6. vuelve a probar
7. documenta

No sobreingenierices.

## 28. REPORTE FINAL OBLIGATORIO

Al terminar NO avances a Phase 2. Entrega:

## PHASE 1 RESULT
### STATUS
PASS / PASS WITH ISSUES / BLOCKED

### ENVIRONMENT
- macOS:
- Architecture:
- Xcode:
- Swift:
- SDK:

### REPOSITORY
- Branch:
- Base commit:
- Final commit:
- Working tree:

### IMPLEMENTED
- App:
- AirTrackCore integration:
- Camera:
- Permissions:
- Preview:
- Vision:
- HandState mapping:
- Debug UI:
- Tracking loss:
- Tracking recovery:
- Logging:

### TESTS
- AirTrackCore tests:
- Total tests:
- Failures:
- Unexpected:
- macOS build:
- Build result:

### MANUAL VALIDATION
- Camera:
- Permission:
- Hand detection:
- Landmarks:
- Coordinate alignment:
- Tracking loss:
- Tracking recovery:

### PERFORMANCE
- Camera FPS:
- Vision FPS:
- Vision processing time:
- Vision latency:

### FILES CREATED
- ...

### FILES MODIFIED
- ...

### WARNINGS
- ...

### KNOWN ISSUES
- ...

### ARCHITECTURAL DECISIONS
- ...

### GIT
- Commit:
- Branch:
- Working tree:

### NEXT PHASE
Phase 2 — Cursor Control

NO implementes Phase 2.

## 29. ORDEN DE EJECUCIÓN

AUDIT
→ APP FOUNDATION
→ AIRTRACKCORE INTEGRATION
→ CAMERA PERMISSIONS
→ CAMERA MANAGER
→ CAMERA PREVIEW
→ VISION HAND TRACKING
→ HANDSTATE MAPPING
→ COORDINATE TRANSFORMATIONS
→ DEBUG OVERLAY
→ TRACKING LOSS / RECOVERY
→ FPS / PERFORMANCE
→ ERROR HANDLING
→ TESTS
→ BUILD
→ RUN
→ MANUAL VALIDATION
→ DOCUMENTATION
→ GIT REVIEW
→ FINAL REPORT

No inventes resultados. No marques como probado algo que no se ejecutó. No avances a Phase 2.

EMPIEZA AHORA CON LA AUDITORÍA DEL ENTORNO Y DEL REPOSITORIO.
