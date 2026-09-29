# Roadmap

Numeración oficial (vigente desde PHASE 1; sustituye a la anterior, que tenía Camera
y Hand Tracking como fases separadas):

| Fase | Contenido | Estado |
|---|---|---|
| **PHASE 0** | Core + Architecture | **COMPLETE** |
| **PHASE 1** | macOS Foundation + Camera + Vision Hand Tracking | **VALIDATED on the real Mac** (PHASE 1.1) |
| **PHASE 2** | Cursor Control | **VALIDATED on the real Mac** con G, H, J y L parciales (→ 2.1) |
| **PHASE 2.1** | Adaptive Cursor & Peripheral Hand Tracking | **VALIDATED on the real Mac** (confirmado por el usuario) |
| **PHASE 3A-1** | Gesture Engine Foundation (modo sombra) | **IMPLEMENTED — PHYSICAL VALIDATION PENDING** (`PHASE3A1_RESULT.md`) |
| **PHASE 3A-2** | Scroll: 2 dedos y mano abierta, inercia, congelación del cursor | Probada en el Mac tras el fix de scroll: "estable para seguir" |
| **PHASE 3B** | Left click + drag (pinch índice + pulgar), según `PHASE3B_MASTER_SPEC.md` | **IMPLEMENTED — PENDING USER VALIDATION** (`PHASE3B_RESULT.md`) |
| PHASE 3C | (Drag: incluido en 3B por su especificación) | — |
| PHASE 3D | Zoom | NOT STARTED |
| PHASE 3E | Swipe (2 y 4 dedos) | NOT STARTED |
| PHASE 3F | Double click | NOT STARTED |
| PHASE 3G | Right click | NOT STARTED |
| PHASE 4 | (Scroll se adelantó a 3A según `PHASE3_MASTER_SPEC.md`) | — |
| PHASE 5 | Menu Bar / Settings / Calibration | NOT STARTED |
| PHASE 6 | Optimization | NOT STARTED |
| PHASE 7+ | Advanced Gestures | NOT STARTED |

La lógica de click/drag de PHASE 0 (`GestureStateMachine`) sigue en AirTrackCore sin conectar
(código legado con sus tests); PHASE 3B no la reconecta: el click y el drag son una familia
nueva (`pinch`) del `InteractionEngine`. Una fase se completa cuando funciona en un Mac real,
no cuando existen tests.

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

Resultado: el usuario confirmó en el Mac la identidad de los landmarks, la vertical, la estabilidad con la distancia, las dos manos, LOST/recovery, el filtrado y el rendimiento (~30 FPS, Vision ~11 ms, Capture → HandState ~46 ms, Camera drops 0). PHASE 1 queda validada.

## PHASE 2: estado de validación

| Criterio | Estado |
|---|---|
| Matemática del cursor (mapeo, Y, clamp, active area, sensibilidad, smoothing, dead zone) | ✅ tests (176/176) |
| Pérdida y recuperación seguras, solo la mano primaria, estado desactivado | ✅ tests |
| `CGEvent` aislado en la app; Core solo usa Foundation | ✅ revisión + job Linux |
| La app compila | ✅ CI `xcodebuild` |
| Pruebas A–L en el Mac (`PHASE2_RESULT.md` §15) | ⏳ DEFERRED TO LOCAL MAC VALIDATION |

Resultado en el Mac: A–F, I y K PASS; G, H, J y L PARTIAL (retraso en movimientos rápidos,
pérdida cerca del borde inferior, recuperación algo congelada). Se abordan en PHASE 2.1.

## PHASE 2.1: estado de validación

| Criterio | Estado |
|---|---|
| Smoothing adaptativo: sin overshoot, determinista, lag acotado, basado en tiempo | ✅ tests |
| Tracking periférico seguro (adquisición estricta, continuidad, timeouts, sin datos obsoletos) | ✅ tests |
| Huecos cortos sin reacquisición | ✅ tests |
| La app compila | ✅ CI `xcodebuild` |
| Pruebas A–N en el Mac (`PHASE2_1_RESULT.md` §9) | ⏳ DEFERRED TO LOCAL MAC VALIDATION |

PHASE 3 no empieza hasta que el usuario confirme A–N en el Mac.

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
| Smoothing del cursor | Adaptativo por velocidad y basado en tiempo (2.1): reposo 0.6, response 1.0 | Calibrar con la prueba M; interpolación a la frecuencia de pantalla (PHASE 6) |
| Scroll (3A-2) | 250 pt/escala, deadband 0.15 escalas/s, commit 0.12 escalas, congelación a 0.09 s, inercia τ 0.3 s ≤ 1 s | Calibrar en el Mac; dirección frente a "Desplazamiento natural" por verificar |
| Tracking periférico | Confianza 0.5/0.6, 3 alturas/s, HOLD 0.15 s, 3 s degradado, 1 s solo índice | Calibrar con la prueba N; active area más alto si Vision pierde la mano en el borde |
| Umbrales de pinch | 3B: 0.25 / 0.35 escalas de mano (Phase 3), confianza de puntas 0.5, drag 0.15 neto, click ≤ 1 s; no calibrados | Calibrar en el Mac; ancla con mirada atrás si el click cae desplazado; calibración por usuario (PHASE 5) |
| Cursor | Active area 0.15–0.85, sensibilidad 1, smoothing 0.6 adaptativo, dead zone 0.003, blend 0.2 s (sliders sin persistir) | Calibración y persistencia (PHASE 5) |
| Atajo de pausa | ⌃⌥⌘A solo con AirTrack en primer plano | Atajo global (PHASE 5) |
| Referencia de tamaño de mano | wrist → indexMCP (2D) | Otro segmento rígido si la rotación de la mano lo vuelve inestable |
| Resolución de captura | 1280×720 | Bajarla si Vision es lento; subirla si falta precisión |
| Multi-monitor | Un display objetivo | Mapeo sobre varios displays |
