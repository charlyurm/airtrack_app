# AIRTRACK — PHASE 1.1
## Tracking, Coordinate Conversion, Landmark Mapping & Stability Fix

**Status:** READY FOR IMPLEMENTATION  
**Phase:** 1.1 — Fixes after real Mac hardware validation  
**Repository:** `charlyurm/airtrack_app`  
**Workflow:** Claude Code Cloud → GitHub → local Mac validation

> **IMPORTANT:** Phase 2 MUST NOT start until Phase 1.1 passes validation on the physical Mac.

---

## 1. PURPOSE

Phase 1 established the macOS application, camera pipeline, Vision hand tracking, permissions, preview, debug overlay, performance instrumentation, and `AirTrackCore`.

Real hardware validation found several issues that must be resolved before Phase 1 can be considered complete.

This phase is **not** about cursor control.

Do NOT implement:

- cursor movement
- mouse click
- double click
- drag
- scroll
- `CGEvent`
- Accessibility input
- Phase 2 behavior

The goal is to make the hand-tracking pipeline reliable enough that Phase 2 can safely consume `HandState`.

---

## 2. DEVELOPMENT WORKFLOW

You are working in **Claude Code Cloud on Linux/x86_64**.

You do NOT have access to:

- macOS
- Xcode
- the user's physical Mac
- the Mac camera
- the user's runtime environment

The user performs all real hardware validation on a physical Apple Silicon Mac.

Therefore:

1. Inspect the existing repository.
2. Implement fixes in the cloud environment.
3. Add deterministic automated tests.
4. Run all available tests.
5. Use GitHub Actions/macOS CI where available.
6. Commit and push the changes.
7. Report exactly what was changed.
8. Give the user precise local Mac validation steps.

Do NOT claim that camera behavior was personally tested on the physical Mac.

---

## 3. CURRENT BASELINE

Before Phase 1.1:

- AirTrackCore exists and is separated from macOS-specific code.
- Phase 1 macOS app exists.
- Camera preview works.
- Vision hand tracking works.
- Tracking LOST/recovery works.
- Debug overlay exists.
- Performance metrics exist.
- Existing automated test suite passed: **85/85**.
- Phase 1 is currently **IN PROGRESS**, not complete.

Pipeline:

```text
Camera
  ↓
AVCaptureVideoDataOutput
  ↓
Vision hand pose detection
  ↓
Vision joint extraction
  ↓
HandState
  ↓
AirTrackCore
  ↓
Debug overlay
```

---

## 4. REAL HARDWARE VALIDATION RESULTS

These results were obtained on a real Apple Silicon Mac.

### Camera

- Camera works: PASS
- Preview works: PASS
- Camera status: RUNNING
- Camera FPS: approximately 30 FPS

### Permissions

- Camera permission flow: PASS

### Hand detection

- One hand: detected
- Two hands: only one hand currently represented

### Landmarks

The user reported:

- Sometimes landmarks are correct.
- At approximately 20 cm from the camera/screen, detection becomes less reliable.
- False positives can occur.
- When the hand moves farther away, landmark points visibly shift.

A real runtime screenshot also revealed a more specific problem:

> The displayed `wrist → indexMCP → indexPIP → indexDIP → indexTip` chain appears to follow the wrong anatomical finger. The chain visually terminates around the middle-finger region instead of consistently following the actual index finger.

This means the issue may not be only coordinate alignment. The **identity/mapping of Vision joints to AirTrack joints must be explicitly audited**.

### Horizontal movement

- PASS

### Vertical movement

- FAIL
- Vertical movement behaves in the opposite direction / coordinate direction is incorrect.

### Distance change

- Moving the hand farther away causes visible landmark displacement.

### Tracking LOST

- PASS

### Tracking recovery

- PASS

### Performance

Initial validation:

```text
Camera FPS:             30
Vision FPS:             30
Vision processing:      ~30 ms
Capture → HandState:    ~45 ms
Dropped frames:         22
```

A later screenshot showed:

```text
Camera FPS:             30.0
Vision FPS:             30.1
Vision processing:      11.6 ms
Capture → HandState:    45 ms
Dropped frames:         23
```

The application also states that `Capture → HandState` does not include screen rendering time and therefore is not end-to-end latency.

---

## 5. PRIMARY OBJECTIVES

Phase 1.1 must address:

1. Explicitly verify and fix Vision → HandJoint identity mapping.
2. Fix vertical coordinate direction.
3. Investigate landmark displacement when hand distance changes.
4. Improve invalid/low-confidence tracking behavior.
5. Support representation of up to two detected hands.
6. Investigate dropped frames without introducing latency accumulation.
7. Preserve the existing architecture.
8. Add deterministic tests for all corrected behavior.
9. Document the final coordinate conventions and tracking behavior.

---

# 6. OBJECTIVE 1 — AUDIT LANDMARK IDENTITY MAPPING

This is the highest-priority issue.

The real screenshot suggests that the displayed index-finger chain may not correspond to the actual index finger.

Do NOT assume the issue is simply an overlay offset.

Audit the complete pipeline:

```text
VNHumanHandPoseObservation
        ↓
recognizedPoints(...)
        ↓
Vision joint identifiers
        ↓
AirTrack HandJoint mapping
        ↓
HandState
        ↓
Overlay rendering
```

### IMPORTANT

Do NOT rely on array ordering.

Do NOT assume the order returned by Vision corresponds to the order expected by AirTrack.

Every joint must be mapped explicitly by its Vision identifier.

At minimum verify:

```text
wrist

thumbCMC
thumbMP
thumbIP
thumbTip

indexMCP
indexPIP
indexDIP
indexTip

middleMCP
middlePIP
middleDIP
middleTip

ringMCP
ringPIP
ringDIP
ringTip

littleMCP
littlePIP
littleDIP
littleTip
```

Create or verify an explicit mapping table:

```text
Vision joint identifier
        ↓
AirTrack HandJoint
        ↓
Expected anatomical landmark
```

### Required tests

Create synthetic deterministic tests proving that joint identity is preserved.

Example:

```text
indexTip  = (0.30, 0.80)
middleTip = (0.50, 0.80)
ringTip   = (0.70, 0.80)
littleTip = (0.90, 0.80)
```

After conversion:

```text
HandState.indexTip  == (0.30, 0.80)
HandState.middleTip == (0.50, 0.80)
HandState.ringTip   == (0.70, 0.80)
HandState.littleTip == (0.90, 0.80)
```

Also test complete finger chains.

The tests must validate behavior, not merely implementation details.

---

# 7. OBJECTIVE 2 — FIX VERTICAL COORDINATE DIRECTION

Audit:

```text
Camera frame
→ AVCaptureVideoPreviewLayer
→ Vision normalized coordinates
→ LandmarkCoordinateConversion
→ HandState
→ Overlay coordinate system
```

Determine exactly where the vertical inversion occurs.

Do NOT blindly add another Y inversion.

Verify:

- Vision normalized coordinate convention
- AirTrackCore coordinate convention
- SwiftUI coordinate convention
- preview layer coordinate conversion
- mirroring
- aspect ratio
- video gravity
- orientation
- overlay coordinate conversion

Required behavior:

- Vision top maps to AirTrack top.
- Vision bottom maps to AirTrack bottom.
- Moving the hand upward produces upward coordinates.
- Moving the hand downward produces downward coordinates.
- Existing horizontal behavior remains correct.

Preserve one clear coordinate convention throughout the system and document it.

---

# 8. OBJECTIVE 3 — INVESTIGATE LANDMARK DISPLACEMENT WITH DISTANCE

The user reports that when the hand moves farther away, landmark points visibly shift.

Investigate whether the cause is:

- Vision landmark instability
- incorrect coordinate conversion
- preview/overlay mismatch
- aspect-ratio handling
- crop/letterboxing
- mirroring
- camera format dimensions
- camera orientation
- capture connection orientation
- incorrect scaling/normalization
- stale state
- a combination of the above

Do not assume the root cause.

Use the existing architecture and make the smallest correct fix.

If underlying Vision coordinates are valid normalized coordinates, coordinate conversion should remain stable regardless of hand distance.

Add deterministic synthetic tests proving valid normalized coordinates are not incorrectly shifted by distance-related transformations.

---

# 9. OBJECTIVE 4 — INVALID TRACKING / FALSE POSITIVES

At approximately 20 cm from the camera/screen, the user reports reduced reliability and false positives.

Review:

- Vision confidence handling
- minimum useful hand size
- low-confidence joints
- temporal persistence
- stale landmark reuse
- failed Vision requests
- tracking-loss transitions
- whether old landmarks survive a failed observation

### IMPORTANT

Never invent landmarks when Vision does not provide a valid hand.

If confidence is insufficient:

- report no valid hand / tracking lost as appropriate
- do not reuse stale coordinates as current coordinates
- do not generate a false positive hand state
- do not manufacture gesture input

Do NOT solve this simply by lowering thresholds.

---

# 10. OBJECTIVE 5 — SUPPORT UP TO TWO HANDS

Current runtime behavior represents only one hand.

Review the Vision request configuration.

If it is explicitly limited to one hand, update it to allow up to two hands.

Phase 1.1 should represent:

```text
0 hands
1 hand
2 hands
```

Do not redesign the entire application.

The gesture engine may continue using one selected/primary hand for now.

The Vision layer must no longer silently discard the second detected hand.

### Stable ordering

Define deterministic ordering for multiple hands.

Do not rely on arbitrary Vision result order.

Use an existing hand identity/selection concept if one exists; otherwise use a simple deterministic representation and document it.

### Tests

Add tests for:

- zero hands
- one hand
- two hands
- deterministic ordering
- no accidental loss of the second hand

---

# 11. OBJECTIVE 6 — DROPPED FRAMES / LOW LATENCY

Current metrics:

```text
Camera FPS: 30
Vision FPS: ~30
Vision processing: 11.6–30 ms
Capture → HandState: ~45 ms
Dropped frames: 22–23
```

The existing architecture intentionally drops frames when Vision is busy to avoid latency accumulation.

Do NOT replace this with an unbounded queue.

Target behavior:

> latest useful frame wins

The system should:

- avoid accumulating stale frames
- avoid processing old frames after newer frames are available
- avoid unbounded memory growth
- avoid increasing latency over time
- remain responsive
- maintain approximately real-time processing

Investigate why dropped frames occur.

If appropriate, implement or improve latest-frame-wins behavior.

Do not optimize blindly.

Do not sacrifice tracking correctness merely to make the dropped-frame counter reach zero.

---

# 12. PRESERVE ARCHITECTURE

Do not rewrite AirTrack.

Keep:

```text
AirTrackCore
    = pure Foundation
    = testable math/state/gesture logic

macOS App
    = Camera
    = Vision
    = Permissions
    = UI
    = macOS integration
```

Only modify `AirTrackCore` when a genuine coordinate/math/state fix is required.

Do not move AVFoundation, Vision, SwiftUI, or AppKit/macOS-specific dependencies into Core.

---

# 13. DO NOT MODIFY FUTURE GESTURES

Do NOT implement:

- cursor movement
- mouse click
- double click
- drag
- scroll
- right click
- CGEvent
- Accessibility automation
- Spaces
- Mission Control
- zoom
- horizontal swipe

Those belong to later phases.

---

# 14. TESTING REQUIREMENTS

Current baseline:

```text
85/85 tests passing
```

After Phase 1.1:

**All existing tests must continue passing.**

Add tests for:

### Coordinate conversion

- vertical orientation
- horizontal orientation
- mirror behavior
- aspect ratio
- edge coordinates
- corner coordinates
- top/bottom mapping

### Landmark identity

- explicit Vision joint → HandJoint mapping
- index chain
- middle chain
- ring chain
- little chain
- thumb chain
- synthetic coordinates preserving identity

### Hand representation

- zero hands
- one hand
- two hands
- deterministic ordering

### Invalid tracking

- no valid hand
- low confidence
- tracking loss
- tracking recovery
- stale landmark prevention
- failed observation does not create a false positive

### Stability

Where practical, add deterministic tests proving valid normalized coordinates remain unchanged through coordinate conversion regardless of simulated distance/scale context.

Do not create fake tests that merely mirror implementation code.

---

# 15. DOCUMENTATION

Update relevant documentation to reflect:

- explicit Vision joint mapping
- coordinate conventions
- Vision → HandState conversion
- overlay coordinate conversion
- mirror behavior
- aspect-ratio behavior
- invalid-hand behavior
- confidence handling
- two-hand representation
- deterministic hand ordering
- frame dropping/latest-frame strategy
- known hardware limitations

Create:

```text
PHASE1_1_RESULT.md
```

It must contain:

1. Problem
2. Root cause
3. Fix
4. Files changed
5. Tests added
6. Test results
7. Remaining risks
8. Exact local Mac validation steps

Do not mark Phase 1 complete.

---

# 16. REQUIRED LOCAL VALIDATION AFTER IMPLEMENTATION

The user will compile the new commit on the real Mac.

### A — Vertical movement

Move the hand slowly:

```text
bottom → top
top → bottom
```

Expected:

- landmarks move in the same physical direction
- no inverted vertical behavior

### B — Landmark identity

Open the hand.

Verify visually:

```text
indexTip  → actual index fingertip
middleTip → actual middle fingertip
ringTip   → actual ring fingertip
pinkyTip  → actual pinky fingertip
thumbTip  → actual thumb tip
```

Verify the white finger chains follow the correct fingers.

### C — Close distance

Test around the previously problematic close distance (~20 cm).

Expected:

- stable detection
- no obvious false positives
- no anatomically incorrect landmark assignment

### D — Normal/far distance

Move the hand gradually farther from the camera.

Expected:

- landmarks remain attached to the correct anatomical locations
- no large artificial shifts caused by coordinate conversion

### E — Two hands

Place two hands in the camera view.

Expected:

```text
Hands = 2
```

and both hands should be represented correctly if both are sufficiently visible/confident.

### F — Tracking LOST

Remove the hand.

Expected:

```text
Tracking = LOST
```

No stale landmark positions should be treated as current.

### G — Recovery

Return the hand.

Expected:

```text
HAND DETECTED
```

with correct landmark positions.

### H — Performance

Record:

```text
Camera FPS:
Vision FPS:
Vision processing:
Capture → HandState:
Dropped frames:
```

---

# 17. ACCEPTANCE CRITERIA

Phase 1.1 is successful only if:

- [ ] Vision joint identities are explicitly mapped correctly.
- [ ] Index chain follows the actual index finger.
- [ ] Other finger chains follow their actual fingers.
- [ ] Vertical movement is no longer inverted.
- [ ] Landmark conversion remains stable across hand distance.
- [ ] Invalid/low-confidence observations do not create false positives.
- [ ] Stale landmarks are not treated as fresh tracking.
- [ ] Vision can represent up to two hands.
- [ ] Existing 85 tests continue passing.
- [ ] New tests pass.
- [ ] No Phase 2 functionality was introduced.
- [ ] Documentation is updated.
- [ ] Changes are committed and pushed.
- [ ] User validates changes on the physical Mac.

**Passing CI is NOT sufficient to close Phase 1.1. Real camera validation is required.**

---

# 18. GIT REQUIREMENTS

Before finishing:

```bash
git status
```

Ensure there are no accidental unrelated changes.

Run all available tests.

Use GitHub Actions/macOS CI where possible.

Commit with a clear message, for example:

```text
fix: stabilize hand tracking and coordinate conversion
```

Push to the current branch.

Do not rewrite unrelated history.

---

# 19. FINAL RESPONSE FORMAT

Return exactly:

```text
## PHASE 1.1 RESULT

STATUS:
PASS / PASS WITH ISSUES / BLOCKED

ROOT CAUSE:
...

FIXES:
- ...
- ...
- ...

LANDMARK MAPPING:
- ...
- ...

TWO-HAND SUPPORT:
...

COORDINATE PIPELINE:
...

FRAME PIPELINE:
...

TESTS:
- Existing tests: X/X
- New tests: X
- Total: X/X

FILES:
- ...

COMMIT:
...

LOCAL VALIDATION REQUIRED:

A — Vertical movement
B — Landmark identity
C — Close distance
D — Normal/far distance
E — Two-hand detection
F — Tracking LOST
G — Recovery
H — Performance

IMPORTANT:
Do not declare Phase 1 complete.
The user must validate the fixes on the real Mac first.
```

---

# 20. FINAL RULE

**DO NOT START PHASE 2.**

Phase 2 begins only after the user confirms that:

1. landmarks map to the correct fingers,
2. vertical movement is correct,
3. distance changes do not cause incorrect landmark displacement,
4. false positives are controlled,
5. two-hand detection behaves as expected,
6. tracking loss/recovery remains correct,
7. performance is acceptable on the physical Mac.

Until then, Phase 1 remains **IN PROGRESS**.
