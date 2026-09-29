# Testing

## Unit tests de AirTrackCore (sin hardware)

```bash
cd AirTrackCore
swift test
```

Total: **78 tests** en 6 suites.

| Suite | Tests | Cubre |
|---|---|---|
| `CursorMapperTests` | 12 | espejo, zona activa, límites, sensibilidad, NaN, calibración de dos esquinas |
| `ScreenMapperTests` | 9 | esquinas, multi-monitor, orígenes negativos, conversión AppKit → global |
| `CursorSmootherTests` | 7 | fórmula EMA, convergencia, reducción de jitter, reset, límites |
| `PinchRecognizerTests` | 15 | pinch sí/no, invariancia a escala de mano, histéresis, spikes, ruido con semilla, aspect ratio, oclusión, confianza |
| `GestureStateMachineTests` | 27 | click, ancla, drag sin salto, double click, tracking loss, pausa, re-armado |
| `GestureEngineTests` | 8 | pipeline completo, pausa, reanudar con mano cerrada, reset al perder tracking, settings |

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

Determinismo:
- Los timestamps se inyectan; nada depende del reloj.
- El "ruido" usa un PRNG con semilla fija.
- Las posiciones de los tests de drag son valores diádicos (0.5, 0.625, 1/128…),
  exactos en binario, así que las comparaciones son exactas.

## CI

`.github/workflows/airtrackcore-tests.yml` ejecuta `swift test` en cada push que
toque `AirTrackCore/`:
- `macos-15` (arm64, toolchain real de Apple)
- `ubuntu-24.04` (x86_64; demuestra que AirTrackCore no depende de frameworks de Apple)

El contenedor de desarrollo en la nube no puede instalar Swift (la política de red
bloquea `download.swift.org`), así que la ejecución real de los tests es la de CI.

## Pruebas manuales — REQUIRES MACOS

Ninguna está hecha todavía:

- [ ] `swift test` en el Mac del desarrollador
- [ ] `** BUILD SUCCEEDED **` de la app (`MACOS_SETUP.md`, L)
- [ ] Captura de cámara y estados Connected / Permission Required / Error
- [ ] Landmarks visibles y estables en el modo debug
- [ ] Pérdida de tracking detectada visualmente
- [ ] Cursor con baja latencia y bajo jitter
- [ ] Click sin desplazamiento del objetivo
- [ ] Drag sin salto al empezar ni al soltar
- [ ] Double click en Finder
- [ ] Drag de una ventana y de un archivo
- [ ] Pausa y reanudación con el atajo
- [ ] Flujo de permisos de cámara y de accesibilidad
- [ ] Calibración de los umbrales de pinch con manos y distancias reales
- [ ] Medición de la latencia del pinch (confirmación en 2 frames)
