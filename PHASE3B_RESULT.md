# PHASE 3B — Left Click + Drag — RESULT

**Estado:** IMPLEMENTED — **PENDING USER VALIDATION** (nada de esto se ha probado en un Mac físico).

Especificaciones: `PHASE3B_MASTER_SPEC.md`, `PHASE3B_IMPLEMENTATION_SPEC.md`.
Commits: `88e3b17` (`feat: implement phase 3b click and drag`), `095ab39` y `708f440`
(dos arreglos de compilación de los tests: orden de argumentos y una expresión que el
type-checker de macOS no resolvía a tiempo; sin cambios de comportamiento).

## 1. Arquitectura

```text
HandState → PointerTracker (FULL / PARTIAL / INDEX / HOLD / LOST, trackedHand)
  → HandFeatures (+ pinchConfidence) → FeatureHistory (+ pinchDistance por muestra)
  → PoseClassifier (pose PINCH con histéresis 0.25 / 0.35)
  → Recognizers: ScrollRecognizer, PinchGestureRecognizer (solo candidatos)
  → IntentArbiter (un único dueño; ambigüedad = nada; releasedKind)
  → InteractionEngine
       ├─ familia scroll → ScrollController                     → .scroll
       └─ familia pinch  → PinchIntentController (click vs drag) → .leftClick / .beginDrag / .endDrag
  → HandTrackingPipeline (visionQueue)
       ├─ DragController: ancla fija + libro del botón primario
       └─ MacOSEventController: leftMouseDown / leftMouseDragged / leftMouseUp (CGEvent público)
```

- Core sigue sin frameworks de Apple. Los recognizers no publican eventos; solo el árbitro hace
  commit; el CGEvent vive solo en `MacOSEventController`.
- `GestureKind.pinch` / `GestureFamily.pinch` son una familia nueva del mismo árbitro: scroll y
  pinch compiten por la mano y nunca hay dos dueños.
- El motor antiguo de PHASE 0 (`GestureEngine`, `GestureStateMachine`, `PinchRecognizer`) **no se
  reconecta**: queda como código legado con sus tests.

## 2. Click izquierdo

| Paso | Regla |
|---|---|
| Candidato | Pose cruda PINCH (un frame). Nada se envía. |
| Confirmado (`PINCH_CONFIRMED`) | Pose **estable** PINCH (2 frames), distancia pulgar–índice ≤ **0.25** escalas de mano, confianza de ambas puntas ≥ **0.5**, tracking FULL, nadie más es dueño y el pinch está *armado*. |
| Pendiente (`CLICK/DRAG_PENDING`) | Se registra: tiempo, modo de tracking, punta del índice, escala, distancia. El cursor se **congela**. |
| Suelta | Distancia > **0.35** en **2 frames medidos consecutivos** (un frame abierto con ruido = SUSPENDED, no suelta). |
| Click | Solo si la suelta es limpia (`gestureEnded`), con tracking FULL en ese frame, sin HOLD durante el pinch, sostenido ≤ **1.0 s**, movimiento neto < umbral de drag y salida live. Exactamente un `leftClick` (down + up, click state 1). |

- **Histéresis:** entrar 0.25 < salir 0.35 (`PoseConfiguration`), en unidades de la escala de mano
  de Phase 3 (mayor medida rígida de la palma ≈ 9–11 cm): ≈ 2.5 cm para entrar, ≈ 3.5 cm para
  salir. Puntas en contacto miden ≈ 0.1–0.2 (Vision pone las puntas en la yema); índice
  apuntando relajado ≥ 0.6. No son los valores de PHASE 0 reutilizados a ciegas: aquellos
  usaban otra referencia (`wrist → indexMCP`).
- **Mantenimiento por distancia, no por pose:** un pinch apretado puede hacer que el pulgar se
  clasifique como doblado; eso no suelta ni hace click. Punta ausente/ocluida = incierto
  (SUSPENDED, ≤ 0.25 s de gracia del árbitro); agotar la gracia es `recognitionTimeout` → sin
  click.
- **Cursor durante el click:** congelado desde la confirmación hasta la suelta, para que el click
  caiga donde apuntabas (cerrar los dedos desplaza la punta del índice). Al soltar vuelve con el
  deslizamiento de reacquisición de 2.1. El click se publica **antes** de mover el cursor ese
  frame.
- **Armado:** un pinch que se forma mientras otro gesto es dueño (scroll) o mientras corre la
  inercia pertenece a esa interacción: no hace click ni drag hasta que se abre (no es una pose
  neutra: basta con re-pinchar). Igual tras una cancelación con el pinch cerrado.
- **Doble click (reservado):** `PinchIntentController.lastClick` guarda tiempo y duración de
  cada click. No se sintetiza nunca click state 2.

## 3. Drag

| Paso | Regla |
|---|---|
| Commit | Pinch confirmado, **soportado** en este frame, tracking FULL, desplazamiento **neto** de los nudillos desde la confirmación ≥ **0.15** escalas de mano (≈ 1.5 cm). → `beginDrag` una vez. |
| Ancla | `offset = anchorCursor − anchorIndex`, fijado con la primera muestra del índice tras el mouseDown; nunca se recalcula. `dragCursor = clamp(index + offset)`. |
| Movimiento | El índice pasa por el **mismo** mapeo de 2.1 (`CursorController`: área activa, espejo, dead zone, sensibilidad, smoothing adaptativo; sin blend). `DragController` suma el offset. Se publica como `leftMouseDragged` (el único escritor del cursor en ese frame). |
| Suelta | Cualquier fin (suelta, timeout, LOST, cancel, salida apagada) → `endDrag` → `mouseUp` en la última posición del drag. Nunca un click. |

- El umbral se mide en los **nudillos** (`FeatureHistory`, robusto a nudillos que desaparecen),
  así el propio gesto de pinchar no dispara un drag; y es **neto**, así el temblor de ida y
  vuelta se cancela. Rápido: un movimiento claro hace commit en el primer frame; lento: cuando
  el recorrido llega al umbral, sin exigir tiempo mínimo.
- **Sin salto:** el objeto está donde estaba el cursor congelado; el recorrido previo al umbral
  no se transfiere (como el umbral de arrastre de un ratón).
- **Incierto durante el drag** (punta ocluida, primer frame abierto, HOLD): el objeto se queda
  quieto; nada obsoleto ni extrapolado. Vuelve la evidencia → sigue el mismo drag, sin segundo
  mouseDown.
- Al terminar, `CursorController` se reinicia y el cursor vuelve al índice con el deslizamiento
  de 2.1 desde el punto donde se soltó.

## 4. Click frente a drag

Una sesión de pinch acaba en **exactamente una** de: click, par mouseDown/mouseUp, o nada.

| Evidencia | Resultado |
|---|---|
| Pinch + suelta rápida en el sitio | CLICK |
| Pinch + movimiento pequeño (< 0.15 neto) + suelta | CLICK |
| Pinch + movimiento intencional sostenido | DRAG (el click queda cancelado) |
| Drag + volver al punto de partida + suelta | solo mouseUp |
| Pinch > 1 s quieto, HOLD/LOST durante el pinch, timeout, ambigüedad, confianza baja, pinch en la banda de histéresis | NADA |

## 5. Arbitraje

- Scroll dueño → no hay candidato de pinch; un pinch estable **termina** el scroll y queda
  desarmado → ni click ni drag de ese pinch.
- Pinch/drag dueño → el reconocedor de scroll no propone nada (`activeKind != nil`); un cambio
  de pose incidental no empieza un scroll. Abrir los dedos termina el drag (es la suelta).
- La salida de scroll ahora solo sigue a dueños de la familia scroll (`releasedKind`), sin
  cambiar ninguna regla de 3A.
- Salida por familia (`InteractionOutputs`): scroll y click/drag tienen su propio interruptor;
  una familia apagada queda en sombra (se reconoce, no publica, no toca el cursor).

## 6. Seguridad del botón

- **Libro del botón** (`DragController`, en la cola de Vision): un segundo mouseDown se ignora,
  un mouseUp solo sale si hay mouseDown, y no hay click con el botón pulsado.
- **Invariante en cada frame:** si el botón está abajo y la política aplicada no es `.drag` o el
  cursor no está permitido → mouseUp inmediato.
- **Pérdida:** HOLD → drag suspendido (quieto) dentro de la gracia de 0.25 s; más → mouseUp.
  LOST → mouseUp en ese mismo frame. Click pendiente + HOLD o LOST → sin click. No hay un
  segundo sistema de pérdida: todo sale del modo de `PointerTracker`.
- **Pausa / Cursor Control / Accesibilidad / cámara parada:** `setCursorControl(false)` →
  `closeInteraction(engine.cancel())` → mouseUp si y solo si hay drag pulsado; el click
  pendiente se descarta.
- **Reset de cámara / cambio de ajustes:** igual (`closeInteraction`).
- **Cierre de la app:** `applicationWillTerminate` → `shutdown()` → `visionQueue.sync` →
  `closeInteraction`.
- **Limitación de plataforma:** si se revoca el permiso de Accesibilidad durante un drag, macOS
  descarta también el mouseUp sintético; AirTrack lo envía igualmente, pero no puede
  garantizar el estado del botón sin permiso.

## 7. Adaptador macOS

API pública de CoreGraphics: `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`
con `.leftMouseDown`, `.leftMouseDragged`, `.leftMouseUp`, `mouseEventClickState = 1`,
`post(tap: .cghidEventTap)`. Con el botón pulsado macOS entrega el movimiento como
`leftMouseDragged` (un `mouseMoved` no arrastraría nada): es la realización del
"mouseDown → mouseMoved → mouseUp" de la especificación. Los eventos sintéticos se aproximan a
un trackpad; no son idénticos.

## 8. Tests

- Nuevas suites: `PinchRecognitionTests` (14), `ClickDragTests` (33), `ClickDragSafetyTests`
  (10: invariantes con 16 secuencias aleatorias reproducibles, `PinchIntentController`,
  `DragController`). 57 tests nuevos.
- Tests existentes actualizados (extensión legítima, ninguno eliminado):
  - `InteractionEngineTests.testPinchAndFourFingersAreRecognizedButDoNothingYet` →
    `testPinchInShadowAndFourFingersAreRecognizedButDoNothing`: en 3A el pinch no era un gesto;
    ahora sí, así que en modo sombra se comprueba que no hay acciones ni política aplicada.
  - `testCursorScrollCursorPinchScrollWithoutNeutralPose`: la última aserción comprobaba
    "cualquier intent"; ahora exige `.twoFingerScroll`, porque el pinch ya es un intent.
  - `GestureStateMachineTests`: sus dos `switch` exhaustivos sobre `InteractionAction` incluyen
    los tres casos nuevos.
- Resultado CI: **410/410, 0 failures** en macOS y en Linux (353 anteriores + 57 nuevos).

## 9. Build y CI

| Commit | Tests macOS | Tests Linux | Build app |
|---|---|---|---|
| `88e3b17` | no compila (test) | no compila (test) | `** BUILD SUCCEEDED **` |
| `095ab39` | no compila (type-checker, test helper) | 410/410, 0 failures | `** BUILD SUCCEEDED **` |
| `708f440` | **410/410, 0 failures** | **410/410, 0 failures** (Swift 6.4) | **`** BUILD SUCCEEDED **`**. Único warning: AppIntents (benigno) |

Comando de build (CI, macOS 15):
`xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -configuration Debug -destination 'platform=macOS' build`.

## 10. Limitaciones conocidas

- Todos los umbrales (0.25 / 0.35, confianza 0.5, drag 0.15, click ≤ 1 s, gracia 0.25 s) son
  iniciales, **sin calibrar** con manos reales.
- El recorrido de acercamiento de los dedos *antes* del frame de confirmación (1 frame) sí
  mueve el cursor; si el click cae desplazado en el Mac, la solución prevista es un ancla con
  mirada atrás (como la de PHASE 0), no aplicada todavía.
- Un pinch cerca del borde (PARTIAL / INDEX) no empieza gestos y su suelta no hace click;
  un drag sí continúa en esos modos.
- Soltar tras un pinch de más de 1 s sin moverse no hace nada (intención dudosa).
- Solo pantalla principal (igual que el cursor).

## 11. Validación física — PENDING USER VALIDATION

Panel de debug: sección **Click / drag (PHASE 3B)** (pinch ratio, confianza, estado, intent,
movimiento / umbral, último resultado, lifecycle, botón izquierdo, tracking) y el interruptor
**Click y arrastre con gestos**.

CLICK
1. Pinch rápido natural → un click.
2. Pinch lento → un click (si dura < 1 s).
3. Pinch con movimiento pequeño → click, no drag.
4. Clicks repetidos → uno por pinch, sin doble click.
5. Click en distintas zonas de la pantalla.
6. Click justo después de mover el cursor → cae donde apuntabas.
7. Click después de un scroll.
8. Click tras recuperar la mano (reacquisition).

DRAG
9. Pinch + mantener + mover → drag.
10. Drag lento. 11. Normal. 12. Rápido.
13. Horizontal. 14. Vertical. 15. Diagonal.
16. Drag hasta el borde de la pantalla.
17. Suelta normal → el objeto se suelta.
18. Pérdida breve de tracking → el drag sigue.
19. Pérdida prolongada → se suelta solo (sin botón pegado).
20. Recuperación tras una pérdida breve → sin salto ni segundo mouseDown.

CONFLICTOS
21. Scroll → pinch (el pinch que termina el scroll no hace click; re-pinchar sí).
22. Pinch → scroll.
23. Drag → nunca empieza un scroll.
24. Gesto ambiguo → nada.

SEGURIDAD
25. Pausa (⌃⌥⌘A) durante un drag → se suelta.
26. Cámara interrumpida durante un drag → se suelta.
27. Accesibilidad retirada durante un drag.
28. Cerrar la app durante un drag → botón no queda pulsado.

REGRESIÓN
29. Cursor como en 2.1. 30. Scroll como en 3A. 31. Transición cursor ↔ scroll.
32. Nunca queda el botón izquierdo pulsado.

Naturalidad: ¿rápido?, ¿exige posición exacta?, ¿el click cae donde se espera?, ¿el objeto
salta al empezar el drag?, ¿sigue al índice?, ¿hay clicks o drags accidentales?
