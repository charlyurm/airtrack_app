# Permisos

## Cámara (PHASE 1: implementado, DEFERRED TO LOCAL MAC VALIDATION)

Configuración del proyecto:
- `NSCameraUsageDescription` (build setting `INFOPLIST_KEY_NSCameraUsageDescription`):
  *"AirTrack necesita la cámara para detectar los movimientos de tu mano. Las imágenes se
  procesan solo en este Mac y nunca se guardan ni se envían."*
- Entitlement `com.apple.security.device.camera` (`AirTrack/AirTrack.entitlements`).
  Es obligatorio cuando el Hardened Runtime está activo; sin él, la captura falla aunque
  el usuario haya concedido el permiso. Con la firma por defecto ("Sign to Run Locally",
  ad-hoc) Xcode desactiva el Hardened Runtime, así que solo importa al firmar con un Team.
- **App Sandbox desactivado** (decisión del MVP).

Flujo (`Permissions/CameraPermissionManager.swift` + `App/AppModel.swift`):

| Estado del sistema | Comportamiento |
|---|---|
| `notDetermined` | Al abrir la app se muestra el diálogo del sistema |
| `authorized` | Se arranca la cámara por defecto |
| `denied` / `restricted` | `Camera: PERMISSION REQUIRED`, explicación, botón "Abrir Configuración del Sistema" (Privacidad y seguridad → Cámara) y "Reintentar". Sin crash ni bucles de solicitud |

`CameraManager.start` vuelve a comprobar el permiso antes de configurar la sesión.

Para repetir el flujo desde cero en desarrollo:
`tccutil reset Camera com.airtrack.AirTrack`

## Accesibilidad (PHASE 2: no implementado)

- Se verificará con `AXIsProcessTrusted()` / `CGPreflightPostEventAccess()` y se pedirá
  con `AXIsProcessTrustedWithOptions` / `CGRequestPostEventAccess()`.
- La app no puede concederse el permiso sola: el usuario lo activa en Configuración del
  Sistema → Privacidad y seguridad → Accesibilidad.
- Texto obligatorio: "AirTrack necesita permiso de Accesibilidad para controlar el
  cursor y generar eventos de entrada."
- Nunca fallar en silencio: si falta el permiso, la UI lo mostrará y no se enviarán eventos.

## Riesgo conocido en desarrollo

macOS asocia los permisos a la firma del binario. Con "Sign to Run Locally" la firma
puede cambiar entre builds y macOS puede volver a pedir el permiso o dejar de reconocer
la app. Si pasa: `tccutil reset Camera com.airtrack.AirTrack`, o firmar siempre con el
mismo Team.
