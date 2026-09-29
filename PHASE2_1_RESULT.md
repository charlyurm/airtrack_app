# PHASE 2.1 — Adaptive Cursor & Peripheral Hand Tracking: resultado

**Estado: READY FOR LOCAL VALIDATION.** Implementada y verificada en CI (tests en macOS y
Linux, `xcodebuild` de la app). **No está validada físicamente**: las pruebas A–N de la §9
las tiene que hacer el usuario en su Mac.

Especificación: `PHASE2_1_PROMPT.md` (sin cambios). Base: commit `1e1cf4c` (PHASE 2
validada en el Mac con G, H, J y L en PARTIAL).

---

## 1. Causas raíz

Encontradas leyendo el código, no midiendo en el Mac. Las marcadas "probable" dependen del
comportamiento real de Vision y se confirman con los contadores nuevos del panel (§8).

### G (movimiento rápido con retraso) y "smoothing bajo = congelado"

1. **EMA fija por frame** (`CursorSmoother`, peso 0.35 en todas las velocidades). Una EMA
   fija obliga a elegir entre jitter y lag: con 0.35 y un dedo a 2.5 pantallas/s el filtro
   sumaba unos 65 pt de retraso, que con 0.7 subían a unos 280 pt. Eso explica que "alto" se sintiera natural pero
   lento.
2. **Smoothing bajo = saltos a 30 Hz.** Sin suavizado, el cursor salta una vez por frame de
   Vision (~30 Hz), sin interpolar, mientras la pantalla refresca a 60/120 Hz. Además, la dead
   zone con ancla, a velocidad lenta, produce escalones (queda quieto un frame y luego salta).
   Eso se percibe "congelado/antinatural".
3. **Dependencia del frame rate:** el peso por frame hacía que el retraso real cambiara con
   los FPS de Vision.
4. **(Probable) micro-pérdidas por blur:** ver J. En un movimiento rápido, un frame sin mano
   provocaba un reinicio completo.

### H, L, N2 y N3 (tracking perdido cerca del borde inferior)

Ruta exacta de rechazo. `HandValidation` (PHASE 1.1) exige `wrist`, `thumbTip`, `indexMCP`
e `indexTip`, ≥ 10 joints y elimina los joints con y > 1.05. Con la mano apuntando hacia
arriba, la muñeca queda ~0.24 alturas por debajo de la punta del índice. Para llevar el
cursor al borde inferior, la punta tiene que llegar a y = 0.85 (límite del active area), y
entonces la muñeca está en y ≈ 1.09: **fuera de la imagen → `missingRequiredJoint(wrist)`
→ mano rechazada → 0 manos → `CursorController.reset()`**. Pasa antes del borde útil, y es
justo lo que describe L. Con la palma horizontal, además se pierden `thumbTip` e `indexMCP`.

No se puede afirmar cuál de las dos cosas pasa en N3: que Vision entregue la observación con
esos joints fuera o con baja confianza (que AirTrack sí puede aprovechar), o que Vision deje
de detectar la mano (que nadie puede arreglar sin inventar landmarks). El panel ahora lo
distingue: modo `PARTIAL`/`INDEX` frente a `LOST`, más "Rechazadas: falta wrist".

### J (recuperación "algo congelada") y parte de G

Cualquier frame sin una mano estricta (blur, un fallo de Vision o una mano parcial en el
borde) disparaba esta secuencia:

1. `HandPresenceFilter` pone el contador a 0 y `CursorController.reset()` borra la sesión.
2. Al volver la mano, el **gate de 2 frames** se repite: el primer frame no produce nada.
3. La sesión nueva empieza con el **blend de reacquisición**, cuyo primer frame devuelve
   exactamente la posición actual del cursor (0 movimiento) y luego se desliza durante 0.2 s.

Cada micro-pérdida costaba unos 3 frames sin movimiento (~100 ms) más 200 ms de glide. En
una pérdida real (sacar la mano) es aceptable; en un hueco de un frame se percibe como un
tirón o congelación.

## 2. Cambios de arquitectura

```text
candidatos ─▶ PointerTracker (Core, NUEVO) ─┬─▶ hands estrictas (overlay, UI) ← HandPresenceFilter sin cambios
                                            └─▶ PointerObservation (FULL/PARTIAL/INDEX/HOLDING/LOST)
                                                   ─▶ CursorController.update(pointer:)
                                                        … DeadZone → sensibilidad → AdaptiveCursorSmoother (NUEVO) → blend → ScreenMapper
```

| Archivo | Cambio |
|---|---|
| `AirTrackCore/.../Cursor/AdaptiveCursorSmoother.swift` | **Nuevo.** Filtro adaptativo por velocidad y basado en tiempo |
| `AirTrackCore/.../Tracking/PointerTracker.swift` | **Nuevo.** Máquina de estados FULL → PARTIAL → INDEX → HOLDING → LOST |
| `AirTrackCore/.../Cursor/CursorController.swift` | Usa el smoother adaptativo; nueva entrada `update(pointer:…)` (HOLD conserva la sesión, LOST la borra); `CursorUpdate` añade `speed` y `smoothing`. La entrada de PHASE 2 `update(hands:…)` se mantiene idéntica |
| `AirTrackCore/.../Tracking/HandPresenceFilter.swift` | Solo se extrae `HandValidation.cleaned` (misma lógica, reutilizable). La validación y el gate no cambian |
| `AirTrackCore/.../Models/AirTrackSettings.swift` | `cursorSpeedResponse` (1.0, 0…8), `cursorPeripheralTracking` (true); `cursorSmoothing` por defecto 0.35 → **0.6** (ver §3) |
| `AirTrack/.../Vision/HandTrackingPipeline.swift` | `PointerTracker` en lugar de `HandPresenceFilter`; el cursor recibe el puntero; la posición real del cursor solo se lee al empezar una sesión |
| `AirTrack/.../App/AppModel.swift` | Modo del puntero, contadores "gaps bridged / losses", aspect ratio del frame; "hay mano" incluye un puntero establecido |
| `AirTrack/.../UI/TrackingStatusView.swift` | Filas Pointer, Index confidence, Finger speed, Smoothing now, Gaps bridged / losses; sliders Speed response y Reacquisition glide; toggle Peripheral tracking |
| `AirTrack/.../UI/HandDebugOverlay.swift`, `ContentView.swift` | Anillo sobre el índice que mueve el cursor (verde FULL, amarillo PARTIAL, naranja INDEX) |

Sin colas, timers, sleeps, esperas ni red. Todo sigue en `visionQueue`, latest-frame-wins.
AirTrackCore sigue importando solo Foundation.

## 3. Cursor adaptativo

```text
tau(v)  = tauReposo / (1 + speedResponse · v)        v = velocidad estimada (pantallas/s)
peso    = exp(−dt / tau(v))                          dt = tiempo real entre frames
salida  = anterior + (entrada − anterior) · (1 − peso)
```

- **tauReposo** sale de `cursorSmoothing` con el mismo significado de PHASE 2: el peso por
  frame a 30 fps con el dedo quieto (`tau = −(1/30)/ln(s)`). Con `speedResponse = 0` y 30 fps
  es **exactamente** la EMA de PHASE 2 (test).
- **Velocidad:** distancia entre la entrada nueva y la salida anterior, dividida por dt y
  filtrada (constante de 50 ms), igual que el filtro 1€. Así, si el cursor va detrás del
  dedo, el filtro se acelera hasta alcanzarlo. Con el dedo quieto, la dead zone da una
  entrada idéntica y la velocidad es exactamente 0.
- **Garantías (tests):** determinista; la salida siempre queda entre la salida anterior y la
  entrada en cada eje, así que no hay overshoot ni oscilación; lag acotado (tiende a
  `tauReposo/speedResponse`); basado en tiempo; dt duplicado o fuera de orden cae en la EMA
  por frame; un hueco largo cuenta como máximo 0.25 s.
- **Por qué la velocidad está en pantallas/s:** se mide después de la sensibilidad, en
  espacio de display normalizado, así que no depende de la resolución.

Perfil por defecto (reposo 0.6, response 1.0), calculado con el mismo algoritmo, 30 fps, en una pantalla de 1440 pt:

| Velocidad del dedo | Peso efectivo | Lag del filtro | PHASE 2 (0.35 fijo) |
|---|---|---|---|
| 0.05 pantallas/s (preciso) | 0.57 | ~3 pt | 0.35 · ~1 pt |
| 0.5 (normal) | 0.39 | ~16 pt | 0.35 · ~13 pt |
| 1.0 | 0.29 | ~20 pt | 0.35 · ~26 pt |
| 2.5 (rápido) | 0.14 | ~19 pt | 0.35 · ~65 pt |

El lag del filtro se suma a la latencia de captura + Vision (~46 ms medidos en PHASE 1),
que no cambia.

**Cambio de default (transparencia):** `cursorSmoothing` pasa de 0.35 a 0.6. Con la
adaptación, un reposo más alto da la suavidad que el usuario encontró "más natural" sin el
lag en movimientos rápidos. Mantener 0.35 habría bajado el peso efectivo a ~0.1–0.2 a
velocidad normal, justo la sensación "congelada" del smoothing bajo. Por eso cambia **una
aserción** de un test de PHASE 2 (`testDefaultCursorSettings`: el valor por defecto 0.35 →
0.6, más las aserciones de los dos settings nuevos). Ningún test de comportamiento de PHASE 2
se modificó. Si en el Mac 0.35 se siente mejor, basta con mover el slider "Smoothing (rest)".

## 4. Tracking periférico

Estados (`PointerTrackingMode`):

| Modo | Cuándo | Cursor |
|---|---|---|
| `FULL` | Mano estricta adquirida (gate de 2 frames), **o** mano estricta que continúa la ya establecida tras un hueco | Se mueve |
| `PARTIAL` | Mano establecida con parte fuera de la imagen: sin muñeca, pulgar o nudillos, ≥ 6 joints confiables | Se mueve |
| `INDEX` | Mano establecida reducida al índice: punta + al menos otra articulación del índice | Se mueve |
| `HOLD` | No hay índice confiable en ESTE frame, pero el último es de hace ≤ 0.15 s | **Quieto** (sin eventos, sin extrapolar) |
| `LOST` | Sin mano establecida | Quieto; la sesión se borra |

Pruebas que exige una observación degradada (todas en `PointerTracker.bestContinuation`):

| Evidencia | Valor por defecto (sin calibrar) |
|---|---|
| Existe una mano adquirida en modo estricto (sesión) | obligatorio |
| Observación fresca (timestamp ≥ el del frame) y frame posterior al último confiable | obligatorio |
| Confianza de la mano (Vision) | ≥ 0.3 (igual que la estricta) |
| Confianza de la punta del índice | ≥ 0.5 (parcial), ≥ 0.6 (solo índice); la estricta pide 0.3 |
| Desplazamiento de la punta desde la última confiable | ≤ 3 alturas/s · Δt, acotado a 0.02…0.12 |
| Chirality | no puede contradecir la de la sesión (desconocida = no contradice) |
| Geometría del dedo | otra articulación del índice a 0.05…1.5 × el tamaño de la mano (muñeca → indexMCP) |
| Tamaño de la mano (si aún se ve muñeca + indexMCP) | 0.5…2 × el establecido |
| Coherencia de los joints que sobreviven | ≥ 50 % se movieron ≤ 2 × el desplazamiento permitido |
| Tiempo sin ningún frame FULL | ≤ 3 s (luego LOST) |
| Racha de solo índice | ≤ 1 s (luego LOST) |
| Hueco sin índice confiable | ≤ 0.15 s de HOLD (luego LOST) |

Si hay varias candidatas válidas, gana la más cercana a la última punta confiable. Tras
`LOST`, solo una mano **estricta y adquirida** (2 frames) vuelve a activar el cursor; una
detección parcial nunca lo hace.

La regla de PHASE 2 se conserva: si hay una mano estricta adquirida, ella manda (la "1").
Un movimiento rápido real con la mano completa nunca se rechaza por el límite de salto; ese
límite solo aplica a las observaciones degradadas.

`Peripheral tracking` (toggle, activado por defecto) apagado = comportamiento exacto de
PHASE 2: sin modos degradados y sin HOLD. Sirve para comparar A/B en el Mac.

## 5. Reacquisición

- **Huecos cortos (≤ 0.15 s):** ya no hay reacquisición. HOLD deja el cursor quieto y conserva
  la sesión. El siguiente frame con la misma mano (aunque el gate estricto todavía no la
  haya aceptado) continúa al instante, sin gate de 2 frames y sin glide. Se ve en
  "Gaps bridged".
- **Pérdida real:** igual que en PHASE 2, que el usuario validó: gate estricto de 2 frames,
  inicio en la posición real del cursor y glide lineal (0.2 s por defecto) hasta el dedo, sin
  salto. El glide ahora tiene slider ("Reacquisition glide", 0–0.5 s) para ajustarlo en el Mac.
  0 = sin glide.
- **Sin posiciones viejas:** HOLD y LOST nunca llevan posición. Tras LOST se borran
  smoothing, dead zone y blend. `startsSession` fuerza un inicio limpio aunque el
  controlador no se hubiera reiniciado.

## 6. Seguridad

- La adquisición inicial sigue siendo la de PHASE 1.1 (validación estricta + 2 frames).
- Una detección parcial o un índice aislado desconocidos nunca activan el cursor (tests).
- Sin extrapolación ni predicción: el cursor se mueve solo con posiciones del frame actual.
- Límites de tiempo en todos los modos degradados, y el HOLD es corto.
- Conservado de PHASE 2: Cursor Control apagado al arrancar, pausa ⌃⌥⌘A, permiso de
  Accesibilidad comprobado cada segundo, solo `.mouseMoved`, pantalla principal, puntos lógicos.
- Nada de click, drag, scroll ni gestos nuevos. Sin red ni APIs externas.

## 7. Tests

| Suite | Tests | Cubre |
|---|---|---|
| `AdaptiveCursorSmootherTests` (nuevo) | 18 | quieto exacto, micro jitter (RMS), lento, normal/rápido (peso decreciente), lag acotado frente a fijo, aceleración, deceleración y parada sin overshoot, inversión de dirección, independencia de FPS (exacta sin adaptación, cercana con ella), determinismo, salida siempre en rango, reset, timestamp duplicado o fuera de orden, hueco largo, saneo de parámetros, equivalencia con la EMA de PHASE 2 |
| `PointerTrackerTests` (nuevo) | 24 | mano completa tras la adquisición estricta, mano estricta siempre manda, parcial tras la adquisición, continuidad del índice, degradación y vuelta a FULL, mano saliendo por abajo (N2/N3), índice aislado o mano parcial desconocidos nunca activan, salto brusco, baja confianza, observación obsoleta, chirality contraria, geometría imposible, joints incoherentes, gana la candidata continua, hueco corto sin reacquisición, hueco largo → LOST, parcial prolongado → LOST, límite de solo índice, tras timeout solo una adquisición completa, desactivado = PHASE 2, settings, reset, determinismo, saneo de la configuración |
| `CursorPointerIntegrationTests` (nuevo) | 11 | PARTIAL/INDEX mueven como FULL, HOLD sin eventos y sin glide nuevo, LOST borra la sesión, glide desde el cursor real, `startsSession`, inactivo/sin punta/NaN/display inválido, HOLD/LOST nunca llevan posición, rápido sigue más cerca que fijo, dedo quieto = smoothing de reposo, **el índice llega al borde inferior de la pantalla mientras la palma sale de la imagen**, un frame perdido no reinicia el cursor |

Total: **229 tests** (176 anteriores + 53 nuevos). Los 176 anteriores siguen pasando. La
única aserción de PHASE 2 que cambió es la del valor por defecto del smoothing (§3).

## 8. Build y CI

CI run `36546406394`, commit `9d20d76`:

| Job | Resultado |
|---|---|
| `swift test (macOS)` (macos-15, arm64) | `Executed 229 tests, with 0 failures` |
| `swift test (Linux)` (ubuntu-24.04, Swift 6.4) | `Executed 229 tests, with 0 failures` |
| `xcodebuild AirTrack.app` (macos-15) | `** BUILD SUCCEEDED **`. Único warning: "Metadata extraction skipped. No AppIntents.framework dependency found." (benigno, igual que en PHASE 2) |

El primer push (`03d5120`) falló en CI por tres errores de compilación **en los tests nuevos**
(una llamada al helper `XCTAssertPointEqual` con mensaje, que no lo aceptaba, y un acceso
exclusivo solapado). La app compiló en ese mismo run. Se corrigió en `9d20d76`: el helper
admite ahora un mensaje opcional, así que ese error no puede repetirse.

Debug nuevo en el panel (sección Cursor), para la validación:
- **Pointer:** FULL / PARTIAL / INDEX / HOLD / LOST. Es el modo real que usa el cursor.
- **Index confidence:** confianza de la punta usada.
- **Finger speed** (pantallas/s) y **Smoothing now** (0 = pegado al dedo, 1 = congelado).
- **Gaps bridged / losses:** huecos cortos salvados sin reacquisición y pérdidas reales. Si
  "gaps bridged" crece al mover rápido, confirma la causa probable de G/J.

## 9. Validación en el Mac

```bash
git pull
cd AirTrackCore && swift test && cd ..     # Executed 229 tests, with 0 failures
open AirTrack/AirTrack.xcodeproj           # ⌘R
```

Activa **Cursor Control**. Deja los sliders en su valor por defecto salvo que la prueba diga
otra cosa. Anota PASS/FAIL por fila.

| # | Preparación | Acción | Resultado esperado (PASS) |
|---|---|---|---|
| **A** Accesibilidad | Permiso concedido | Activar Cursor Control | `Permission: READY`, `Cursor: ACTIVE` con la mano en cuadro |
| **B** Centro | Índice en el centro del rectángulo discontinuo | Mantener | Cursor en el centro de la pantalla |
| **C** Horizontal | — | Izquierda → derecha (tuyas) | El cursor va igual, sin inversión |
| **D** Vertical | — | Arriba → abajo | El cursor va igual, sin inversión |
| **E** Esquinas | — | Las 4 esquinas del rectángulo | El cursor llega a las 4 esquinas |
| **F** Jitter | Dedo quieto 5 s | Mirar el cursor y "Finger speed" | Sin temblor visible; speed ≈ 0.00; Smoothing now ≈ 0.60 |
| **G** Rápido | — | Barridos rápidos de lado a lado | El cursor acompaña sin retraso molesto ni "congelado"; Smoothing now baja (< 0.3) durante el barrido |
| **H** Periférico | — | Llevar el índice a los 4 bordes del rectángulo | El cursor llega al borde de la pantalla sin `LOST`; Pointer puede pasar a PARTIAL/INDEX |
| **I** Pérdida | — | Sacar la mano entera | El cursor se detiene (como mucho 0.15 s en HOLD, quieto) y luego `LOST`, `WAITING FOR HAND` |
| **J** Reacquisición | — | Volver a meter la mano en otro sitio | El cursor sale de donde estaba y se desliza hasta el dedo sin salto ni pausa perceptible. Probar también "Reacquisition glide" en 0.1 s |
| **K** Dos manos | Dos manos en cuadro | Mover la mano "2" | Solo la "1" mueve el cursor |
| **L** Active area | — | Sacar el índice del rectángulo por abajo | El cursor queda en el borde inferior; Pointer no pasa a LOST mientras el índice se vea |
| **M** Smoothing adaptativo | Defaults (reposo 0.6, response 1.0) | 1) lento y preciso sobre un botón pequeño; 2) normal; 3) rápido; 4) acelerar desde quieto; 5) frenar en seco | 1) estable, sin temblor; 2) suave y natural; 3) sin retraso perceptible; 4) responde enseguida; 5) se detiene sin pasarse ni rebotar. **Comparar** con Speed response = 0 (≈ PHASE 2) y con Smoothing (rest) 0.35 y 0.75: anotar cuál se siente mejor |
| **N** Índice periférico | Mano completa en el centro (FULL) | N1 índice cerca del borde inferior con la palma visible; N2 bajar más (parte de la mano fuera); N3 aún más (casi solo el índice); después bordes superior, izquierdo y derecho | N1 FULL; N2 PARTIAL; N3 PARTIAL o INDEX, con el cursor siguiendo al índice hasta el borde de la pantalla. Si Vision deja de ver el dedo: HOLD → LOST y el cursor quieto. **Nunca** un salto a otro punto. Repetir N2/N3 con "Peripheral tracking" apagado: debe fallar como en PHASE 2 (comparación A/B) |

Qué reportar: PASS/FAIL por fila; para N, el modo que muestra "Pointer" en N1–N3 y los
"Rechazadas: …" si aparece LOST; para G/J, cuánto sube "Gaps bridged" al mover rápido; y
para M, la combinación de sliders que se sintió mejor.

## 10. Limitaciones conocidas

1. **Vision puede dejar de detectar la mano** cuando queda muy poca dentro de la imagen.
   Entonces no hay observación que continuar y el cursor se detiene (HOLD → LOST). No se
   inventan landmarks. Si N3 falla por esto, la solución es geométrica: subir el borde
   inferior del active area (p. ej. y 0.10–0.75) para que la mano no tenga que salir de la
   imagen. Es calibración de PHASE 5, o antes si el usuario lo pide.
2. **Parámetros sin calibrar:** reposo 0.6, response 1.0, umbrales de confianza 0.5/0.6,
   3 alturas/s, HOLD 0.15 s, 3 s degradado, 1 s solo índice. Los sliders no se guardan todavía.
3. **El cursor sigue actualizándose a la frecuencia de Vision (~30 Hz).** Interpolar a la
   frecuencia de la pantalla necesitaría un timer o un display link, que este prompt
   excluye. Candidato para PHASE 6.
4. **Latencia de captura + Vision** (~46 ms medidos) no cambia; el filtro solo reduce su
   propia parte.
5. **Cambio de mano primaria:** si con dos manos aparece una estricta a la izquierda de la
   que controla en modo parcial, manda la estricta (regla de PHASE 2).
6. **El glide de reacquisición es lineal** (PHASE 2, validado). Su primer frame reproduce la
   posición actual del cursor, que es lo que garantiza "sin salto".
7. Las causas "probables" (micro-pérdidas por blur) se confirman con "Gaps bridged" en el Mac.
