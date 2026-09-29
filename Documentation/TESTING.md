# Testing

## Unit tests (sin hardware)

```bash
cd AirTrackCore
swift test
```

| Suite | Cubre |
|---|---|
| `CursorMapperTests` | espejo, zona activa, límites, sensibilidad, NaN, calibración de dos esquinas |
| `ScreenMapperTests` | esquinas, multi-monitor, orígenes negativos, conversión AppKit → global |
| `CursorSmootherTests` | fórmula EMA, convergencia, reducción de jitter, reset, límites |
| `PinchRecognizerTests` | pinch sí/no, invariancia a escala de mano, histéresis, spikes, ruido con semilla, aspect ratio, oclusión, confianza |
| `GestureStateMachineTests` | un pinch = un click, cursor congelado, ancla, drag por tiempo y por movimiento, double click, pérdida de tracking, pausa, re-armado |
| `GestureEngineTests` | pipeline completo, pausa, reanudar con mano cerrada, reset al perder tracking, settings |

El "ruido" se genera con un PRNG con semilla fija, así que los tests son
reproducibles.

## CI

`.github/workflows/airtrackcore-tests.yml` ejecuta `swift test` en:
- `macos-15` (toolchain real de Apple)
- `ubuntu-24.04` (demuestra que AirTrackCore no depende de frameworks de Apple)

## Pruebas manuales — REQUIRES MACOS

Ninguna está hecha todavía:

- [ ] Captura de cámara y estados Connected / Permission Required / Error
- [ ] Landmarks visibles y estables en el modo debug
- [ ] Pérdida de tracking detectada visualmente
- [ ] Cursor con baja latencia y bajo jitter
- [ ] Click sin desplazamiento del objetivo
- [ ] Double click en Finder
- [ ] Drag de una ventana y de un archivo
- [ ] Pausa y reanudación con el atajo
- [ ] Flujo de permisos de cámara y de accesibilidad
- [ ] Calibración de los umbrales de pinch con manos y distancias reales
