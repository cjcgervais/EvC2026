# The LOCKED-SPEC gate — control-spec guardian

This is the single most important rule in the project. Chad, verbatim:
*"significant aspects of the control need to be maintained and protected. If I ask
for it to be a certain way we can't change it collaterally to do something else —
we have to foresee and not compromise on the control of flight."* Collateral
regressions to control feel are, in his words, *"the single biggest way this
project goes backwards."*

The eagle flight / control / camera feel is **SIGNED OFF** — the crown jewel.
Treat every CS row below as protected. This gate runs in the PLAN step whenever a
change touches **control, camera, input, flight-feel, or the aero kernel.**

## The gate — run this before editing (do not skip on "it's a one-liner")

1. **Grep + read the live registry.** The authoritative list is in
   `docs/HANDOFF.md` under "LOCKED FLIGHT-CONTROL SPECS." Read it there — this
   file summarizes, but HANDOFF is source of truth and may have newer rows/status.
2. **Match your change against every CS row.** For each one, answer: *does my
   change touch, or interact with, this behavior?* Include second-order effects
   (input assembly, camera up-vector, aim gating, stamina, energy terms).
3. **Foresee collateral (the failure mode that keeps happening).** The classic
   bug: a change "to do something else" silently altered a locked behavior —
   keyboard-authority once curved his loops via the still-active aim pull. Ask:
   *what else reads or writes the same state my change does?*
4. **If it touches a LOCKED row, or intent is at all fuzzy → STOP and ASK.** Do
   not reinterpret or "improve" a locked behavior. Implement his literal ask, not
   your guess (he has explicitly rejected reinterpretations before).
5. **Protect the kernel invariants** (see below) — some are not CS rows but are
   equally load-bearing.
6. **Checkpoint before you edit** (commit/tag) so any regression is one revert away.
7. **After the change, the playtest checklist must re-confirm the touched CS
   rows still hold** — name them explicitly in the checklist you hand Chad.

## The registry (summary — HANDOFF is authoritative)

Status: **LOCKED** = player-confirmed, do not change · **SPECIFIED** = implement
exactly, pending Chad's verify · **MUST-FIX** = specified but code violates it.

- **CS-1 — Keyboard fully overrides mouse-aim.** While ANY of Q/W/E/A/S/D is held,
  the cursor has ZERO pull on ALL axes (a held S makes a *straight* loop); release
  → aim resumes. GLOBAL gate in `onFlightStep`. *"This one can't change anymore."*
  Never re-add per-axis blending; never "solve" it by re-anchoring the cursor.
- **CS-2 — Free-look = UPRIGHT spherical orbit.** Full 360° yaw; pitch soft-stops
  just shy of straight up/down (`Camera.freeLookPitchLimitDeg` = 85); operator
  stays world-upright (horizon level, never rolls/inverts). The over-the-top
  unbounded orbit is RETIRED (it flipped him upside down).
- **CS-3 — Free-look vertical is INVERTED** (mouse-up = look down). One-line sign
  at the `freeLook.pitch` input site. ⚠️ The sign has flipped across sessions and
  a memory records the opposite preference — **confirm with Chad, do not guess.**
- **CS-4 — Free-look toggles on SPACE** (tap on/off, not hold); survives crow-swap.
- **CS-5 — NO auto-leveling.** Nose stays where pointed; AoA changes ONLY on input
  (`STABILITY_RATE=0`, both `recoverNoseDownRate=0`).
- **CS-6 — Grip model "flies where you point"** (velocity follows the nose;
  requires `cl0 > 0` — never set `cl0=0`). This is what keeps it stall-free
  without auto-level.
- **CS-7 — Control mapping** (the full keymap: A/D bank, Q/E yaw, W/S pitch,
  LShift/LCtrl throttle, LMB strike, RMB awareness-zoom, wheel zoom, F formation,
  R respawn, 1–4 possess crow). See `CLAUDE.md` Controls.
- **CS-8 — Mouse-aim = nose-chases-WORLD-cursor** (world-anchored direction; the
  nose reticle chases and resolves on it; camera lags the heading).
- **CS-9 — A DIVE is a REST** — no stamina cost + stamina REGENS while diving
  (wings tuck; even with Shift/Ctrl held). Stamina drains only for active flapping
  in non-dive flight. **PLAYTEST-CONFIRMED.**

> **Never silently drop or reinterpret a row.** When Chad confirms or specifies a
> new control behavior, add a CS row (in HANDOFF) — that is part of CLOSE.

## Kernel invariants that MUST survive (not all are CS rows)

- `cl0 > 0` (grip safety) — never `cl0 = 0`.
- Auto-leveling OFF: `STABILITY_RATE = 0`, both `recoverNoseDownRate = 0`.
- Keyboard-first control.
- **stall < spawn < cruise** ordering must hold.
- `GRAVITY_G` is the master **loft knob** — a *tunable*, currently **1.3** (swept
  2.0 → 1.5 → 1.3), NOT a fixed invariant. The real invariant: `AIR_DENSITY`
  scales with it in lockstep (`GRAV_SCALE`) so the stall/cruise/dive ordering
  holds at any value. (Older notes citing "GRAVITY_G=2.0" predate the sweep.)

## Do-not-reopen list (without a fresh, explicit Chad ask)

The eagle flight model's **calibration** is signed off: the lift curve, gravity,
stall math, energy retention, camera, and mouse-aim. The frontier is **combat +
the crow + the 1-v-4**, not eagle flight. If a combat/balance change would force a
kernel recalibration, flag it and ask before proceeding — flight == balance, but
the loved feel wins ties unless Chad reopens it.
