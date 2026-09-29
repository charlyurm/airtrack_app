# Roadmap

Numeración oficial (vigente desde PHASE 1; sustituye a la anterior, que tenía Camera
y Hand Tracking como fases separadas):

| Fase | Contenido | Estado |
|---|---|---|
| **PHASE 0** | Core + Architecture | **COMPLETE** |
| **PHASE 1** | macOS Foundation + Camera + Vision Hand Tracking | **IN PROGRESS**: código implementado; falta la validación en el Mac |
| PHASE 2 | Cursor Control | NOT STARTED |
| PHASE 3 | Click / Double Click / Drag | NOT STARTED |
| PHASE 4 | Scroll | NOT STARTED |
| PHASE 5 | Menu Bar / Settings / Calibration | NOT STARTED |
| PHASE 6 | Optimization | NOT STARTED |
| PHASE 7+ | Advanced Gestures | NOT STARTED |

PHASE 2 y PHASE 3 figuran como NOT STARTED aunque su lógica ya existe en AirTrackCore:
una fase se completa cuando funciona en un Mac real, no cuando existen tests.

## Flujo de trabajo

```text
Claude Code (nube) → código y revisión → GitHub (CI: swift test + xcodebuild)
      → Mac del usuario (build, ejecución, cámara, pruebas físicas)
      → resultados y errores → Claude corrige
```

Todo lo que exige hardware real queda marcado como **DEFERRED TO LOCAL MAC VALIDATION**
hasta que el usuario lo prueba.

## PHASE 1: criterios para pasar a COMPLETE

| Criterio | Estado |
|---|---|
| App macOS existe | ✅ código en `AirTrack/` |
| AirTrackCore integrado como paquete local | ✅ |
| Core con 0 failures | ✅ CI |
| App compila (`BUILD SUCCEEDED`) | ver `TESTING.md` (CI con `xcodebuild`) |
| CameraStatus con `disconnected` separado de `error` | ✅ código |
| Permiso de cámara funciona | ⏳ DEFERRED TO LOCAL MAC VALIDATION |
| Preview funciona | ⏳ DEFERRED |
| Vision detecta la mano | ⏳ DEFERRED |
| Landmarks visibles y alineados | ⏳ DEFERRED (requiere confirmación visual) |
| Tracking loss / recovery | ⏳ DEFERRED |
| FPS y tiempos medidos en hardware real | ⏳ DEFERRED |

## Definición de done del MVP

- [ ] Proyecto compila (app macOS) — pendiente de confirmar también en el Mac del usuario
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
- [ ] Unit tests principales pasan (los de AirTrackCore sí; la app todavía no tiene target de tests)
- [ ] App funciona en Apple Silicon real
- [ ] Documentación está actualizada

## Decisiones provisionales a revisar con hardware real

| Tema | Valor actual | Opciones futuras |
|---|---|---|
| Latencia del pinch | 2 frames de confirmación (~33 ms a 30 fps) | Menos frames, confirmación por timestamps, predicción, otro filtro |
| Smoothing | EMA por frame | **Time-based smoothing** (misma sensación a 30/60/120 fps); filtro One Euro si las mediciones lo justifican |
| Umbrales de pinch | Ratios 0.25 / 0.35, no calibrados | Calibración por usuario (PHASE 5) |
| Referencia de tamaño de mano | wrist → indexMCP (2D) | Otro segmento rígido si la rotación de la mano lo vuelve inestable |
| Resolución de captura | 1280×720 | Bajarla si Vision es lento; subirla si falta precisión |
| Multi-monitor | Un display objetivo | Mapeo sobre varios displays |
