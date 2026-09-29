# PHASE 3A-1 — Gesture Engine Foundation (shadow mode): resultado

**Estado: IMPLEMENTED — PHYSICAL VALIDATION PENDING USER VALIDATION.**
Implementado y verificado en CI (tests en macOS y Linux, `xcodebuild` de la app). No está
validado en el Mac.

Especificaciones: `PHASE3_MASTER_SPEC.md`, `PHASE3A1_IMPLEMENTATION_SPEC.md`.
`PHASE3A_MASTER_SPEC.md`, citado como dependencia, **no existe en el repositorio**; se
trabajó con los otros dos.

**Decisión del usuario:** 3A-1 y 3A-2 en la misma ejecución, sin parar a validar entre ambas.
Esto sustituye la regla "no pasar a 3A-2 sin validar 3A-1" de los specs. Por eso, en el Mac, la
parte de 3A-1 se valida con **"Scroll con gestos" apagado** (modo sombra puro, ver §6).

## 1. Qué hace

Reconoce la mano sin actuar: features → historial → pose → candidatos → intención → ciclo
de vida. Con el scroll apagado no envía ningún evento nuevo a macOS, y el cursor es exactamente
el de Phase 2.1.

## 2. Arquitectura

```text
candidatos (Vision)
  → PointerTracker (sin cambios de decisión; + trackedHand)
  → HandFeatureExtractor   escala robusta, palma, dedos EXTENDED/BENT/UNKNOWN, distancias / escala
  → FeatureHistory         ring buffer ≤ 0.5 s / 32 muestras, movimiento del usuario en escalas de mano
  → PoseClassifier         POINTING, TWO_FINGER, OPEN_HAND, FOUR_FINGER, PINCH, UNKNOWN (histéresis 2 frames)
  → Recognizers            ScrollRecognizer (2 dedos y mano abierta, vertical): solo candidatos
  → IntentArbiter          un solo dueño; ambigüedad → nada; IDLE/CANDIDATE/CONFIRMED/ACTIVE/SUSPENDED/RELEASING/CANCELLED
  → InteractionEngine      InteractionFrame (debug + cursorPolicy + actions)

cursor (independiente, Phase 2.1):  PointerTracker → CursorController → MacOSEventController (mouseMoved)
```

| Pieza | Archivo | Notas |
|---|---|---|
| `trackedHand` | `Tracking/PointerTracker.swift` | Aditivo. FULL: mano estricta. PARTIAL/INDEX: la observación degradada (el motor NO la usa para gestos). HOLD/LOST: nil |
| Features | `Interaction/HandFeatures.swift` | Escala = el mayor de muñeca→MCP de índice/medio/meñique y el ancho de la palma / 0.7 (el escorzo solo acorta). Dedo: rectitud + longitud proyectada + punta frente a PIP respecto de la muñeca; pulgar: distancia punta→palma. Escorzado o ambiguo → UNKNOWN |
| Historial | `Interaction/FeatureHistory.swift` | `RingBuffer` fijo. Espejo aplicado una vez (como CursorMapper). Si la línea de tiempo retrocede, se borra |
| Poses | `Interaction/PoseClassifier.swift` | Pinch con histéresis (0.25 / 0.35), no si el pulgar está plegado (puño). Pulgar sobre la punta del medio → no es TWO_FINGER (relación de click derecho futuro). FOUR_FINGER conservador (pulgar claramente plegado) |
| Reconocedores | `Interaction/GestureRecognition.swift` | Protocolo `GestureRecognizer` sin estado; `GestureKind` (dedos + pose + familia). Nuevos gestos = nuevos reconocedores, no un switch central |
| Árbitro | `Interaction/IntentArbiter.swift` | Commit único; 2 candidatos listos → ambiguo; el dueño tolera 1 frame sin pose; `FeatureAvailability` sale de PointerTracker (sin un segundo temporizador de pérdida) |
| Motor | `Interaction/InteractionEngine.swift` | Frames frescos solamente; en HOLD conserva pose e historial; en PARTIAL/INDEX/LOST los borra |
| App | `Vision/HandTrackingPipeline.swift`, `App/AppModel.swift`, `UI/TrackingStatusView.swift` | Sección "Gestos (PHASE 3A)" en el panel |

Umbrales (todos **SIN CALIBRAR**): dedo extendido con rectitud ≥ 0.8 y longitud ≥ 0.4 escalas;
doblado con rectitud ≤ 0.6 o punta < 0.9 × la distancia del PIP a la muñeca; pulgar extendido
≥ 0.75 y plegado ≤ 0.5; commit del scroll a 0.12 escalas verticales con eje dominante ×2;
congelación del cursor a los 0.09 s de un candidato estable.

## 3. Tests

58 nuevos. Total: **298** en el gate de 3A-1 (CI run 36614313094, commit `03134e5`: macOS
298/298, Linux verde, `xcodebuild` OK).

| Suite | Tests | Cubre |
|---|---|---|
| `HandFeaturesTests` | 13 | escala 0.5×/1×/2×, distancias invariantes (tamaño, posición, aspect 16:9), rotación ±30°, centro de la palma, estados por dedo, identidad de dedo, pulgar incierto, dedo hacia la cámara → UNKNOWN, joints ausentes o con baja confianza, ruido reproducible, manos no medibles, NaN/∞ |
| `PoseClassifierTests` | 9 | las 5 poses, invariancia (escala × rotación × aspect), ambiguas → UNKNOWN, puño ≠ pinch, pulgar ambiguo ≠ FOUR_FINGER, pulgar en el medio ≠ TWO_FINGER, banda de histéresis del pinch, 1 frame ruidoso no cambia la pose, parpadeo, sin features → UNKNOWN |
| `FeatureHistoryTests` | 7 | ring buffer acotado, ventana ≤ 0.5 s, velocidad y desplazamiento en escalas/s, invariancia a la distancia, espejo y aspect, línea de tiempo desordenada, eje dominante |
| `IntentArbiterTests` | 9 | candidato → commit → activo, ambigüedad, cancelación, tolerancia de 1 frame, gap → SUSPENDED → recuperación, LOST y degradado liberan, sin commit sin features frescas, inicio del candidato, `cancelAll` |
| `InteractionEngineTests` | 18 | scroll vertical (2 dedos, mano abierta), horizontal/diagonal/bajo el umbral no hacen commit, lento frente a rápido, invariancia a la escala, pointing sin candidato, pinch y 4 dedos sin acción, congelación tras el retraso, HOLD/recuperación/LOST, degradado, mano desconocida, frames obsoletos, transiciones sin pose neutra, **el modo sombra no emite nunca**, cancel/reset, determinismo |
| `PointerTrackerTrackedHandTests` | 2 | `trackedHand` en cada modo; las decisiones del puntero no cambian |

Regresión: los 240 tests anteriores pasan sin cambios.

## 4. Build

`xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -configuration Debug -destination 'platform=macOS' build`
→ `** BUILD SUCCEEDED **`. Único warning: AppIntents (benigno, igual que antes).

El primer push de 3A-1 (`4e01638`) **no compiló**: un helper se llamaba `set(where:)` dentro de
una propiedad calculada y el parser lo leía como un setter. Se corrigió en `e9757c6` y
`03134e5` (renombrado a `fingerSet(in:)`). Sin cambios de comportamiento.

## 5. Limitaciones conocidas

1. **La detección de dedos en 2D es el mayor riesgo de Phase 3.** Un dedo que apunta a la
   cámara se ve escorzado y queda UNKNOWN. Es lo correcto por seguridad, pero puede hacer
   que una pose real no se reconozca. Solo el Mac lo dirá.
2. Umbrales sin calibrar (ver §2).
3. La chirality de Vision todavía no se usa: la selección de mano Izquierda/Derecha/Auto del
   spec maestro (§4) no forma parte de 3A.
4. `GestureEngine` / `GestureStateMachine` de Phase 0 siguen en el repo **sin conectar**. Se
   reutilizarán en 3B/3C.

## 6. Validación física — PENDING USER VALIDATION

Para validar 3A-1 en modo sombra puro: sección Gestos → **apaga "Scroll con gestos"**. Lo que
ves es solo observación, y el cursor es el de Phase 2.1.

| # | Prueba | Esperado |
|---|---|---|
| A | ☝️ Apuntar y mover | Pose POINTING; cursor idéntico a Phase 2.1 |
| B | ☝️🖕 | TWO_FINGER; Dedos `? E E B B` o `B E E B B`; sin scroll |
| C | 🖐️ | OPEN_HAND; sin scroll |
| D | 4 dedos con el pulgar doblado | FOUR_FINGER (o UNKNOWN si duda); nunca una acción |
| E | 🤏 | PINCH; ningún click |
| F | Cerca, media y lejos | Las mismas poses; "Escala mano" cambia y el resto no |
| G | Rotar la mano | Poses estables |
| H | POINTING → TWO_FINGER → POINTING → PINCH → POINTING | Cambia sin pose neutra, sin parpadeo |
| I | Movimientos al azar o parciales | UNKNOWN / sin candidato; nunca Intent |
| J | Cursor | Idéntico a Phase 2.1 |

Anota en qué poses aparece `?` en algún dedo y a qué distancia.
