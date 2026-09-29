# AIRTRACK — PHASE 2.1
## Adaptive Cursor & Peripheral Hand Tracking

### Repository / Workflow

- GitHub: `charlyurm/airtrack_app`
- Branch: `claude/gifted-carson-iyjqxg`
- Current validated commit: `1e1cf4c`
- Architecture: macOS SwiftUI + Vision + AirTrackCore Swift Package
- Claude Code works in the cloud/Linux environment; the user pulls and validates on a physical Apple Silicon Mac.
- Do NOT ask the user to run Claude locally.
- Do NOT rewrite unrelated parts of the application.

---

## Physical Validation of Phase 2

The user physically validated Phase 2 on a real Apple Silicon Mac.

| Test | Result | Observation |
|---|---|---|
| A — Accessibility | PASS | Permission works |
| B — Center | PASS | Cursor centers correctly |
| C — Horizontal | PASS | Correct direction |
| D — Vertical | PASS | No inversion |
| E — Corners | PASS | Correct mapping |
| F — Jitter / Dead Zone | PASS | Stable |
| G — Fast movement | PARTIAL | Cursor follows but feels delayed / slightly frozen |
| H — Distance / tracking | PARTIAL | Tracking quality degrades near edges |
| I — Tracking loss | PASS | Cursor stops correctly |
| J — Recovery | PARTIAL | Works but feels slightly frozen |
| K — Two hands | PASS | Only one hand controls cursor |
| L — Active Area | PARTIAL | Tracking is lost before the useful edge |

### Additional observations

- Low smoothing is much faster, but feels somewhat frozen / unnatural.
- Medium/current smoothing feels normal.
- High smoothing feels more natural and pleasant, but introduces additional latency.
- The user perceives a small lag behind fast finger movement.
- Near the lower edge, the index may remain visible while much of the palm leaves the useful image region.
- N1: index near edge with palm visible → tracking works.
- N2: index farther toward edge with partial hand outside → tracking lost.
- N3: more hand outside → tracking lost.
- The lower usable area is especially affected when the palm becomes horizontal and only the index remains clearly visible.

# PHASE 2.1 OBJECTIVES

1. Adaptive / velocity-aware cursor response.
2. Safer partial-hand / index continuity tracking near frame edges.
3. Improve reacquisition so it does not feel frozen.
4. Preserve all currently passing Phase 2 behavior.

# OBJECTIVE 1 — ADAPTIVE / VELOCITY-AWARE CURSOR RESPONSE

Current pipeline:

```text
HandPresenceFilter
→ primary hand
→ index tip
→ mirror
→ active area
→ dead zone
→ sensitivity
→ EMA smoothing
→ reacquisition blend
→ ScreenMapper
→ MacOSEventController
→ CGEvent mouseMoved
```

Do NOT simply remove smoothing.

Implement adaptive smoothing based on movement velocity.

Desired behavior:
- Very small movements → prioritize stability and jitter suppression.
- Normal movements → smooth and natural.
- Fast intentional movements → reduce effective smoothing / increase responsiveness.
- When movement stops → return to stable, smooth behavior without oscillation or overshoot.

Requirements:
- deterministic;
- bounded;
- no overshoot;
- no oscillation;
- no cursor teleportation;
- no frame-rate-dependent instability;
- preserve dead-zone, sensitivity, mapping, and logical display behavior.

Prefer a small, explicit adaptive smoothing mechanism in AirTrackCore.

Do not introduce timers, async work, queues, or UI dependencies into AirTrackCore.

The algorithm must be unit-testable with synthetic sequences.

Consider velocity in normalized input/cursor space rather than hardcoded screen resolution.

Expose sensible parameters through `AirTrackSettings` if appropriate and sanitize/clamp them.

# OBJECTIVE 2 — PERIPHERAL / PARTIAL-HAND TRACKING

Audit first:
- `HandPresenceFilter`
- Vision landmark conversion
- `HandState`
- `HandOrdering`
- primary-hand selection
- index-tip confidence
- required joints
- minimum valid joint count
- hand-size calculation
- stale-frame handling
- tracking-loss semantics

Do not change anything until the exact rejection path is understood.

We need a controlled degraded-tracking mode:

```text
FULL TRACKING
↓
PARTIAL TRACKING
↓
INDEX-CONTINUITY TRACKING
↓
LOST
```

This must NOT become "any index-like point moves the cursor."

Partial tracking must require sufficient evidence such as:
- index-tip confidence;
- temporal continuity with the previously tracked index;
- reasonable maximum movement per frame;
- previously established valid hand identity;
- recent full-hand tracking;
- known chirality when available;
- continuity of other surviving landmarks when available;
- plausible finger geometry;
- no implausible jumps;
- no stale observations.

Safety rules:
- Full-hand acquisition remains strict.
- Partial tracking is allowed only AFTER a valid hand has already been acquired.
- Unknown partial-index detections must NOT activate cursor control.
- If the established hand is lost for too long, return to normal `WAITING FOR HAND` acquisition.
- Do not use indefinite extrapolation.
- Do not keep moving using stale positions.
- Invalid confidence/continuity must enter normal tracking-loss behavior.

# OBJECTIVE 2 — EDGE-OF-FRAME BEHAVIOR

Allow the index to move farther toward the edge while maintaining control when the index itself is reliably observed and continuity is established.

Do not:
- invent landmarks;
- extrapolate indefinitely;
- keep moving after actual tracking is lost;
- create false-positive hands.

If Vision cannot reliably observe the index anymore, stop movement safely.

# OBJECTIVE 3 — REACQUISITION

Current physical result:
- tracking loss works;
- recovery works;
- recovery feels slightly frozen.

Desired behavior:
- loss → no stale cursor movement;
- return → establish valid current input;
- cursor smoothly reconnects to current finger position;
- no visible freeze;
- no jump;
- no old-position following;
- no long fixed delay.

Use the current cursor position as the starting reference when appropriate and unit test the transition.

# OBJECTIVE 4 — PRESERVE EXISTING BEHAVIOR

Do NOT regress:
- horizontal direction;
- vertical direction;
- mirror behavior;
- active-area mapping;
- screen corners;
- logical display coordinates;
- dead zone;
- sensitivity;
- smoothing settings;
- primary-hand selection;
- two-hand behavior;
- tracking-loss safety;
- no stale position reuse;
- accessibility handling;
- CGEvent safety.

Phase 2.1 remains CURSOR MOVEMENT ONLY.

Do NOT implement click, double click, drag, scroll, right click, Spaces, Mission Control, zoom, or other gestures.

# ARCHITECTURE REQUIREMENTS

Maintain the current separation.

AirTrackCore:
- pure deterministic logic;
- geometry;
- cursor mapping;
- smoothing;
- dead zone;
- cursor controller;
- tracking continuity logic if platform-independent.

macOS app:
- Vision;
- AVCapture;
- CGEvent;
- permissions;
- SwiftUI.

Do not move macOS-specific APIs into AirTrackCore.
Do not add unnecessary dependencies.
Do not introduce networking or cloud APIs.
AirTrack remains local-first.

# TEST REQUIREMENTS

Before implementation:
1. Inspect current repository and Phase 2 implementation.
2. Read `PHASE2_RESULT.md`, `PHASE2_PROMPT.md`, and relevant architecture/testing docs.
3. Identify exact root causes.

## Adaptive cursor tests
Include:
- stationary input;
- micro jitter;
- slow movement;
- normal movement;
- fast movement;
- acceleration;
- deceleration;
- stop after fast movement;
- no overshoot;
- deterministic output;
- bounded latency/response;
- parameter sanitization.

## Partial tracking tests
Include:
- full valid hand;
- partial hand after valid acquisition;
- valid index continuity;
- invalid isolated index;
- sudden index jump;
- low-confidence index;
- stale observation;
- prolonged partial tracking;
- timeout back to `WAITING FOR HAND`;
- reacquisition requiring full valid hand after timeout;
- no cursor movement from unknown partial detection;
- no stale position reuse.

All existing Phase 2 tests must continue passing.

Target: zero test failures.

Run:
- macOS arm64 tests;
- Linux tests if supported;
- macOS app build with `xcodebuild`.

# PERFORMANCE

The existing pipeline is latest-frame-wins.

Do not introduce:
- blocking work;
- additional queues;
- unnecessary timers;
- sleeps;
- synchronous waits;
- expensive per-frame operations.

Keep cursor latency low and avoid unnecessary allocations in the per-frame hot path.

# UI / DEBUG

If useful, expose minimal debug information:
- tracking mode: `FULL`, `PARTIAL`, `LOST`;
- effective smoothing;
- estimated input velocity;
- index confidence.

Do not clutter production UI. Debug information can use the existing debug UI.

# DOCUMENTATION

Create/update:

## `PHASE2_1_RESULT.md`
Include:
- status;
- exact root causes found;
- architecture changes;
- adaptive smoothing design;
- partial tracking design;
- safety rules;
- tests added;
- test counts;
- build result;
- known limitations;
- local validation protocol.

## `PHASE2_1_PROMPT.md`
This specification is the implementation and traceability document.

Also update relevant:
- `README.md`
- `Documentation/ARCHITECTURE.md`
- `Documentation/TESTING.md`
- `Documentation/ROADMAP.md`

# GIT

Do not rewrite history.
Do not force push.
Keep commits logical.

Suggested commits:
1. `feat: add adaptive cursor response`
2. `feat: add safe peripheral tracking`
3. `test: cover phase 2.1 behavior`
4. `docs: document phase 2.1 validation`

Fewer logical commits are acceptable.

Push final result to:
`claude/gifted-carson-iyjqxg`

Keep working tree clean.

# LOCAL VALIDATION PROTOCOL

After implementation, provide a concise physical test protocol.

## Existing
A — Accessibility
B — Center
C — Horizontal
D — Vertical
E — Corners
F — Jitter
G — Fast movement
H — Peripheral tracking
I — Tracking loss
J — Reacquisition
K — Two hands
L — Active Area

## Phase 2.1
M — Adaptive smoothing:
- slow movement;
- fast movement;
- acceleration;
- deceleration;
- stop;
- compare perceived latency and naturalness.

N — Peripheral index tracking:
- full hand;
- index near edge;
- partial hand;
- partial palm;
- lower edge;
- upper edge;
- left edge;
- right edge.

For every test define setup, action, expected result, and PASS/FAIL.

# IMPORTANT IMPLEMENTATION PRINCIPLE

Do not optimize for passing unit tests only.

The goal is:

> "Move my index finger naturally in front of the camera and have the Mac cursor feel like an extension of my hand."

It should feel:
- responsive;
- smooth;
- predictable;
- stable;
- low-latency;
- forgiving near the edges;
- safe when tracking is genuinely lost.

Do not claim success until:
1. all tests pass;
2. the macOS app builds;
3. the implementation is documented;
4. the user can physically validate the new behavior.

# FINAL RESPONSE FORMAT

Return exactly:

```text
PHASE 2.1 RESULT

STATUS: READY FOR LOCAL VALIDATION / BLOCKED

ROOT CAUSE:
- ...

IMPLEMENTED:
- ...

ADAPTIVE CURSOR:
- ...

PERIPHERAL TRACKING:
- ...

REACQUISITION:
- ...

SAFETY:
- ...

TESTS:
- ...

BUILD:
- ...

COMMITS:
- ...

FILES:
- ...

LOCAL VALIDATION:
A ...
B ...
...
N ...

KNOWN LIMITATIONS:
- ...
```

Do not claim physical validation.
The user must perform the physical Mac validation.
