# PHASE 2 RESULT — Cursor Control

**Estado: READY FOR LOCAL VALIDATION.** Implementado y verificado con tests y CI. **El cursor
real no se ha probado**: el desarrollo se hizo en Claude Code Cloud (Linux, sin Mac, cámara ni
pantalla). PHASE 2 no está completa hasta que se valide en el Mac físico.

Alcance: solo **índice → cursor**. No hay pinch, click, doble click, drag, scroll, right click,
swipe, Mission Control, Spaces ni zoom. La auditoría con `grep` no encuentra
`mouseDown/mouseUp/scrollWheel/leftMouseDragged/GestureEngine/PinchRecognizer` en la app.

---

## 1. Arquitectura

```text
Vision → HandPresenceFilter (Core, 1.1) → [HandState] primaria primero
   │                                       (visionQueue, mismo hilo, sin colas nuevas)
   ▼
CursorController (Core, puro)
   primary hand → indexTip → active area → dead zone → sensitivity → EMA → blend de reacquisición
   → ScreenMapper (Rect2D de la pantalla)
   ▼
CursorUpdate (screen en puntos)
   ▼
MacOSEventController (app) → CGEvent .mouseMoved → macOS
```

- **Core (solo Foundation):** `CursorController`, `CursorControlState`, `DeadZoneFilter`; se
  reutilizan `CursorMapper` (partido en dos pasos), `CursorSmoother`, `ScreenMapper`,
  `AirTrackSettings`, `HandOrdering` y `HandPresenceFilter`.
- **App:** `Events/MacOSEventController` (única llamada a `CGEvent`),
  `Permissions/AccessibilityPermissionManager`, integración en `HandTrackingPipeline`, estado
  en `AppModel`, panel de diagnóstico y overlay del active area.
- `GestureEngine` (pinch y click, escrito en PHASE 0) **no está conectado**. PHASE 3 lo hará
  consumir la salida de `CursorController`, sin reescribirlo.

## 2. Modelo de coordenadas del cursor

| Paso | Espacio | Transformación |
|---|---|---|
| `HandState.indexTip` | imagen real, 0…1, origen arriba-izquierda, Y hacia abajo, **sin espejo** | — |
| Espejo | punto de vista del usuario | `x' = 1 − x` (una sola vez; `mirrorCamera`, por defecto activo) |
| Active area | 0…1 dentro del área (sin clamp) | `(p − min) / tamaño` |
| Dead zone | igual | ancla si el movimiento es ≤ umbral |
| Sensibilidad | display normalizado | `0.5 + (n − 0.5)·s`, luego clamp 0…1 |
| Smoothing / blend | display normalizado | EMA; offset de reacquisición que decae |
| Pantalla | global CG: puntos, origen arriba-izquierda de la pantalla principal, Y hacia abajo | `ScreenMapper`: `origen + n·tamaño`, clamp a `max − 1` |

- **Y nunca se invierte:** `y` de `HandState` y de la pantalla crecen hacia abajo, igual que
  en CoreGraphics. Subir la mano disminuye `y` en los dos.
- **El espejo no es un espejo "adicional":** `HandState` es la imagen real, y como la cámara
  mira al usuario, la izquierda física del usuario es la derecha de la imagen. Sin ese único
  espejo, el cursor iría al revés en horizontal.
- **Retina:** CoreGraphics trabaja en puntos lógicos; `CGDisplayBounds` también. No hay
  ningún factor de escala en la matemática.

## 3. Active area

`AirTrackSettings.activeArea` (en el espacio espejado, el que ves en el preview).
**Por defecto x 0.15–0.85, y 0.15–0.85**, un valor inicial que se puede ajustar. Dentro del
área: `xMin → izquierda`, `xMax → derecha`, `yMin → arriba`, `yMax → abajo`. Fuera del área,
el cursor queda en el borde. El preview dibuja el área efectiva (la que cubre toda la
pantalla con la sensibilidad actual) como un rectángulo blanco discontinuo.

## 4. Sensibilidad

`cursorSensitivity`, por defecto 1.0 (rango 0.5–3). Escala alrededor del centro **después**
de la dead zone. Es equivalente a encoger el active area por 1/s (lo prueba
`testTwoStepMappingEqualsShrinkingTheActiveArea`). Se puede ajustar con un slider del panel.

## 5. Dead zone

`cursorDeadZone`, por defecto **0.003** en unidades del active area (≈ 4 pt en una pantalla
de 1440 pt con sensibilidad 1; rango 0–0.05). `DeadZoneFilter` guarda un ancla: si el
movimiento es ≤ umbral, la salida es el ancla (el cursor no tiembla); si es mayor, pasa sin
cambios y se convierte en la nueva ancla. **Nunca añade retraso** a un movimiento real; como
mucho, un único paso del tamaño del umbral al empezar a moverse. El límite de 0.05 impide que
el cursor se quede "pegado".

## 6. Smoothing

Se reutiliza `CursorSmoother` (EMA), sin un segundo filtro. Por defecto `cursorSmoothing` =
**0.35**: antes era 0.5; se bajó porque ahora la dead zone se encarga del dedo quieto.
- El retraso en régimen constante es `v·α/(1−α)` (≈ 0.54 del paso por frame): probado.
- Sin overshoot (combinación convexa): probado.
- Determinista: probado.
- Se reinicia al perder la mano.

Slider en el panel.

## 7. CursorController

`update(hands:timestamp:display:isActive:currentCursor:) -> CursorUpdate?` (Core, puro, sin
cámara, Vision ni UI):

1. usa `hands.first` (primaria según `HandOrdering`);
2. toma `indexTip` con confianza ≥ `minimumLandmarkConfidence`;
3. active area → dead zone → sensibilidad → EMA → blend → `ScreenMapper`;
4. devuelve `nil` (**no mover**) si no está activo, si no hay mano, si falta la punta o no es
   finita, o si la pantalla no es válida. En todos esos casos **borra todo su estado**.

## 8. Capa de eventos macOS

`MacOSEventController`: `mainDisplayBounds()` (`CGDisplayBounds(CGMainDisplayID())`),
`currentCursorLocation()` (`CGEvent(source: nil).location`) y `moveCursor(to:)`
(`CGEvent .mouseMoved` publicado en `.cghidEventTap`; las apps reciben eventos de
movimiento normales). **No tiene** mouseDown, mouseUp, click, drag ni scroll. Se ejecuta en
la cola de Vision, justo después del filtro: no hay saltos de hilo, ni colas, ni timers.

## 9. Permiso

Publicar eventos requiere **Accesibilidad**:
- `CGPreflightPostEventAccess()` comprueba el permiso;
- `CGRequestPostEventAccess()` muestra el diálogo del sistema **solo al pulsar "Conceder
  permiso" y como máximo una vez por sesión**; después ese botón abre Configuración del
  Sistema → Privacidad y seguridad → Accesibilidad.
- El permiso se vuelve a comprobar cada segundo: si se revoca, el cursor deja de moverse.

El permiso de cámara no cambia.

## 10. Tracking loss y activación

`CursorControlState` = `off` (por defecto al arrancar) · `paused` · `waitingForPermission` ·
`waitingForHand` · `active`. **Solo `active` mueve el cursor**, y requiere a la vez:
- el interruptor "Cursor Control" activado,
- que no esté en pausa,
- el permiso de Accesibilidad,
- la cámara en `RUNNING`,
- una mano primaria válida en **este** frame.

Si cualquiera falla, las actualizaciones se detienen al instante y se borra el estado.

- **Pérdida:** no se envía nada más; no se reutiliza ninguna posición antigua.
- **Recuperación:** empieza desde la posición **real** actual del cursor y se desliza hacia
  la posición del dedo en 0.2 s (`cursorReacquisitionBlend`), en lugar de saltar. El
  smoothing arranca de cero, así que no arrastra la posición vieja.
- **Pausa:** botón o **⌃⌥⌘A** (solo con AirTrack en primer plano; el atajo global es PHASE 5).
  Sacar la mano del cuadro también suelta el cursor.

## 11. Mano primaria

Solo mueve el cursor la primera mano de `HandOrdering` (1.1): la más a la izquierda en la
imagen real, es decir, la más a la **derecha en el preview espejado**. La segunda mano se
ignora (probado).

## 12. Multi-display

PHASE 2 usa **solo la pantalla principal** (la de la barra de menús). La arquitectura acepta
cualquier `Rect2D` (probado con pantallas desplazadas y orígenes negativos), así que añadir
la elección de pantalla más adelante no cambia la matemática.

## 13. Tests

44 nuevos (176 en total):

| Suite | Tests nuevos | Cubre |
|---|---|---|
| `CursorControllerTests` | 27 | centro, bordes, esquinas, fuera del área/clamp, Y (subir = subir), izquierda física = izquierda, sin espejo, pantallas arbitrarias/desplazadas/negativas, puntos lógicos (Retina), pantalla inválida, sensibilidad, smoothing, dead zone, **solo la mano primaria**, sin mano, punta ausente/débil/NaN, desactivado, pérdida inmediata, recuperación sin datos obsoletos, recuperación sin salto (blend), sin referencia, determinismo, estados de activación, ajustes por defecto/personalizados/en caliente/saneados |
| `DeadZoneFilterTests` | 9 | primer punto, bajo el umbral, **exactamente** en el umbral, sobre el umbral, dedo quieto con ruido, movimiento intencional sin retraso, reset, umbral limitado |
| `CursorMapperTests` | +4 | normalización sin clamp, sensibilidad alrededor del centro, dos pasos ≡ área encogida, área por defecto 15–85 % |
| `CursorSmootherTests` | +4 | reposo exacto, sin overshoot, retraso acotado, determinismo |

Único cambio en un test existente: `GestureEngineTests` tenía escrito a mano el active area
anterior (0.2–0.8); ahora lo calcula a partir de `CursorMapper.defaultActiveArea`. No se
eliminó ningún test.

## 14. CI / build

Run `36540663197`, commit `dad01ad`:

| Job | Resultado |
|---|---|
| `swift test` macOS 15 arm64 | **176/176**, 0 failures, 0 unexpected |
| `swift test` Ubuntu 24.04 x86_64 | **176/176**, 0 failures, 0 unexpected |
| `xcodebuild` AirTrack.app | **OK**; único warning: AppIntents metadata (benigno) |

Historial honesto: el primer push de Phase 2 falló en CI por dos errores **en los tests**
(una llamada al helper con un mensaje extra, y dos tests de la dead zone con un umbral
mayor que el máximo permitido). Se corrigieron los tests; el código no cambió.

## 15. Validación en el Mac

```bash
git pull
cd AirTrackCore && swift test && cd ..     # Executed 176 tests, with 0 failures
open AirTrack/AirTrack.xcodeproj           # ⌘R
```

Pon la mano frente a la cámara y activa **Cursor Control** en el panel.

| # | Prueba | Qué hacer | Resultado esperado |
|---|---|---|---|
| **A** | Permiso | Activar Cursor Control sin permiso | `Permission: REQUIRED`, `Cursor: WAITING FOR PERMISSION`. "Conceder permiso" muestra el diálogo **una vez**; activa AirTrack en Accesibilidad → `READY`. Sin crash ni bucles |
| **B** | Centro | Índice en el centro del rectángulo discontinuo | Cursor cerca del centro de la pantalla principal; "Mapped cursor" ≈ la mitad del tamaño de la pantalla |
| **C** | Horizontal | Mover el índice izquierda → centro → derecha (tu izquierda y tu derecha) | El cursor va en la misma dirección, sin inversión |
| **D** | Vertical | Arriba → centro → abajo | El cursor sube y baja igual que la mano. **No debe haber inversión vertical** |
| **E** | Esquinas | Las 4 esquinas del rectángulo | El cursor llega a las 4 esquinas de la pantalla |
| **F** | Movimientos pequeños | Dedo quieto y luego movimientos mínimos | El cursor apenas tiembla con el dedo quieto; los movimientos pequeños intencionales sí mueven |
| **G** | Movimiento rápido | Mover rápido | Sigue sin retraso molesto; si lo hay, bajar Smoothing |
| **H** | Distancia | Acercar y alejar la mano | El mapeo no cambia de forma extraña (a igual posición del índice en la imagen, mismo cursor) |
| **I** | Tracking loss | Sacar la mano | El cursor se detiene **al instante**; `Cursor: WAITING FOR HAND` |
| **J** | Recovery | Volver a meter la mano en otro sitio | El cursor sale de donde estaba y se desliza en ~0.2 s hasta el dedo, sin saltar |
| **K** | Dos manos | Dos manos en cuadro | Solo la mano "1" mueve el cursor; mover la "2" no hace nada |
| **L** | Active area | Sacar el índice del rectángulo | El cursor queda en el borde de la pantalla |

Extra: comprobar que ⌃⌥⌘A pausa y reanuda (con AirTrack en primer plano) y que al apagar
Cursor Control el ratón físico vuelve a mandar.

Qué reportar: OK o falla por prueba, con la dirección exacta si algo falla, los valores de
los sliders si los cambiaste y si la sensación fue natural, lenta o temblorosa.

## 16. Limitaciones conocidas

1. **Valores sin calibrar:** active area, sensibilidad, smoothing 0.35, dead zone 0.003 y
   blend 0.2 s. Se ajustan con los sliders; no se guardan todavía (UserDefaults es PHASE 5).
2. **Atajo de pausa solo local** (AirTrack en primer plano). El atajo global es PHASE 5.
3. **Conflicto con el ratón físico:** mientras la mano esté en cuadro, AirTrack mueve el
   cursor aunque uses el trackpad. Para recuperar el control: sacar la mano, pausar o apagar.
4. **Solo la pantalla principal.**
5. **La mano primaria es espacial:** si las manos se cruzan, puede cambiar cuál es la "1".
6. **El smoothing es por frame:** a más FPS, menos retraso (el smoothing basado en tiempo
   sigue pendiente).
7. **La precisión en los bordes depende de Vision** con la mano cerca del límite de la imagen.
8. **Firma ad-hoc:** si macOS "olvida" el permiso de Accesibilidad tras recompilar, quita
   AirTrack de la lista y vuelve a añadirlo (o `tccutil reset Accessibility com.airtrack.AirTrack`).
