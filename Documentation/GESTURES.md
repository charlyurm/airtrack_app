# Gestos

Todos los valores son **iniciales y no están calibrados**: hay que ajustarlos con
tracking real en un Mac (REQUIRES MACOS).

## Cursor (índice)

1. `indexTip`, en coordenadas de cámara normalizadas.
2. Espejo horizontal (`mirrorCamera`, por defecto activado).
3. Zona activa (por defecto x 0.2–0.8, y 0.2–0.8) con `cursorSensitivity`
   (1.0 por defecto; >1 reduce la zona).
4. Normalización a 0…1 con clamp.
5. EMA con `cursorSmoothing` (alpha 0.5 por defecto; 0 = sin smoothing, máximo 0.95).

## Pinch

```text
ratio = distancia(thumbTip, indexTip) / distancia(wrist, indexMCP)
```

- Distancias corregidas por aspect ratio y en unidades de alto de imagen.
- Histéresis: empieza con `ratio < 0.25` y se suelta con `ratio > 0.35`.
- Cada transición exige 2 frames consecutivos (unos 33 ms extra a 30 fps).
- Si el ratio no se puede medir (pulgar ocluido o confianza < 0.3), se mantiene el
  estado hasta 3 frames; después se suelta.

## Máquina de estados: click, double click y drag

| Fase | Qué envía a macOS |
|---|---|
| `pointing` | `moveCursor`, solo si la posición cambió |
| `clickCandidate` | **Nada.** El cursor queda congelado en el ancla |
| → release | `mouseDown` + `mouseUp` en el ancla (**CLICK**) |
| → hold ≥ 0.3 s o movimiento ≥ 0.03 | `mouseDown` en el ancla + `mouseDrag` (**DRAG**) |
| `dragging` | `mouseDrag`, el cursor sigue al dedo |
| → release | `mouseUp` en la última posición de drag (**RELEASE**) |

- **Ancla:** la posición del cursor ~70 ms antes de confirmar el pinch, es decir,
  antes de que los dedos arrastren la punta del índice.
- **Double click:** un segundo pinch dentro de 0.4 s desde el release del primero
  y a ≤ 0.02 del mismo punto. El segundo click reutiliza la posición del primero
  y se envía con `clickCount = 2`.
- **Un pinch mantenido nunca es double click:** el drag siempre usa `clickCount = 1`.
- **El tercer pinch rápido** empieza una secuencia nueva (`clickCount = 1`).
- Un drag no cuenta como primer click de un double click.

## Pérdida de tracking y pausa

| Situación | Resultado |
|---|---|
| Mano perdida < 150 ms | Se ignora; el drag continúa |
| Mano perdida ≥ 150 ms en `clickCandidate` | Se cancela sin enviar nada |
| Mano perdida ≥ 150 ms en `dragging` | `mouseUp` y fase `idle` |
| Pausa | Igual, pero inmediata; después, silencio total |
| Mano recuperada (o al iniciar) ya cerrada | Solo mueve el cursor; tiene que abrirse (`ratio > 0.35`) antes de otro pinch |

## Atajo de emergencia

`emergencyToggleShortcut`, configurable. Por defecto es **⌃⌥⌘A**; se descartó
⌘⇧A porque Finder lo usa para "Ir a Aplicaciones". REQUIRES MACOS: verificar que
no tenga conflictos en tu Mac.

## Aún no implementado

- Scroll con la mano abierta (PHASE 5).
