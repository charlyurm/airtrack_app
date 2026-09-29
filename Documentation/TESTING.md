# Testing

## Unit tests de AirTrackCore (sin hardware)

```bash
cd AirTrackCore
swift test
```

Total: **132 tests** en 11 suites (85 hasta PHASE 1 + 47 de PHASE 1.1).

| Suite | Tests | Cubre |
|---|---|---|
| `CursorMapperTests` | 12 | espejo, zona activa, límites, sensibilidad, NaN, calibración de dos esquinas |
| `ScreenMapperTests` | 9 | esquinas, multi-monitor, orígenes negativos, conversión AppKit → global |
| `CursorSmootherTests` | 7 | fórmula EMA, convergencia, reducción de jitter, reset, límites |
| `PinchRecognizerTests` | 15 | pinch sí/no, invariancia a escala de mano, histéresis, spikes, ruido con semilla, aspect ratio, oclusión, confianza |
| `GestureStateMachineTests` | 27 | click, ancla, drag sin salto, double click, tracking loss, pausa, re-armado |
| `GestureEngineTests` | 8 | pipeline completo, pausa, reanudar con mano cerrada, reset al perder tracking, settings |
| `LandmarkCoordinateConversionTests` | 7 | origen abajo-izquierda → arriba-izquierda, esquinas, sin espejo, confidence/timestamp/aspect, joints descartados, mano no detectada, compatibilidad con el pinch |
| `HandJointIdentityTests` (1.1) | 11 | 21 joints distintos, cadenas de los 5 dedos (wrist → punta, sin solapes), identidad de las 21 posiciones tras la conversión, cada cadena sigue su dedo, índice ≠ medio |
| `PreviewGeometryTests` (1.1) | 11 | vertical (subir la mano = subir en pantalla), horizontal, espejo, letterbox lateral y superior/inferior, esquinas y bordes, entradas degeneradas, estabilidad con la distancia, transformación afín |
| `HandPresenceFilterTests` (1.1) | 19 | 0/1/2 manos, máximo 2, orden determinista, baja confianza (mano y joints), joint requerido, detección parcial, mano diminuta, fuera de imagen, valores inválidos, falso positivo de un frame, pérdida inmediata, sin datos obsoletos, salida del frame actual, recuperación |
| `HandOrderingTests` (1.1) | 6 | 0/1/2 manos, izquierda → derecha independiente del orden de entrada, desempate por altura, centroide sin muñeca, descarte de manos vacías |

### Tests de drag (`GestureStateMachineTests`)

| Requisito | Test |
|---|---|
| Drag empieza sin salto | `testDragStartsWithoutAJump`, `testMovementTriggeredDragStartsWithoutAJump` |
| Offset se conserva | `testOffsetIsPreservedThroughoutTheDrag` |
| Movimiento del dedo = movimiento equivalente del cursor | `testFingerMovementProducesEquivalentCursorMovement` |
| El cursor no cambia abruptamente al entrar en DRAG | `testCursorNeverChangesAbruptlyWhenEnteringDrag` |
| Release termina el drag (sin salto de vuelta) | `testReleaseEndsDragWithoutSnappingBack` |
| Tracking loss termina el drag | `testTrackingLossEndsDragAfterTheGracePeriod` |
| Pausa durante drag termina el drag | `testPauseEndsDragImmediately` |
| Un pinch corto no entra en drag | `testShortPinchDoesNotEnterDrag` |
| (extra) El drag no sale de la pantalla | `testDragPositionStaysOnScreen` |

Determinismo: timestamps inyectados, PRNG con semilla fija y posiciones diádicas
(exactas en binario) en los tests de drag.

## App macOS

- **No tiene target de tests.** La lógica comprobable sin hardware, como la conversión
  de coordenadas de Vision, vive en AirTrackCore y se prueba allí. Lo que queda en la
  app es integración con AVFoundation, Vision y AppKit, que solo se verifica ejecutándola.
- **Compilación:** verificada en CI con `xcodebuild` (ver abajo).

## CI

`.github/workflows/airtrackcore-tests.yml` ("AirTrack CI") en cada push que toque
`AirTrackCore/` o `AirTrack/`:

| Job | Runner | Qué hace |
|---|---|---|
| `swift test (macOS)` | `macos-15` (arm64) | Tests de AirTrackCore |
| `swift test (Linux…)` | `ubuntu-24.04` (x86_64) | Tests de AirTrackCore; demuestra que no depende de Apple |
| `xcodebuild AirTrack.app` | `macos-15` | Compila la app completa (Debug, firma ad-hoc) y lista los warnings. **No la ejecuta**: el runner no tiene cámara |

El contenedor de desarrollo en la nube no tiene Swift ni Xcode, así que la ejecución
real de tests y builds es la del CI.

### Último resultado verificado

| Commit | Tests macOS | Tests Linux | Build app |
|---|---|---|---|
| `b041b7e` | 85/85, 0 failures | 85/85, 0 failures | `** BUILD SUCCEEDED **`. Único warning: "Metadata extraction skipped. No AppIntents.framework dependency found." (benigno) |
| `4b117fc` (1.1) | 132/132, 0 failures | 132/132, 0 failures | Build OK. Único warning: el mismo de AppIntents (benigno) |

## Validación manual — DEFERRED TO LOCAL MAC VALIDATION

La checklist detallada (qué hacer y qué esperar) está en `MACOS_SETUP.md`, sección M.

- [ ] `swift test` en el Mac del usuario
- [ ] `** BUILD SUCCEEDED **` en el Xcode del usuario
- [ ] Permiso de cámara (conceder y denegar)
- [ ] Preview con imagen real
- [ ] Detección de la mano (`HAND DETECTED`, `Hands: 1`)
- [ ] Los 21 landmarks aparecen agrupados por dedo
- [ ] Landmarks alineados sobre la mano (con y sin espejo), cada color en su dedo
- [ ] Vertical correcta: subir la mano baja `Index tip y`
- [ ] `Hands: 2` con dos manos
- [ ] Movimiento y distancia
- [ ] Tracking loss (`LOST`) y recovery
- [ ] Desconexión de cámara (`DISCONNECTED`)
- [ ] Camera FPS, Vision FPS, Vision processing y Capture → HandState con valores plausibles
- [ ] Sin errores repetitivos en el log

Pendientes de fases posteriores:
- [ ] Cursor con baja latencia y bajo jitter (PHASE 2)
- [ ] Click, double click y drag reales (PHASE 3)
- [ ] Calibración de los umbrales de pinch con manos reales
