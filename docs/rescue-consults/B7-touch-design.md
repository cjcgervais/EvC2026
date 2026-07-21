# B7 — Touch/mobile input design spec (Fable consult, CHAD-GATED)

> Design consult for MASTER-PLAN packet B7 (Chad S42 directive #3: "could be fun on mobile too";
> Gate-C precondition per the S41 audit). NOTHING here is built. Chad answers §7's one question,
> then ONLY packets B7-P1/P2 get built — the proof-of-feel flight — before anything else exists.
> Scope: touch. Gamepad is parked as B7-P6 (§6) — its right answer differs from touch's.

## 0. The architectural fact that decides everything (pinned)
The ENTIRE signed-off aim law consumes exactly ONE input: the per-frame pixel delta at
`BirdController.client.luau:2495` (`UserInputService:GetMouseDelta()`). Everything Chad loves —
the world-anchored cursor (`aimTargetDir`, :211), the tight curl, the S26 screen-circle clamp +
rim-pinned sustained turn (:2534-2559), the lead washout (:2594), the CS-1 keyboard mute, the PD
instructor — lives DOWNSTREAM of that line, in LOCKED math that never knows what device produced
the delta. Therefore: **touch is a DELTA-SOURCE ADAPTER above :2495, never a new control law.**
Kernel untouched (it was never in question); the instructor byte-identical; CS-8's math unedited.
Any candidate that cannot be expressed as "produce a delta stream" is surgery inside locked code
and is rejected on architecture before feel is even argued.

## 1. The aim analog — candidates, ranked

### A (RECOMMENDED) — THE FINGER-DRAG CURSOR: mouse-parity, two regimes
Your finger drags the SAME green cursor ring. Mapping:
- **DRAG regime:** finger displacement/frame x `touchDragGain` -> the dx/dy the mouse would have
  produced -> the unchanged pipeline (swing `aimTargetDir` about camera axes, cone clamp, circle
  clamp). One finger-px = ~1.3-1.6 mouse units (phone px are physically smaller — a dial).
- **HOLD regime (the rim-pin analog):** a locked mouse has infinite travel; a finger runs out of
  glass. So: a finger held > `touchBandPx` (~60) from its touch anchor emits a synthetic delta
  stream at a rate proportional to the overshoot. The cursor pins against the S26 circle ->
  `rimBinding` stays true -> the lead washes out (:2594) -> full plant-rate sustained turn,
  EXACTLY the mouse's held-throw.
- **Lift:** stream stops -> cursor stays WORLD-ANCHORED -> the nose finishes the chase -> arrival
  shaping fades back in. The mouse's throw-end behavior, verbatim.
CS ledger: preserves CS-8's math AND its felt character (drag = swing; the cursor stays where you
put it; the nose catches it). All other CS rows: §2. Catch chain §3.1: untouched (§3). Kernel:
source swap only — zero instructor/kernel edits.
Failure mode + tell: the band boundary reads as a detent — "I keep swiping over and over to hold
a turn" (rate too low / band too big) or "a nudge becomes a turn" (band too small). Both are
dials (`touchBandPx`, `touchHoldRate`), not architecture — tunable live at the proof-of-feel.

### B — TAP-THE-SKY (absolute placement): rank 2, the fallback
Press -> `ScreenPointToRay` -> world direction -> write `aimTargetDir` directly (through the same
cone + circle clamps); hold = keep pinning to the finger ray (rim-hold sustained turn works);
lift = stays world-anchored. The kid floor is spectacular (touch the squirrel's halo; the eagle
goes). Why it ranks below A: (1) it is a SECOND WRITE PATH into the locked CS-8 block — the swing
math is bypassed, so this is surgery inside the locked function, not a source swap; (2) a 60-deg
cursor jump slews `aimApplied` at `aimResponse` 13/s -> near-instant full deflection = SNAP
turns; the felt SWING is the loved feel, and B deletes it; (3) your finger occludes the squirrel
at exactly the moment that matters; (4) every stray UI touch is an aim command (gating
whack-a-mole). Graft note: B's best trait can later ride ON A (double-tap = assist-snap the
cursor toward a beacon) without replacing the law — choosing A does not forfeit B's kid floor.

### C — THE SWING-RATE STICK: rank 3 for touch — but the RIGHT answer for gamepad
A persistent right-side pad; deflection = cursor swing RATE fed through the same delta seam.
Architecturally clean (pure source), world-anchoring preserved on release — but every fine
correction becomes rate-integration (the mouse's 1:1 position character is gone; micro-aim goes
mushy) and a visible stick invites the thumbstick-flying mental model. Ceiling below the read
for touch. PARK IT: sticks are native rate devices, so C IS the gamepad adapter (B7-P6).

### KILLED (do not resurrect)
- **Virtual thumbstick -> pitch/roll directly:** bypasses the instructor entirely = a SECOND
  control law; forks the feel (mobile players fly a different, worse game); no cursor, no CS-8;
  ceiling = generic mobile flight sim. Violates the settled aim law by construction.
- **Tilt/gyro:** posture-hostile (a 5-yo on a couch, a phone lying flat), no rim-pin analog,
  drift, and it fights the slow-mo watch-the-catch beats. Precision floor below the catch.
- **Tap-to-fly-there autopilot:** deletes P2 — the approach IS the skill of the sacred catch; an
  autopilot flies the approach for you. Also needs a path solver = a new system. (Distinct from
  B: B sets a DIRECTION you still have to fly; this flies it for you.)

## 2. LOCKED registry ledger (CS-1..CS-9, row by row)
- **CS-1** (keyboard overrides aim): touch has no keyboard -> `kb.*` stay 0, the gate rests
  inert. NO touch gesture claims the override role in v1. Unchanged by all candidates.
- **CS-2** (upright free-look orbit): LOOK button hold + other-thumb drag writes ONLY
  `freeLook.yaw/pitch` through the existing clamp path. Orbit math untouched.
- **CS-3** (free-look vertical inverted): sign preserved as spec'd. FLAG: drag conventions may
  read opposite on glass — if Chad wants it flipped ON TOUCH ONLY, that is a per-device sign
  dial logged as a NEW row, never an edit to CS-3.
- **CS-4** (free-look HOLD): the LOOK button = identical edge semantics (press ->
  `setFreeLook(true)`, release -> false; focus-loss failsafe intact; CS-2 exit snap on release).
- **CS-5 / CS-6 / CS-9** (no auto-level / grip / dive-rest): kernel rows — untouched by
  construction; the flap slider feeds the EXISTING `flapThrottle` ramp; a dive still rests.
- **CS-7** (control mapping): the locked row is the keyboard/mouse mapping — touch ADDS a
  parallel mapping beside it. Procedure: after Chad's proof-of-feel verdict, the touch mapping
  enters the registry as a NEW row (CS-10), citing the :2495 seam. CS-7's text is never edited.
- **CS-8** (nose-chases-world-cursor): the crux — candidate A preserves math + felt swing (§1).

## 3. The catch-gate chain (§3.1) — untouched by construction
`RescueRules.eligibility` (`BirdController:2049`; server envelope per the A2 amendment) consumes
position/velocity/carry — there is no input-device term anywhere in the chain, so no adapter can
move it. The parity oracle keeps client/server in lockstep regardless of device. ONE WATCH for
the mobile FTUE: touch pilots will average slower, so the closing gate (0.30 x glide) may reject
more beginner flybys — if the tell appears ("I flew right past him and nothing happened"), the
dial is the EXISTING `ftueRadiusMult`/`ftueGateFrac` applied per-platform. A Chad tuning call
later; NOT part of B7, and never a weakening of the guaranteed catch (P1: trigger => catch).

## 4. The other controls (rescue-era; combat keys are moot)
| Desktop | Rescue role | Touch v1 |
|---|---|---|
| Shift/Ctrl sticky `flapThrottle` | energy | **FLAP SLIDER**, left edge, vertical, notch at glide-0 — the sticky throttle made VISIBLE; writes the same variable |
| Space (hold) free-look | scan | **LOOK button** (hold), lower-left; the other thumb drags the orbit |
| LMB strike | none (catch is proximity-auto) | **NOT BOUND** — the mobile gift of P1: zero buttons for the sacred beat |
| RMB aim-zoom | scan aid | **CUT v1**; candidate: pinch = zoom (deferred, P3+) |
| Wheel camera zoom | comfort | pinch (deferred) |
| R respawn | recovery | pause-sheet menu item — NOT a thumb button (5-yo accidental-reset guard) |
| 1-4 / F | combat-era | absent |

**Thumb zones.** 5-yo floor: a ONE-FINGER game — the whole surface not claimed by a control is
the drag surface; no simultaneous inputs ever required; glide + drag + auto-catch is a complete
round. Targets >= 9mm (slider >= 64px wide, LOOK >= 72px), bottom corners, safe-area respected.
15-yo ceiling: the two-thumb claw — left thumb rides the flap slider (energy management) and
taps LOOK mid-glide; right thumb rim-pins sustained turns and band-holds dives. The ceiling
ports because the instructor is IDENTICAL — depth is device-neutral by construction.

## 5. What must change outside input
- **Camera:** NO composition edit (LOCKED). Two identity-default dials only, judged at the
  proof-of-feel: `Camera.mobileFOVBoost` (0; try +6 if a 6-inch valley feels tunnel-y) and a
  chase `mobileDistMult` (1.0). Chad's call in flight; revert = identity.
- **HUD scale + safe areas:** reticle sizes are px constants (cursor ring 48px :266, nose 18px
  :246, `aimCursorEdgeMarginPx` 48 `GameConfig:1520`) -> viewport-scaled with physical-size
  floors; notch/rounded-corner safe areas on every GUI.
- **Stage-1 legibility at phone DPI:** halo/chevron were certified on a desktop monitor; the
  same angular size on a 6-inch screen is ~1/3 the physical size. Add a minimum PROJECTED-size
  clamp for chevron/halo billboards; headless-gate the envelope (FX feel-gate pattern), Chad
  certifies the read. Flag `Rescue.mobileLegibility`.
- **Perf (S43 pinned: ~1160 alive particles / 30 non-shadow PointLights):** the LIGHTS are the
  low-end cliff — 30 point lights exceeds a low-end phone's forward-renderer budget even
  shadowless; NOT survivable at 30fps with the particle load. Mobile tier: **lights <= 8,
  particles <= ~550**, master dial = `Fire.maxVisualBurning` 30 -> **12** (each burning cell
  carries flipbook + emitter + light, so ONE dial moves all three), vortex trails off, feather
  pool halved. Mechanism: `GameConfig.Quality` tiers keyed off `UserInputService.TouchEnabled`
  + a memory heuristic; desktop tier = identity (byte-identical). The fire SIM is server-side
  and untouched — the burn and the balance stay bit-identical; only render density changes.
  Extend `tests/perf.spec.luau` to assert the mobile envelope headlessly.

## 6. Packet breakdown (dependency order; each independently gated + revertable)
- **B7-P1 — `TouchAimAdapter` (pure module) + spec.** `step(state, touch, dt, cfg) -> dx, dy`
  synthetic delta. Flag `Controls.touchAim=false` (inert). Lune spec: mouse-PARITY ORACLE (a
  scripted drag sequence yields exact px-delta equality with the mouse path's expectation),
  band properties (motion stops inside the band -> zero output; overshoot -> monotone rate
  proportional to overshoot; release -> zero forever), no-NaN storm, determinism.
  `[gate: tests]`
- **B7-P2 — THE PROOF-OF-FEEL (the cheapest decisive flight).** A one-line seam at
  `BirdController:2495` (adapter delta when flag+touch, else `GetMouseDelta`) + a bare unstyled
  flap slider. No HUD pass, no perf tier. Chad flies Studio Device-Emulator touch (or tablet
  Team Test). THE flight that answers §7. Felt target, in his words: "it's still MY eagle
  chasing MY cursor — the same curl." The tell it's wrong: the detent tells in §1-A, or "it
  feels like a different game." Revert: flag false = byte-identical.
  `[gate: CHAD — the aim decision]`
- **B7-P3 — Touch HUD layout** (styled slider, LOOK, pause sheet + respawn, safe areas,
  viewport-scaled reticles). Flag `UI.touchLayout`. `[gate: tests + batched Play]`
- **B7-P4 — Mobile perf tier** (§5 budget + perf.spec mobile envelope).
  `[gate: tests + device smoke]`
- **B7-P5 — DPI legibility clamp** (§5). Flag `Rescue.mobileLegibility`.
  `[gate: FX feel-gate + batched Play]`
- **B7-P6 — Gamepad = candidate C on the same seam** (stick deflection -> delta rate).
  Mini-consult when scheduled; not a touch blocker. `[gate: design -> tests -> batched Play]`
Order: P1 -> P2 **(CHAD GATE — nothing past this line gets built if the answer changes)** ->
P3 -> P4/P5 (parallel) -> P6.

## 7. THE ONE QUESTION FOR CHAD
**On a phone, should your finger MOVE the cursor ring, or PLACE it?** — **DRAG** (your finger
drags the same green ring: drag to swing it, hold past a small dead-band to keep turning, lift
and it stays while the nose finishes the chase — mouse-parity, my recommendation) or **TAP**
(the ring jumps to wherever you touch — easiest for little kids, but the swing becomes a snap).
Answer "DRAG" or "TAP" in one word and B7-P1/P2 build exactly that adapter for you to fly
before anything else exists.

## 8. Pillar check
P1: the catch stays guaranteed and needs ZERO buttons on touch — the sacred beat is
device-neutral by construction. P2: the identical instructor means the skill IS the approach on
every device; speed-as-style intact. P3: input-only, no tone surface; respawn tucked behind the
pause sheet so a 5-yo can't self-eject. P4: untouched. Kid floor: one finger is a complete
game. Perf: the §5 caps are named and machine-pinned before any phone ever runs it.
