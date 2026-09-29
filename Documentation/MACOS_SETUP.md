# Setup en macOS

Guía para continuar AirTrack en un Mac real a partir de PHASE 0.

> **Estado de esta guía:** redactada en un entorno Linux, **sin Xcode**. Los comandos
> de terminal son estándar de macOS. Los pasos de la interfaz de Xcode **no se pudieron
> verificar**: los nombres de menús y paneles cambian entre versiones (marcados como
> ⚠️ VERSIÓN). Si algo no coincide con tu Xcode, sigue la intención del paso y
> corrige este documento.

---

## A. Requisitos

| Requisito | Valor | Motivo |
|---|---|---|
| Mac | Apple Silicon (arm64) | Objetivo del proyecto. AirTrackCore también compila en Intel, pero la app no se prueba ahí. |
| macOS | 13 Ventura o superior | Deployment target elegido (p. ej., `MenuBarExtra` de SwiftUI requiere macOS 13). Vision hand pose existe desde macOS 11. |
| Xcode | Versión completa (no solo Command Line Tools) con Swift ≥ 5.9 (Xcode 15+) | `Package.swift` usa `swift-tools-version:5.9`. XCTest requiere Xcode completo. |
| Cámara | Integrada, USB o Continuity Camera | Hace falta desde PHASE 1. |
| Permisos | Cámara y Accesibilidad | Los concede el usuario en Configuración del Sistema (ver H e I). |

Comprobarlo:

```bash
uname -m              # esperado: arm64
sw_vers               # ProductVersion ≥ 13
xcodebuild -version   # Xcode 15 o superior
swift --version       # Swift 5.9 o superior
xcode-select -p       # debe apuntar a /Applications/Xcode.app/..., no a CommandLineTools
```

Si `xcode-select -p` apunta a `CommandLineTools`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## B. Obtener el proyecto

```bash
git clone https://github.com/charlyurm/airtrack_app.git
cd airtrack_app
git checkout claude/gifted-carson-iyjqxg   # rama de desarrollo mientras no se fusione
```

## C. Estructura del repositorio

```text
airtrack_app/
├── AirTrackCore/                 Swift Package: lógica pura + tests (EXISTE)
├── Documentation/                Esta documentación (EXISTE)
├── AIRTRACK_PROJECT_STRUCTURE.md Documento maestro de arquitectura (EXISTE)
├── README.md
└── AirTrack/ + AirTrack.xcodeproj  App macOS (NO EXISTE: se crea en el paso F)
```

## D. AirTrackCore

- Contiene modelos, geometría, mapeo del cursor, smoothing, pinch, máquina de
  estados de gestos y matemática de calibración.
- **No importa** AppKit, AVFoundation, Vision, CoreGraphics ni SwiftUI. Esta regla
  no se rompe: todo lo que dependa del sistema va en la app.
- Entrada: `HandState` por frame. Salida: `[InteractionAction]` en coordenadas
  normalizadas. Detalles en `ARCHITECTURE.md`.

## E. Ejecutar los tests

Terminal:

```bash
cd AirTrackCore
swift test
```

Resultado esperado: `Executed N tests, with 0 failures`. N es el total indicado en
`TESTING.md`. También puede aparecer una línea de swift-testing del tipo
"Test run with 0 tests passed"; es normal, porque los tests usan XCTest.

Desde Xcode: abrir `AirTrackCore/Package.swift` (doble clic o `xed AirTrackCore`) y
ejecutar Product → Test (⌘U).

## F. Crear el proyecto macOS

⚠️ VERSIÓN: los nombres de los diálogos pueden variar.

1. Xcode → File → New → Project… → pestaña **macOS** → **App**.
2. Opciones:
   - Product Name: `AirTrack`
   - Interface: **SwiftUI** · Language: **Swift**
   - Organization Identifier: el tuyo (define el Bundle ID, que se usa en `tccutil`).
   - Storage/Testing: sin Core Data ni SwiftData. Los tests de la app son opcionales.
3. Guardarlo **en la raíz del repositorio**.
   - Desmarcar "Create Git repository" (el repo ya existe).
4. Comprobar dónde quedó el proyecto:

   ```bash
   git status
   find . -name "*.xcodeproj" -maxdepth 3
   ```

   Xcode suele crear una carpeta contenedora (`AirTrack/AirTrack.xcodeproj` +
   `AirTrack/AirTrack/`), que difiere ligeramente del árbol del documento maestro. Es
   aceptable. Anota la ruta real y actualiza `AIRTRACK_PROJECT_STRUCTURE.md` en el
   commit de PHASE 1.

## G. Agregar AirTrackCore como Swift Package local

⚠️ VERSIÓN. Dos métodos; usa el que exista en tu Xcode:

- **Método 1:** File → Add Package Dependencies… → botón **Add Local…** →
  seleccionar la carpeta `AirTrackCore/` → añadir la librería `AirTrackCore` al
  target `AirTrack`.
- **Método 2:** arrastrar la carpeta `AirTrackCore/` al Project Navigator. Después:
  target `AirTrack` → General → *Frameworks, Libraries, and Embedded Content* → `+`
  → `AirTrackCore`.

Verificación: añadir `import AirTrackCore` en cualquier archivo de la app y compilar
(⌘B). Si falla con "No such module", ver O.

## H. Permiso de cámara

1. Info.plist: clave `NSCameraUsageDescription`, con el texto sugerido
   *"AirTrack usa la cámara para detectar tu mano. Las imágenes se procesan solo en
   este Mac y nunca se guardan ni se envían."*
   - ⚠️ VERSIÓN: en proyectos recientes, Info.plist se genera desde build settings.
     Añádela en target → Info (Custom macOS Application Target Properties) como
     "Privacy - Camera Usage Description", o como build setting
     `INFOPLIST_KEY_NSCameraUsageDescription`.
   - **Sin esta clave, macOS termina la app** en el primer acceso a la cámara.
2. Hardened Runtime: si la capability está activa (ver J), marca **Camera** en
   Resource Access. Sin eso, la captura falla aunque el usuario haya concedido
   el permiso.
3. La implementación (`AirTrack/Permissions/CameraPermission.swift`) es de PHASE 1;
   todavía no existe.

## I. Permiso de Accesibilidad

- No usa clave en Info.plist ni entitlement. El usuario lo concede en Configuración
  del Sistema → Privacidad y seguridad → **Accesibilidad**.
- La app lo consultará con `AXIsProcessTrusted()` / `CGPreflightPostEventAccess()` y
  mostrará un botón para abrir esa pantalla (PHASE 3).
- **Desarrollo:** el permiso queda asociado a la firma del binario. Si la firma
  cambia entre builds, macOS puede dejar de reconocer la app aunque aparezca
  activada. Solución en O.

## J. Entitlements y capabilities

| Capability / entitlement | Valor para el MVP |
|---|---|
| App Sandbox (`com.apple.security.app-sandbox`) | **Eliminada** (decisión aprobada: CGEvent y sandbox no son compatibles para este uso) |
| Hardened Runtime | Puede quedar activa; si lo está, **Resource Access → Camera** (`com.apple.security.device.camera = true`) |
| Red / archivos / otros | Ninguno. AirTrack no usa red. |

⚠️ VERSIÓN: la plantilla de Xcode puede o no incluir App Sandbox y Hardened Runtime.
Revísalo en target → **Signing & Capabilities**.

## K. Ejecutar desde Xcode

1. Scheme `AirTrack`, destino **My Mac**.
2. Signing: elige tu Team o "Sign to Run Locally", y **mantén el mismo** entre builds
   (ver I).
3. Product → Run (⌘R).

## L. Comprobar BUILD SUCCEEDED

```bash
# Ajusta -project a la ruta real del paso F
xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -configuration Debug build 2>&1 | tail -3
```

Debe terminar en `** BUILD SUCCEEDED **`. Para comprobar la arquitectura:

```bash
APP_DIR=$(xcodebuild -project AirTrack/AirTrack.xcodeproj -scheme AirTrack -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')
file "$APP_DIR/AirTrack.app/Contents/MacOS/AirTrack"   # esperado: arm64
```

## M. Comprobar la cámara

Antes de PHASE 1 (el hardware y macOS, sin AirTrack):

```bash
system_profiler SPCameraDataType   # debe listar al menos una cámara
```

También puedes abrir Photo Booth y confirmar que muestra imagen.

Desde PHASE 1, la vista de debug de AirTrack mostrará `Camera: Connected`,
`Camera: Permission Required` o `Camera: Error`. Para volver a probar el flujo de
permiso desde cero:

```bash
tccutil reset Camera <tu.bundle.id>
```

## N. Comprobar Accesibilidad

Configuración del Sistema → Privacidad y seguridad → Accesibilidad: AirTrack debe
aparecer y estar activada. Desde PHASE 3, la app mostrará el estado del permiso.
Para repetir el flujo:

```bash
tccutil reset Accessibility <tu.bundle.id>
```

## O. Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| `swift test`: "no such module 'XCTest'" | Solo están instaladas las Command Line Tools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| "No such module 'AirTrackCore'" en la app | El paquete no está enlazado al target | Repetir G (Frameworks, Libraries…) |
| Errores de resolución del paquete | Caché de SwiftPM | ⚠️ VERSIÓN: File → Packages → Reset Package Caches |
| La app se cierra al acceder a la cámara | Falta `NSCameraUsageDescription` | Paso H.1 |
| Permiso de cámara concedido pero sin frames | Hardened Runtime sin Camera, u otra app usando la cámara | Paso H.2; cerrar las otras apps |
| No aparece el diálogo de permiso | TCC ya guardó una decisión | `tccutil reset Camera <bundle.id>` |
| Accesibilidad activada pero sin efecto tras recompilar | La firma cambió | Quitar AirTrack de la lista (−), volver a añadirla, o `tccutil reset Accessibility <bundle.id>`; firmar siempre igual |
| `file` muestra x86_64 | Xcode corriendo bajo Rosetta o arquitectura forzada | Revisar Architectures = Standard y abrir Xcode sin Rosetta |

---

## Checklist de inicio de PHASE 1

- [ ] A: requisitos verificados con los comandos
- [ ] E: `swift test` con 0 fallos en tu Mac
- [ ] F + G: proyecto creado con AirTrackCore enlazado
- [ ] H + J: `NSCameraUsageDescription`, sandbox eliminado, Camera en Hardened Runtime si aplica
- [ ] L: `** BUILD SUCCEEDED **` y binario arm64
- [ ] Commit del proyecto vacío: `feat: add macOS app shell`
