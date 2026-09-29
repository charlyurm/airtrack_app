# AIRTRACK — PHASE 3B MASTER SPEC
## Left Click + Drag

**Status:** Specification / ready for implementation  
**Depends on:** Phase 2.1 cursor + Phase 3A interaction/scroll foundation

---

## 1. Product Vision

AirTrack must feel like the user's hand is an extension of the Mac trackpad.

Phase 3B adds two fundamental interactions:

1. Left click
2. Drag

Priorities:

1. Naturalness
2. Precision
3. Responsiveness
4. Safety
5. Extensibility

Core principle:

> If intent is uncertain, do nothing.

## 2. Existing Behavior That Must Be Preserved

Phase 2.1 cursor behavior and Phase 3A cursor/scroll behavior are the foundation.

Do not regress:

- cursor mapping
- adaptive cursor smoothing
- dead zone
- active area
- peripheral tracking
- reacquisition
- tracking safety
- Accessibility
- Phase 3A scroll behavior

Integrate with the existing interaction architecture rather than replacing the cursor pipeline.

## 3. Left Click

Gesture:

**Index finger + thumb pinch**

```text
☝️ + 👍
     ↓
    🤏
```

A quick, intentional pinch with little/no movement should produce one left click.

Recognition must be relative to hand size and tolerant of normal hand/camera variation.

## 4. Click Intent

Consider:

- normalized pinch distance
- pinch trajectory
- approach velocity
- hold duration
- cursor/hand movement
- temporal stability
- tracking confidence
- whether drag has already been committed

Quick pinch + release without meaningful movement:

> LEFT CLICK

Pinch held + intentional movement:

> DRAG

Ambiguous behavior:

> NO ACTION

## 5. Drag

```text
🤏
 ↓
hold
 ↓
intentional movement
 ↓
DRAG
```

The dragged object follows the index finger.

Drag must not require an exact hand position.

## 6. Click vs Drag

### Click

```text
pinch
→ brief hold
→ little/no intentional movement
→ release
→ click
```

### Drag

```text
pinch
→ hold
→ intentional movement
→ mouseDown
→ drag
→ release
→ mouseUp
```

Use temporal + spatial evidence, not one arbitrary frame threshold.

All thresholds must be tunable and documented.

## 7. Naturalness

Do not require:

- exact pixel coordinates
- exact thumb/index overlap
- exact pinch speed
- rigid hand orientation
- exaggerated poses
- neutral pose between interactions

Tolerate variation in hand size, camera distance, rotation, finger angle, and small tracking noise.

## 8. Cursor During Click

During a click candidate:

- cursor remains usable;
- do not freeze unnecessarily;
- click occurs at the intended pointer location;
- no visible cursor jump.

If cancelled:

- no mouseDown;
- no mouseUp;
- no click.

## 9. Cursor During Drag

Once drag is committed:

- mouse button is held;
- pointer follows index;
- existing cursor mapping remains the source of coordinates;
- drag must not create a second cursor mapping system.

## 10. Drag Anchor

At drag start, establish a stable anchor:

```text
offset = anchorCursor - currentIndexPosition
```

During drag:

```text
cursor = currentIndexPosition + offset
```

Clamp to display bounds.

Do not reset the anchor every frame.

## 11. Tracking Loss During Drag

Expected:

```text
DRAG ACTIVE
    ↓
temporary tracking loss
    ↓
HOLD / recovery
    ↓
tracking returns
    ↓
continue drag
```

If recovery fails:

```text
mouseUp
→ terminate drag safely
```

Never leave mouseDown held indefinitely. No stale-position extrapolation.

## 12. Click Safety

Never click because of:

- UNKNOWN finger state
- isolated partial index/thumb observations
- stale landmarks
- ambiguous pose
- tracking loss
- an already active drag

Safest behavior:

> no action.

## 13. Interaction Continuity

Natural transitions must work:

```text
cursor → pinch → click → cursor
cursor → pinch → drag → release → cursor
```

No neutral-pose requirement.

## 14. Conflicts

If scroll is already committed:

> click must not fire.

Before click/drag commitment:

> intent remains undecided.

After drag commitment:

> click is cancelled.

After click commitment:

> drag is not retroactively created.

## 15. Future Gestures

Reserve architecture for:

- double click
- right click
- zoom
- 2-finger swipe
- 4-finger swipe
- 3-finger gestures
- 5-finger gestures
- customizable gestures

Do not implement those in Phase 3B.

## 16. macOS Events

Use public macOS event APIs.

Left click maps to a normal primary-button click.

Drag uses:

```text
mouseDown
→ mouseMoved
→ mouseUp
```

Do not claim synthetic input is identical to a physical trackpad.

## 17. Safety

Guarantee:

- no stuck mouseDown
- no mouseUp without corresponding mouseDown
- no click after tracking loss
- no click after drag begins
- no drag without confirmed intent
- no stale extrapolation
- safe pause
- safe shutdown

## 18. Physical Validation

### Click

- quick natural pinch → exactly one click
- slow/ambiguous pinch → no accidental click
- small hand movements → no accidental drag
- different hand sizes/distances → consistent intent

### Drag

- pinch + hold + movement → drag
- index follows naturally
- no jump at drag start
- slow/normal/fast drag
- horizontal/vertical/diagonal
- edge-of-screen
- normal release
- brief tracking loss recovery
- prolonged tracking loss safely releases

### Regression

- cursor remains as good as Phase 2.1
- scroll remains as validated Phase 3A
- click/drag do not interfere with scroll

## 19. Definition of Done

Phase 3B is done when:

- click is natural and reliable;
- drag is natural and reliable;
- click vs drag is correctly separated;
- tracking loss is safe;
- cursor remains stable;
- scroll remains stable;
- automated tests pass;
- macOS build passes;
- physical validation passes;
- no stuck-button safety issue remains.
