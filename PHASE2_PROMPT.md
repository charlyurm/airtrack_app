# AIRTRACK — PHASE 2 MASTER PROMPT
## Cursor Control

**Status:** READY FOR IMPLEMENTATION  
**Phase:** 2 — Cursor Control  
**Workflow:** Claude Code Cloud → GitHub → local Mac validation

> **IMPORTANT:** Phase 2 is only `INDEX FINGER → CURSOR`. Do not implement click, pinch, double click, drag, scroll, or other gestures.

---

# 1. MISSION

Implement **PHASE 2 — CURSOR CONTROL** for AirTrack.

Phase 0, Phase 1 and Phase 1.1 are complete and were validated on a real Apple Silicon Mac.

The hand-tracking pipeline is now considered a stable input source.

The objective of this phase is:

```text
INDEX FINGER → CONTROL macOS CURSOR
```

Do NOT implement:

- pinch
- click
- double click
- drag
- scroll
- right click
- two-finger gestures
- swipe
- Mission Control
- Spaces
- zoom
- custom gestures

This phase establishes a high-quality cursor-control layer that later gesture phases can safely build on.

---

# 2. VERIFIED BASELINE

Phase 1.1 was physically validated on the user's Mac.

Verified:

- Camera works
- Vision works
- ~30 FPS camera
- ~30 FPS Vision
- ~11 ms Vision processing observed
- ~46 ms Capture → HandState observed
- Camera drops: 0
- Superseded frames behave as expected
- Landmark identity is correct
- All five fingers are correctly mapped
- Vertical coordinates are correct
- Distance changes do not cause landmark drift
- Two-hand detection works
- Tracking LOST works
- Tracking recovery works
- Invalid tracking filtering works

Current repository includes:

- AirTrackCore
- HandState
- HandJoint
- coordinate conversion
- PreviewGeometry
- HandPresenceFilter
- HandOrdering
- Vision tracking
- SwiftUI debug overlay
- macOS camera pipeline
- existing test suite
- macOS CI

Phase 1.1 commits:

```text
4b117fc fix: stabilize hand tracking and coordinate conversion
70b8404 docs: document Phase 1.1 root cause, coordinate conventions and Mac validation
```

Do not regress Phase 1 or Phase 1.1 behavior.

---

# 3. DEVELOPMENT ENVIRONMENT

You are working in Claude Code Cloud on Linux/x86_64.

You do NOT have:

- macOS runtime
- Xcode GUI
- physical Mac
- Mac camera
- physical display
- real cursor interaction

The user uses the physical Apple Silicon Mac for runtime validation.

Therefore:

**DO NOT CLAIM TO HAVE TESTED REAL CURSOR MOVEMENT.**

You may:

- inspect the code
- implement the architecture
- write deterministic tests
- run Linux tests where possible
- use GitHub Actions/macOS CI
- build the macOS target in CI
- reason about macOS APIs
- document exact local validation steps

---

# 4. PHASE 2 SCOPE

Implement only:

1. Cursor mapping
2. Cursor smoothing
3. Active area
4. Sensitivity
5. Dead zone / stabilization
6. Screen bounds
7. Edge handling
8. Tracking-loss safety
9. Cursor enable/disable state
10. Pause/resume behavior if required
11. macOS cursor event integration
12. Debug metrics/UI required to validate cursor behavior
13. Automated tests
14. Documentation

Do NOT implement any future gesture behavior.

---

# 5. ARCHITECTURAL PRINCIPLE

Do NOT simply do:

```text
camera X/Y → mouse X/Y
```

Raw finger position should be transformed into a controlled cursor position.

Desired pipeline:

```text
Vision
  ↓
HandState
  ↓
primary hand selection
  ↓
indexTip
  ↓
active-area normalization
  ↓
dead-zone / stabilization
  ↓
sensitivity
  ↓
screen mapping
  ↓
smoothing
  ↓
cursor controller
  ↓
MacOSEventController
  ↓
macOS cursor
```

Keep pure mathematics in `AirTrackCore`.

Keep macOS-specific APIs outside `AirTrackCore`.

---

# 6. STEP 1 — AUDIT CURRENT CODE

Before modifying anything:

Inspect the existing architecture.

Identify:

- current `HandState`
- current primary-hand logic
- existing `CursorMapper`
- existing `CursorSmoother`
- existing `ScreenMapper`
- existing `AirTrackSettings`
- existing macOS event abstractions
- existing phase roadmap
- existing test coverage
- current app state architecture
- current permission architecture

Do NOT create duplicate abstractions if an appropriate one already exists.

Reuse existing Core components when correct.

If an existing component is insufficient, improve it rather than creating unnecessary parallel implementations.

---

# 7. STEP 2 — DEFINE CURSOR COORDINATE MODEL

Current `HandState` coordinate convention:

- normalized 0...1
- origin top-left
- X increases to the right
- Y increases downward
- no mirror in `HandState`

Use this convention consistently.

Convert:

```text
indexTip.x
indexTip.y
```

into:

```text
screenX
screenY
```

without accidental Y inversion.

Explicitly document the transformation.

---

# 8. STEP 3 — ACTIVE AREA

Implement a configurable active area.

The user should not need to reach the extreme edges of the camera image to reach the extreme edges of the display.

Conceptually:

```text
camera active area:

xMin ... xMax
yMin ... yMax
```

Inside this area:

```text
xMin → screen left
xMax → screen right
yMin → screen top
yMax → screen bottom
```

Clamp input outside the active area.

Do NOT use undocumented arbitrary constants.

Prefer configuration through `AirTrackSettings`.

Initial values may be conservative and easy to tune.

Suggested initial range:

```text
horizontal: ~0.15 → ~0.85
vertical:   ~0.15 → ~0.85
```

These are initial values only and must be easy to change.

Add deterministic tests for:

- center
- left edge
- right edge
- top edge
- bottom edge
- corners
- outside active area
- clamping

---

# 9. STEP 4 — SCREEN MAPPING

Create or improve `ScreenMapper`.

Input:

```text
Point2D normalized 0...1
```

Output:

```text
screen coordinate in active display coordinate space
```

Handle:

- screen origin
- screen size
- Retina scaling correctly
- screen bounds

Do NOT hard-code display sizes such as:

```text
1920x1080
2560x1440
```

Use actual display bounds supplied by macOS.

Pure Core mapping should operate on abstract `Rect2D`.

macOS layer obtains actual screen bounds.

Do not over-engineer multi-monitor support in this phase.

If multiple displays exist, Phase 2 may initially target the main display.

Document this limitation.

Add tests for arbitrary screen sizes.

---

# 10. STEP 5 — CURSOR SMOOTHING

Raw Vision movement must NOT directly control the cursor.

Implement or improve the existing `CursorSmoother`.

Requirements:

- low jitter when finger is stationary
- responsive movement
- no excessive lag
- predictable behavior
- deterministic tests

Audit the existing smoother first.

If it is already correct, reuse it.

If it needs improvement, modify it.

Avoid excessive smoothing.

Goal:

```text
stable when still
+
responsive when moving
```

Do not introduce a large artificial delay.

If using EMA or another filter, expose parameters in a testable/configurable way.

---

# 11. STEP 6 — DEAD ZONE / MICRO-MOVEMENT

The finger naturally produces tiny movements.

The cursor should not visibly jitter when the user is trying to keep the finger still.

Implement a small stabilization/dead-zone strategy.

Requirements:

- tiny movements below threshold should not cause visible cursor jitter
- larger intentional movement must pass through
- threshold should be configurable
- behavior must be deterministic

Do NOT create a large dead zone that makes the cursor feel stuck.

Add tests.

---

# 12. STEP 7 — SENSITIVITY

Cursor movement must be tunable.

Create a sensitivity parameter.

Do not hard-code sensitivity inside the cursor controller.

`AirTrackSettings` should own user-tunable cursor settings.

At minimum consider:

- sensitivity
- smoothing
- active area
- dead zone

Use sensible defaults.

Document them.

Do not build a full Settings UI yet unless required for testing.

A debug UI control is acceptable if it materially helps local validation, but avoid scope expansion.

---

# 13. STEP 8 — CURSOR CONTROLLER

Create or improve a dedicated `CursorController`.

Responsibilities:

- receive valid `HandState`
- extract primary-hand `indexTip`
- map it to screen coordinates
- smooth/stabilize
- emit cursor position

It must NOT know about:

- Vision
- AVCapture
- camera frames
- gesture recognition

It should operate on already validated `HandState` data.

Keep it testable.

Conceptually:

```text
HandState
    ↓
CursorController
    ↓
CursorPosition
```

---

# 14. STEP 9 — macOS CURSOR EVENT LAYER

Create or improve a macOS-specific abstraction for moving the cursor.

For example:

```text
MacOSEventController
```

or an equivalent existing abstraction.

`AirTrackCore` must NOT import AppKit or CoreGraphics.

The macOS layer may use appropriate macOS APIs such as `CGEvent` where required.

For this phase we only need:

```text
MOVE CURSOR
```

Do not implement:

- click
- mouseDown
- mouseUp
- drag

---

# 15. STEP 10 — ACCESSIBILITY / INPUT PERMISSION

Review the existing permissions architecture.

Cursor movement may require appropriate macOS input-control permission.

The app should:

- detect missing permission
- explain what is required
- provide a clear path to System Settings if already supported
- fail safely if permission is absent
- avoid repeatedly requesting permission

Do not break existing camera permission behavior.

---

# 16. STEP 11 — TRACKING LOSS SAFETY

This is critical.

If the hand disappears:

- stop updating the cursor immediately
- do not use stale `indexTip` coordinates
- do not continue moving from the last known hand
- do not generate synthetic positions

When tracking returns:

- resume cursor control from the new valid position
- avoid a large unexpected cursor jump

A reasonable approach is to establish a new cursor reference on reacquisition rather than jumping from stale state.

Add deterministic tests.

---

# 17. STEP 12 — PRIMARY HAND

Phase 1.1 supports two hands.

Phase 2 uses:

```text
PRIMARY HAND ONLY
```

Reuse the current deterministic primary-hand ordering.

The secondary hand must not move the cursor.

Do not implement two-handed cursor control.

Document this clearly.

---

# 18. STEP 13 — CURSOR ACTIVATION

The application should have a clear state indicating whether cursor control is active.

Do not make cursor movement start accidentally merely because a hand is detected.

Use existing app-state architecture where possible.

If needed, implement simple states such as:

```text
disabled
waiting for permission
waiting for hand
active
paused
```

Do not overbuild a state machine unnecessarily.

---

# 19. STEP 14 — SAFETY / FAILSAFE

Cursor control must fail safely.

If any of these occur:

- camera stops
- Vision stops
- tracking lost
- permission revoked
- app paused
- cursor controller disabled

then:

```text
STOP CURSOR UPDATES
```

Never continue using stale hand coordinates.

The app must never move the cursor indefinitely after input tracking disappears.

Add deterministic tests wherever possible.

---

# 20. STEP 15 — MULTI-DISPLAY

Do not implement full multi-monitor navigation yet.

However:

- do not hard-code screen size
- use current display bounds
- keep architecture extensible

If the user has multiple displays, Phase 2 may initially target the main display.

Document this limitation.

---

# 21. STEP 16 — DEBUG UI

Update the debug UI so the user can understand cursor mapping during local testing.

At minimum show:

```text
Cursor Control: ON / OFF

Primary hand: 1 / 2

Index tip: x, y

Mapped cursor: x, y

Active area: x / y ranges

Smoothing: value

Sensitivity: value

Tracking: HAND DETECTED / LOST

Permission: READY / REQUIRED
```

Do not clutter the interface unnecessarily.

The debug UI exists to make real Mac validation easy.

---

# 22. STEP 17 — TEST ARCHITECTURE

All cursor mathematics must be testable without macOS.

Use synthetic:

- `Point2D`
- `Rect2D`
- `HandState`
- cursor settings

Tests must NOT require:

- camera
- Vision
- physical mouse
- physical display
- macOS runtime

Required tests:

## CursorMapper

- center → screen center
- left edge
- right edge
- top edge
- bottom edge
- corners
- outside active area
- clamping
- arbitrary screen sizes
- Y direction

## CursorSmoother

- stationary input remains stable
- small jitter is reduced
- intentional movement passes through
- deterministic behavior
- no unexpected overshoot
- reset behavior

## Dead zone

- below threshold
- exactly threshold
- above threshold
- stationary finger
- intentional movement

## CursorController

- valid primary hand moves cursor
- missing hand stops updates
- invalid `HandState` stops updates
- tracking loss stops updates
- recovery establishes valid reference
- secondary hand does not control cursor
- disabled controller emits no movement

## Settings

- default settings
- custom sensitivity
- custom smoothing
- custom active area
- custom dead zone

## Screen mapping

- arbitrary screen rectangle
- Retina-independent logical coordinate mapping
- clamping

---

# 23. STEP 18 — PERFORMANCE

Do not introduce unnecessary processing.

Cursor control should operate comfortably within the existing ~30 FPS Vision pipeline.

Avoid:

- blocking Vision
- synchronous expensive work on main
- queues that accumulate
- unnecessary per-frame allocations
- timers competing with Vision

Prefer:

```text
Vision output
→ cursor calculation
→ main/UI/event update
```

The cursor path should be lightweight.

---

# 24. STEP 19 — REAL MAC VALIDATION PLAN

After implementation, the user will build and test on the physical Apple Silicon Mac.

Prepare the application for this exact validation.

## TEST A — Permission

Verify cursor/input permission.

Expected:

- app clearly indicates permission status
- no crash
- no endless permission request loop

## TEST B — Center

Place index finger at center of active area.

Expected:

Cursor approximately at screen center.

## TEST C — Horizontal

Move index:

```text
left → center → right
```

Expected:

- cursor follows correctly
- no inversion

## TEST D — Vertical

Move index:

```text
top → center → bottom
```

Expected:

- cursor follows correctly
- no inversion

## TEST E — Corners

Move index toward:

```text
top-left
top-right
bottom-left
bottom-right
```

Expected:

Cursor reaches corresponding screen regions.

## TEST F — Small movement

Hold finger still.

Expected:

Minimal cursor jitter.

## TEST G — Fast movement

Move finger quickly.

Expected:

Cursor remains responsive.

No excessive lag.

## TEST H — Distance

Move hand closer/farther.

Expected:

Cursor behavior remains stable because normalized `HandState` coordinates are already camera-independent.

## TEST I — Tracking loss

Remove hand.

Expected:

Cursor stops immediately.

No continued motion.

## TEST J — Recovery

Return hand.

Expected:

Cursor resumes without a large unexpected jump.

## TEST K — Two hands

Use two hands.

Expected:

Only primary hand controls cursor.

Secondary hand does not move cursor.

## TEST L — Active area

Move index beyond active-area boundaries.

Expected:

Cursor clamps to screen edge.

---

# 25. UX GOAL

Do not optimize only for mathematical correctness.

The real goal is:

**NATURAL CURSOR CONTROL**

The user should be able to evaluate whether:

- small finger movements are controllable
- cursor is not shaking
- cursor does not feel delayed
- screen edges are reachable
- cursor does not jump
- tracking loss is safe
- system feels predictable

Do not invent subjective claims.

The user evaluates physical feel on the Mac.

---

# 26. DO NOT ADD CLICK

This is mandatory.

Phase 2 ends at:

```text
INDEX FINGER → CURSOR
```

Do NOT implement:

- pinch
- click
- double click
- drag
- scroll

Those belong to later phases.

Architecture must allow Phase 3 to add pinch/click without rewriting `CursorController`.

---

# 27. DOCUMENTATION

Create:

```text
PHASE2_RESULT.md
```

Document:

1. Architecture
2. Cursor coordinate model
3. Active area
4. Sensitivity
5. Dead zone
6. Smoothing
7. CursorController
8. macOS event layer
9. Permission requirements
10. Tracking-loss behavior
11. Primary-hand behavior
12. Multi-display limitation
13. Tests
14. CI/build results
15. Local Mac validation procedure
16. Known limitations

Update:

- `ROADMAP`
- `ARCHITECTURE`
- `TESTING`
- `MACOS_SETUP`
- `README`

Do not mark Phase 2 complete before physical Mac validation.

---

# 28. GIT

Before changes:

```bash
git status
git log --oneline -5
```

Verify the repository is clean.

After implementation:

- run all tests
- build macOS target in CI if available
- inspect `git diff`
- ensure no unrelated changes
- commit
- push

Suggested commit:

```text
feat: implement phase 2 cursor control
```

If multiple logically separate commits are preferable, that is acceptable, but keep history clear.

---

# 29. ACCEPTANCE CRITERIA

Phase 2 implementation is ready for local validation only if:

- [ ] Index finger controls cursor.
- [ ] Cursor mapping is mathematically correct.
- [ ] Y direction is correct.
- [ ] Active area exists.
- [ ] Active area is configurable.
- [ ] Cursor clamps to screen bounds.
- [ ] Sensitivity is configurable.
- [ ] Smoothing is configurable.
- [ ] Dead zone/stabilization exists.
- [ ] Cursor does not jitter excessively in synthetic tests.
- [ ] Tracking loss stops cursor updates.
- [ ] Recovery is safe.
- [ ] Secondary hand cannot control cursor.
- [ ] macOS event integration is isolated from Core.
- [ ] Permission handling is safe.
- [ ] Existing Phase 1.1 tests remain passing.
- [ ] New Phase 2 tests pass.
- [ ] macOS build passes in CI.
- [ ] Documentation is updated.
- [ ] No click/pinch/drag/scroll functionality was added.
- [ ] Changes are committed and pushed.
- [ ] Exact physical Mac validation steps are documented.

**Passing CI does NOT mean Phase 2 is complete.**

The user must physically test cursor movement on the Mac.

---

# 30. FINAL RESPONSE FORMAT

Return exactly:

```text
## PHASE 2 RESULT

STATUS:
READY FOR LOCAL VALIDATION / PASS WITH ISSUES / BLOCKED

ARCHITECTURE:
...

CURSOR MAPPING:
...

ACTIVE AREA:
...

SMOOTHING:
...

DEAD ZONE:
...

SENSITIVITY:
...

TRACKING LOSS SAFETY:
...

PRIMARY HAND:
...

MACOS EVENT LAYER:
...

PERMISSION:
...

TESTS:
- Existing tests: X/X
- New tests: X
- Total: X/X

BUILD:
...

FILES:
- ...

DOCUMENTATION:
- ...

COMMIT:
...

LOCAL MAC VALIDATION REQUIRED:

A — Permission
B — Center
C — Horizontal
D — Vertical
E — Corners
F — Small movement
G — Fast movement
H — Distance
I — Tracking loss
J — Recovery
K — Two hands
L — Active area

IMPORTANT:
Do not declare Phase 2 complete.
The user must validate real cursor movement on the physical Mac first.
```

---

# 31. FINAL RULE

**PHASE 2 = INDEX FINGER → CURSOR ONLY.**

Do not implement any click or gesture behavior.

Build the cursor-control foundation correctly so Phase 3 can add pinch/click without rewriting the architecture.
