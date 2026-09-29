# Roadmap

Numeración oficial (aprobada):

| Fase | Contenido | Estado |
|---|---|---|
| **PHASE 0** | Bootstrap + arquitectura + AirTrackCore | En revisión |
| PHASE 1 | Camera | Pendiente |
| PHASE 2 | Hand tracking (Vision → HandState) | Pendiente |
| PHASE 3 | Cursor (CGEvent) + pausa de emergencia | Pendiente (la lógica ya está en Core) |
| PHASE 4 | Click / double click / drag | Pendiente (la lógica ya está en Core) |
| PHASE 5 | Scroll | Pendiente |
| PHASE 6 | Menu bar / settings / calibración | Pendiente |
| PHASE 7 | Optimización | Pendiente |
| PHASE 8+ | Gestos avanzados | Post-MVP |

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
- [ ] Unit tests principales pasan
- [ ] App funciona en Apple Silicon real
- [ ] Documentación está actualizada

## Candidatos post-MVP ya identificados

- Filtro One Euro en lugar de EMA, si el jitter y la latencia lo justifican con mediciones.
- Smoothing dependiente del tiempo (hoy es por frame).
- Mapeo multi-monitor.
