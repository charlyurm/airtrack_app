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
| Permisos | Cámara | Lo concede el usuario (H). Accesibilidad llega en PHASE 2. |

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
swift test          # esperado: Executed 85 tests, with 0 failures
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

## I. Accesibilidad

**No se usa en PHASE 1.** Llega en PHASE 2 (cursor).

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

## M. Validación manual de PHASE 1 (lo que tienes que mirar)

Abre la app. A la izquierda está el preview con el overlay; a la derecha, el panel.

| # | Prueba | Qué hacer | Resultado esperado |
|---|---|---|---|
| A | Cámara | Abrir la app | Imagen real de la cámara; `Camera: RUNNING` en verde |
| B | Permiso | Primera ejecución (o tras `tccutil reset Camera com.airtrack.AirTrack`) | Aparece el diálogo con el texto de AirTrack. Si lo rechazas: `Camera: PERMISSION REQUIRED`, explicación y botón a Configuración del Sistema, sin crash |
| C | Mano | Mano abierta frente a la cámara | `Tracking: HAND DETECTED`, `Hands: 1`, joints en verde en la lista |
| D | Landmarks | Mirar el preview | Punto **verde** en la punta del índice, **naranja** en la del pulgar, blancos en muñeca/MCP/PIP/DIP/otras puntas, línea por la cadena del índice y línea discontinua pulgar–índice. **Deben quedar encima de tu mano** |
| E | Movimiento | Mover la mano a izquierda, derecha, arriba y abajo | Los puntos siguen a la mano en la misma dirección que ves en el preview |
| F | Distancia | Acercar y alejar la mano | Los puntos siguen alineados; el tracking no se pierde a distancias normales |
| G | Espejo | Desactivar "Espejar preview" | La imagen se invierte y **los puntos se invierten con ella** (siguen sobre la mano) |
| H | Tracking loss | Sacar la mano del encuadre | `Tracking: LOST`, `Hands: 0`, el overlay desaparece, sin errores repetidos |
| I | Recovery | Volver a meter la mano | `HAND DETECTED` de nuevo, sin reiniciar nada |
| J | Mano izquierda/derecha | Probar ambas | Ambas se detectan (una a la vez: `maximumHandCount = 1`) |
| K | Desconexión (si tienes cámara externa o Continuity) | Desconectarla con la app abierta | `Camera: DISCONNECTED` (naranja), no ERROR. Reconectar → Reintentar → RUNNING |
| L | Rendimiento | Mirar el panel | Camera FPS ~30 (depende de la cámara y de la luz), Vision FPS parecido, Vision processing en ms, Dropped frames creciendo poco |

**Qué reportar:** el resultado de cada fila (OK / falla + descripción), una captura de
pantalla del preview con la mano y los valores de FPS / processing / Capture →
HandState. Si los puntos están desplazados, invertidos o rotados, describe en qué
dirección (por ejemplo, "se mueven al revés en horizontal").

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
