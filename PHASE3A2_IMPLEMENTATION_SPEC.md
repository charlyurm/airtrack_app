# AIRTRACK — PHASE 3A-2
# SCROLL IMPLEMENTATION

**Status:** Implement only after 3A-1 physical validation passes  
**Depends on:** `PHASE3_MASTER_SPEC.md`, `PHASE3A_MASTER_SPEC.md`, `PHASE3A1_RESULT.md`

---

# 1. Objective

Turn the validated Phase 3A-1 scroll recognition into actual natural scrolling.

Supported scroll inputs:

1. Two-finger vertical scroll.
2. Open-hand vertical scroll.

The cursor must freeze during active scroll.

Scroll must feel proportional to hand movement and velocity, with controlled inertia.

---

# 2. Preconditions

Do not begin 3A-2 unless:

- 3A-1 is implemented;
- tests pass;
- macOS build succeeds;
- physical pose validation has been completed;
- two-finger and open-hand poses are reliable;
- cursor behavior still matches Phase 2.1.

If these conditions are not satisfied, stop and report the blocker.

---

# 3. Protect Phase 2.1

Do not modify unnecessarily:

- `CursorController`;
- `AdaptiveCursorSmoother`;
- `CursorMapper`;
- `DeadZoneFilter`;
- `HandPresenceFilter`;
- existing pointer tracking behavior;
- camera/Vision;
- Accessibility.

The cursor should be frozen by the interaction pipeline, not by rewriting CursorController.

---

# 4. Architecture

Expected flow:

```text
PointerTracker
      ↓
HandFeatures
      ↓
FeatureHistory
      ↓
PoseClassifier
      ↓
ScrollRecognizer
      ↓
IntentArbiter
      ↓
ScrollController
      ↓
InteractionFrame
      ↓
cursorPolicy = FROZEN
      ↓
InteractionAction.scroll
      ↓
MacOSEventAdapter
      ↓
CGEvent scroll
```

---

# 5. InteractionAction

Add the minimum semantic scroll action.

Conceptually:

```swift
.scroll(
    delta: ScrollDelta,
    phase: ScrollPhase,
    momentum: MomentumPhase
)
```

The exact Swift representation may differ if the existing architecture has a cleaner equivalent.

The Core should express semantic scroll intent.

The macOS adapter decides how to encode it.

---

# 6. ScrollRecognizer

Implement two recognition paths.

## 6.1 Two-finger scroll

Pose:

```text
☝️🖕
```

Requirements:

- index + middle must be confidently tracked;
- movement must be vertically dominant;
- sufficient displacement before commit;
- ambiguous diagonal → no commit;
- horizontal movement → do not scroll;
- once committed, lock the vertical axis until release/cancellation.

Do not require the fingers to touch.

Natural finger spacing is valid.

---

## 6.2 Open-hand scroll

Pose:

```text
🖐️
```

Use stable palm/finger movement.

Requirements:

- open-hand pose confidently established;
- vertical movement dominant;
- sufficient displacement;
- horizontal movement does not commit scroll;
- once committed, lock the vertical axis.

---

# 7. Cursor Freeze

When scroll becomes confidently active:

```text
cursorPolicy = FROZEN
```

The existing CursorController should not be updated with new pointer positions while scroll owns the interaction.

Do not modify CursorController internals merely to achieve this.

---

# 8. Cursor Freeze Timing

Initial recommendation:

> Freeze after a stable scroll candidate for approximately 80–100 ms.

This is intentionally subject to physical validation.

Reason:

- freezing too early makes normal cursor movement feel sticky;
- freezing too late allows the cursor to drift while starting scroll.

If the physical result is poor, document the issue rather than immediately exposing a sensitivity setting.

---

# 9. Scroll Delta

Scroll magnitude should be proportional to hand movement and velocity.

Conceptually:

```text
normalized hand displacement
× velocity response
× scroll sensitivity
→ scroll delta
```

Use hand-relative coordinates.

Do not use screen-pixel cursor velocity.

The existing `AdaptiveCursorSmoother` velocity must not be reused for scroll because it is screen-space and already smoothed.

---

# 10. Deadband

Small hand movements should not generate noisy scrolling.

Implement a deadband around zero.

Expected behavior:

```text
hand almost still
→ 0 scroll

small intentional movement
→ controlled small scroll

larger/faster movement
→ larger scroll
```

The deadband must be validated physically.

---

# 11. Decimal Accumulation

macOS scroll event deltas may require integer values.

Do not discard fractional Core deltas.

Use an accumulator:

```text
0.4
+ 0.4
+ 0.4
→ 1 event
```

Preserve remaining fractional value.

This avoids low-speed scroll becoming unresponsive or stepped.

---

# 12. Scroll Smoothing

Avoid excessive smoothing.

The Phase 2.1 cursor problem demonstrated that too much smoothing can feel:

- delayed;
- frozen;
- unnatural.

Scroll should therefore prioritize:

> immediate response + controlled noise suppression.

Use only the minimum smoothing necessary.

---

# 13. Inertia

Use bounded inertia.

Recommended behavior:

```text
SCROLL ACTIVE
      ↓
gesture ends
      ↓
capture final velocity
      ↓
MOMENTUM
      ↓
velocity decays
      ↓
END
```

If the pose remains active but the hand simply stops:

> scrolling should stop.

Do not continuously generate inertia while the gesture is still held.

Inertia begins when the gesture actually releases/ends.

---

# 14. Inertia Constraints

Inertia must have:

- maximum duration;
- maximum initial velocity;
- deterministic decay;
- zero output after termination;
- no uncontrolled acceleration.

A new gesture should cancel existing inertia.

For example:

```text
SCROLL
 ↓
INERTIA
 ↓
new PINCH
 ↓
INERTIA CANCELLED
 ↓
PINCH handling
```

No neutral pose required.

---

# 15. Tracking Loss

Use `PointerTracker` as the single source of truth.

Do not create a second independent tracking-loss timer.

## HOLD

Short tracking gap:

```text
SCROLL
 ↓
HOLD
 ↓
SUSPENDED
```

During suspension:

- no new scroll deltas;
- existing controlled inertia may continue only according to the defined policy;
- if tracking returns quickly, scroll may resume.

## LOST

Real tracking loss:

```text
SCROLL
 ↓
LOST
 ↓
stop new deltas
 ↓
bounded inertia may finish
 ↓
scroll ends
```

Do not extrapolate hand movement indefinitely.

---

# 16. Pause / Permission / Shutdown Safety

If any of these occur:

- AirTrack paused;
- cursor control disabled;
- Accessibility permission lost;
- camera stopped;
- application exits;

the scroll interaction must terminate cleanly.

The event adapter should emit the appropriate end phase.

No stale scroll state may survive.

---

# 17. macOS Event Adapter

Implement the macOS-specific scroll output.

Current event layer only handles:

```text
.mouseMoved
```

Extend it with scroll support.

Audit/use the public API:

```text
CGEvent(scrollWheelEvent2Source:...)
```

Prefer continuous/pixel scrolling if supported by the current architecture.

Potential fields:

```text
scrollWheelEventIsContinuous
scrollWheelEventScrollPhase
scrollWheelEventMomentumPhase
```

These must be validated on the real Mac.

Do not claim that synthetic events reproduce every native trackpad behavior.

---

# 18. Natural Scrolling Direction

The Core should represent semantic direction:

> "content follows the finger."

Do not hard-code assumptions about macOS's Natural Scrolling setting.

The adapter should determine the correct sign after physical validation.

Document:

- test result;
- whether the sign matches the system's Natural Scrolling preference;
- whether behavior is consistent across apps.

---

# 19. Two-Finger vs Open-Hand Conflict

The two scroll recognizers may produce candidates simultaneously.

The IntentArbiter must ensure:

```text
ONE scroll intent
```

not two independent scroll controllers.

Once scroll is committed:

- lock the owning gesture family;
- suppress incompatible cursor/swipe/right-click interpretation;
- release only when the gesture ends.

---

# 20. Swipe Conflict

Vertical two-finger movement:

```text
SCROLL
```

Horizontal two-finger movement:

```text
NOT SCROLL
```

Swipe is implemented later in Phase 3E.

For 3A-2:

```text
horizontal two-finger candidate → no scroll
```

Do not implement swipe yet.

---

# 21. Right-Click Conflict

Right click is implemented later in Phase 3G.

For 3A-2:

```text
thumb + middle
```

must not accidentally produce scroll unless the actual scroll pose is confidently recognized.

If the finger relationship is ambiguous:

> no scroll.

---

# 22. Tests

Add deterministic tests for:

### Recognition

- two-finger vertical;
- open-hand vertical;
- horizontal;
- diagonal;
- ambiguous;
- insufficient displacement.

### Velocity

- slow;
- medium;
- fast.

Expected:

```text
faster movement → larger deltas
```

### Deadband

- hand still;
- tiny movement;
- intentional movement.

### Decimal accumulation

Verify no fractional deltas are silently lost.

### Axis locking

Once vertical scroll commits:

- horizontal noise does not redirect it.

### Cursor freeze

Verify:

- cursor updates before scroll;
- cursor stops during active scroll;
- cursor resumes after scroll.

### Inertia

Verify:

- begins only after gesture ends;
- decays;
- bounded duration;
- bounded velocity;
- new gesture cancels inertia.

### Tracking

Test:

- HOLD;
- recovery;
- LOST.

### Safety

Verify:

- pause ends scroll;
- permission loss ends scroll;
- camera stop ends scroll;
- no stale scroll events.

### Regression

All existing tests must remain green.

---

# 23. Physical Validation

Run on the real Apple Silicon Mac.

## A — Two-finger scroll

Slow vertical movement.

Expected:

- controlled;
- immediate;
- no cursor movement.

## B — Fast two-finger scroll

Expected:

- faster scroll;
- no uncontrolled acceleration.

## C — Open-hand scroll

Expected:

- natural;
- proportional;
- no cursor drift.

## D — Horizontal movement

Expected:

- no vertical scroll.

## E — Diagonal movement

Expected:

- vertical only when clearly dominant;
- ambiguous movement produces no action.

## F — Start/stop

Expected:

- scroll starts naturally;
- stops naturally;
- bounded inertia.

## G — Cursor return

After scroll:

- cursor returns smoothly;
- no large jump;
- no unnatural delay.

## H — Transition

Test:

```text
CURSOR
→ SCROLL
→ CURSOR
→ PINCH
```

No neutral pose.

## I — Tracking loss

Test:

```text
SCROLL
→ short loss
→ recovery
```

and:

```text
SCROLL
→ real loss
```

Expected:

- safe termination;
- no runaway scroll.

## J — False positives

Move the hand naturally without intending to scroll.

Expected:

> cursor remains usable and no unexpected scroll occurs.

---

# 24. PASS Criteria

3A-2 passes when:

- two-finger scroll feels natural;
- open-hand scroll feels natural;
- cursor freezes reliably;
- cursor returns without a noticeable jump;
- scroll responds proportionally to speed;
- inertia is controlled;
- horizontal movement does not cause accidental vertical scroll;
- tracking loss is safe;
- pause/permission/shutdown are safe;
- no major false positives occur;
- Phase 2.1 cursor behavior remains intact.

---

# 25. FAIL Criteria

Fail if:

- scrolling feels delayed;
- scrolling feels frozen;
- cursor drifts during scroll;
- cursor jumps after scroll;
- inertia is excessive;
- inertia is absent when clearly expected;
- diagonal movement causes unwanted scroll;
- natural hand movement triggers scroll accidentally;
- tracking loss causes runaway events;
- Phase 2.1 cursor behavior regresses.

---

# 26. Expected Files

Likely Core:

```text
Interaction/ScrollController.swift
Interaction/ScrollRecognizer.swift
Models/InteractionAction.swift
Models/AirTrackSettings.swift
```

Likely App:

```text
Events/MacOSEventController.swift
Vision/HandTrackingPipeline.swift
App/AppModel.swift
```

Tests:

```text
ScrollControllerTests.swift
ScrollRecognizerTests.swift
InteractionEngineTests.swift
```

Do not modify unrelated components.

---

# 27. Documentation

Create:

```text
PHASE3A2_RESULT.md
```

Document:

- implementation;
- files changed;
- tests;
- build;
- physical validation;
- macOS event behavior;
- Natural Scrolling result;
- inertia behavior;
- cursor return behavior;
- known issues;
- recommended next phase.

---

# 28. Final Rule

Do not proceed to Phase 3B until 3A-2 has been physically validated.

The standard is not:

> "It technically scrolls."

The standard is:

> **"It feels like scrolling a real Mac trackpad with my hand."**

Natural movement first.
Responsiveness second.
Safety always.
Configuration later.
