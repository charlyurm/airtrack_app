# Permisos

> Estado: **documentado pero no implementado.** Todo este documento es REQUIRES MACOS.

## Cámara

- Clave `NSCameraUsageDescription` en Info.plist. Sin ella, macOS termina la app
  al acceder a la cámara.
- Consultar `AVCaptureDevice.authorizationStatus(for: .video)` y pedir el permiso
  con `AVCaptureDevice.requestAccess(for: .video)`.
- Si se deniega, mostrar "Camera: Permission Required" y un botón a
  Configuración del Sistema → Privacidad y seguridad → Cámara.
- Implementación única en `AirTrack/Permissions/CameraPermission.swift`
  (no existe ninguna duplicada en `Camera/`).

## Accesibilidad (generar eventos de entrada)

- Verificar con `AXIsProcessTrusted()` / `CGPreflightPostEventAccess()`.
- Pedir con `AXIsProcessTrustedWithOptions` (prompt) / `CGRequestPostEventAccess()`.
- La app **no puede concederse el permiso sola**: el usuario lo activa en
  Configuración del Sistema → Privacidad y seguridad → Accesibilidad.
- Texto obligatorio: "AirTrack necesita permiso de Accesibilidad para controlar el
  cursor y generar eventos de entrada."
- Nunca fallar en silencio: si falta el permiso, la UI lo muestra y no se envían eventos.

## Sandbox

**App Sandbox desactivado** durante el MVP (decisión aprobada). Por eso no hace
falta el entitlement `com.apple.security.device.camera`; basta con
`NSCameraUsageDescription`.

## Riesgo conocido en desarrollo

macOS asocia el permiso de Accesibilidad a la firma del binario. Si recompilas con
otra firma, el permiso puede invalidarse y hay que volver a activarlo. Conviene
firmar siempre con el mismo Team en Xcode.
