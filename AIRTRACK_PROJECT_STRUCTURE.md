# AIRTRACK — PROJECT STRUCTURE & ARCHITECTURE

**Version:** 0.2 — MVP Architecture (amended after the Phase 0 environment audit)  
**Platform:** macOS  
**Target:** Apple Silicon (arm64)  
**Language:** Swift  
**UI:** SwiftUI  
**Processing:** 100% local  
**Project type:** Native macOS application

---

## 1. PROJECT OBJECTIVE

AirTrack is a native macOS application that turns the user's hand, detected through the Mac camera, into a virtual trackpad.

The application must translate hand position and gestures into standard macOS pointer and interaction events.

### Core concept

```text
Mac Camera
    ↓
Hand Detection
    ↓
Hand Landmarks
    ↓
Gesture Engine
    ↓
Interaction Mapping
    ↓
macOS Mouse / Scroll Events
```

The goal is not to create a conventional "air mouse" only. The long-term goal is to reproduce useful trackpad interactions using hand gestures in the air.

---

# 2. MVP SCOPE

The first version must remain intentionally small.

### MVP gestures

| Gesture | Action |
|---|---|
| Index finger movement | Move cursor |
| Index + thumb pinch | Left click |
| Two quick pinches | Double click |
| Pinch held + index movement | Drag |
| Open hand + vertical movement | Scroll |
| Pause gesture / disabled state | Stop pointer control |

### MVP non-goals

Do NOT implement initially:

- Mission Control
- Spaces switching
- App switching
- Zoom
- Multi-hand interaction
- Voice commands
- Cloud AI
- Remote processing
- User accounts
- Backend
- Internet dependency
- Complex profiles
- iCloud synchronization

These belong to later phases.

---

# 3. DESIGN PRINCIPLES

## 3.1 Local first

Camera frames, hand landmarks and gesture interpretation must be processed locally.

The application must not upload camera frames or hand data to a remote server.

## 3.2 Low latency

The cursor must feel immediate.

Avoid architectures that introduce unnecessary network calls, LLM calls or heavyweight processing between hand movement and cursor movement.

## 3.3 Deterministic gesture recognition

Basic gestures should be detected using measurable geometric relationships and temporal thresholds rather than asking an AI model to interpret every frame.

Examples:

- Distance between thumb tip and index tip
- Finger extension state
- Hand velocity
- Gesture duration
- Direction of movement
- Time between gestures

## 3.4 Safety

The user must always be able to disable AirTrack quickly.

There must be a clear active/inactive state.

A keyboard shortcut must provide an emergency toggle.

## 3.5 Modular architecture

Camera capture, hand tracking, gesture recognition and macOS event generation must be independent modules.

---

# 4. RECOMMENDED PROJECT STRUCTURE

> **Amendment (approved after the Phase 0 audit):** all hardware-independent logic
> lives in the `AirTrackCore` Swift package, which does not import AppKit,
> AVFoundation, Vision or CoreGraphics and is tested without a camera (also on
> Linux). The macOS app consumes it as a local package. There is exactly ONE
> `CameraPermission.swift`, in `Permissions/`.

```text
AirTrack/
│
├── AirTrackCore/                      ← Swift Package, pure logic, no hardware
│   ├── Package.swift
│   ├── Sources/AirTrackCore/
│   │   ├── Models/        HandJoint (21) + HandSkeleton, HandState, InteractionAction,
│   │   │                  AirTrackSettings, KeyboardShortcut,
│   │   │                  LandmarkCoordinateConversion
│   │   ├── Geometry/      Point2D, Rect2D, PreviewGeometry
│   │   ├── Tracking/      HandValidation, HandPresenceFilter, HandOrdering
│   │   ├── Cursor/        CursorController, CursorControlState, DeadZoneFilter,
│   │   │                  CursorMapper, CursorSmoother, ScreenMapper
│   │   ├── Gestures/      HandScale, PinchRecognizer,
│   │   │                  GestureStateMachine, GestureEngine
│   │   └── Calibration/   ActiveAreaCalibration
│   └── Tests/AirTrackCoreTests/
│       ├── CursorMapperTests.swift
│       ├── ScreenMapperTests.swift
│       ├── CursorSmootherTests.swift
│       ├── PinchRecognizerTests.swift
│       ├── GestureStateMachineTests.swift
│       ├── GestureEngineTests.swift
│       ├── LandmarkCoordinateConversionTests.swift
│       ├── HandJointIdentityTests.swift
│       ├── PreviewGeometryTests.swift
│       ├── HandPresenceFilterTests.swift
│       ├── HandOrderingTests.swift
│       ├── CursorControllerTests.swift
│       └── DeadZoneFilterTests.swift
│
├── AirTrack/                          ← macOS app (Phase 1): hardware + UI only
│   ├── AirTrack.xcodeproj
│   ├── AirTrack.entitlements
│   └── AirTrack/                      ← folder-synchronized source root
│       ├── App/          AirTrackApp (+ AppDelegate), AppModel
│       ├── Camera/       CameraManager, CameraFrame, CameraStatus
│       ├── Vision/       VisionHandTrackingEngine, HandStateMapper, HandTrackingPipeline
│       ├── Events/       MacOSEventController      (Phase 2: mouse-moved only)
│       ├── Permissions/  CameraPermissionManager   (the ONLY camera-permission type),
│       │                 AccessibilityPermissionManager (Phase 2)
│       ├── UI/           ContentView, CameraPreviewView, HandDebugOverlay, TrackingStatusView
│       └── Utilities/    Logging, FrameRateCounter
│
│   Planned (not created yet): click/drag/scroll events (Phase 3–4), menu bar, settings
│   and calibration UI, global shortcut (Phase 5).
│
├── Documentation/
│   ├── ARCHITECTURE.md
│   ├── GESTURES.md
│   ├── PERMISSIONS.md
│   ├── TESTING.md
│   ├── ROADMAP.md
│   └── MACOS_SETUP.md
│
└── README.md
```

---

# 5. SYSTEM ARCHITECTURE

```text
                    ┌──────────────────┐
                    │   Mac Camera     │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │ CameraManager    │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │ HandTracking     │
                    │ Engine           │
                    └────────┬─────────┘
                             │
                       Landmarks
                             │
                             ▼
                    ┌──────────────────┐
                    │ Gesture Engine   │
                    └────────┬─────────┘
                             │
                  ┌──────────┼──────────┐
                  ▼          ▼          ▼
               Cursor      Click      Scroll
                  │          │          │
                  └──────────┼──────────┘
                             ▼
                    ┌──────────────────┐
                    │ macOS Event      │
                    │ Controller       │
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────┐
                    │     macOS        │
                    └──────────────────┘
```

---

# 6. MAIN COMPONENTS

## 6.1 CameraManager

Responsibilities:

- Request camera permission.
- Select appropriate camera.
- Start/stop capture.
- Deliver frames to the tracking engine.
- Avoid unnecessary frame copies.
- Handle camera errors.

The camera layer must not contain gesture logic.

---

## 6.2 HandTrackingEngine

Responsibilities:

- Receive camera frames.
- Detect a hand.
- Produce normalized landmarks.
- Maintain tracking state.
- Handle tracking loss.

The output should be independent of the camera implementation.

Example conceptual output:

```swift
HandState(
    isTracked: true,
    landmarks: [...],
    timestamp: ...
)
```

---

# 7. HAND LANDMARK MODEL

The system should work with normalized coordinates.

```text
x = 0.0 ... 1.0
y = 0.0 ... 1.0
z = relative depth
```

Important landmarks include:

```text
Wrist
Thumb Tip
Index MCP
Index PIP
Index DIP
Index Tip
Middle Tip
Ring Tip
Pinky Tip
```

The exact landmark provider may change during implementation. The rest of the application must not depend directly on a specific tracking library.

---

# 8. GESTURE ENGINE

The Gesture Engine converts raw landmarks into semantic gestures.

Example:

```text
Raw landmarks
      ↓
Distance calculations
      ↓
Finger state
      ↓
Velocity
      ↓
Temporal filtering
      ↓
Gesture state machine
      ↓
Semantic gesture
```

Possible semantic states:

```swift
enum Gesture {
    case idle
    case pointing
    case pinchStarted
    case pinchHeld
    case pinchReleased
    case doublePinch
    case scrolling
    case paused
}
```

The gesture engine must avoid generating multiple clicks from one physical pinch.

---

# 9. PINCH DETECTION

Basic pinch detection:

```text
distance(thumbTip, indexTip)
```

If distance falls below a configurable threshold:

```text
PINCH = TRUE
```

If it rises above the release threshold:

```text
PINCH = FALSE
```

Use hysteresis.

> **Amendment:** thresholds are NOT absolute image distances (an absolute 0.045
> changes meaning as the hand moves toward/away from the camera). The distance is
> aspect-corrected and divided by the hand reference length `wrist → indexMCP`:
>
> ```text
> pinchRatio = distance(thumbTip, indexTip) / distance(wrist, indexMCP)
> pinchStartRatio   = 0.25   (initial, uncalibrated)
> pinchReleaseRatio = 0.35   (initial, uncalibrated)
> ```
>
> Starts/releases also require 2 consecutive frames to reject one-frame spikes.
> Implemented in `AirTrackCore/Gestures/PinchRecognizer.swift`.

These are starting values only and must be calibrated experimentally.

Do not hard-code final thresholds without testing.

---

# 10. CLICK STATE MACHINE

The click system should distinguish:

```text
Pointing
   ↓
Pinch
   ↓
Pinch Released
   ↓
Click
```

Double click:

```text
Click
   ↓
Second pinch within time window
   ↓
Double Click
```

The system must expose configurable values for:

- pinch threshold
- release threshold
- maximum double-click interval
- minimum pinch duration

> **Amendment — click stabilization (approved):** closing the fingers drags the
> index tip, so the click must not land where the tip ends up. Approved machine:
>
> ```text
> POINTING → PINCH_START → CLICK_CANDIDATE ─release──────────→ CLICK
>                               │                                  (down+up at anchor)
>                               └─hold ≥ 0.3 s or move ≥ 3 %──→ DRAG ──release──→ RELEASE
> ```
>
> - The anchor is the cursor position ~70 ms before the pinch was confirmed.
> - The cursor is frozen at the anchor during CLICK_CANDIDATE, never during DRAG.
> - Nothing is sent to macOS until the gesture is resolved.
> - A held pinch always drags with clickCount 1: it is never a double click.
>
> Implemented in `AirTrackCore/Gestures/GestureStateMachine.swift`; details in
> `Documentation/GESTURES.md`.

---

# 11. CURSOR CONTROL

The index finger controls cursor position.

Conceptually:

```text
Index position
      ↓
Normalize
      ↓
Mirror camera coordinates
      ↓
Apply active area
      ↓
Map to screen coordinates
      ↓
Smooth
      ↓
Cursor
```

The system should support:

- sensitivity
- acceleration
- smoothing
- dead zone
- screen bounds

The user should not need to move their hand across the entire camera frame to move the cursor across the entire screen.

---

# 12. CURSOR SMOOTHING

Raw hand tracking will contain noise.

Implement smoothing without introducing excessive latency.

Possible first implementation:

```text
smoothed = previous * alpha + current * (1 - alpha)
```

The smoothing coefficient must be configurable.

The objective is:

```text
Less jitter
+
Low latency
=
Natural cursor
```

Do not over-smooth.

---

# 13. DRAG

Drag behavior:

```text
Pinch begins
      ↓
Mouse Down
      ↓
Pinch remains held
      ↓
Index moves
      ↓
Cursor moves
      ↓
Pinch released
      ↓
Mouse Up
```

The system must prevent accidental drag initiation.

> **Amendment — drag continuity (approved):** mouseDown is sent at the click anchor
> and the drag continues with a cursor–finger offset, so entering a drag never
> moves the cursor:
>
> ```text
> offset = anchor − finger (at drag start)
> cursor = clamp(finger + offset)
> ```
>
> After release the offset fades linearly to zero over 200 ms instead of snapping.
> Details in `Documentation/GESTURES.md`.

---

# 14. SCROLL

For MVP, scroll should use an open-hand state.

Example:

```text
Open hand detected
      ↓
Measure palm / wrist vertical velocity
      ↓
Apply threshold
      ↓
Generate scroll event
```

Scroll must include:

- dead zone
- direction
- sensitivity
- smoothing

Small involuntary hand movements should not cause scrolling.

---

# 15. PAUSE / SAFETY

AirTrack must have a reliable way to stop interaction.

Minimum requirements:

### Keyboard shortcut

> **Amendment:** ⌘ + Shift + A is rejected (Finder: "Go to Applications").
> The shortcut is the configurable setting `emergencyToggleShortcut`, default
> `⌃ + ⌥ + ⌘ + A`. Absence of conflicts must be verified on a real Mac.

This shortcut toggles:

```text
ACTIVE
INACTIVE
```

### Menu bar indicator

```text
● AirTrack Active
```

or

```text
○ AirTrack Paused
```

When paused:

- No cursor movement.
- No click events.
- No scroll events.
- Camera processing may continue if needed for fast resume.

---

# 16. PERMISSIONS

The application will likely require:

### Camera permission

Required to access the Mac camera.

### Accessibility permission

Required to generate/control certain macOS input events.

The app must:

1. Detect missing permissions.
2. Explain why they are required.
3. Provide a button to open the relevant macOS settings.
4. Never silently fail.

> **Amendment:** App Sandbox is disabled for the MVP (posting CGEvents from a
> sandboxed app is not viable). Distribution, notarization and the Mac App Store
> are out of MVP scope.

---

# 17. UI ARCHITECTURE

AirTrack should initially run primarily as a menu-bar application.

Menu:

```text
AirTrack

Status: ● Active

──────────────

Cursor       ✓
Click        ✓
Drag         ✓
Scroll       ✓

──────────────

Sensitivity
    ━━━━━●━━

Smoothing
    ━━━●━━━━

──────────────

Calibrate...

Settings...

Quit AirTrack
```

Do not build a large main window for MVP.

---

# 18. CALIBRATION

Calibration will eventually allow the user to configure:

- camera position
- active tracking area
- cursor sensitivity
- smoothing
- pinch threshold
- scroll sensitivity

Initial calibration can be simple.

Example:

```text
1. Place hand in center.
2. Move index to top-left.
3. Move index to bottom-right.
4. Confirm.
```

Calibration data should be stored locally.

---

# 19. SETTINGS STORAGE

Use a native macOS mechanism such as `UserDefaults` for MVP settings.

Possible settings:

```swift
struct AirTrackSettings {
    var cursorSensitivity: Double
    var cursorSmoothing: Double
    var scrollSensitivity: Double
    var pinchThreshold: Double
    var pinchReleaseThreshold: Double
    var doubleClickInterval: Double
    var enabledGestures: Set<Gesture>
}
```

Avoid introducing a database.

---

# 20. TESTING STRATEGY

The project must separate testable mathematics from hardware-dependent behavior.

### Unit-test

Test:

- coordinate mapping
- cursor bounds
- smoothing
- pinch distance
- gesture state transitions
- double-click timing
- scroll direction
- calibration math

### Hardware test

Manually verify:

- camera capture
- hand tracking
- cursor movement
- click
- double click
- drag
- scroll
- permission flow
- emergency pause

---

# 21. PERFORMANCE REQUIREMENTS

Target:

- responsive cursor
- minimal perceived latency
- stable tracking
- no unnecessary CPU usage
- no unnecessary camera processing when disabled

Performance must be measured rather than assumed.

Log useful diagnostics during development:

```text
FPS
Tracking latency
Gesture latency
Dropped frames
CPU usage
```

Diagnostics should be disableable in production.

---

# 22. PRIVACY

AirTrack must process camera data locally.

No:

- cloud image uploads
- remote vision APIs
- analytics containing camera data
- storage of camera frames by default

Camera frames should exist only as long as necessary for processing.

---

# 23. DEVELOPMENT PHASES

> **Amendment (Phase 1):** Camera and Hand tracking were merged into Phase 1, because
> the camera cannot be validated without landmarks. This numbering is the official one
> and supersedes both the master prompt's and v0.2's. Live status: `Documentation/ROADMAP.md`.

## Phase 0 — Core + Architecture

- Create `AirTrackCore` (pure logic) with unit tests passing.
- Establish folder structure, permissions plan and documentation.

## Phase 1 — macOS Foundation + Camera + Vision Hand Tracking

- Native macOS app consuming AirTrackCore.
- Camera permission, capture, frame pipeline.
- Vision hand pose → HandState.
- Preview + landmark debug overlay.
- Tracking loss/recovery, FPS and latency metrics.

## Phase 2 — Cursor Control

- Index tracking.
- Coordinate mapping.
- Smoothing.
- macOS cursor movement (Accessibility).
- Emergency pause.

## Phase 3 — Click / Double Click / Drag

- Pinch detection.
- Click.
- Double click.
- Drag.

## Phase 4 — Scroll

- Open-hand detection.
- Vertical movement.
- Scroll events.
- Sensitivity.

## Phase 5 — Menu Bar / Settings / Calibration

- Menu bar app.
- Settings.
- Calibration.
- Permission onboarding.
- Status indicators.

## Phase 6 — Optimization

- Latency.
- CPU usage.
- Tracking stability.
- False gesture reduction.

## Phase 7+ — Advanced trackpad gestures

Only after MVP is stable:

- horizontal swipe
- Spaces
- Mission Control
- app switching
- zoom
- multi-finger gestures
- custom gestures

---

# 24. FUTURE GESTURE SYSTEM

Long term, gestures should be configurable.

Example:

```text
Gesture:
Two-finger horizontal swipe

Action:
Next Space
```

or:

```text
Gesture:
Thumb + middle finger pinch

Action:
Right Click
```

The architecture should allow adding these without rewriting the cursor engine.

---

# 25. RULES FOR CLAUDE CODE

Claude Code must follow these rules:

1. Work only inside the AirTrack project.
2. Do not modify unrelated projects.
3. Do not modify ALHEN OS.
4. Do not modify AirCard.
5. Do not delete user files.
6. Do not install unnecessary dependencies.
7. Prefer Apple-native frameworks.
8. Keep the application local-first.
9. Do not add cloud services unless explicitly requested.
10. Do not add AI APIs for basic gesture recognition.
11. Compile after meaningful changes.
12. Fix build errors before moving to the next phase.
13. Keep documentation updated.
14. Do not implement future phases prematurely.
15. Explain architectural decisions before introducing major dependencies.

---

# 26. DEFINITION OF DONE — MVP

The MVP is considered functional when a user can:

1. Launch AirTrack.
2. Grant camera permission.
3. Grant Accessibility permission.
4. Activate AirTrack.
5. Point the index finger at the camera.
6. Move the macOS cursor naturally.
7. Pinch index + thumb to click.
8. Perform two pinches to double-click.
9. Hold the pinch and move to drag.
10. Open the hand and move vertically to scroll.
11. Pause AirTrack instantly.
12. Resume AirTrack instantly.
13. Quit the application without leaving background processes unexpectedly.

The experience should feel responsive enough to be usable before advanced gestures are added.

---

# 27. FIRST IMPLEMENTATION PRINCIPLE

Do not attempt to build the entire application in one step.

Recommended implementation order:

```text
BUILD
  ↓
RUN
  ↓
TEST
  ↓
FIX
  ↓
DOCUMENT
  ↓
NEXT COMPONENT
```

The first objective is not feature quantity.

The first objective is:

> **Make the index finger move the Mac cursor reliably and with low latency.**

Once that works, build gestures on top of it.

---

# 28. PRODUCT VISION

AirTrack should eventually feel like:

> "I don't need to touch a trackpad. My hand IS the trackpad."

The interaction should be:

- natural
- fast
- predictable
- configurable
- private
- local
- low latency

The software should disappear into the interaction rather than making the user think about the technology.
