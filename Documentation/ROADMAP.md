# Roadmap

Numeración oficial (vigente desde PHASE 1; sustituye a la anterior, que tenía Camera
y Hand Tracking como fases separadas):

| Fase | Contenido | Estado |
|---|---|---|
| **PHASE 0** | Core + Architecture | **COMPLETE** |
| **PHASE 1** | macOS Foundation + Camera + Vision Hand Tracking | **IN PROGRESS**: 1.1 (correcciones tras la prueba en el Mac real) implementada; falta la validación física |
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

## PHASE 1: estado de validación

Primera prueba en el Mac real (PHASE 1): cámara, permiso, preview, tracking LOST y
recovery y movimiento horizontal **OK**. Fallaron la vertical (invertida), la identidad
visual de la cadena del índice, el desplazamiento con la distancia, las dos manos y hubo
falsos positivos a ~20 cm. PHASE 1.1 los aborda (ver `PHASE1_1_RESULT.md`).

| Criterio | Estado |
|---|---|
| App macOS existe y compila | ✅ CI (`xcodebuild`) |
| AirTrackCore integrado, 0 failures | ✅ CI |
| Cámara, permiso, preview | ✅ Mac real (PHASE 1) |
| Tracking loss / recovery | ✅ Mac real (PHASE 1); hay que revalidarlo con el gate nuevo |
| Movimiento horizontal | ✅ Mac real (PHASE 1) |
| Movimiento vertical correcto | ⏳ corregido en 1.1, DEFERRED TO LOCAL MAC VALIDATION |
| Cada cadena sigue su dedo | ⏳ corregido en 1.1, DEFERRED |
| Sin desplazamiento con la distancia | ⏳ corregido en 1.1, DEFERRED |
| Falsos positivos controlados | ⏳ filtro nuevo en 1.1, DEFERRED (umbrales sin calibrar) |
| Dos manos representadas | ⏳ implementado en 1.1, DEFERRED |
| Rendimiento aceptable | ⏳ DEFERRED (latest-frame-wins nuevo) |

PHASE 2 no empieza hasta que el usuario confirme todos estos puntos en el Mac.

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
