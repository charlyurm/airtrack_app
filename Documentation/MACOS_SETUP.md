# Setup y validación en macOS

Guía para compilar, ejecutar y validar AirTrack en un Mac real.

> **Cómo se escribió:** en un entorno Linux sin Xcode. La compilación de la app sí se
> verifica en CI (`xcodebuild` en un runner macOS de GitHub, ver `TESTING.md`). Los pasos
> de la interfaz de Xcode **no se verificaron** y pueden cambiar entre versiones
> (marcados ⚠️ VERSIÓN). Si algo no coincide con tu Xcode, sigue la intención del paso
> y corrige este documento.

---

## A. Requisitos

| Requisito | Valor | Motivo |
|---|---|---|
| Mac | Apple Silicon (arm64) | Objetivo del proyecto |
| macOS | 14 Sonoma o superior | Deployment target de la app (`@Observable`, tipos de cámara modernos) |
| Xcode | **16 o superior**, instalación completa | El proyecto usa grupos sincronizados con carpetas (objectVersion 77), que requieren Xcode 16. Swift 6. |
| Cámara | Integrada, USB o Continuity Camera | Captura de la mano |
| Permisos | Cámara y Accesibilidad | Los concede el usuario (H, I) |

```bash
uname -m              # esperado: arm64
sw_vers               # ProductVersion ≥ 14
xcodebuild -version   # Xcode ≥ 16
swift --version
xcode-select -p       # debe apuntar a /Applications/Xcode*.app/..., no a CommandLineTools
```

Si `xcode-select -p` apunta a `CommandLineTools`:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## B. Obtener el código

```bash
git clone https://github.com/charlyurm/airtrack_app.git   # o, si ya lo tienes:
cd airtrack_app
git checkout claude/gifted-carson-iyjqxg
git pull
```

## C. Estructura del repositorio

```text
airtrack_app/
├── AirTrackCore/                     Swift Package: lógica pura + tests
├── AirTrack/
│   ├── AirTrack.xcodeproj            Proyecto de Xcode (app macOS)
│   ├── AirTrack.entitlements         Entitlement de cámara (Hardened Runtime)
│   └── AirTrack/                     Código de la app (carpeta sincronizada)
│       ├── App/  Camera/  Vision/  Permissions/  UI/  Utilities/
├── Documentation/
└── README.md
```

Carpeta sincronizada: cualquier `.swift` que se añada dentro de `AirTrack/AirTrack/`
entra automáticamente en el target, sin tocar el `.pbxproj`.

## D. AirTrackCore

Lógica pura (solo Foundation). La app lo consume como paquete local
(`XCLocalSwiftPackageReference "../AirTrackCore"`). Detalles en `ARCHITECTURE.md`.

## E. Tests de AirTrackCore

```bash
cd AirTrackCore
swift test          # esperado: Executed 176 tests, with 0 failures
```

## F. Abrir el proyecto

```bash
open AirTrack/AirTrack.xcodeproj
```

Xcode resuelve el paquete local automáticamente. Si aparece "Missing package product
AirTrackCore": ⚠️ VERSIÓN, File → Packages → Resolve Package Versions (o Reset
Package Caches).

## G. AirTrackCore como paquete local

Ya está configurado en el proyecto. Para comprobarlo: target **AirTrack** → General →
*Frameworks, Libraries, and Embedded Content* debe listar **AirTrackCore**.

## H. Permiso de cámara

Ya configurado:
- `NSCameraUsageDescription` (build setting `INFOPLIST_KEY_NSCameraUsageDescription`).
- Entitlement `com.apple.security.device.camera` para cuando el Hardened Runtime está
  activo (ver J).
- App Sandbox: **no** está (decisión del MVP).

Al abrir la app por primera vez, macOS muestra el diálogo de permiso.

## I. Accesibilidad (PHASE 2, cursor)

Hace falta para que el índice mueva el cursor. En el panel, sección **Cursor**:
1. Activa **Cursor Control**. Sin permiso verás `Permission: REQUIRED`.
2. Pulsa **Conceder permiso**: macOS muestra su diálogo una sola vez.
3. En Configuración del Sistema → Privacidad y seguridad → **Accesibilidad**, activa AirTrack.
4. Vuelve a la app: en ≤ 1 s aparece `Permission: READY`.

Si tras recompilar macOS "olvida" el permiso (firma ad-hoc): quita AirTrack de la lista con
"−" y vuelve a añadirlo, o ejecuta `tccutil reset Accessibility com.airtrack.AirTrack`.

## J. Firma y entitlements

| Ajuste | Valor |
|---|---|
| Signing | "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`): no necesita cuenta de desarrollador |
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME = YES`, pero con firma ad-hoc Xcode lo **desactiva** ("Disabling hardened runtime with ad-hoc codesigning", visto en el log del CI). Solo se aplica si firmas con un Team; en ese caso `AirTrack.entitlements` ya incluye Camera |
| App Sandbox | No |
| Bundle ID | `com.airtrack.AirTrack` |

Si prefieres firmar con tu Team: target → Signing & Capabilities → Team. Mantén la
**misma** firma entre builds; macOS asocia los permisos a ella.

## K. Ejecutar desde Xcode

Scheme **AirTrack**, destino **My Mac**, Product → Run (⌘R).

## L. Comprobar BUILD SUCCEEDED

```bash
xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -configuration Debug build 2>&1 | tail -3
```

Debe terminar en `** BUILD SUCCEEDED **`. Para comprobar la arquitectura:

```bash
APP_DIR=$(xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')
file "$APP_DIR/AirTrack.app/Contents/MacOS/AirTrack"      # esperado: arm64
open "$APP_DIR/AirTrack.app"                               # ejecutar sin Xcode
```

## M. Validación manual de PHASE 1.1 (lo que tienes que mirar)

A la izquierda está el preview con el overlay; a la derecha, el panel. Colores del overlay:
**pulgar naranja · índice verde · medio azul · anular morado · meñique rosa**, muñeca
blanca con la etiqueta "1" o "2" (+ L/R si Vision informa chirality).

| # | Prueba | Qué hacer | Resultado esperado |
|---|---|---|---|
| A | Movimiento vertical | Mover la mano despacio de abajo arriba y de arriba abajo | Los puntos se mueven **en la misma dirección** que la mano. En el panel, "Index tip (x, y)": **subir la mano hace BAJAR y** (0 = arriba) |
| B | Identidad de landmarks | Mano abierta, dedos separados | Punta verde = punta del índice; azul = medio; morada = anular; rosa = meñique; naranja = pulgar. Cada cadena de color recorre **su** dedo |
| C | Distancia corta | Mano a ~20 cm | Si se detecta, los colores siguen en los dedos correctos. Si la mano no cabe o Vision duda, es aceptable ver `LOST` y "Rechazadas: …"; **no** es aceptable un esqueleto sobre algo que no es tu mano |
| D | Distancia normal/lejana | Alejar la mano poco a poco | Los puntos siguen pegados a los mismos puntos anatómicos; no hay desplazamiento que crezca con la distancia |
| E | Dos manos | Ambas manos en cuadro | `Hands: 2`, dos esqueletos ("1" y "2"); la mano 1 es la que está más a la izquierda en la imagen real (más a la derecha en el preview espejado) |
| F | Tracking LOST | Sacar las manos | `Tracking: LOST`, `Hands: 0` y el overlay desaparece **en el acto** (sin esqueletos congelados) |
| G | Recovery | Volver a meter la mano | `HAND DETECTED` en unos ~2 frames, con los colores correctos |
| H | Rendimiento | Mirar el panel ~1 minuto | Anotar Camera FPS, Vision FPS, Vision processing, Capture → HandState, Superseded frames y Camera drops |
| I | Espejo | Desactivar "Espejar preview" | La imagen se invierte en horizontal y **los puntos se invierten con ella** |
| J | Desconexión (opcional) | Desconectar la cámara externa o de Continuity | `Camera: DISCONNECTED` (no ERROR); reconectar → Reintentar → RUNNING |

**Qué reportar:** el resultado de cada fila (OK / falla + descripción), una captura con la
mano abierta y los valores de la fila H. Si algo falla, di la dirección exacta (por ejemplo,
"la punta verde cae en el dedo medio" o "al subir la mano, y sube").

## P. Validación de PHASE 2 (cursor)

Las 12 pruebas A–L, con lo que debes ver en cada una, están en `PHASE2_RESULT.md` §15.
Resumen: activa Cursor Control → el índice de la mano "1" mueve el cursor. Comprueba centro,
horizontal, **vertical (sin inversión)**, esquinas, quietud, rapidez, distancia, que al sacar
la mano el cursor se detenga, que al volver no salte, que la mano "2" no mueva nada y que
fuera del rectángulo discontinuo el cursor quede en el borde.

Para soltar el cursor: saca la mano del cuadro, pulsa **Pausar** (⌃⌥⌘A con AirTrack en
primer plano) o apaga Cursor Control.

## N. Logs

Console.app → filtrar por el subsystem `com.airtrack.AirTrack` (categorías `camera`,
`vision`, `tracking`, `permissions`). O en la terminal:

```bash
log stream --predicate 'subsystem == "com.airtrack.AirTrack"' --level info
```

Se registran solo los cambios de estado (permiso, cámara seleccionada, start/stop,
desconexión, errores de Vision, mano adquirida/perdida); nunca frames.

## O. Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| "The project … cannot be opened" / formato no soportado | Xcode < 16 | Actualizar Xcode |
| "Missing package product 'AirTrackCore'" | Paquete sin resolver | ⚠️ VERSIÓN: File → Packages → Resolve Package Versions |
| Error de firma | Configuración de signing | Signing & Capabilities → "Sign to Run Locally" o elegir tu Team |
| La app se cierra al pedir la cámara | Falta `NSCameraUsageDescription` en el Info.plist generado | Revisar el build setting `INFOPLIST_KEY_NSCameraUsageDescription` |
| Permiso concedido pero preview negro / sin frames | Falta el entitlement de cámara con Hardened Runtime, u otra app usa la cámara | Revisar `AirTrack.entitlements`; cerrar otras apps de cámara |
| No aparece el diálogo de permiso | TCC ya tiene una decisión guardada | `tccutil reset Camera com.airtrack.AirTrack` |
| `Camera FPS` bien pero `Vision FPS` muy bajo | Vision lento en este hardware | Reportar los números; la resolución se puede bajar en `CameraManager` |
| `Capture → HandState` muestra "—" | El timestamp de captura no está en el reloj host | Reportarlo; la métrica se ajustará |
| Puntos desalineados o espejados al revés | Transformación de coordenadas | Reportar la dirección exacta del error (sección M) |
| Warnings de Swift 6 Concurrency | Diferencias de SDK entre el CI y tu Xcode | Reportar el texto del warning |
