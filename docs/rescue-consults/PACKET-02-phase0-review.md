# Fable Consult Packet 02 — Phase-0 Slice Review & Playtest Brief

> Fable 5 review of the BUILT Phase-0 slice, S32 (2026-07-13). Companion agent: `a4dde65f5237b0baf`.
> Fable's read: structurally the right slice; two of my choices beat the Packet-01 spec
> (latched `tellHoldMin=1.2`; style as a SEPARATE 2nd stamp that never touches the base GOTCHA).

## A) CHAD'S PLAYTEST CHECKLIST (priority order — fly it cold)
Gate: *did you grin at the 3rd catch, and push your luck for one more before the waterfall?*
1. **First catch reads as "the squirrel jumped TO you"?** Wrong→teleport/pop. Knobs: `arcApexHeight` 10→14; if it chases sideways, `arcConvergeFrac` 0.85→0.75.
2. **Slow-mo = gift or stumble?** Hitch→`slowmoEaseIn` 0.11→0.15. Lost-control→`slowmoScale` 0.25→**0.45** (first move). No punch→`slowmoSnapBack` 0.20→0.14.
3. **Did you SEE the tell before the catch?** (watch the squirrel, not the reticle). At 130/s, 0.4s=52 studs but sphere=28/42 → the tell may fire INSIDE the sphere. If never seen: `tellLeadTime` 0.40→0.60.
4. **Trigger fairness both ways:** a near-hover must NOT fire (else raise `closingGateFrac` 0.40→0.50); a fast pass that SHOULD catch and doesn't = robbery (worse) → `triggerRadius` 28→34 or gate 0.40→0.30. **Bias generous.**
5. **Back-riders read as riding, not cargo?** (tells us if rider idle-sway is next).
6. **At 2/3 near the waterfall — real "one more or bank it?"** Always-bank→`deliverBonus` 25→40; never-deliver-early→`triageAt` 60→75.
7. **Updraft ride = victory lap or chore?** >10-12s hold = tax → `updraftStrength` 210→280.
8. **Triage (last 60s) reads as "world helps" or "game stole my squirrels"?**
9. **Round size:** competent adult should land **5-8** saves/120s. <4 → shrink `valleyRadius` 1000→700. 9+ no tension → raise stakes not count.
10. **Did you start a 4th round voluntarily?** (outranks 1-9.)

## B) TOP 5 FEEL RISKS a can't-playtest build likely got wrong (ranked)
1. **Flying through 0.25× while sim is real-time** — the seam shows for ~0.7s. Fix: `slowmoScale` 0.45; or shorten the dilated portion (start snap-back AT contact).
2. **Arc re-fit every frame = visible homing** (reads fake, kills "it jumped"). Fix: fit ONCE at launch, correct only inside the converge window, hide the final snap inside the feather burst.
3. **Tell firing inside the sphere** (see A3) — anticipation→payoff is the whole grammar. Fix: `tellLeadTime` 0.6 + make the plant pose LOUD.
4. **Stamp pile-up** (GOTCHA+style+SWIFT+woohoo in ~1.5s = noise). Fix: strict sequence w/ gaps (GOTCHA at contact → style +0.4s only if >×1.5 → woohoo 0.5s after snap-back). Never 3 at once.
5. **Dead travel between catches** (11 in r=1000 ≈ 250+ studs apart; style decays half-life 2s). Fix: **cluster squirrels in 3-4 GROVES of 2-4** → catch chains + style continuity. Cheapest high-leverage world change.

## C) HIGHEST-LEVERAGE JUICE UPGRADE NEXT
**Make the back-riders ALIVE** — per-rider idle loop (breathing sway off flapPhase, tail flick, look-around), a hop-and-settle when a new one lands, all riders throwing starfish arms in a dive. Why it wins: the ride is 30-60s/loop of screen-time carrying the aww between 1s beats; converts carry from an inventory number into *three little lives on your back* = makes "one more before the waterfall" an emotional bet. Pure Motor6D on rigs already built; delivery payoff free (riders leap OFF onto the pad, reuse the arc in reverse).

## D) AGE 5-20 GUT CHECK
- **5-yo bounces off the closing GATE** (they fly slow/wobbly → silent rejection = cruelest failure). Fix: FTUE gate ~0.15; on a slow flyby that enters the sphere but fails the gate, the squirrel waves excitedly (no catch, no fail sound) — failure has a face. **Never silence.**
- **5-yo waterfall nav:** when carrying ≥1, a faint gold streamer arcs from the eagle toward the waterfall (diegetic compass, zero UI).
- **15-yo finds the catch hollow by round 3** (it's guaranteed) → mastery must live in style, which is under-exposed. Fix: **BLAZING catches visibly different IN THE BEAT** (deeper slow-mo, bigger burst, gold GOTCHA). Same guaranteed catch, escalating spectacle for executed lines.
- **Numbers:** `styleMultMax 3` + 2s half-life needs groves (B5) to be reachable. 11/120s → skilled clears the field; decide finite-round (better tension) vs topped-up respawn (better for young kids) — explicit Chad read.

## E) REPORT-BACK for Packet 03
1. Verbatim first utterance at catch #1; did the grin hit by catch #3?
2. Saves/round ×3, and count **robberies** vs **freebies**.
3. Saw the tell before any catch (yes/never/sometimes), unprompted.
4. Slow-mo verdict: gift / hitch / lost-control.
5. The "one more?" moment: happened? at what carry/time? which choice?
6. Deliver-loop seconds (decide→pad); chore or victory lap?
7. Style: chased on purpose? highest × seen? did SWIFT/BLAZING fire?
8. Where his eyes were during a catch (squirrel / reticle / HUD).
9. Triage: helped vs robbed (verbatim).
10. Started round 4 unprompted? First thing he says it NEEDS.
11. Which rbxasset sound ids actually resolved (from Packet 01 §E).

## THE 3 THINGS THAT DECIDE "YES, KEEP BUILDING"
1. **The leap reads as a leap** (A1/B2) — the jump-to-you story lands even gray-box → the hook is real.
2. **Flying stays fun THROUGH the beat** (B1) — if slow-mo costs control, the two pillars fight = structural, fix first.
3. **The push-your-luck moment occurs unprompted** (A6/E5) — one genuine "…one more" = the loop has a heartbeat.
