# AIRTRACK — PHASE 3B IMPLEMENTATION SPEC
## Left Click + Drag

**Status:** Ready for implementation  
**Depends on:** Phase 2.1 + Phase 3A

---

## 1. Implementation Goal

Implement:

1. Left click
2. Drag

using the Phase 3 interaction architecture.

Target:

```text
HandState
  ↓
PointerTracker
  ↓
HandFeatures
  ↓
FeatureHistory
  ↓
PoseClassifier
  ↓
Recognizers
  ↓
IntentArbiter
  ↓
InteractionEngine
  ↓
ClickController / DragController
  ↓
InteractionAction
  ↓
MacOSEventController
```

Do not replace the Phase 2.1 cursor pipeline.

## 2. Preserve Existing Contracts

Preserve:

- PointerTracker continuity
- FULL / PARTIAL / INDEX / HOLD / LOST behavior
- trackedHand
- HandFeatures
- FeatureHistory
- PoseClassifier
- IntentArbiter
- InteractionEngine
- Phase 3A ScrollController
- CursorController
- AdaptiveCursorSmoother
- CursorMapper
- DeadZoneFilter
- Accessibility handling

Do not modify Phase 2.1 cursor files unless a direct integration requirement is demonstrated.

## 3. Semantic Actions

Extend the semantic interaction layer minimally for:

- leftClick
- drag lifecycle
- mouseDown
- mouseUp

Core must not import AppKit/CoreGraphics event APIs.

## 4. Pinch Features

Use normalized:

- thumb/index distance
- pinch confidence
- thumb state
- index state
- hand scale
- temporal history
- normalized movement
- pointer/index velocity
- tracking confidence

No absolute pixel pinch threshold.

## 5. Pinch Recognizer

Create a recognizer that produces candidates rather than directly clicking.

Conceptual states:

```text
NONE
↓
PINCH_CANDIDATE
↓
PINCH_CONFIRMED
↓
CLICK_INTENT or DRAG_INTENT
```

A single noisy frame must not create a click.

## 6. Pinch Detection

Use relative thumb/index distance with hysteresis:

```text
distance <= pinchEnterThreshold
    → candidate/confirmed pinch

distance >= pinchExitThreshold
    → released
```

Require:

```text
pinchEnterThreshold < pinchExitThreshold
```

Thresholds must be configurable/tunable.

## 7. Click Candidate

Record:

- timestamp
- pointer position
- index position
- hand scale
- pinch ratio
- pointer movement
- index movement
- tracking quality

Candidate creation emits no mouse event.

## 8. Click vs Drag Intent

### Click evidence

- valid pinch established;
- release within a short natural interval;
- displacement below drag threshold;
- no strong directional movement;
- no drag commitment.

### Drag evidence

- pinch remains held;
- intentional movement exceeds drag threshold;
- movement is temporally coherent;
- tracking remains reliable.

Avoid a single-frame decision.

## 9. Movement Threshold

Use normalized hand-space movement or equivalent feature.

Do not use raw screen pixels as the primary intent threshold.

Make the threshold tunable and document the default.

## 10. Click Commitment

On valid pinch release without drag criteria:

```text
LEFT CLICK
```

Exactly one click per pinch.

No duplicate mouse events.

## 11. Drag Commitment

When a pinch remains held and intentional movement crosses the drag threshold:

1. Establish drag anchor.
2. Post mouseDown.
3. Begin pointer movement updates.

Do not emit a click for the same interaction.

## 12. Drag Anchor

At commitment:

```text
anchorCursor = current cursor position
anchorIndex = current index pointer position
offset = anchorCursor - anchorIndex
```

During drag:

```text
dragCursor = indexPointer + offset
```

Clamp to screen bounds.

Anchor remains fixed until drag ends.

## 13. Cursor Ownership During Drag

The existing Phase 2.1 cursor mapping remains authoritative.

Prevent competing cursor updates.

Do not allow:

```text
CursorController update
+
DragController update
```

to independently post mouse movement.

There must be one clear mouse-movement owner.

## 14. Drag Pointer Updates

While active:

- use current index position;
- no stale position;
- no indefinite extrapolation;
- preserve existing smoothing where compatible;
- avoid a second smoothing pipeline unless required.

## 15. Click/Drag Transition

Expected:

```text
PINCH
  ↓
candidate
  ↓
hold
  ↓
movement
  ↓
DRAG
```

No visible cursor jump at transition.

If movement remains below threshold:

```text
PINCH
  ↓
release
  ↓
CLICK
```

## 16. Release

### Click

```text
candidate → click → idle
```

### Drag

```text
drag active
→ mouseUp
→ idle
```

Guarantee exactly one mouseUp for every mouseDown.

## 17. Tracking Loss

### Click Candidate

Real tracking loss:

```text
cancel candidate
```

No click.

### Active Drag

Use bounded recovery consistent with PointerTracker:

```text
DRAG ACTIVE
 ↓
HOLD
 ↓
recovery
 ↓
continue
```

If recovery exceeds the safe window:

```text
mouseUp
→ terminate
```

Never leave mouseDown active indefinitely.

## 18. Tracking Loss Must Not Click

Absolute rule:

If pinch begins and tracking disappears before release:

```text
NO CLICK
```

Do not infer release from stale data.

## 19. Pause / Accessibility / Camera / Shutdown

During drag, any of:

- pause
- Cursor Control disabled
- Accessibility unavailable
- camera stopped
- app shutdown

must guarantee mouseUp if and only if a drag mouseDown is active.

Click candidates are cancelled.

## 20. Scroll Conflict

If Phase 3A scroll is active:

- no click;
- no drag.

Once scroll owns the interaction, it remains owner until its lifecycle ends.

Once drag is committed, drag owns the interaction and incidental pose changes must not start scroll.

## 21. Arbitration

Treat:

```text
scroll
pinch/click
drag
```

as competing intents.

Never commit multiple actions simultaneously.

Rule:

> uncertain intent = no action.

## 22. Lifecycle

Recommended:

```text
IDLE
  ↓
PINCH_CANDIDATE
  ↓
PINCH_CONFIRMED
  ↓
CLICK_PENDING
  ↓
CLICK_COMMITTED
  ↓
IDLE
```

or:

```text
IDLE
  ↓
PINCH_CANDIDATE
  ↓
PINCH_CONFIRMED
  ↓
DRAG_PENDING
  ↓
DRAG_ACTIVE
  ↓
DRAG_RELEASING
  ↓
IDLE
```

Support cancellation/suspension/loss without duplicating PointerTracker lifecycle.

## 23. Double Click Preparation

Do not implement double click yet.

Preserve timing information so a future phase can recognize:

```text
pinch
release
pinch
release
```

without redesigning the entire click architecture.

## 24. macOS Event Adapter

Use public macOS APIs.

Left click requires primary mouse-button events.

Drag requires:

```text
mouseDown
mouseMoved
mouseUp
```

Keep CGEvent code outside Core.

## 25. Event Safety Invariants

Add tests for:

```text
mouseDown count <= 1 active drag
mouseUp count == mouseDown count
no mouseUp without active drag
no click after drag commitment
no click after tracking loss
no drag without pinch confirmation
```

## 26. Automated Tests

### Pinch

- enter
- exit
- hysteresis
- noise
- confidence
- different hand scales
- different orientations

### Click

- quick pinch
- release
- one click
- no duplicate click
- small movement
- ambiguous pinch
- tracking loss
- pause

### Drag

- pinch hold
- movement threshold
- commitment
- anchor
- movement
- release
- mouseUp
- slow/normal/fast
- diagonal
- edge drag

### Click vs Drag

- pinch + release → click
- pinch + tiny movement → click
- pinch + intentional movement → drag
- drag must not click
- click must not drag

### Tracking

- HOLD recovery
- LOST release
- stale frame rejection
- no extrapolation

### Conflicts

- scroll owns interaction
- drag owns interaction
- ambiguity → no action

### Regression

All existing Phase 0–3A tests must continue passing.

## 27. Physical Validation

### Click

1. Natural quick pinch.
2. Slow pinch.
3. Slightly noisy pinch.
4. Different screen positions.
5. Different hand distances.
6. Repeated single clicks.
7. Small movement during pinch.

Expected:

- one intentional click;
- no accidental click from ambiguity.

### Drag

1. Pinch + hold.
2. Slow movement.
3. Normal movement.
4. Fast movement.
5. Horizontal.
6. Vertical.
7. Diagonal.
8. Screen edges.
9. Normal release.
10. Brief tracking loss.
11. Prolonged tracking loss.

Expected:

- no jump;
- index follows naturally;
- release always releases mouse button;
- no stuck drag.

### Regression

12. Cursor remains like Phase 2.1.
13. Scroll remains like validated Phase 3A.
14. No scroll/pinch conflict.
15. No false click during normal cursor movement.

## 28. Debug Panel

Expose useful diagnostics:

- pinch ratio
- pinch confidence
- pinch candidate
- pinch state
- click/drag intent
- movement since pinch
- drag threshold
- interaction lifecycle
- mouse button state
- tracking state

## 29. Performance

Avoid:

- blocking main thread
- unnecessary allocations
- unbounded histories
- duplicate cursor pipelines
- duplicate event loops

Maintain real-time performance.

## 30. Build / Test

Use the actual repository build system.

If Xcode project is authoritative:

```text
xcodebuild -project AirTrack/AirTrack.xcodeproj   -scheme AirTrack   -configuration Debug   -destination 'platform=macOS'   build
```

Run the complete available test suite.

Do not claim success without actually running it.

## 31. Documentation

Create:

```text
PHASE3B_RESULT.md
```

Document:

- architecture
- click recognition
- drag recognition
- arbitration
- tracking safety
- event adapter
- tests
- build
- known limitations
- physical validation status

Initially:

```text
PENDING USER VALIDATION
```

## 32. Git

Prefer:

```text
feat: implement phase 3b click and drag
```

Do not force push or reset destructively.

Verify:

```text
git status
git branch --show-current
git log --oneline -8
```

## 33. Definition of Done

Implementation is complete when:

- click candidate works;
- click emitted exactly once;
- drag commitment works;
- drag follows index;
- drag anchor is stable;
- click vs drag is separated;
- tracking loss is safe;
- mouseDown/mouseUp invariants pass;
- scroll regression tests pass;
- cursor regression tests pass;
- full tests pass;
- macOS build passes;
- documentation is updated.

Physical validation remains separate.

## 34. Critical Rules

1. Do not touch the stable cursor pipeline unnecessarily.
2. Do not weaken Phase 3A scroll to make click work.
3. Do not lower confidence thresholds blindly.
4. Do not use absolute pixel pinch thresholds.
5. Do not require exact finger positions.
6. Do not require a neutral pose.
7. Do not click on ambiguous input.
8. Do not start drag without confirmed pinch + intentional movement.
9. Once drag starts, click is cancelled.
10. Never leave mouseDown stuck.
11. Never extrapolate indefinitely after tracking loss.
12. Do not implement double click, right click, zoom or swipe yet.
13. Do not claim physical validation.
14. Do not claim tests passed unless actually run.
15. Do not claim build succeeded unless actually built.

## 35. Product Target

The desired interaction is:

```text
move hand
   ↓
pinch naturally
   ↓
click
```

or:

```text
move hand
   ↓
pinch
   ↓
hold
   ↓
move
   ↓
drag
```

The user should feel:

> "I am touching and moving the computer with my hand."
