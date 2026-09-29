# PHASE 3A-2 — Scroll: resultado

**Estado: IMPLEMENTED — PHYSICAL VALIDATION PENDING USER VALIDATION.**
Implementado y verificado en CI (tests en macOS y Linux, `xcodebuild`). No está validado en
el Mac. Por decisión del usuario, se implementó sin validar antes 3A-1 físicamente
(`PHASE3A2_IMPLEMENTATION_SPEC.md` §2 pedía esperar).

## 1. Qué hace

☝️🖕 (índice + medio) o 🖐️ (mano abierta) moviéndose en **vertical** hacen scroll en la app
que está bajo el cursor. Mientras dura, el cursor queda congelado. Al soltar con velocidad hay
una inercia acotada. Al terminar, el cursor vuelve con el mismo deslizamiento de
reacquisición de Phase 2.1.

## 2. Arquitectura

```text
PointerTracker → HandFeatures → FeatureHistory → PoseClassifier → ScrollRecognizer
  → IntentArbiter → InteractionEngine → ScrollController → InteractionAction.scroll
  → HandTrackingPipeline (cursorPolicy) → MacOSEventController → CGEvent scroll-wheel
```

| Pieza | Archivo | Qué hace |
|---|---|---|
| Acción semántica | `Models/InteractionAction.swift` | `.scroll(ScrollAction)`: `delta` en puntos enteros de **contenido** (+ = el contenido baja, sigue a la mano), `phase` (began/changed/ended) y `momentum` (none/began/changed/ended) |
| Respuesta e inercia | `Interaction/ScrollController.swift` | Velocidad de la mano (escalas/s, suavizado de 40 ms), deadband suave, ganancia con aceleración suave, tope, acumulador de fracciones, inercia exponencial acotada |
| Motor | `Interaction/InteractionEngine.swift` | Salida **live** (`emitsActions`) o **sombra**; solo el eje vertical; SUSPENDED en HOLD; fases de cierre al cancelar |
| Ajustes | `Models/AirTrackSettings.swift` | `scrollSensitivity` (0.25–4, no expuesto en la UI), `scrollGesturesEnabled` (on), `scrollDirectionInverted` (off) |
| Adaptador macOS | `Events/MacOSEventController.swift` | `CGEvent(scrollWheelEvent2Source:units: .pixel, …)` + `scrollWheelEventIsContinuous`, `…ScrollPhase`, `…MomentumPhase` |
| Pipeline | `Vision/HandTrackingPipeline.swift` | Live = Cursor Control permitido **y** "Scroll con gestos" activo. Aplica `cursorPolicy`. Cierra el scroll al pausar, apagar, perder el permiso, parar la cámara y al salir de la app (`applicationWillTerminate`) |

### Respuesta (sin calibrar)

```text
v   = velocidad vertical de la palma (escalas de mano/s), suavizado τ = 40 ms
e   = max(0, |v| − 0.15)                               deadband suave: sin escalón
pt/s = 250 × sensibilidad × e × (1 + 0.5·e), tope 5000   más rápido → proporcionalmente más
delta = pt/s × dt + resto anterior → parte entera (el resto se conserva)
```

Ejemplos: 0.5 escalas/s → ~100 pt/s; 1 → ~300; 2.2 → ~1050; 4 → ~2800. Se mide en escalas de
mano, así que el mismo gesto físico hace el mismo scroll cerca o lejos de la cámara.

### Inercia (sin calibrar)

- Empieza **solo al soltar el gesto** (la pose termina o el tracking se degrada a
  PARTIAL/INDEX) y solo si la velocidad al soltar es ≥ 250 pt/s. Si la mano se detiene con la
  pose mantenida, el scroll para y no hay inercia.
- Nunca después de LOST (datos obsoletos) ni de una cancelación.
- `v(t) = v0·e^(−t/0.3 s)`, v0 ≤ 2500 pt/s. Termina por debajo de 30 pt/s o a 1 s. Distancia
  máxima = v0·τ ≤ 750 pt. Integral exacta entre frames, así que es igual a 30 o a 60 fps.
- La cancela un gesto nuevo (pose TWO_FINGER, OPEN_HAND, FOUR_FINGER o PINCH, un candidato o un
  commit). Apuntar no la cancela: el cursor vuelve mientras el contenido se desliza.
- Avanza con los frames de la cámara (llegan aunque no haya mano). Sin timers.

### Cursor

- Congelado mientras el scroll es dueño de la mano, y también desde los 0.09 s de un
  candidato de scroll estable (spec: ~80–100 ms), para que el cursor no derive mientras empieza
  el scroll.
- `CursorController` **no se modificó**. Mientras está congelado no se le alimenta y se
  reinicia, así que al volver empieza una sesión nueva con el deslizamiento de reacquisición de
  Phase 2.1 (0.2 s) desde donde esté el cursor. Es el único sistema de reacquisición.

### Conflictos

| Caso | Resultado |
|---|---|
| 2 dedos en horizontal | Sin scroll (reservado para el swipe, 3E) |
| Diagonal / ambiguo | Sin commit hasta que la vertical domine ×2 |
| Ruido horizontal durante el scroll | Ignorado (eje vertical bloqueado) |
| 2 dedos y mano abierta a la vez | Un solo dueño (árbitro); dos candidatos listos → nada |
| Pulgar sobre la punta del medio | No es la pose de scroll → nada (click derecho futuro, 3G) |
| Pinch | Reconocido, sin acción (3B); cancela la inercia |

### Tracking

| PointerTracker | Scroll |
|---|---|
| HOLD (≤ 0.15 s) | SUSPENDED: sin deltas nuevos; al volver continúa el mismo scroll (sin nuevo `began`) |
| PARTIAL / INDEX | Termina (`ended`); inercia permitida (la velocidad es reciente) |
| LOST | Termina (`ended`); **sin** inercia; nada después |

### Dirección y "Desplazamiento natural"

- Core: el contenido sigue a la mano (spec).
- Adaptador: `wheel1 = +delta`. En un evento de rueda, un valor positivo mueve el contenido
  hacia abajo.
- **No está verificado** si macOS aplica la preferencia "Desplazamiento natural" a los eventos
  sintéticos. Si el contenido va al revés, activa **"Invertir dirección del scroll"** en el panel
  y anótalo.

## 3. Tests

36 nuevos. Total: **334** (CI run 36615091543, commit `a6a77a6`): macOS 334/334, Linux
334/334, `xcodebuild` OK.

| Suite | Tests | Cubre |
|---|---|---|
| `ScrollControllerTests` | 18 | mano quieta, deadband (y que sea suave), movimiento lento intencional, lento < medio < rápido, dirección, tope, sensibilidad, fracciones sin pérdida, fases, parar sin inercia, inercia que decae y termina, cotas de duración/velocidad/distancia, igual a 30 y 60 fps, sin inercia tras LOST o si es lenta, cancelación de la inercia, cancel en cualquier estado, saneo del ajuste |
| `ScrollInteractionTests` | 18 | scroll live con 2 dedos y con mano abierta, horizontal/diagonal sin scroll, pulgar sobre el medio sin scroll, mano más rápida = más scroll, ruido horizontal ignorado, horizontal puro tras el commit, parar sin inercia, soltar → inercia acotada y el cursor vuelve, un gesto nuevo cancela la inercia, cursor antes/durante/después, HOLD/recuperación, LOST sin inercia ni datos obsoletos, degradado con inercia, apagar la salida cierra el scroll, `cancel` cierra el scroll o la inercia, modo sombra, determinismo |

Regresión: los 298 anteriores pasan. Los dos helpers de `GestureStateMachineTests` que hacían
`switch` exhaustivo sobre `InteractionAction` recibieron el caso `.scroll` (cambio mecánico,
sin cambio de comportamiento).

## 4. Build

`xcodebuild … -configuration Debug -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`.
Único warning: AppIntents (benigno).

## 5. Seguridad

- Incierto → nada: sin pose estable, sin eje dominante o con dos candidatos, no hay commit.
- Sin extrapolación: los deltas salen solo de frames frescos; en HOLD, cero.
- Sin scroll colgado: pausa, Cursor Control apagado, permiso de Accesibilidad perdido, cámara
  parada, "Scroll con gestos" apagado y cierre de la app emiten el cierre de fase
  (`ended` / momentum `ended`).
- Inercia acotada (§2) y nunca desde datos obsoletos.
- Ningún click, drag, zoom, swipe ni atajo: `MacOSEventController.post` ignora a propósito los
  casos de ratón.

## 6. Limitaciones conocidas

1. **Los eventos sintéticos no son un trackpad real.** Las fases y el flag continuo son API
   pública, pero cómo reacciona cada app (rebote elástico, inercia propia, Safari/Chrome/Finder)
   solo se sabe en el Mac.
2. **Dirección sin verificar** frente a "Desplazamiento natural" (§2). Tienes el toggle para
   comprobarlo.
3. Todos los parámetros están sin calibrar (ganancia, deadband, commit 0.12 escalas, retraso de
   congelación 0.09 s, inercia).
4. **Scroll a ~30 Hz:** un evento por frame de Vision. Puede verse a escalones frente a un
   trackpad a 60–120 Hz. Interpolar exigiría un timer (Phase 6).
5. **Sin scroll horizontal:** el spec reserva el eje horizontal para el swipe.
6. La referencia del movimiento es la palma (nudillos), no las puntas. Doblar solo los dedos
   no hace scroll; hay que mover la mano. Es a propósito: al cerrar el dedo medio para terminar,
   las puntas se mueven y darían un tirón falso.
7. El cursor vuelve deslizándose hasta la posición actual del dedo (reacquisición de Phase 2.1).
   Tras un scroll largo, el dedo puede estar lejos, así que el cursor se desplaza 0.2 s.
   Alternativa futura (requiere tocar el cursor): un offset que se consuma con el movimiento.
8. Si se reactiva la salida en mitad de un gesto, ese gesto sigue solo observado hasta
   soltarlo (no aparece un `began` a mitad).

## 7. Validación física — PENDING USER VALIDATION

Preparación: `git pull`, ⌘R, Cursor Control activado, "Scroll con gestos" activado. Prueba en
una página larga (Safari o Chrome) y en Finder.

| # | Prueba | Esperado |
|---|---|---|
| 1 | Cursor normal | Idéntico a Phase 2.1 |
| 2 | ☝️🖕 mover en vertical | Scroll en la ventana bajo el cursor, en la dirección de la mano |
| 3 | 🖐️ mover en vertical | Igual |
| 4 | Lento | Scroll controlado, que no se sienta congelado |
| 5 | Medio | Natural |
| 6 | Rápido | Más rápido, sin aceleración descontrolada |
| 7 | Cursor durante el scroll | Quieto ("Cursor policy: FROZEN") |
| 8 | Volver a ☝️ | El cursor vuelve suave (≈0.2 s), sin salto brusco ni pausa rara |
| 9 | Soltar en movimiento | Inercia breve (≤ ~1 s) que se detiene sola; ☝️ mueve el cursor mientras tanto |
| 10 | 2 dedos en horizontal | Sin scroll |
| 11 | Diagonal | Scroll solo si la vertical domina claramente |
| 12 | Sacar la mano durante el scroll | Se detiene sin inercia desbocada; nada después |
| 13 | Pérdida breve y vuelta | Continúa el mismo scroll |
| 14 | Pausar (⌃⌥⌘A) o apagar Cursor Control a mitad | Se detiene al instante |
| 15 | Quitar el permiso de Accesibilidad a mitad | Se detiene; `WAITING FOR PERMISSION` |
| 16 | Sensación general | ¿Se siente como el scroll de un trackpad? |

Qué reportar: la dirección (¿necesitaste "Invertir"?), la velocidad lenta/media/rápida
(corta, bien o larga), la inercia (ausente, bien o excesiva), el retorno del cursor, falsos
positivos y en qué apps lo probaste.
