# AIRTRACK — PHASE 3A-1
# GESTURE ENGINE FOUNDATION — SHADOW MODE

**Status:** Ready for implementation  
**Mode:** Shadow / no-action  
**Depends on:** `PHASE3_MASTER_SPEC.md`, `PHASE3A_MASTER_SPEC.md`

---

## 1. Objective

Build the foundation of the Phase 3 Gesture Engine without allowing gestures to control macOS yet.

The purpose of 3A-1 is to prove that AirTrack can reliably understand:

- ☝️ Pointing
- ☝️🖕 Two fingers
- 🖐️ Open hand
- Four fingers
- 🤏 Pinch

across different hand sizes, distances, orientations, and normal tracking noise.

**No new gesture event may be sent to macOS.**

The existing Phase 2.1 cursor must remain unchanged.

---

## 2. Mandatory Rule

> **3A-1 is recognition only.**

Allowed:

```text
HandState
→ Features
→ History
→ Pose
→ Candidates
→ Intent
→ Debug UI
```

Not allowed:

```text
Gesture
→ mouseDown
→ mouseUp
→ click
→ scroll
→ zoom
→ swipe
→ keyboard shortcut
```

The only live macOS interaction permitted is the existing Phase 2.1 cursor movement.

---

## 3. Protect Phase 2.1

Do not redesign or replace:

- `CursorController`
- `AdaptiveCursorSmoother`
- `CursorMapper`
- `DeadZoneFilter`
- `HandPresenceFilter`
- existing `PointerTracker` behavior
- camera pipeline
- Vision pipeline
- Accessibility system
- existing cursor event generation

The old Phase 0 `GestureEngine` must not be connected directly to the cursor pipeline.

---

## 4. Required Architecture

Implement:

```text
PointerTracker
      ↓
trackedHand
      ↓
HandFeatureExtractor
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
Shadow InteractionFrame
      ↓
Debug UI
```

The cursor remains on its existing independent path:

```text
PointerTracker
      ↓
CursorController
      ↓
MacOSEventController
      ↓
mouseMoved
```

---

## 5. PointerTracker

Add an additive:

```swift
trackedHand: HandState?
```

Semantics:

- `FULL`: current tracked hand available.
- `PARTIAL` / `INDEX`: do not assume full gesture features.
- `HOLD`: no fresh hand landmarks.
- `LOST`: `nil`.

Do not alter the existing tracking behavior.

---

## 6. Hand Features

Create a pure Core feature representation.

Required features:

- robust hand scale;
- thumb/index normalized distance;
- thumb/middle normalized distance;
- index/middle normalized distance;
- finger extended/bent/uncertain state;
- extended finger count;
- per-finger confidence;
- palm center;
- normalized hand velocity;
- finger velocity where useful;
- movement direction;
- dominant axis;
- accumulated displacement.

All geometry must be relative to hand scale where applicable.

Avoid absolute pixel thresholds.

When geometry is ambiguous:

```text
UNKNOWN
```

not a forced classification.

---

## 7. Finger Classification

Support:

```text
Thumb
Index
Middle
Ring
Little
```

Each should be approximately:

```text
EXTENDED
BENT
UNKNOWN
```

The classifier must tolerate:

- hand scale changes;
- moderate rotation;
- normal landmark noise;
- camera distance.

A finger pointing toward the camera may become ambiguous.

Ambiguity must produce `UNKNOWN`.

---

## 8. Pose Classifier

Create a `PoseClassifier` with hysteresis.

Initial poses:

```text
POINTING
TWO_FINGER
OPEN_HAND
FOUR_FINGER
PINCH
UNKNOWN
```

A one-frame fluctuation must not cause pose flickering.

The classifier must preserve finger identity internally.

---

## 9. Feature History

Create a bounded temporal history.

Target:

```text
≤ 0.5 seconds
```

Store enough information for:

- velocity;
- displacement;
- direction;
- dominant axis;
- pose continuity;
- temporal evidence.

Use a deterministic ring buffer.

No unbounded history.

---

## 10. Recognizers

Recognizers only generate candidates.

They do not execute actions.

Conceptually:

```text
Recognizer
→ GestureCandidate
```

Candidate should contain:

- gesture family;
- evidence/confidence;
- relevant fingers;
- direction;
- dominant axis;
- timing;
- readiness to commit.

For 3A-1, include observation-only recognizers for:

- two-finger vertical scroll;
- open-hand vertical scroll.

---

## 11. IntentArbiter

Implement a single arbitration point.

Rules:

1. Recognizers may produce simultaneous candidates.
2. Only the Arbiter may commit an intent.
3. Conflicting gestures cannot execute simultaneously.
4. Evidence must accumulate.
5. Ambiguity means no action.
6. No global neutral pose is required.
7. Gesture families may re-arm independently.

---

## 12. Gesture Lifecycle

Use:

```text
IDLE
 ↓
CANDIDATE
 ↓
CONFIRMED
 ↓
ACTIVE
 ↓
RELEASING
 ↓
IDLE
```

Cancellation:

```text
CANDIDATE
 ↓
CANCELLED
 ↓
IDLE
```

Short tracking gap:

```text
ACTIVE
 ↓
SUSPENDED
 ↓
ACTIVE
```

or:

```text
ACTIVE
 ↓
SUSPENDED
 ↓
CANCELLED
```

Use the existing `PointerTracker` continuity model rather than creating a second independent tracking-loss timer.

---

## 13. Scroll in Shadow Mode

Recognize only.

### Two-finger

```text
☝️🖕
```

Vertical movement.

### Open hand

```text
🖐️
```

Vertical movement.

Rules:

- vertical must be dominant;
- horizontal should not commit scroll;
- ambiguous diagonal → no commit;
- insufficient movement → no commit;
- no scroll event is emitted.

---

## 14. InteractionEngine

Create the new interaction layer.

Recommended name:

```text
InteractionEngine
```

It coordinates:

```text
features
→ history
→ pose
→ recognizers
→ arbiter
→ lifecycle
```

In 3A-1:

```text
actions = []
```

No macOS events.

---

## 15. Debug UI

Expose enough information to validate recognition physically.

Display where practical:

```text
Tracking:
FULL / PARTIAL / INDEX / HOLD / LOST

Pose:
POINTING
TWO_FINGER
OPEN_HAND
FOUR_FINGER
PINCH
UNKNOWN

Finger states:
Thumb
Index
Middle
Ring
Little

Hand scale
Hand speed
Dominant axis
Gesture candidate
Intent
Lifecycle
```

Optional:

- hand skeleton;
- finger labels;
- candidate visualization;
- feature trajectory.

Debug UI must not affect production behavior.

---

## 16. Tests

Add deterministic tests for:

### Features

- 0.5× scale;
- 1× scale;
- 2× scale;
- rotation;
- translation;
- reproducible noise;
- missing joints;
- low confidence;
- NaN/infinite protection.

### Poses

- ☝️
- ☝️🖕
- 🖐️
- four fingers;
- 🤏;
- unknown;
- hysteresis;
- ambiguous thumb.

### Candidates

- vertical movement;
- horizontal movement;
- diagonal movement;
- ambiguous axis;
- below threshold;
- slow;
- fast.

### Tracking

- FULL;
- HOLD;
- recovery;
- LOST;
- PARTIAL.

### Safety

Verify:

- uncertain input → no action;
- shadow engine → no macOS gesture event;
- unknown hand → no activation;
- stale frames → no activation.

### Regression

All existing tests must remain green.

---

## 17. Physical Validation

Run on the real Apple Silicon Mac.

### A — Pointing

Expected:

- cursor identical to Phase 2.1;
- POINTING recognized.

### B — Two fingers

Expected:

- TWO_FINGER recognized;
- no scroll event;
- cursor remains normal.

### C — Open hand

Expected:

- OPEN_HAND recognized;
- no scroll event.

### D — Four fingers

Expected:

- FOUR_FINGER recognized conservatively;
- no action.

### E — Pinch

Expected:

- PINCH recognized;
- no click.

### F — Distance

Test close, medium, and far.

### G — Rotation

Test natural hand rotation.

### H — Transitions

```text
POINTING
→ TWO_FINGER
→ POINTING
→ PINCH
→ POINTING
```

No neutral pose.

### I — False positives

Try random/ambiguous/partial movement.

Expected:

> uncertain → no action.

### J — Cursor regression

Expected:

> cursor feels identical to Phase 2.1.

---

## 18. PASS Criteria

3A-1 passes when:

- tests are green;
- cursor behavior is unchanged;
- poses are stable;
- scale variation is tolerated;
- ambiguous cases become UNKNOWN;
- no gesture event is emitted;
- natural transitions work;
- physical validation passes.

---

## 19. FAIL Criteria

Fail if:

- cursor behavior regresses;
- classifier flickers heavily;
- exact positioning is required;
- ambiguous input triggers actions;
- partial tracking creates false gestures;
- shadow engine emits macOS interaction events;
- tracking loss leaves stale gesture state.

---

## 20. Git Requirements

Before implementation:

- confirm branch;
- confirm clean working tree;
- read `PHASE3_MASTER_SPEC.md`;
- read `PHASE3A_MASTER_SPEC.md`;
- inspect actual architecture.

During implementation:

- small commits;
- no force push;
- full tests;
- macOS build;
- document results.

Do not claim physical validation unless actually performed on the user's Mac.

---

## 21. Final Deliverable

At completion create:

```text
PHASE3A1_RESULT.md
```

Include:

- status;
- architecture implemented;
- files changed;
- tests;
- build result;
- physical validation status;
- known issues;
- recommended next step.

Do not proceed to 3A-2 until 3A-1 physical validation is complete.
