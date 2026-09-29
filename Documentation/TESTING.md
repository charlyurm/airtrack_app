# Testing

## Unit tests de AirTrackCore (sin hardware)

```bash
cd AirTrackCore
swift test
```

Total: **334 tests** en 25 suites (85 hasta PHASE 1 + 47 de PHASE 1.1 + 44 de PHASE 2 + 53 de PHASE 2.1 + 11 del hotfix de Accesibilidad + 58 de PHASE 3A-1 + 36 de PHASE 3A-2). Detalle de 3A en `PHASE3A1_RESULT.md` §3 y `PHASE3A2_RESULT.md` §3.

| Suite | Tests | Cubre |
|---|---|---|
| `CursorMapperTests` | 16 | espejo, zona activa, límites, sensibilidad, NaN, calibración de dos esquinas; (PHASE 2) normalización sin clamp, sensibilidad alrededor del centro, dos pasos ≡ área encogida, área por defecto |
| `ScreenMapperTests` | 9 | esquinas, multi-monitor, orígenes negativos, conversión AppKit → global |
| `CursorSmootherTests` | 11 | fórmula EMA, convergencia, reducción de jitter, reset, límites; (PHASE 2) reposo exacto, sin overshoot, retraso acotado, determinismo |
| `PinchRecognizerTests` | 15 | pinch sí/no, invariancia a escala de mano, histéresis, spikes, ruido con semilla, aspect ratio, oclusión, confianza |
| `GestureStateMachineTests` | 27 | click, ancla, drag sin salto, double click, tracking loss, pausa, re-armado |
| `GestureEngineTests` | 8 | pipeline completo, pausa, reanudar con mano cerrada, reset al perder tracking, settings |
| `LandmarkCoordinateConversionTests` | 7 | origen abajo-izquierda → arriba-izquierda, esquinas, sin espejo, confidence/timestamp/aspect, joints descartados, mano no detectada, compatibilidad con el pinch |
| `HandJointIdentityTests` (1.1) | 11 | 21 joints distintos, cadenas de los 5 dedos (wrist → punta, sin solapes), identidad de las 21 posiciones tras la conversión, cada cadena sigue su dedo, índice ≠ medio |
| `PreviewGeometryTests` (1.1) | 11 | vertical (subir la mano = subir en pantalla), horizontal, espejo, letterbox lateral y superior/inferior, esquinas y bordes, entradas degeneradas, estabilidad con la distancia, transformación afín |
| `HandPresenceFilterTests` (1.1) | 19 | 0/1/2 manos, máximo 2, orden determinista, baja confianza (mano y joints), joint requerido, detección parcial, mano diminuta, fuera de imagen, valores inválidos, falso positivo de un frame, pérdida inmediata, sin datos obsoletos, salida del frame actual, recuperación |
| `CursorControllerTests` (2) | 27 | (2.1: cambia solo la aserción del smoothing por defecto 0.35 → 0.6) centro, bordes, esquinas, clamp, dirección Y, izquierda física, pantallas arbitrarias y desplazadas, puntos lógicos, sensibilidad, smoothing, dead zone, solo la mano primaria, sin mano, punta inválida, desactivado, pérdida inmediata, recuperación sin datos obsoletos y sin salto, determinismo, estados de activación, ajustes |
| `DeadZoneFilterTests` (2) | 9 | bajo el umbral, exactamente en el umbral, sobre el umbral, dedo quieto con ruido, movimiento intencional sin retraso, reset, umbral limitado |
| `AdaptiveCursorSmootherTests` (2.1) | 18 | quieto exacto, micro jitter, lento/normal/rápido, lag acotado, aceleración, deceleración y parada sin overshoot, inversión de dirección, independencia de FPS, determinismo, rango, reset, timestamps duplicados, hueco largo, saneo, equivalencia con la EMA de PHASE 2 |
| `PointerTrackerTests` (2.1) | 24 | adquisición estricta, parcial e índice tras la adquisición, mano saliendo por abajo, índice aislado/parcial desconocido nunca activa, salto, baja confianza, obsoleto, chirality, geometría, coherencia, HOLD, timeouts, reacquisición completa, desactivado = PHASE 2, determinismo, saneo |
| `CursorPointerIntegrationTests` (2.1) | 11 | modos que mueven el cursor, HOLD sin eventos ni glide, LOST borra la sesión, glide desde el cursor real, borde inferior alcanzable con la palma fuera, un frame perdido no reinicia |
| `AccessibilityPermissionTrackerTests` (hotfix 2.1) | 11 | concedido al iniciar (nunca WAITING FOR PERMISSION), denegado al iniciar, false → true al volver a la app, true → false (periódico), activación/acciones siempre consultan, periódico limitado a 1/s, sin estado obsoleto, prompt como mucho una vez, sin solicitud si ya hay permiso, reloj hacia atrás. La API real de TCC no se simula: solo se prueban las transiciones |
| `HandFeaturesTests` (3A-1) | 13 | escala, invariancia (tamaño/posición/aspect/rotación), estados de dedo, UNKNOWN, ruido, NaN |
| `PoseClassifierTests` (3A-1) | 9 | 5 poses, invariancia, ambiguas → UNKNOWN, histéresis |
| `FeatureHistoryTests` (3A-1) | 7 | ring buffer acotado, velocidad/desplazamiento en escalas, espejo, eje dominante |
| `IntentArbiterTests` (3A-1) | 9 | un dueño, ambigüedad, ciclo de vida, SUSPENDED, liberaciones |
| `InteractionEngineTests` (3A-1) | 18 | reconocimiento de scroll en modo sombra, política del cursor, tracking, transiciones, sin acciones |
| `PointerTrackerTrackedHandTests` (3A-1) | 2 | `trackedHand` por modo, decisiones sin cambios |
| `ScrollControllerTests` (3A-2) | 18 | deadband, velocidad, fracciones, fases, inercia acotada |
| `ScrollInteractionTests` (3A-2) | 18 | scroll live, conflictos, bloqueo de eje, inercia, cursor, tracking, seguridad de la salida |
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
| `dad01ad` (2) | 176/176, 0 failures | 176/176, 0 failures | Build OK. Único warning: AppIntents (benigno) |
| `9d20d76` (2.1) | 229/229, 0 failures | 229/229, 0 failures (Swift 6.4) | `** BUILD SUCCEEDED **`. Único warning: AppIntents (benigno) |
| `7d234e1` (hotfix Accesibilidad) | 240/240 | 240/240 | Build OK. Único warning: AppIntents |
| `03134e5` (3A-1) | 298/298 | verde | Build OK. Único warning: AppIntents |
| `a6a77a6` (3A-2) | 334/334, 0 failures | 334/334, 0 failures | `** BUILD SUCCEEDED **`. Único warning: AppIntents (benigno) |

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

PHASE 2 (cursor): pruebas A–L en `PHASE2_RESULT.md` §15 y `MACOS_SETUP.md` §P.
PHASE 2.1 (cursor adaptativo y tracking periférico): pruebas A–N en `PHASE2_1_RESULT.md` §9.
PHASE 3A-1 (poses, modo sombra): pruebas A–J en `PHASE3A1_RESULT.md` §6. PHASE 3A-2 (scroll):
pruebas 1–16 en `PHASE3A2_RESULT.md` §7.

Pendientes de fases posteriores:
- [ ] Click, double click y drag reales (PHASE 3)
- [ ] Calibración de los umbrales de pinch con manos reales
