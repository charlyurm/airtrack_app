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

## Accesibilidad (PHASE 2: implementado, DEFERRED TO LOCAL MAC VALIDATION)

Necesaria para mover el cursor (publicar `CGEvent`). `Permissions/AccessibilityPermissionManager.swift`
(sistema) + `AccessibilityPermissionTracker` (AirTrackCore, transiciones con tests):
- Comprobación (hotfix 2.1): `AXIsProcessTrusted() || CGPreflightPostEventAccess()` sobre el
  proceso que se está ejecutando. Se consulta al arrancar, **al volver a AirTrack**
  (`NSApplication.didBecomeActiveNotification`), al pulsar un botón del permiso y, con Cursor
  Control activado, como máximo una vez por segundo (para detectar una revocación).
- Solicitud: `AXIsProcessTrustedWithOptions` con prompt, **solo al pulsar "Conceder permiso"** y
  como máximo una vez por sesión; después, el botón abre Configuración del Sistema →
  Privacidad y seguridad → Accesibilidad. Nunca se pide en bucle.
- Sin permiso: `Permission: REQUIRED`, `Cursor: WAITING FOR PERMISSION`, no se publica ningún evento.
- Reiniciar el flujo: `tccutil reset Accessibility com.airtrack.AirTrack` **y**
  `tccutil reset PostEvent com.airtrack.AirTrack` (ver el troubleshooting).
- La app no puede concederse el permiso sola: el usuario lo activa en Configuración del
  Sistema → Privacidad y seguridad → Accesibilidad.
- Texto obligatorio: "AirTrack necesita permiso de Accesibilidad para controlar el
  cursor y generar eventos de entrada."
- Nunca fallar en silencio: si falta el permiso, la UI lo mostrará y no se enviarán eventos.

## ACCESSIBILITY PERMISSION TROUBLESHOOTING

### Cómo funciona la detección

| Pregunta a macOS | Servicio TCC | Qué lo concede |
|---|---|---|
| `AXIsProcessTrusted()` | Accessibility | Activar AirTrack en la lista, añadirlo con "+", el prompt de `AXIsProcessTrustedWithOptions` |
| `CGPreflightPostEventAccess()` | PostEvent | El prompt de `CGRequestPostEventAccess` (lo que usaba PHASE 2) |

Los dos aparecen en la misma lista (Privacidad y seguridad → Accesibilidad) y cualquiera de
los dos basta para mover el cursor. AirTrack considera el permiso concedido si **alguno** es
"sí". Las dos respuestas son para **el binario firmado que se está ejecutando**, no para "la
app llamada AirTrack".

Cuándo pregunta AirTrack (`AccessibilityPermissionTracker`):

| Momento | Consulta |
|---|---|
| Arranque | Siempre. Si ya hay permiso, nunca muestra WAITING FOR PERMISSION |
| Volver a AirTrack (desde Configuración del Sistema u otra app) | Siempre, al instante |
| "Cursor Control", "Conceder permiso", "Comprobar de nuevo" | Siempre |
| Con Cursor Control activado | Como máximo 1 vez por segundo (revocación en caliente) |

### Qué hace AirTrack cuando cambia

- **Concedido:** `WAITING FOR PERMISSION` → `WAITING FOR HAND` → `ACTIVE` cuando hay mano.
- **Revocado:** en ≤ 1 s (con Cursor Control activado), o al volver a la app, pasa a
  `WAITING FOR PERMISSION` y deja de publicar eventos.
- El prompt del sistema se muestra como mucho una vez por sesión. Después, el botón abre
  Configuración del Sistema.

### Causa raíz de "Configuración del Sistema dice permitido, AirTrack dice que no"

1. **Firma ad-hoc (la causa principal).** El proyecto firma con "Sign to Run Locally"
   (`CODE_SIGN_IDENTITY = "-"`, sin equipo). Con firma ad-hoc, la identidad que TCC guarda al
   conceder el permiso es el **hash de ese binario concreto (cdhash)**, y cambia en cada
   recompilación (cada `git pull` + ⌘R). La entrada "AirTrack" sigue activada en la lista,
   pero pertenece a un build anterior y no aplica al proceso actual. Apagar y encender el
   interruptor no la actualiza: hay que **quitarla ("−")** y volver a pedir el permiso desde el
   build actual.
2. **Servicio distinto (PHASE 2).** AirTrack solo preguntaba por PostEvent. Un permiso
   añadido a mano con "+", o recreado tras `tccutil reset Accessibility`, es del servicio
   Accessibility, y ese comando **no borra** PostEvent. Resultado: la lista decía "permitido"
   y AirTrack seguía en WAITING FOR PERMISSION. Corregido: ahora cuentan los dos servicios.
3. **Sin re-comprobación al volver a la app (PHASE 2).** El estado solo se refrescaba con
   Cursor Control activado y la cámara en marcha. Corregido: se comprueba al volver a la app.

### Qué hacer si la lista dice permitido y AirTrack dice que no

1. En AirTrack, abre **Diagnóstico de Accesibilidad** (sección Cursor):
   - `AX trusted: no` y `Post events: no` → macOS no reconoce **este** binario.
   - `Firma: ad-hoc` → la causa 1 es la más probable.
   - Ruta del ejecutable → el build que se está ejecutando (normalmente `~/Library/Developer/Xcode/DerivedData/AirTrack-…/Build/Products/Debug/AirTrack.app`).
2. Cierra AirTrack. En Configuración del Sistema → Privacidad y seguridad → Accesibilidad,
   selecciona **todas** las entradas "AirTrack" y quítalas con **"−"** (no basta con apagarlas).
3. Limpia los dos servicios:
   ```bash
   tccutil reset Accessibility com.airtrack.AirTrack
   tccutil reset PostEvent com.airtrack.AirTrack
   ```
4. Ejecuta AirTrack desde Xcode (⌘R), activa Cursor Control y pulsa **Conceder permiso**. En el
   diálogo, abre Configuración y activa la entrada que aparece. **No** añadas la app a mano con
   "+" desde otra carpeta: podrías autorizar un binario distinto del que ejecuta Xcode.
5. Vuelve a AirTrack: el estado cambia solo, sin reiniciar la app ni el Mac.

### Cómo identificar el binario o la firma incorrectos

```bash
# Ruta: cópiala del panel (Diagnóstico de Accesibilidad)
codesign -dv --verbose=4 "<ruta>/AirTrack.app" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier|CDHash"
```

- `Signature=adhoc` y `TeamIdentifier=not set` → firma ad-hoc: el permiso muere en cada build.
- Un `CDHash` distinto entre dos builds confirma que para macOS son apps distintas.
- Logs: `log stream --predicate 'subsystem == "com.airtrack.AirTrack" AND category == "permissions"' --level info`
  muestra en cada comprobación (arranque, volver a la app, botones) `AX trusted`, `post events`,
  bundle ID y firma. La ruta del ejecutable aparece como `<private>` en el log.

**Solución permanente (recomendada):** firmar con tu **Personal Team** (Apple ID gratuito):
target AirTrack → Signing & Capabilities → Team → tu nombre (Personal Team). Con una firma
de equipo, la identidad es estable entre builds y el permiso se concede **una sola vez**.
Después de cambiar la firma, repite los pasos 2–5 una vez.

### Limitaciones conocidas

- Con firma ad-hoc, **cada** recompilación puede requerir quitar la entrada y volver a
  concederla. AirTrack no puede evitarlo: es cómo TCC identifica el código. Lo resuelve firmar
  con un equipo, que requiere tu Apple ID en Xcode.
- AirTrack no puede concederse el permiso ni borrar entradas de la lista.
- Una revocación con AirTrack en segundo plano y Cursor Control apagado se detecta al volver
  a la app, no antes.
- El resultado real de TCC solo se puede comprobar en un Mac. Los tests cubren las
  transiciones, no la API del sistema.

## Riesgo conocido en desarrollo

macOS asocia los permisos a la firma del binario. Con "Sign to Run Locally" la firma
puede cambiar entre builds y macOS puede volver a pedir el permiso o dejar de reconocer
la app. Si pasa: `tccutil reset Camera com.airtrack.AirTrack`, o firmar siempre con el
mismo Team.
