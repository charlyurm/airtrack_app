# Gestos

Todos los valores son **iniciales y no están calibrados**: hay que ajustarlos con
tracking real en un Mac (REQUIRES MACOS). Estado: la lógica está implementada y
probada en AirTrackCore; todavía no se ha conectado a una cámara ni a macOS.

## Cursor (índice)

1. `indexTip`, en coordenadas de cámara normalizadas.
2. Espejo horizontal (`mirrorCamera`, por defecto activado).
3. Zona activa (por defecto x 0.2–0.8, y 0.2–0.8) con `cursorSensitivity`
   (1.0 por defecto; >1 reduce la zona).
4. Normalización a 0…1 con clamp.
5. EMA con `cursorSmoothing` (alpha 0.5 por defecto; 0 = sin smoothing, máximo 0.95).

**Decisión provisional — smoothing por frame:** la EMA se aplica por frame, así que
el lag efectivo depende del FPS (a 60 fps se suaviza "menos tiempo" que a 30). Mejora
futura: **time-based smoothing**, para que 30/60/120 fps se sientan igual. No se
implementa todavía.

## Pinch

```text
ratio = distancia(thumbTip, indexTip) / distancia(wrist, indexMCP)
```

- Distancias corregidas por aspect ratio y en unidades de alto de imagen.
- Se normaliza por el tamaño de la mano: la mano cerca o lejos de la cámara produce el
  mismo ratio. **Nunca** se vuelve a un umbral absoluto.
- Histéresis: empieza con `ratio < 0.25` y se suelta con `ratio > 0.35`.
  **No calibrado:** son valores estimados a partir de proporciones típicas de la mano,
  no medidos. Hay que validarlos con la cámara real.
- Si el ratio no se puede medir (pulgar ocluido o confianza < 0.3), se mantiene el
  estado hasta 3 frames; después se suelta.

**Decisión provisional — latencia del pinch:** cada transición exige **2 frames
consecutivos** (~33 ms a 30 fps). Se mantiene así para evitar falsos positivos.
Tras medir en hardware real se decidirá si reducir la confirmación, usar timestamps,
predicción u otro filtro.

## Máquina de estados: click, double click y drag

| Fase | Qué envía a macOS |
|---|---|
| `pointing` | `moveCursor`, solo si la posición cambió |
| `clickCandidate` | **Nada.** El cursor queda congelado en el ancla |
| → release | `mouseDown` + `mouseUp` en el ancla (**CLICK**) |
| → hold ≥ 0.3 s o dedo movido ≥ 0.03 | `mouseDown` en el ancla, **sin mover el cursor** (**DRAG**) |
| `dragging` | `mouseDrag` a `dedo + offset` |
| → release | `mouseUp` en la última posición de drag (**RELEASE**) |

- **Ancla:** la posición del cursor ~70 ms antes de confirmar el pinch, es decir,
  antes de que los dedos arrastren la punta del índice.
- **Umbral de movimiento:** se mide desde la posición del dedo al confirmar el pinch
  (no desde el ancla), así la deriva previa al pinch no dispara un drag.
- **Double click:** un segundo pinch dentro de 0.4 s desde el release del primero y
  a ≤ 0.02 del mismo punto. El segundo click reutiliza la posición del primero y se
  envía con `clickCount = 2`.
- **Un pinch mantenido nunca es double click:** el drag siempre usa `clickCount = 1`.
- **El tercer pinch rápido** empieza una secuencia nueva (`clickCount = 1`).
- Un drag no cuenta como primer click de un double click.

### Continuidad del drag (sin salto)

Mientras el cursor está congelado en el ancla, el dedo se desplaza un poco (deriva
del pinch o movimiento intencional). Si al empezar el drag el cursor saltara al
dedo, el objeto arrastrado saltaría con él. Para evitarlo:

```text
al entrar en DRAG:   offset = ancla − dedo
durante el DRAG:     cursor = clamp(dedo + offset)     // mismo delta que el dedo
al soltar:           residual = cursor − dedo
después (pointing):  cursor = dedo + residual · max(0, 1 − Δt / 0.2 s)
```

- Entrar en drag no mueve el cursor.
- Cada movimiento del dedo produce exactamente el mismo movimiento del cursor.
- Al soltar, el offset se desvanece linealmente en 200 ms (`dragOffsetDecayDuration`)
  en vez de saltar.
- Limitación: cerca de un borde, el offset puede impedir llegar al borde opuesto
  durante ese drag (el cursor se limita a la pantalla).

## Pérdida de tracking y pausa

| Situación | Resultado |
|---|---|
| Mano perdida < 150 ms | Se ignora; el drag continúa con el mismo offset |
| Mano perdida ≥ 150 ms en `clickCandidate` | Se cancela sin enviar nada |
| Mano perdida ≥ 150 ms en `dragging` | `mouseUp` y fase `idle` |
| Pausa | Igual, pero inmediata; después, silencio total; el offset se descarta |
| Mano recuperada (o al iniciar) ya cerrada | Solo mueve el cursor; tiene que abrirse (`ratio > 0.35`) antes de otro pinch |

## Atajo de emergencia

`emergencyToggleShortcut`, configurable. Por defecto es **⌃⌥⌘A**; se descartó ⌘⇧A
porque Finder lo usa para "Ir a Aplicaciones". REQUIRES MACOS: verificar que no
tenga conflictos en tu Mac.

## Aún no implementado

- Scroll con la mano abierta (PHASE 5).
