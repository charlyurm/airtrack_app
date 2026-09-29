# Roadmap

Numeración oficial (aprobada):

| Fase | Contenido | Estado |
|---|---|---|
| **PHASE 0** | Core + Architecture | **COMPLETE** |
| PHASE 1 | Camera | NOT STARTED |
| PHASE 2 | Hand Tracking | NOT STARTED |
| PHASE 3 | Cursor | NOT STARTED |
| PHASE 4 | Click / Double Click / Drag | NOT STARTED |
| PHASE 5 | Scroll | NOT STARTED |
| PHASE 6 | Menu Bar / Settings / Calibration | NOT STARTED |
| PHASE 7 | Optimization | NOT STARTED |
| PHASE 8+ | Advanced Gestures | NOT STARTED |

PHASE 3 y PHASE 4 figuran como NOT STARTED aunque su lógica ya existe en AirTrackCore:
una fase se completa cuando funciona en un Mac real, no cuando existen tests.

## PHASE 0: qué se entregó

- AirTrackCore (Swift Package) con tests en macOS y Linux vía CI.
- Pinch normalizado por tamaño de mano, con histéresis y confirmación en 2 frames.
- Máquina de estados de click, double click y drag con click estabilizado (ancla)
  y drag sin saltos (offset).
- Tracking loss y pausa seguros (`mouseUp` garantizado).
- Documentación y guía de setup en macOS.

Aún no existe: el proyecto de Xcode. Se crea al inicio de PHASE 1 siguiendo
`MACOS_SETUP.md`.

## Definición de done del MVP

- [ ] Proyecto compila (app macOS)
- [ ] Cámara funciona
- [ ] Permiso de cámara funciona
- [ ] Permiso de accesibilidad funciona
- [ ] Mano se detecta
- [ ] Landmarks funcionan
- [ ] Índice mueve cursor
- [ ] Cursor tiene baja vibración
- [ ] Pinch hace click
- [ ] Double pinch hace double click
- [ ] Pinch mantenido permite drag
- [ ] Mano abierta permite scroll
- [ ] Pausa funciona
- [ ] Tracking loss es seguro (lógica cubierta por tests de Core; falta probarlo en un Mac real)
- [ ] No existen errores críticos
- [ ] Unit tests principales pasan (los de AirTrackCore sí; faltan los de la app)
- [ ] App funciona en Apple Silicon real
- [ ] Documentación está actualizada

## Decisiones provisionales a revisar con hardware real

| Tema | Valor actual | Opciones futuras |
|---|---|---|
| Latencia del pinch | 2 frames de confirmación (~33 ms a 30 fps) | Menos frames, confirmación por timestamps, predicción, otro filtro |
| Smoothing | EMA por frame | **Time-based smoothing** (misma sensación a 30/60/120 fps); filtro One Euro si las mediciones lo justifican |
| Umbrales de pinch | Ratios 0.25 / 0.35, no calibrados | Calibración por usuario (PHASE 6) |
| Referencia de tamaño de mano | wrist → indexMCP (2D) | Otro segmento rígido si la rotación de la mano lo vuelve inestable |
| Multi-monitor | Un display objetivo | Mapeo sobre varios displays |
