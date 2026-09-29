# AIRTRACK — PHASE 3 MASTER SPECIFICATION

**Document:** `PHASE3_MASTER_SPEC.md`  
**Status:** Design specification — pre-implementation  
**Purpose:** Official product, UX, and technical specification for AirTrack Phase 3.

---

## 1. Vision

AirTrack is not intended to feel like a gesture-control application.

The target experience is:

> **The user's hand should feel like an extension of the computer.**

The user should perform familiar Mac/iPhone-like interactions naturally, without thinking about exact coordinates, rigid poses, artificial activation positions, or complicated gesture sequences.

The system should infer **intent from relationships, movement, timing, continuity, and context**, rather than relying on rigid absolute positions.

### Core experience requirements

AirTrack must:

- Feel natural.
- Feel responsive.
- Avoid unnecessary latency.
- Avoid requiring exact hand positions.
- Adapt to different hand sizes and distances from the camera.
- Allow natural transitions between gestures.
- Prefer doing nothing over performing an incorrect action.
- Work continuously rather than requiring manual mode switching.
- Preserve the stable cursor/tracking behavior already validated in Phase 2.1.
- Be architected for future 3-, 4-, and 5-finger gestures.
- Eventually support configurable gesture mappings.

The user should not think:

> "I need to perform a special gesture."

The intended mental model is:

> "I want to do something on the computer, so I naturally move my hand."

---

# 2. Design Principles

## 2.1 Natural over rigid

Do not require exact:

- coordinates;
- distances in pixels;
- hand angles;
- camera positions;
- finger positions;
- timing values that feel unnatural.

Measurements should be normalized where appropriate.

## 2.2 Relative geometry

Finger relationships should be evaluated relative to hand scale.

For example:

- pinch distance should be normalized by hand size;
- zoom should use relative change in finger distance;
- multi-finger gestures should tolerate changes in physical hand size caused by distance from the camera.

Absolute pixel thresholds should not be the primary gesture mechanism.

## 2.3 Intent over pose

A static pose alone should generally not determine the action.

The engine should consider:

- current geometry;
- previous geometry;
- movement direction;
- movement speed;
- temporal sequence;
- gesture continuity;
- hand identity;
- confidence;
- contextual conflicts.

Example:

`INDEX + THUMB CLOSE` is not automatically a click.

Instead:

`PINCH + quick release` → click

while:

`PINCH + hold + movement` → drag

and:

`PINCH + increasing/decreasing distance` → zoom.

## 2.4 Uncertainty policy

If the engine is not sufficiently confident about the user's intent:

> **Do nothing.**

False actions are considered worse than missed gestures.

## 2.5 Continuous interaction

There should be no requirement to return to a neutral pose between gestures.

Example:

```text
CURSOR
  ↓
SCROLL
  ↓
CURSOR
  ↓
CLICK
  ↓
DRAG
  ↓
CURSOR
```

Transitions should happen naturally as hand/finger relationships change.

---

# 3. Priority Order

1. **Cursor**
2. **Scroll**
3. **Left Click**
4. **Drag**
5. **Zoom**
6. **Swipe**
7. **Double Click**
8. **Right Click**

Cursor behavior is already implemented and physically validated in Phase 2.1.

Phase 3 must avoid unnecessary changes to the cursor system.

---

# 4. Hand Selection

AirTrack must support left and right hands.

The active hand must be configurable:

```text
Primary Hand:
- Left
- Right
- Automatic
```

Phase 3 should preserve the existing primary-hand architecture and avoid destabilizing Phase 2.1.

---

# 5. Gesture Definitions

## 5.1 Cursor

### Gesture

```text
☝️
```

Index-finger movement controls the cursor.

This is an existing stable subsystem from Phase 2/2.1.

Phase 3 must integrate with it rather than rewrite it unnecessarily.

---

## 5.2 Scroll

Scroll is a top priority because it strongly affects whether AirTrack feels natural.

### Two-finger scroll

```text
☝️ 🖕
   ↑
   ↓
```

Index + middle finger moving vertically.

### Open-hand scroll

```text
🖐️
 ↑
 ↓
```

An open hand moving vertically.

### Behavior

When scroll is active:

- cursor position is frozen;
- pointer movement must not interfere with scroll;
- direction follows finger/hand movement;
- magnitude is proportional to movement;
- velocity affects scroll speed;
- slow movement produces controlled scrolling;
- fast movement produces faster scrolling;
- vertical movement is reserved for scroll.

### Inertia

Scroll must support bounded inertia:

```text
gesture movement
      ↓
scroll velocity
      ↓
hand stops
      ↓
controlled decay
      ↓
scroll stops
```

When the gesture ends:

- stop generating new scroll deltas;
- allow controlled inertia to finish;
- return naturally to cursor control.

The user must not need a neutral pose.

---

## 5.3 Left Click

### Gesture

```text
☝️ + 👍
      ↓
     🤏
```

Index + thumb pinch.

Recognition must be:

- normalized by hand scale;
- tolerant of hand distance from camera;
- tolerant of natural timing;
- based on relative finger relationship;
- resistant to accidental activation.

Conceptually:

```text
OPEN
  ↓
PINCH CANDIDATE
  ↓
PINCH
  ↓
QUICK RELEASE
  ↓
LEFT CLICK
```

A sustained pinch must not repeatedly generate clicks.

---

## 5.4 Drag

### Gesture

```text
🤏
 ↓
hold
 ↓
move
```

Drag begins when:

1. a valid left-click pinch is established;
2. the pinch remains held;
3. movement exceeds the drag threshold.

A stationary pinch should not automatically become drag.

### Pointer reference

During drag:

> **The dragged object follows the index.**

Preserve the existing drag-anchor safety behavior from Phase 0/2.

### Tracking loss

```text
DRAG
 ↓
tracking loss
 ↓
short recovery window
 ↓
tracking returns → continue
```

If tracking does not return:

```text
DRAG
 ↓
tracking loss
 ↓
mouseUp
 ↓
cancel
```

A stuck mouse button is unacceptable.

---

## 5.5 Double Click

### Gesture

```text
🤏
release
🤏
```

Two rapid pinch actions.

Requirements:

- tolerate natural timing variation;
- distinguish double click from drag;
- distinguish double click from unrelated clicks;
- avoid rigid timing;
- cancel safely if tracking is lost.

---

## 5.6 Right Click

### Gesture

```text
👍 + 🖕
```

Thumb + middle finger.

This must be distinguished from the two-finger scroll gesture:

```text
☝️ + 🖕
```

Recognition should use finger identity, relationship, movement, and temporal context.

Right click must not accidentally trigger while starting a scroll.

---

## 5.7 Zoom

Zoom follows the familiar iPhone/Mac pinch paradigm.

### Zoom in

```text
🤏
 ↗ ↖
```

Index + thumb separate.

### Zoom out

```text
↘ ↙
 🤏
```

Index + thumb move closer.

Recognition is based on **change in distance between index and thumb**, not fixed absolute distance.

Zoom magnitude is proportional to normalized distance change.

During zoom:

> **The cursor remains frozen.**

The same fingers therefore have multiple possible intents:

```text
PINCH + quick release
        ↓
      CLICK

PINCH + hold + hand movement
        ↓
      DRAG

PINCH + meaningful finger separation change
        ↓
      ZOOM
```

The engine must avoid premature commitment.

---

## 5.8 Swipe

Swipe is horizontal only. Vertical movement is reserved for scroll.

### Two-finger swipe

```text
☝️ 🖕
←   →
```

Purpose:

> Navigate backward/forward between pages.

Use native macOS/application-level behavior where possible.

### Four-finger swipe

```text
4 fingers
←   →
```

Purpose:

> Move between applications/Spaces.

Use native macOS behavior where appropriate.

Swipe should use coordinated movement, direction, velocity, distance, continuity, and confidence. It must not require an exact starting position.

---

# 6. Context-Aware Behavior

AirTrack should behave as much like a real Mac trackpad as macOS permits.

Preferred architecture:

```text
Natural hand gesture
       ↓
AirTrack interpretation
       ↓
Native macOS interaction/event
       ↓
Application decides final behavior
```

AirTrack should not unnecessarily hard-code application-specific behavior.

Examples:

- browser navigation should use native navigation mechanisms;
- zoom should use appropriate native/system input where possible;
- Spaces/app switching should use native macOS behavior.

---

# 7. Gesture State Model

The Gesture Engine should use explicit lifecycle states.

Generic lifecycle:

```text
IDLE
 ↓
CANDIDATE
 ↓
CONFIRMED
 ↓
ACTIVE
 ↓
RELEASE
 ↓
IDLE
```

Not every gesture needs every state, but the architecture must support the lifecycle.

### Click

```text
IDLE
 ↓
PINCH CANDIDATE
 ↓
PINCH CONFIRMED
 ↓
RELEASE
 ↓
CLICK
 ↓
IDLE
```

### Drag

```text
IDLE
 ↓
PINCH
 ↓
HOLD
 ↓
MOVEMENT
 ↓
DRAG ACTIVE
 ↓
RELEASE
 ↓
IDLE
```

### Scroll

```text
IDLE
 ↓
2-FINGER / OPEN-HAND CANDIDATE
 ↓
SCROLL CONFIRMED
 ↓
SCROLLING
 ↓
INERTIA
 ↓
IDLE
```

### Zoom

```text
IDLE
 ↓
PINCH RELATION
 ↓
SEPARATION CHANGE
 ↓
ZOOM ACTIVE
 ↓
RELEASE
 ↓
IDLE
```

---

# 8. Gesture Conflict Resolution

Conflicting interpretations are expected.

The engine must not execute multiple incompatible actions simultaneously.

Examples:

### Pinch vs Zoom

Immediate release → click.

Meaningful finger-separation change → zoom.

### Pinch vs Drag

Held pinch + translation → drag.

### Scroll vs Right Click

Index + middle vertical movement → scroll.

Thumb + middle interaction without index involvement → right click.

### Scroll vs Cursor

Once scroll is confidently active:

> freeze cursor.

### Swipe vs Scroll

Vertical → scroll.

Horizontal → swipe.

When ambiguity remains:

> no action.

---

# 9. No Forced Neutral Pose

The user must not reset the hand after every action.

Example:

```text
☝️
CURSOR

☝️🖕 ↑
SCROLL

☝️
CURSOR

🤏
CLICK

🤏 →
DRAG

☝️
CURSOR
```

This is a core requirement.

---

# 10. Tracking Loss Policy

| Gesture | Tracking loss behavior |
|---|---|
| Cursor | Stop movement |
| Left click | Cancel |
| Double click | Cancel sequence |
| Drag | Brief recovery attempt → `mouseUp` if recovery fails |
| Scroll | Stop new deltas; controlled inertia may finish |
| Zoom | Stop zoom |
| Swipe | Cancel |
| Right click | Cancel |

No gesture may invent missing landmarks, extrapolate indefinitely, or remain active indefinitely on stale data.

---

# 11. Safety Rules

1. No uncertain gesture should execute.
2. No repeated clicks from a held pinch.
3. No stuck mouse button.
4. `mouseUp` must be guaranteed after failed drag recovery.
5. Tracking loss must cancel unsafe active actions.
6. No indefinite extrapolation.
7. No stale landmarks.
8. Gesture modes that freeze the cursor must not move it unexpectedly.
9. Scroll inertia must be bounded.
10. Gesture recognition must not require network access.

---

# 12. Architecture Requirements

Preserve separation between pure gesture logic and macOS-specific event output.

Preferred architecture:

```text
Vision / Hand Tracking
        ↓
HandState
        ↓
Gesture Features
        ↓
Gesture Interpreter
        ↓
Gesture State Machine
        ↓
InteractionAction
        ↓
macOS Event Adapter
        ↓
CGEvent / native macOS action
```

### Core

Pure Swift/Foundation logic should contain:

- normalized gesture geometry;
- hand-scale calculations;
- finger relationships;
- velocity;
- gesture candidates;
- gesture state machines;
- conflict resolution;
- thresholds;
- timing;
- inertia calculations;
- deterministic tests.

### macOS layer

macOS-specific code should contain:

- CGEvent;
- Accessibility;
- application/Space navigation;
- system event generation;
- lifecycle;
- camera/Vision integration;
- UI/debugging.

The Core must remain testable without camera hardware.

---

# 13. Extensibility

Reserve architecture for:

- 3 fingers;
- 4 fingers;
- 5 fingers;
- future gestures;
- configurable mappings.

Future examples:

- Mission Control;
- desktop;
- Launchpad;
- app switching;
- Spaces;
- custom shortcuts;
- user-defined actions.

Do not implement future gestures merely to reserve the architecture.

---

# 14. Configuration

Do not expose extensive sensitivity controls prematurely.

First priority:

> **Make the default behavior feel natural.**

After physical validation, future configuration may expose:

- scroll sensitivity;
- scroll inertia;
- pinch sensitivity;
- zoom sensitivity;
- swipe sensitivity;
- gesture timing;
- double-click tolerance;
- drag threshold;
- primary hand;
- gesture mappings.

Configuration must not be used to compensate for fundamentally incorrect recognition.

---

# 15. Testing Strategy

Every gesture must have deterministic Core tests.

Tests should cover:

### Recognition

- valid gesture;
- invalid gesture;
- borderline gesture;
- slow movement;
- fast movement;
- different hand scales;
- different camera distances;
- different orientations;
- confidence changes.

### Temporal behavior

- candidate;
- confirmation;
- activation;
- release;
- cancellation;
- timeout.

### Conflicts

- pinch vs click;
- pinch vs drag;
- pinch vs zoom;
- scroll vs right click;
- scroll vs cursor;
- swipe vs scroll.

### Tracking loss

Every gesture must have explicit loss/recovery tests.

### Safety

Verify:

- uncertain input produces no action;
- drag eventually produces `mouseUp`;
- stale landmarks do not create events;
- inertia is bounded;
- no duplicate clicks occur.

---

# 16. Physical Validation

No phase is complete based only on unit tests or CI.

Physical validation must be performed on the real Apple Silicon Mac.

For each gesture validate:

1. Natural starting position.
2. Different hand distances.
3. Slight hand rotation.
4. Slow movement.
5. Fast movement.
6. Transition from another gesture.
7. Tracking loss.
8. Recovery.
9. False-positive attempts.
10. Overall subjective naturalness.

The most important criterion:

> **Does it feel like an extension of the hand rather than a gesture-controlled application?**

---

# 17. PASS / FAIL Philosophy

### PASS

A gesture passes when:

- it activates naturally;
- it does not require exact positioning;
- it is responsive;
- it does not feel delayed;
- it does not produce obvious false positives;
- it transitions naturally;
- it recovers safely;
- it remains consistent at different hand distances;
- it works without teaching the user unnatural poses.

### FAIL

A gesture fails when:

- it requires exact positioning;
- it feels slow;
- it feels sticky;
- it requires repeated attempts;
- it triggers unexpectedly;
- it conflicts with another common gesture;
- it requires a neutral reset;
- it behaves differently with small camera-distance changes;
- it leaves an unsafe active mouse state.

---

# 18. Suggested Phase 3 Roadmap

The exact subdivision may change after architecture review.

## Phase 3A — Gesture Engine Foundation + Scroll

Priority because scroll is both important and technically sensitive.

Implement:

- gesture feature extraction;
- gesture state infrastructure;
- two-finger scroll;
- open-hand scroll;
- velocity;
- inertia;
- cursor freezing;
- scroll/cursor conflict handling.

Physical validation required.

## Phase 3B — Left Click

Implement:

- index + thumb pinch;
- natural confirmation;
- click release;
- no repeated click;
- conflict handling with zoom/drag.

Physical validation required.

## Phase 3C — Drag

Implement:

- pinch hold;
- movement threshold;
- index anchor;
- drag safety;
- tracking-loss recovery.

Physical validation required.

## Phase 3D — Zoom

Implement:

- pinch separation;
- zoom in/out;
- normalized distance change;
- cursor freeze;
- click/drag/zoom conflict resolution.

Physical validation required.

## Phase 3E — Swipe

Implement:

- two-finger horizontal navigation;
- four-finger application/Space switching;
- velocity/distance;
- horizontal-only recognition;
- scroll conflict handling.

Physical validation required.

## Phase 3F — Double Click

Implement:

- two natural pinch actions;
- tolerant timing;
- click/double-click conflict resolution.

Physical validation required.

## Phase 3G — Right Click

Implement:

- thumb + middle;
- conflict handling with index + middle scroll;
- safe confirmation.

Physical validation required.

---

# 19. Phase 3 Non-Goals

Do not use Phase 3 to:

- redesign the camera pipeline;
- rewrite Phase 2.1 cursor behavior;
- add cloud processing;
- add network-dependent gesture recognition;
- add AI/cloud vision APIs;
- implement all future 3/4/5-finger gestures;
- build full user customization;
- optimize every parameter before physical validation;
- add unnecessary UI complexity.

---

# 20. Known Risks

### Risk 1 — Gesture ambiguity

Index + thumb participates in:

- click;
- drag;
- zoom.

This requires strong temporal and movement-based intent recognition.

### Risk 2 — Scroll/right-click overlap

Index + middle is scroll while thumb + middle is right click.

The engine must recognize finger identity and movement intent.

### Risk 3 — Naturalness vs detection rate

Aggressive thresholds can improve detection but make the system feel artificial.

Natural interaction is the priority.

### Risk 4 — Inertia

Too little inertia feels mechanical.

Too much inertia feels uncontrolled.

It must be bounded and physically validated.

### Risk 5 — Swipe interpretation

Two-finger navigation and four-finger application/Space switching must not conflict with scroll or ordinary cursor movement.

### Risk 6 — Tracking loss

Every active gesture must have a safe termination path.

---

# 21. Definition of Done

Phase 3 is complete only when:

- Gesture Engine architecture is implemented.
- All target gestures have deterministic tests.
- Conflict resolution is tested.
- Tracking-loss behavior is tested.
- macOS event integration is tested.
- Accessibility continues working.
- Phase 2.1 cursor behavior remains intact.
- Build succeeds.
- CI is green.
- Physical validation passes on the real Mac.
- Gestures feel natural without exact positioning.
- No major false-positive actions occur.
- No gesture feels unnecessarily slow or stiff.

Most importantly:

> **The final physical test should make the user feel that their hand has become the MacBook trackpad.**

---

# 22. Official Product Principle

AirTrack should not train the user to adapt to the software.

The software should adapt to the user's natural movement.

**Natural movement first.  
Intent second.  
Action third.  
Configuration later.**
