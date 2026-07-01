# HANDOFF — Eagles vs Crows

Read this first. It tells the next agent exactly where the project stands, the one decision that's already been made for you, and the prioritized work queue. Pair it with `CLAUDE.md` (architecture + contracts), `docs/RESEARCH.md` (why the numbers are what they are), and project memory (`MEMORY.md` index).

> ## 🦅 SESSION 13 — CS-1 FIX + ARCADE ENERGY RETENTION + UPRIGHT FREE-LOOK CAMERA (2026-06-30) — **THE authoritative cold-start state**
> Worked the SESSION 12 queue under the LOCKED-SPEC process directive. **All three items build-green (`build.ps1`) but UNPLAYTESTED.** No aero-kernel *calibration* was reopened (lift curve / gravity / stall math of `v1.0-eagle-flight` untouched); the one kernel edit is a single bounded, climb-only energy term. Commits on `master`: `d3c3396` (CS-1) and `f61c19a` (energy + camera). Checkpoint/revert points: `d3c3396`, the tag `v1.0-eagle-flight`.
>
> **What landed (UNPLAYTESTED):**
> 1. **CS-1 — keyboard fully overrides mouse-aim (GLOBAL gate).** `onFlightStep`: while ANY of Q/W/E/A/S/D is held, `aimGate = 0` zeroes the ENTIRE `aimApplied` contribution on ALL three axes → a held S now makes a **straight** loop (was curved by the old per-axis roll/yaw aim-pull). Release every key → mouse-aim resumes. Registry CS-1 → **FIXED, pending playtest**.
> 2. **Energy retention (the TOP ask) — one coherent climb-E model.** New per-profile **`energyRetention`** (Eagle **0.7** / Crow **0.4**) in `GameConfig.Profiles`; consumed in `FlightPhysics:Update` right after the drag term. It adds back `energyRetention × GRAVITY·velDir.Y` **only while CLIMBING** (`velDir.Y > 0`) — cancelling that fraction of the *gravity-along-path* bleed (the dominant climb decel, NOT drag). **Dive/stoop untouched** (gated to climbs), capped `<0.95` (never noclip), and `flapDragRetention` is kept as the small extra under-power drag bonus. Eagle>Crow is the 1-v-4 energy lever.
> 3. **CS-2 revised — UPRIGHT free-look camera (Chad chose "stop at vertical").** Free-look is now an upright spherical orbit: `camUp = Vector3.yAxis` (operator never rolls/inverts), full 360° yaw, `freeLook.pitch` clamped to **`Camera.freeLookPitchLimitDeg = 85`** so it soft-stops just shy of straight up/down instead of flipping over the top; base dir flattened to horizontal for symmetric up/down. Fixes "I end up looking at my eagle sideways/upside down."
>
> ### ▶ NEXT AGENT — get Chad a Studio playtest of all three; log outcomes in the registry. **Playtest checklist:**
> - **CS-1:** In mouse-aim, put the cursor off to one side, then hold **S** — the loop must be **straight** (no drift back toward the cursor); same for a held A/D roll or Q/E yaw. Release all keys → cursor regains authority when you move the mouse. *(Locked — must be exact.)*
> - **Energy:** Dive to build speed, level and pull a **~30° climb without hard-turning** — speed should bleed **slowly** and you should **zoom back near your start altitude**; try an **ascending defensive spiral**. Then confirm the **crow can't do it as well** (feels heavier/bleeds faster). Confirm the **dive/stoop still accelerates the same** (retention is off in dives). Knob: `Profiles.Eagle/Crow.energyRetention` (0..0.95). If it reads floaty/noclip, lower it; if still bleeds too fast, raise toward 0.9.
> - **Camera:** Space into free-look, pan **all the way up and all the way down** (should soft-stop near vertical, never flip), spin **fully around** — the **horizon must stay level and you never end up sideways/upside down**. Knob: `Camera.freeLookPitchLimitDeg` (raise toward 90 for a steeper look, lower if the extreme jitters). Verify mouse-up/down direction still matches your preference (CS-3 sign, one line if inverted).
>
> **flight==balance reminder:** the eagle now keeps more climb-E → re-check that **4 crows can still corner/mob it** (the energy asymmetry is intentional but the mob must still pressure it). Ground truth is Chad's Studio Play. ONE change at a time; sweep the knobs live before re-tuning.
>
> ---
>
> ## 🦅 SESSION 12 — FREE-LOOK / KEYBOARD-AUTHORITY / FLAP-ENERGY pass + NEW TOP ASK: WAR-THUNDER-ARCADE ENERGY RETENTION (2026-06-30) — *(superseded by SESSION 13 above; kept for detail)*
> Chad handed live testing notes across this session and I worked them. **Everything below is build-green (`build.ps1`)
> but UNPLAYTESTED.** None of it reopened the aero-kernel *calibration* (the lift curve / gravity / stall math of the
> loved, tagged `v1.0-eagle-flight`); it's camera, input-blend, and one bounded energy term. Committed on `master`.
>
> **What landed this session (all UNPLAYTESTED):**
> 1. **Free-look = FULL vertical orbit (all the way up/down, over the top / under the belly).** The real limiter was
>    NOT the pitch clamp — it was the HORIZON-LOCK, which built the camera up by projecting world-up ⟂ view direction
>    and **degenerated at the poles** (froze on last-good up, so you could never pass straight up/down). Replaced with
>    an **orbit-derived up** (`camUp = orbit:VectorToWorldSpace(Vector3.yAxis)` in `updateCamera`): no pole singularity,
>    and because the orbit is built only from `freeLook.yaw/pitch` about WORLD axes it still never inherits the bird's
>    bank (original horizon-lock intent preserved). Free-look pitch is now **unbounded** (removed the
>    `FREE_LOOK_PITCH_LIMIT` constant + the `freeLookPitchLimit` config knob). Vertical was also **inverted** per Chad
>    (mouse-up looks down). *Chad's earlier "raise the clamp" attempt failed precisely because the clamp was never the cap.*
> 2. **Keyboard authority over mouse-aim (per-axis).** The input assembly was SUMMING `kbPitch + aimApplied.pitch`, so
>    QWEASD fought the aim autopilot. Now a per-axis gate (`1 - |kb.axis|`) **suppresses the mouse-aim command on any
>    axis a flight key is held** → the keyboard cleanly OVERRIDES mouse-aim; release the key and aim resumes on that
>    axis. Per-axis, so you can bank on the keyboard while the mouse still holds pitch. (`onFlightStep` input block.)
>    - **🔒 LOCKED CONTROL SPEC — MUST FIX (Chad, 2026-06-30; my per-axis version is WRONG).** Chad, verbatim: *"even
>      with the key depressed (say S to make a loop) I am not making a straight loop because the cursor is pulling me
>      back to it where they meet. I want to disable the cursor altogether from having pull while pressing a key; when I
>      let go I can find it easily because I'm moving it and I let go of the key that took its authority. This is a
>      critical part of flight control I need this game to have. It can't change anymore."* **True root cause:** my gate
>      is **PER-AXIS** — holding S suppresses PITCH aim but the aim autopilot STILL drives ROLL/YAW toward the cursor,
>      so a pure-pitch loop gets curved off. **REQUIRED BEHAVIOR (locked):** while **ANY** flight key (Q/W/E/A/S/D) is
>      held, the mouse-aim cursor has **ZERO pull on ALL axes** (full manual keyboard flight); the moment every flight
>      key is released, mouse-aim resumes (he re-finds the cursor by moving the mouse — that's intended, NOT a bug).
>      **FIX:** in `onFlightStep`, replace the per-axis gate with a **global** gate — if `kb.pitch~=0 or kb.roll~=0 or
>      kb.yaw~=0` then zero the ENTIRE `aimApplied` contribution (all three axes) this frame. Do NOT re-add per-axis
>      blending, and do NOT "solve" it by re-anchoring the cursor (that was my wrong guess — he wants the cursor to
>      simply have no authority while a key is down). See the per-axis gate in `onFlightStep` (the `aimGateP/R/Y` block).
> 3. **Flap energy retention (FIRST pass — the seed, not the answer).** New per-profile `flapDragRetention` (Eagle 0.6 /
>    Crow 0.4): while actively flapping in **level/climb** flight (scoped OUT of dives so the loved stoop is untouched)
>    it cancels part of the drag bleed so you hold/build speed through a soft climb. `flapThrust` bumped Eagle 800→900,
>    Crow 150→185. ⚠️ **Chad's next ask supersedes the SCOPE of this** — he wants retention EVEN WHEN NOT FLAPPING and
>    aimed at the gravity bleed in climbs. Treat #3 as the starting point to GENERALIZE, not a finished feature.
>
> ### ▶ NEXT AGENT — TOP PRIORITY: WAR-THUNDER-ARCADE ENERGY RETENTION (Chad's exact ask, do this FIRST)
> Chad, verbatim intent: *"way more energy retention **even when NOT flapping** — going straight I shouldn't bleed speed
> so quick, especially climbing ~30° lose speed a LOT slower. Make it feel like **War Thunder arcade**: after a dive, as
> long as you don't turn too much you can BOOM then ZOOM back up to a decent altitude without much loss. More energy in
> the climb would let me fly **ascending defensive spirals** over an opponent I out-energy. Make the flight model better."*
>
> **Measurable target:** a boom-and-zoom that RECOVERS most of its altitude — dive to build speed, then zoom-climb back
> near the start height IF you don't hard-turn; a 30° climb bleeds speed slowly; a sustained **ascending defensive
> spiral** over a lower-energy target is achievable; and (flight==balance) the **crow can't do it as well** (the eagle
> is the energy fighter — this asymmetry IS the 1-v-4 lever).
>
> **THE KEY PHYSICS INSIGHT (so you don't flail on drag knobs):** the dominant speed-bleed in a CLIMB is **gravity's
> component along the flight path, not drag.** In `FlightPhysics:Update` gravity is a constant `(0,-GRAVITY,0)` (~L211);
> at climb angle θ the along-path deceleration = `GRAVITY·sin θ`. With GRAVITY≈70 (GRAVITY_G=2.0) a **30° climb costs
> ~35 studs/s² of pure gravity decel** — that's the fast bleed Chad feels. **Drag** (`(parasiticDrag + inducedDragK·CL²)
> ·q / mass`, ~L250) is comparatively tiny in straight, low-CL flight, so **cutting drag alone will NOT deliver the
> arcade feel.** Real energy conservation is exactly *why* a climb costs speed — WT **arcade** deliberately fudges it.
> So the lever is an arcade **partial cancellation of the gravity-along-path bleed** in climbs (an "instructor / energy-
> retention" term), not more drag-tuning.
>
> **Recommended approach — GENERALIZE #3 into ONE coherent energy model:**
> - Add a **per-profile persistent `energyRetention` (0..1)**, NOT gated on flapping, that reduces the along-path
>   gravity deceleration while climbing (nose/velocity above the horizon). Concretely: in the gravity/integrate step,
>   take the gravity component projected onto `velocity.Unit` when climbing and add back `energyRetention ×` it (the
>   arcade "your engine/inertia keeps your E"). **Eagle retention HIGH, Crow LOWER.**
> - **Fold `flapDragRetention` into this** (or keep it as a small extra under-power bonus) — don't ship two overlapping
>   half-mechanisms; make it one legible model with one or two knobs.
> - Optionally trim `parasiticDrag` slightly for the "straight-line shouldn't bleed" note, but LEAD with the gravity lever.
> - **Cap it (<1) and keep a cost** so it never reads as noclip — the stall/stamina limits and the service ceiling still apply.
>
> **Guardrails (do NOT skip — this touches the loved kernel):**
> - **Checkpoint before editing** (`git commit`/tag). Revert points: this session's commit, and the tag `v1.0-eagle-flight`.
> - **Do NOT reopen** the invariants: `cl0 > 0` stays (grip safety), auto-leveling stays OFF (`STABILITY_RATE=0`,
>   `recoverNoseDownRate=0`), `GRAVITY_G=2.0`, keyboard-first. **stall < spawn < cruise must survive.**
> - **Preserve the loved DIVE/stoop feel** (kept out of #3 on purpose) — energy retention must not make the dive floatier,
>   break `diveSpeedCap`, or reopen the tuned `FLAP_DIVE_*` fade.
> - **flight==balance on every number** — an eagle that keeps climb-energy is a stronger boom-and-zoomer, so re-verify 4
>   crows can still corner/mob it. Per-profile `energyRetention` is the balance lever.
> - Ground truth is **Chad's Studio Play** (build resolves but does NOT run Luau). ONE change, sweep live with Chad, THEN
>   commit the chosen values. Develop via the **loop-orchestrator** skill (roblox-game profile).
>
> **Code pointers:** `FlightPhysics.luau:Update` — gravity term (~L211), drag polar (~L250), GRIP block (~L336);
> `GameConfig.Profiles.Eagle/Crow` (add `energyRetention` as a structurally-symmetric key in BOTH profiles); the shared
> `GameConfig.Flight` table for any global knob. Full design note in the **`flight-energy-retention-arcade`** memory.

---

## 🔒 LOCKED FLIGHT-CONTROL SPECS + PROCESS DIRECTIVE (Chad, 2026-06-30 — READ BEFORE TOUCHING CONTROLS)

**Chad's directive, in his words:** *"We need to start making features an SOP, lock in… significant aspects of the control need to be maintained and protected. If I ask for it to be a certain way we can't change it collaterally to do something else — we have to foresee and not compromise on the control of flight. My testing needs to be logged."* He is also considering **an agentic skill that manages these SOPs and keeps the game from going off the rails.**

**What this means for you (hard rules):**
1. **Flight-control behaviors Chad has specified are LOCKED.** Do not change, reinterpret, or "improve" them. Implement exactly what he asked.
2. **No collateral changes.** Before ANY control/camera/input edit, check it against the LOCKED CONTROL SPECS registry below and reason about interactions — a change made "to do something else" must not alter a locked behavior as a side effect. (This exact failure just happened: adding keyboard-authority curved his loops via the still-active roll/yaw aim pull. See CS-1.)
3. **Log every playtest note** here (append to the registry / a session block) with the outcome, so decisions are durable and not re-litigated.
4. **When in doubt about a control's intended feel, ASK — don't guess.** A wrong guess that ships is worse than a question.
5. *(Proposed, not yet built — do not build unless Chad asks)* a **control-spec guardian skill** that enforces this registry. Natural home: extend `loop_skill/` (the loop-orchestrator SOP set) with a control-spec check gate, or a new skill that lints control edits against this registry. Capture the idea; leave it for Chad to greenlight.

### LOCKED CONTROL SPECS registry (protect these; grep before editing controls)
Status key — **LOCKED**: player-confirmed, do not change · **SPECIFIED**: Chad-asked, implement exactly, pending his verify · **MUST-FIX**: specified but current code violates it.

- **CS-1 — Keyboard fully overrides mouse-aim (cursor has ZERO pull while any flight key is held).** While ANY of Q/W/E/A/S/D is held, the mouse-aim cursor exerts **no pull on ANY axis** (full manual keyboard flight — e.g. a held S makes a *straight* loop); on full release, mouse-aim resumes (re-finding the cursor by moving the mouse is intended). **STATUS: SPECIFIED — FIXED S13, pending Chad's playtest.** Now a GLOBAL gate in `onFlightStep` (`aimGate = (kb.pitch~=0 or kb.roll~=0 or kb.yaw~=0) and 0 or 1`, commit `d3c3396`). Do NOT re-add per-axis blending, and do NOT "solve" it by re-anchoring the cursor. **This one "can't change anymore" per Chad.**
- **CS-2 — Free-look is an UPRIGHT spherical orbit: full 360° yaw; pitch tilts up/down to a SOFT STOP just shy of straight-up/straight-down; the operator stays WORLD-UPRIGHT (horizon always level, never rolls or inverts).** **REVISED by Chad S13** — the prior "full over-the-top / under-the-belly UNBOUNDED orbit" is RETIRED: its orbit-derived up flipped the view upside down ("I lost my orientation and ended up looking at my eagle sideways… I want to stay upright, not sideways or upside down"). Chad explicitly chose *stop at vertical* over *pass over the top & re-level*. Impl: `camUp = Vector3.yAxis` (hard world-up) + `freeLook.pitch` clamped to `Camera.freeLookPitchLimitDeg` (85°) so `lookAt` never reaches the pole; base dir flattened to horizontal for symmetric up/down (commit `f61c19a`). STATUS: SPECIFIED (implemented S13; unplaytested).
- **CS-3 — Free-look vertical is INVERTED** (mouse-up = look down). STATUS: SPECIFIED (S13 preserved the S12 pitch sign; unplaytested — if it now reads wrong, it's the one-line sign at the `freeLook.pitch = freeLook.pitch - input.Delta.Y*s` input site, independent of CS-2).
- **CS-4 — Free-look toggles on SPACE** (tap on/off; not hold), survives crow-swap. STATUS: LOCKED (session 9).
- **CS-5 — NO auto-leveling.** The nose stays exactly where pointed; AoA changes ONLY on player input (`STABILITY_RATE=0`, both `recoverNoseDownRate=0`). STATUS: LOCKED (session 9, explicit Chad ask).
- **CS-6 — Grip model "flies where you point"** (velocity follows the nose; requires `cl0>0` — never set `cl0=0`). This is what keeps it stall-free without auto-level. STATUS: LOCKED (`v1.0-eagle-flight`).
- **CS-7 — Control mapping:** A=bank left / D=bank right; Q=yaw left / E=yaw right; W=pitch nose-down / S=nose-up; LeftShift=flap throttle up, LeftCtrl=down (sticky); LMB=strike; RMB=awareness zoom; wheel=eagle-distance zoom; F=formation; R=respawn; 1–4=possess crow. STATUS: LOCKED (see CLAUDE.md Controls).
- **CS-8 — Mouse-aim = nose-chases-WORLD-cursor** (cursor is a world-anchored direction; the nose reticle chases and resolves on it; camera lags the heading). STATUS: LOCKED (player-tuned, `mouse-aim-pursuit-model` memory).

> **Add new locked specs here as Chad confirms/specifies them. Never silently drop or reinterpret a row.**

---

## 🎯 AIM + CAMERA OVERHAUL — PLAYER-TUNED, COMMITTED & PUSHED (2026-06-30) — *(prior cold-start state; superseded by SESSION 12 above, still valid detail on the aim model)*
> You are inheriting a project whose **flight and now its aim/camera feel are the crown jewels** — Chad has called the
> flight "one of the coolest flight experiences I have experienced, no joke," and this session he live-tuned the
> **mouse-aim + camera** to match, ending on "**it's good there**" / "works fantastic." All of it is committed on
> `master` and pushed to `origin` (commit **`Aim overhaul: nose-chases-world-cursor…`**). **None of it touched the
> `v1.0-eagle-flight` aero kernel** — it's input-shaping, camera, and HUD only, so the loved flight model is intact.
>
> **The settled aim model (do not silently revert — it cost many iterations to land):** the **cursor is a
> WORLD-anchored direction** you swing with the mouse out to a big cone (the reachable circle) and it **stays put**;
> the bird's **NOSE (amber reticle, projected far out front) is the dependent thing that chases the cursor** and
> lands on it when it catches up. It **resolves** (unlike a screen-anchored cursor, which turns forever because the
> chase cam re-centres the nose). Catch-up is **snappy for small deflections, rate-limited by the eagle's turn/yaw
> rate for big ones** (gains saturate the command). The **camera follows the heading with an exponential LAG** in
> aim mode so the cursor hangs out on screen and the nose visibly lags/chases it (not a rubber-band back to centre);
> its up vector is **parallel-transported** so loops don't pole-flip and rolls don't spin the camera. Mouse-aim uses
> a **fixed chase distance** (zoom-independent). **Free-look:** cursor+reticle **fuse on the beak**. **RMB zoom:**
> focuses **into the reticle** (live beak direction) and fades the eagle. Full rationale is in the commit body and
> the **`mouse-aim-pursuit-model`** memory (updated).
>
> **▶ THE FEEL KNOBS** (all in `GameConfig`, one-line sweeps — Chad tunes these live, so know them):
> `Controls.aimAnglePerPixel` (cursor speed) · `aimPitchGain`/`aimRollGain` + `aimPitchDamp`/`aimRollDamp`
> (catch-up snappiness vs overshoot) · `aimLeadScreenFrac`/`aimMaxLeadDeg` (reachable-circle size) ·
> `Camera.mouseAimDistance` (aim pull-back, now 135) · `Camera.aimHeadingLag` (how long the cursor hangs out /
> nose lags) · `Camera.followSmoothing` (overall camera glide) · `Camera.loopVertStart`/`loopVertBand`/`horizonLevelRate`
> (loop-camera). Reticle sizes are `noseMarker`/`aimDot` in `BirdController`.
>
> **▶ NEXT — the frontier is COMBAT and the 1-v-4, not the aim/flight (those are landing).** In priority order:
> 1. **Strike — TALON PATH NOW PLAYTEST-CONFIRMED** ✅ (2026-06-30: Chad landed his first intentional talon kill on
>    a crow — the LMB → server auto-pick → talon-in-belly-zone → kill loop works end-to-end). Still to verify: the
>    **BEAK** path and the **1-v-4 balance**. ⚠️ Watch it: talon 4 s active / 2 s cd ≈ 67% uptime flirts with the
>    >50% "always-on" guardrail — if it plays eagle-favoured, cut talon `duration` / widen `cooldown` / drop
>    offensive damage FIRST (`GameConfig.Combat`).
> 2. **Un-defer the MAP** (already built — 16k arena + spires + thermals; strike now feels close enough) and **make
>    the AI crows MOB.** ⚠️ Playtest finding: the crows "are around, can be really fast and fly away, get scared and
>    crash" — so they still SCATTER instead of swarming. Re-weight `updateAICrows` (`GameConfig.Squad.avoidance` +
>    boids weights) so they close in and pressure the eagle. A 1-v-4 that can't mob isn't a real 4. See [[combat-directional-strike]].
> 3. **Tune the 1-v-4 matchup** — the Crow side + collision trades are the last big design frontier. Flight==balance:
>    reason about the whole 1-eagle-vs-4-crow fight on every number (`feedback-flight-balance-inseparable`).
>
> **How to fly it yourself:** you can't — only Chad's Studio Play validates. `build.ps1` resolves wiring but does NOT
> run Luau. So: reason hard, make ONE change at a time, keep `build.ps1` green, and tee up crisp playtest checklists.
> The bar Chad holds is high and worth it — the flight/aim feel is genuinely special. Make the combat live up to it. 🦅
>
> ---
>
> ## ✅ STRIKE MECHANISM REWORKED (2026-06-30, build-green, UNPLAYTESTED) → `docs/HANDOFF-reticle-map.md`
> After a first pass at the reticles, Chad redesigned the strike model (commit on `master`): **(a)** beak reticle
> re-COUPLED to the aim-error so **cursor-centred = straight & level** (the prior decoupled draw dove at centre);
> **(b)** dropped the left/right talon dichotomy → now **ONE beak zone (forward) + ONE talon zone (a belly ARC
> that swings with bank)**, and the **game auto-picks** beak-vs-talon by **which zone the nearest enemy is in**
> (`GameServer.enemyZone`); **(c)** per-zone timers per Chad — **talon 4 s active / 2 s cd**, **beak 2 s / 4 s**.
> HUD chips L/F/R → BEAK/TALON. **Map build-out (ask #2) is DEFERRED** per Chad until the strike feels right
> (already committed; leave it). **#3 (crows mob)** still needs a Play.
>
> **+ AIM CURSOR — relative virtual cursor, iterated TWICE (latest commits):** Mouse-aim is now a relative
> virtual cursor (`LockCenter` + `GetMouseDelta`). `aimVirtual` = the cursor's **deflection FROM THE NOSE CROSS**
> (zone centred on the nose → symmetric up/down; FIXED Chad's "cursor zone offset downward, can't reach the top").
> The cursor **stays where you put it** and drives the nose; `Controls.aimRecenterRate` is a **gentle** relax of
> the deflection back to the nose so a held deflection eventually straightens (default **3.0→1.0** so it doesn't
> rubber-band/fight you; `0` = fully persistent). See [[mouse-aim-pursuit-model]].
>
> **⚠️ OPEN AIM-FEEL FORK (top priority — needs live tuning WITH Chad):** "cursor-authoritative/persistent
> (low/zero `aimRecenterRate`; hold cursor off-centre = sustained turn, WT-style)" vs "self-resolving (higher
> rate; straightens on its own)." Chad's last steer: the CURSOR moves the bird, NOT the bird moving the mouse
> against him — so lean LOW/persistent and verify it can travel far & doesn't jitter. `aimRecenterRate` is the
> knob (it spans both regimes). Also re-verify the downward-offset is gone (cursor reaches the TOP of the screen).
>
> **Then playtest the STRIKE:** cursor-centred=level (beak reticle), the talon belly-arc swings with bank & the
> right zone auto-lights (crow below=TALON, ahead=BEAK), click throws the lit zone's strike w/ its duration/cd;
> watch 1-v-4 (talon 4s/2s ≈ 67% uptime). **Map build-out is DEFERRED** until the strike+aim feel is locked.
> **#3 crows-mob** still needs a Play. Knobs: `aimRecenterRate`/`aimMouseSensitivity`, `beakReticleDistance`,
> `talonReticleDistance`/`talonArcSpreadDeg`, `Combat.strikes` durations + `strikeSelectRange`. Don't reopen the
> loved flight kernel. ⚠️ Strike balance watch in `combat-directional-strike`.
>
> ## 🎯 (prior) strike reticles, beak-zone aim, build out the map ([`docs/HANDOFF-reticle-map.md`](HANDOFF-reticle-map.md))
> P1–P6 are landed + pushed and Chad has been live-testing them. His 2026-06-30 notes opened **three new asks**
> (full detail + pointers in **[`docs/HANDOFF-reticle-map.md`](HANDOFF-reticle-map.md)**): **(1)** a combat-aim
> UI — a **beak-zone aim reticle** (the cross is 600 studs too far out) plus **LEFT/RIGHT strike reticles that
> light by bank** (bank right → left reticle lights, bank left → right lights, matching the inverted strike
> mapping; the forward reticle follows the mouse); **(2) build out the map** for far-vision "eagle vision"
> perspective (render distance is already opened up — `StreamingEnabled=false` + thin atmosphere — but the world
> needs more legible distant terrain to fly against); **(3) verify the AI crows now MOB** (a flee regression was
> just fixed by reverting to gentle avoidance + a non-lethal AI terrain slide). **Don't reopen the loved kernel
> or regress the confirmed feel.** Recent commits since P6: zoom model fix + `StreamingEnabled=false`
> (`737336a`), inverted strike side + cursor 1/2 + stronger zoom (`2d5e8da`), AI no-suicide slide (`bbc87f0`),
> crow-flee fix + atmosphere (`a7201fd`).
>
> ---
>
> ## 🎯 P1–P6 FLIGHT-FEEL + COMBAT PASS — CODE-COMPLETE, BUILD-GREEN, UNPLAYTESTED (2026-06-30, night shift)
> A cleared-context agent worked the **entire** [`docs/HANDOFF-flight-feel-combat.md`](HANDOFF-flight-feel-combat.md)
> queue. None touch the `v1.0-eagle-flight` aero kernel (input/camera/HUD/config + server-combat only). Two
> commits on `master`: **`317f56b` (P1–P5)** = HUD SPACE-hint, **RMB aim/zoom**, **free-look "unstick"** (crisp
> near-1:1 orbit), Eagle **flap power + stamina** — this commit is the **checkpoint before P6**. **`0df2a37`
> (P6)** = the **directional-strike combat rework**: LMB-only, the eagle's **bank** picks left/right/forward
> strike, server-authoritative, each strike's offset cone **parries a ram AND deals offensive damage** (one
> catch-or-hit/window). HUD = single STRIKE bar + L/F/R armed-direction chips. Remote `WeaponHold` → `Strike`.
> Full detail in the new **[`docs/HANDOFF-flight-feel-combat.md`](HANDOFF-flight-feel-combat.md) "ALL SIX ASKS
> LANDED"** block and the `combat-directional-strike` memory. **NEXT: Chad must Studio-playtest — especially the
> P6 1-v-4 balance** (tune the three windows/downtimes/cones in `GameConfig.Combat.strikes`; the offensive pass
> is the lever to watch hardest — dial down or make defense-only if it skews eagle-favored). Carried-over still
> open: `StreamingEnabled=false`, richer sandbox / Sandbox mode.
>
> ---
>
> ## 🦅 EAGLE FLIGHT + CAMERA/CONTROL FEEL — PLAYER-CONFIRMED & TAGGED `v1.1-eagle-flight-feel` (2026-06-30, Playtest-3)
> Playtest-3 ("dude it is so good!") locked in a full **mouse-aim + camera feel** pass on top of the verified
> kernel. **All player-confirmed, committed & pushed to `origin/master`, tagged `v1.1-eagle-flight-feel`** (the
> new safe revert point; `v1.0-eagle-flight` remains the pure-kernel point). **None touched the aero kernel
> math** — these are input-shaping, camera, and cosmetic only, so the kernel stays `v1.0`-verified. What
> landed (full detail in [`docs/HANDOFF-flight-feel-combat.md`](HANDOFF-flight-feel-combat.md) "Landed"):
> mouse-aim with a tiny deadzone + **fully linear** ramp (`expo 1.0`) + higher authority gains; aim reticle
> clamped to a big centred circle (`aimCursorAreaFrac 0.875`); **free-look horizon lock** (stays world-level
> when you bank); **chase loop turn-over** (`Camera.loopFollowUp 0.8` — camera arcs over *with* the bird,
> "perfect"); **free-look pitch (mouse-up = up) + wider pole range** (`FREE_LOOK_PITCH_LIMIT 1.70`); fainter
> centre crosshair; a proper **white eagle tail**. **Don't regress any of these.**
>
> ### ▶ NEXT GRIND (still open) → same doc [`docs/HANDOFF-flight-feel-combat.md`](HANDOFF-flight-feel-combat.md)
> Five of the six Playtest-3 asks remain: **P1** HUD must headline **SPACE = toggle free-look** (the hint is
> also stale — says "hold"); **P4** **right-click = aim/zoom** anywhere (frees RMB from "beak"); **P5**
> free-look pan **"gets stuck"** → crisp near-1:1 orbit; **P2** more power per flap + **P3** more stamina
> (Eagle — reason 1-v-4); and the big one, **P6** — the **directional-strike combat rework** (LMB-only; the
> eagle's bank picks left/right/forward talon, each with its own duration + downtime; server-authoritative;
> balance-tuned). Plus carried-over sandbox items (`StreamingEnabled`, rich map / Sandbox mode). Full scope,
> pointers, config shapes, and acceptance criteria are in that doc. **Checkpoint before P6** (combat/balance).
> *(Superseded but kept for detail: [`docs/HANDOFF-flight-sandbox.md`](HANDOFF-flight-sandbox.md).)*
>
> ---
>
> ## ⚙️ (2026-06-29) flight + camera holistic redesign — IMPLEMENTED & largely player-confirmed
> The mouse-aim control law, energy tuning, and chase camera were rebuilt holistically on a `deep-research`
> pass (26 sources, 23 verified claims) instead of more band-aids. **What landed** (full rationale +
> citations in **[`docs/RESEARCH.md`](RESEARCH.md) §v4**; problem statement in
> **[`docs/HANDOFF-flight-tuning.md`](HANDOFF-flight-tuning.md)**):
> - **Mouse instructor → PD coordinated-flight controller**: symmetric deadzone+expo on both pitch & bank
>   (WT "nonlinearity"), rate/derivative damping to kill the turn porpoise, and a "ride-the-edge" AoA
>   protection (suspended while powered) so a started **loop now commits** instead of mushing.
> - **Chase camera → continuous, rate-limited full-3D chase direction** + shortest-path `CFrame:Lerp`:
>   **no azimuth snap / no pole flip through a full 360° loop** (the motion-sickness fix).
> - **Free-look → Space TOGGLE** (was hold); the world-referenced orbit holds its aspect.
> - Plant: `inducedDragK` eased for energy retention (keeps the n² EM cost); aerobatic-speed gate lowered.
> **NEXT AGENT: this needs a HUMAN Studio playtest** against the acceptance criteria in the flight-tuning
> doc, then re-tag the kernel. Tune against the §v4 target numbers, not by eyeball. The kernel is NOT back in
> its `v1.0-eagle-flight` HUMAN-VERIFIED state until that playtest passes.
>
> ### ▶ Playtest 1 (2026-06-29) — 3 FREE-LOOK-mode bugs, fixes prescribed
> First live test of the branch surfaced three **free-look-only** issues (mouse-aim mode tested OK). Full
> root-cause + copy-paste-ready fixes (all in `BirdController.client.luau`) in
> **[`docs/HANDOFF-freelook-fixes.md`](HANDOFF-freelook-fixes.md)**: (1) bird noses over into a dive when
> controls are released in free-look (frozen aim command should ease to 0 → hold attitude, keyboard-modifiable);
> (2) camera 180° flip during a loop in free-look (freeze the chase basis while free-looking → world-referenced);
> (3) free-look mouse pitch inverted (one sign flip). Do these next, then re-playtest.

---

## Status (2026-06-23)

### 🛫 First playtest happened (session 3) — two reported bugs fixed
Chad ran it in Studio, spawned as the Eagle. Two problems reported and fixed:

1. **"Stalls way too easily, not much lift" (Eagle) — FIXED (tuning, playtest-provisional).** Root cause: the eagle's *stall speed* (~75 studs/s) sat at its spawn speed (`glideSpeed × 0.6 = 78`) and below its 130 cruise, and it couldn't sustain cruise in level flight (flap thrust accel 380/12≈32 < cruise drag decel ≈41), so it flew permanently ~1.3° from the 18° stall AoA — any climb input stalled it. The crow was fine (stall ~26 vs spawn 57), so this was eagle-only. Changes: `Eagle.liftCoefficient 1.35→2.0` (stall speed → ~62), `Eagle.flapThrust 380→520` (can hold level cruise), spawn velocity `0.6→0.9 × glideSpeed` (both `FlightPhysics.new` and `GameServer.spawnBird`), and a **soft-stall floor** in `FlightPhysics` (`stallFactor` bleeds to 0.15 over `over*1.0` instead of collapsing to 0 over `over*1.6`) so a stall is a recoverable mush, not a death spiral. **Still needs playtest** — verify the eagle now cruises with margin and the crow's low-energy angles advantage is intact.
2. **"Can't respawn unless I stop + F5" — FIXED.** Two compounding causes: (a) `FlightPhysics` drives `Body.CFrame` directly, so birds had **no ground collision** and a crashed bird sank through the baseplate without dying; (b) the stale-ref bug (old desk-check note) — `applyDamage` destroyed the model but never removed it from `rec.birds`, so the solo-flight respawn check `#rec.birds == 0` was never true. Changes in `GameServer`: **`processGroundDeaths`** (Heartbeat: any bird with `Body.Position.Y < GROUND_KILL_Y=4` dies as cause `"crash"`), **prune dead models from `rec.birds`** in `applyDamage`, solo-flight branch now respawns on `not isPlayerAlive(rec.player)` (not `#rec.birds==0`), and a new **`Respawn` RemoteEvent** + **R key** for manual reset (debounced `RESPAWN_COOLDOWN=1.5s`; no Roblox-character reset exists with `CharacterAutoLoads=false`). `Respawn` added to the Remotes contract in CLAUDE.md.

**A multi-agent research+review pass (5 Roblox-SOP web-research agents + 6 per-module adversarial reviewers) ran this session.** It confirmed the tuning math (eagle stall ~62 vs spawn 117 vs cruise 130; flap thrust now sustains cruise) and surfaced real findings. A second batch of contained fixes from it was applied:

3. **Network-ownership handoff rubber-band — FIXED (was HIGH).** `BirdController` drove the Body the instant it existed client-side, before `SetNetworkOwner` actually transferred — so its CFrame writes fought the server's sim → snap/jitter at every spawn and crow-swap. Now `GameServer.trySetNetworkOwner`/`setServerOwned` set a `NetOwner` attribute (UserId / 0) on transfer, and the client's `acquire()` waits for `NetOwner == player.UserId` (5s best-effort timeout) before driving.
4. **Framerate-dependent control feel — FIXED.** `FlightPhysics` control smoothing was a fixed per-frame blend, so spool-up time varied by FPS (and feel = balance). Now `blend = 1 - inertia^(dt*60)` — identical at 60 FPS, constant in wall-clock at any framerate.
5. **AI crows ignored thermals — FIXED.** `updateAICrows` never called `SetThermalForce`, so the 3 server-simulated squadmates couldn't recover energy, sank, and crashed over a round (skewing the 1-v-4). Added `thermalForceAt` (mirrors the client sampler) into the AI step.
6. **Boids weights were inert — FIXED.** Separation was accumulated at physical magnitude while alignment/cohesion/goal were unit vectors, so it dominated ~5-10x and the GameConfig boid weights didn't actually govern formations. Separation is now `safeUnit`-normalized.
7. **Alt-tab fly-away + stale HUD — FIXED.** `BirdController` now clears held input on `WindowFocusReleased` (Roblox doesn't fire InputEnded on focus loss). `GameUI` now empties HP/SPD/ALT/stamina/stall during the death→respawn gap instead of freezing pre-death values.

`build.ps1` re-confirmed after every batch. Remaining review findings (lower severity or larger features) are in the queue below with research citations.

### 🪶 Second playtest (2026-06-24) — banking + a flight-model change
Chad flew the eagle again: banking reversed, "still not enough lift," dives wouldn't accelerate, recovery-from-falling too hard. Root cause of the cluster: **the flight path barely followed the nose in pure pitch.** The only thing realigning velocity toward the nose was the coordinated-turn step, throttled to ~25% unless *banked* — so nosing down built angle-of-attack instead of sending you down (→ stall, no acceleration), and pulling up while falling couldn't redirect motion. Changes:
- **Banking flipped** — `BirdController.keyBindings` A=+1 / D=-1 (A banks left, D banks right). Pure feel; flip back if wrong.
- **PATH TRACKING added** (the real fix) — new `GameConfig.Flight.PATH_TRACK_RATE = 2.2` (rad/s). `FlightPhysics` now rotates the velocity vector toward the nose at this base rate in *every* attitude (authority-scaled), with `sustainedTurnRate` adding tightness only when banked (still the eagle-wide/crow-tight lever). Now "point down = accelerate", "pull up = climb/recover" work; stall only really bites at low speed where authority (and thus tracking) fades. **This is a meaningful model change — re-verify the energy-fighter vs angles-fighter feel still emerges.**
- **Dive is now nose-based** — `isDiving = look.Y < -0.2` (no longer requires holding LeftCtrl), so nosing down lifts the speed cap to `diveSpeedCap` and accelerates you. LeftCtrl is now a *powered tuck* (extra thrust + dive-stamina cost) rather than the dive on/off switch.
- **More lift/forgiveness** — Eagle `liftCoefficient 2.0→2.4`, `stallAngleDeg 18→20`; soft-stall floor `0.15→0.3` (lift never fully dies, so path tracking can always pull you out). All PLAYTEST-PROVISIONAL.

**⚠️ Note on the ground-crash fix:** `Y < 4` is a stopgap. Birds still tunnel through the **spires/perches** (no obstacle collision at all). *(RESOLVED in session 5 — see below.)*

---

## Status (2026-06-24) — session 5: four queue items landed (code-complete, build-green, UNPLAYTESTED)

A fresh session worked the prioritized queue with no Studio access (build resolves but does **not** syntax-check Luau — Studio Play is still the only behavioral gate). Four substantive items landed, each `build.ps1`-verified. **All need a Studio pass** — they are reasoned + build-clean, not playtested.

1. **Real obstacle/ground collision — queue #4 DONE (replaces the `Y<4` stopgap).** New pure module **`src/shared/BirdCollision.luau`** sweeps a `workspace:Spherecast` (swept SPHERE, not a point ray — a point skips thin spires at 260+ studs/s) along each bird's per-step movement. `resolve()` returns: no-hit → fly on; closing speed ≥ `GameConfig.Flight.CRASH_SPEED (45)` → crash; below → slide along the surface. Wiring: **AI crows** resolve inline in `updateAICrows` (server owns them); the **client-owned possessed bird** slides on grazes locally for zero-latency feel (`BirdController.onFlightStep` step 2b) while the server authoritatively detects lethal crashes by sweeping its replicated position delta (`GameServer.processCrashes`, which replaced `processGroundDeaths`). Client doesn't clamp on lethal hits → the server reads a clean delta, so the two never disagree on death. Deep failsafe `Y < -40`. **Emergent balance to watch (flight==balance):** spires become deadly hazards the agile crow can thread but the fast, wide-turning eagle may clip in a turn-fight — verify this plays fair, tune `CRASH_SPEED`.
2. **Anti-cheat envelope — queue #5 DONE.** **`GameServer.processAntiCheat`** (Heartbeat, client-owned birds only; AI crows are trusted). Measures **server-observed** speed from position deltas (never client velocity). Two gates: a per-frame **teleport gate** (`TERMINAL × teleportMult 1.5` + ping pad) and a **leaky-bucket** sustained-speed check (ceiling = `TERMINAL × speedAllowMult 1.25` — based on TERMINAL, *not* `diveSpeedCap`, so an honest plummeting crow that free-falls toward terminal doesn't false-positive). Response ladder per player: **rubber-band** (snap to last good pos) → **reclaim ownership** at 3 strikes → **kick** at 6; strikes decay over clean flight. Legit server moves (spawn/respawn/swap) are whitelisted via **`markServerMove`** (grace window + baseline reset). All knobs in **`GameConfig.Security`** (`enabled=true`; flip false if it interferes with early feel-testing). `AttackRequest`/`SwapCrow` rate-limits were already enforced (`ATTACK_COOLDOWN`, `swapCooldown`).
3. **Spatial-hash perf foundation — queue #6a DONE (behavior-preserving).** New **`src/shared/SpatialHash.luau`** (uniform XZ grid, cell 64). `GameServer` rebuilds one **`birdIndex`** at the top of each Heartbeat; **`findNearestEnemy`** and **`processCollisions`** now query it instead of scanning every bird — turning the O(n²) pair sweep near-linear for the dozens-of-birds target. **Broad-phase only** — callers still do the exact distance test on live positions, so results are identical at current scale (the cell is far larger than any touch/engage radius + per-frame movement, so nothing in range is missed). Pure Luau, so it drops straight into a Parallel Actor later (#6b).
4. **Server robustness cleanups — part of queue #7 DONE.** (a) **Eagle promotion:** if the lone Eagle player leaves, `promoteToEagleIfNeeded` hands the role to a crow so the match doesn't dead-end on "Waiting for an Eagle…". (b) **Attacks are possessed-only:** removed `getActiveBird`'s "first living bird" fallback that let a crow whose possessed bird had just died fire from a server-simulated AI crow. (c) **BirdBuilder replication fix:** `AnimateWings` no longer writes an `IdlePhase` *attribute* every frame (~180×/s × 3 AI crows of pure network waste) — idle phase now lives in a weak-keyed Lua table.

**New `GameConfig` keys (contract):** `Flight.CRASH_SPEED`, and the whole `GameConfig.Security` table. **New Rojo entries:** `ReplicatedStorage.BirdCollision`, `ReplicatedStorage.SpatialHash` (`default.project.json`).

**Still NOT done from the queue:** flight-feel tuning (#2) and lose-lose collision tuning (#3) — both genuinely need playtest, untouched this session. Parallel-Luau Actors (#6b) — gated behind "only after it's fun". Remaining smaller #7 findings (Boids elevation-angle, dead flight levers `stallRecoverRate`/`AEROBATIC_MIN_SPEED`/`climbCeilingBonus`, free-look-on-swap) — left for an in-file opportunistic pass since they touch flight feel.

---

## Status (2026-06-28) — session 6: FlightPhysics **v2 kernel** rewrite (code-complete, build-green, UNPLAYTESTED)

Addresses the persistent "not enough lift, constantly stalls" complaint at its **root** (the prior `Cl→2.4` / `flapThrust→520` / spawn-speed / soft-stall-floor edits were all symptom patches). A fresh deep-research pass on **game flight-model implementation** (Vazgriz, brihernandez/SimpleWings, gasgiant Aircraft-Physics, Aerofly TMD; archived in `docs/RESEARCH.md` §"v2") confirmed the diagnosis independently and supplied the numbers. The kernel is a **drop-in rewrite** — same API + same readable fields, so `BirdController`, `GameServer` AI loop, `Boids`, and `BirdCollision` are untouched. **Git checkpoint committed before the rewrite** (`git log` → "Checkpoint before FlightPhysics v2 kernel rewrite") — revert `FlightPhysics.luau` + `GameConfig.luau` to roll back.

**Root cause (two flaws fighting each other):** (1) lift was `Cl·q·sin(AoA)` → **zero lift at zero AoA**, forcing the bird to fly permanently nose-high a few degrees from stall just to hold altitude; (2) the per-frame **path-tracker rotated velocity toward the nose**, i.e. drove AoA→0 → the no-lift condition. Any speed dip dropped authority, weakening lift+control+tracking together → self-reinforcing stall spiral.

**What landed (`FlightPhysics.luau` `:Update`, `GameConfig.luau`):**
1. **Real lift curve with baseline lift** — `CL(α)=cl0+liftSlopePerDeg·α`, capped at `clMax` at the stall angle, then a forgiving lerp to `postStallCl` over `stallPadDeg` (a recoverable mush, never 0). `cl0=0.30` is THE fix: the bird makes lift at zero AoA, so **level cruise is the hands-off trim** (verified calibration: Eagle trims ~0.47° AoA, stall ~65 < spawn 117 < cruise 130; Crow ~0.57° AoA, stall ~45 < spawn 86 < cruise 95).
2. **Drag polar `CD = CD0 + k·CL²`** (replaces `sin²`) — induced drag ∝ lift² ∝ g-load², so hard turns/climbs bleed energy → Energy-Maneuverability emerges. Drag is mass-normalized (heavier eagle retains energy); **lift is mass-independent** (`liftAccel = CL·AIR_DENSITY·v² / wingLoading`) so `wingLoading` is the stall-speed/turn lever.
3. **Static aerodynamic stability (weathervane) REPLACES path-tracking** — orientation rotates toward the airflow at `STABILITY_RATE·stabilityRate·authority`; AoA self-limits (anti-stall) **without** zeroing lift, and player pitch overrides it. Past stall, `recoverNoseDownRate` adds nose-down-toward-airflow so "do nothing" recovers. **Coordinated turn is now bank-gated only** (`sustainedTurnRate`, eagle-wide/crow-tight) — never acts in the pitch plane, so it cannot recreate the old bug. `rotateLookToward` preserves position (rotates basis only).
4. **Free-look hardened (it's LAW):** vertical clamp widened ±1.3→**±1.54 rad (~88°)** so you can look nearly straight up/down (yaw was already unbounded → full 360°); **free-look now survives a crow-swap** (`acquire()` re-arms to whether Space is still held instead of force-off — fixes queue #7 bug); added an in-code invariant note that free-look must never write `inputState`.

**New `GameConfig` keys (contract):** per-profile `cl0`, `liftSlopePerDeg`, `clMax`, `postStallCl`, `stallPadDeg`, `stabilityRate`, `recoverNoseDownRate`; `Flight.STABILITY_RATE`; recalibrated `Flight.AIR_DENSITY = 0.033`. **Removed:** per-profile `liftCoefficient` and the dead `stallRecoverRate`; **replaced** `Flight.PATH_TRACK_RATE` with `Flight.STABILITY_RATE`. (Dead levers `AEROBATIC_MIN_SPEED`/`climbCeilingBonus` still present — wire or delete in the tuning pass.) All numbers **PLAYTEST-PROVISIONAL.**

**MUST validate in Studio (queue #1 checklist applies, plus these):** (a) Eagle **holds altitude on neutral input / no flap** and only stalls when you yank the nose at low speed, then **recovers by easing off** (mush, not spiral); (b) nose-down accelerates, climb bleeds speed, dive reaches `diveSpeedCap`, banking turns (eagle wide / crow tight); (c) **AI crows hold altitude** (same engine — better lift should fix their sink/crash too); (d) **free-look: hold Space → look fully up/down/behind/360° while flying straight; swap crows 1–4 while holding Space → look persists**; release → snap back to chase; (e) no spawn/swap teleport (the `rotateLookToward` position fix), anti-cheat doesn't false-positive. Then **tune the 1-v-4 matchup** (queue #2) — energy-fighter vs angles-fighter feel, turn radii, dive recovery — reasoning about the matchup on every number.

---

## Status (2026-06-28) — session 7: flight FEEL dialed in (grip-model control) + a new north-star from Chad

Worked entirely through **live Studio playtests with Chad flying the eagle.** The recurring "not enough lift / too much stall / can't climb" was finally fixed at the **MODEL level** (not more number-patching), grounded in `docs/RESEARCH.md` §v2. **Chad confirmed the result "really good."** Two commits: `cf9646e` (vertical envelope) and `f58c465` (grip model + climb + mouse-steer). Full rationale in the `[[flight-vertical-envelope]]` memory.

### What landed (all PLAYTEST-PROVISIONAL but player-approved)
- **Grip-model control (the big one).** `Flight.GRIP_RATE = 2.2` rotates **velocity toward the nose in *every* attitude** (was bank-gated, turns-only), so pointing up climbs *with* lift instead of building AoA → stall. Weathervane auto-leveling slashed (`STABILITY_RATE 1.5 → 0.15`) — Chad wanted it "eliminated." **⚠️ INVARIANT CHANGE:** v2 originally *banned* velocity→nose rotation (it was the v1 spiral), but that only held because v1 had **zero baseline lift**; with `cl0 > 0` it is safe and is now the core feel. **Never set `cl0 = 0`.** (Supersedes the `[[flight-kernel-v2]]` "never rotate velocity toward the nose" note — see `[[flight-vertical-envelope]]` §5.)
- **Powered climb force.** `Eagle.flapClimbForce = 300` (ABOVE gravity 196): flapping nose-up climbs on wingbeats *even after a steep climb bleeds airspeed away* — realistic thrust can't beat gravity in a climb, so this is the explicit arcade climb. "Flap = climb until stamina/ceiling." Mass-independent.
- **Phugoid damping** (`PHUGOID_DAMPING 2.1`) tamed the vertical porpoise; released by pitch input / killed in dives.
- **Vertical envelope:** `SERVICE_CEILING`/`CEILING_BAND`/`FLAP_AUTHORITY_FLOOR 0.6`/`FLAP_LIFT_FLOOR`; wired the previously-dead `climbCeilingBonus` + `AEROBATIC_MIN_SPEED` (eagle can loop at speed) levers.
- **Momentum:** `Eagle.mass 12 → 16` (gentler accel/decel), `clMax 1.4 → 1.6`, `stallAngleDeg 20 → 24`.
- **Mouse-steer scheme** (locked virtual stick, split roll/pitch spring) built but **`Controls.mouseSteer = false`** — Chad reverted to keyboard-only while tuning. Flip to re-enable. (Keyboard holds the nose with no spring decay → rock-solid sustained climb.)

### 🎯 NEW NORTH-STAR (Chad, end of session 7): "the best flight model on Roblox" — real-scale raptor flight
The feel is good; now scale the **world** up to real raptor proportions. Three explicit asks — **but they share ONE hidden crux: world scale ↔ gravity ↔ speeds must be made consistent, and the whole lift/drag calibration is pinned to Roblox's default gravity (196.2 studs/s²). ULTRATHINK this. Read `RESEARCH.md` and AUGMENT it with fresh deep-research** (real golden-eagle stoop speeds & soaring altitudes, dive/stoop aerodynamics, Roblox flight-game scale conventions) **before touching numbers.**

1. **Eagle ceiling ≈ 2 km, not ~520.** `Flight.SERVICE_CEILING = 520` studs today (spawn Y=200 → only ~320 studs of headroom). Raise dramatically. At Roblox's ~0.28 m/stud, 2 km ≈ **7150 studs**; decide literal real scale vs a game "2k studs." Also raise `Thermals.maxHeight` (480) + reposition spawn, and re-check `TERMINAL_VELOCITY` (400) and the deep failsafe (`GameServer` `Y < -40`).
2. **Bigger test area — "it's so easy to crash."** Map = `GameServer.BuildMap` (~line 212): 4000×4000 baseplate at Y=-10, **7 spires clustered within ±900 studs** (heights 220-400), thermals on a 900-radius ring. Vertical play is cramped (spawn 200 ↔ ceiling 520) and hazards are dense relative to eagle speed (130 cruise / 320 dive). Expand the volume H+V, spread/raise/thin the spires, add world bounds, kill the crash-frustration. **Flight==balance:** a bigger sky reshapes the 1-v-4 (more room for the eagle to boom-and-zoom; harder for crows to corner it) — reason about it.
3. **Dive acceleration = real-life raptor speeds.** Golden-eagle stoop ≈ 240-320 km/h (≈ 67-89 m/s); peregrine ≈ 390. `Eagle.diveSpeedCap = 320` studs/s ≈ 320 km/h at 0.28 m/stud — already ~real at the *top end*, so the real issue is **acceleration**: gravity 196.2 studs/s² ≈ **5.6 g** at that scale, so the dive builds too fast/punchy and there's no altitude to develop a long stoop. Reconciling means choosing a scale and likely **re-tuning gravity — which RE-OPENS the entire lift/drag calibration** (`AIR_DENSITY 0.033`, `cl0`, stall speeds, trim AoA are all gravity-pinned; `[[flight-kernel-v2]]`). **Do NOT change gravity blind.** Solve scale → recalibrate → re-verify the `stall < spawn < cruise` invariant.

**Process:** loop-orchestrator skill (roblox-game profile) + compose `deep-research` for the scale/dive research. One system per iteration; **checkpoint before the recalibration** (it's systemic); the only ground truth is Studio Play with Chad. Honor flight==balance on every number. **Don't regress the now-good feel** (it's committed at `f58c465`).

---

## Status (2026-06-28) — session 8: REAL-SCALE recalibration (code-complete, build-green, UNPLAYTESTED)

Executed the session-7 north-star. Fresh deep-research (archived in `docs/RESEARCH.md` §v3) confirmed the crux **by measurement**: 1 stud = 0.28 m is Roblox-canonical, so real gravity = `9.81/0.28 ≈ 35` studs/s² and the default `196.2` is **5.6× too strong** — and the v2 *speed* envelope is already biologically real at 0.28 m/stud (golden-eagle stoop 240–320 km/h = 240–320 studs/s = our `diveSpeedCap`; soaring altitude 1350–2000 m = 4800–7150 studs). So only **gravity** and **world size** were wrong.

**The recalibration theorem (why it was safe):** drop `GRAVITY` and `AIR_DENSITY` by the *same* factor and the flight envelope is invariant — in `v_stall = √(g·WL/(clMax·ρ))` the factor cancels. **Verified numerically: Eagle stall = 61.0, Crow stall = 45.2 at GRAVITY_G ∈ {1,2,3} — identical**, so `stall < spawn(117/85) < cruise(130/95)` is structurally guaranteed at any gravity. Only accelerations get gentler (real-g dive feel) and turns/dives get proportionately bigger (→ bigger world). The player-approved v2 feel *character* is preserved.

**What landed:**
1. **One knob.** `GameConfig` now derives gravity from `METERS_PER_STUD = 0.28` and **`GRAVITY_G`** (fraction of real g — THE sweep knob), and multiplies every gravity-coupled force by `GRAV_SCALE = GRAVITY/196.2`: `AIR_DENSITY`, per-profile `flapThrust` & `flapClimbForce` (still "above gravity" → climb preserved), `Thermals.strength`. **Default `GRAVITY_G = 2.0`** (gravity ≈70, 2.8× gentler than old) — a deliberate arcade-real *first-playtest* value; **sweep toward 1.0 for true real / most majestic.** Scale-free values (all speeds, control-authority speeds, every rad/s rate, `TERMINAL`, `CRASH_SPEED`) untouched.
2. **2 km sky.** `SERVICE_CEILING = meters(2000) ≈ 7143` (was 520), `CEILING_BAND ≈ 607`, `Thermals.maxHeight ≈ 6429`, `SPAWN_HEIGHT = 2000` (≈560 m AGL — lots of dive room + ~5000 climb headroom), `GROUND_FAILSAFE_Y = -200`.
3. **Bigger arena.** `BuildMap`: 16 000×16 000 floor; 7 spires spread across ±900–3400 radius, heights 600–2000, thinner (Ø90) — landmarks to soar around, not a crash-forest. Thermal ring 3200, spawn scatter ±1200, `FogEnd = 16000`. `Workspace.Gravity` now set to match the flight model. World-bounds left soft (huge floor + fog) — hard walls deferred (they'd re-add crash-frustration).

**MUST validate in Studio with Chad (this is the sweep):** fly the eagle and judge majesty-vs-snappy → tune the single `GRAVITY_G` local. Confirm (a) the good grip/climb/momentum feel is intact (it should be — character preserved); (b) the dive now *builds* over a long stoop instead of snapping to cap; (c) it's no longer "so easy to crash" (open sky); (d) the eagle can still climb/thermal to a useful altitude without it feeling tedious (if tedious → raise `Thermals.strength` above the scaled value); (e) AI crows hold altitude & don't suicide on the (now sparse) spires; (f) anti-cheat doesn't false-positive (speeds unchanged, so it shouldn't). **Flight==balance:** a 2 km sky + wider real-scale turns reshapes the 1-v-4 (more boom-and-zoom room for the eagle; harder for crows to corner it) — reason about it while sweeping. **Committed `0e6982d` and pushed to `origin` (github.com/cjcgervais/EvC2026), branch `master`.** Revert point if the recalibration needs rolling back: `f58c465` (the prior good-feel commit). The `GRAVITY_G` sweep tuning is NOT yet committed — playtest, pick a value, then commit on top.

---

## Status (2026-06-28) — session 9: PLAYTESTED & player-loved — eagle flight "locked in" 🦅

Chad flew the real-scale recalibration live and called it **"one of the coolest flight experiences I have experienced, no joke"** — the eagle flight model is now **player-approved and considered nearly done.** `GRAVITY_G` was **left at 2.0** (the value he flew and loved — no further sweep needed for now; the knob remains there if anyone wants to revisit). A batch of feel/QoL fixes from his playtest notes landed and is committed:

1. **Yaw reversed on Q/E** (`BirdController.keyBindings`): Q yaws left, E yaws right (was inverted).
2. **Auto-leveling ELIMINATED** (his explicit ask: "get rid of any auto-levelling… have the AoA not change unless input is given by the user"). `Flight.STABILITY_RATE 0.15 → 0` and **both** profiles' `recoverNoseDownRate → 0` — the weathervane that dragged the nose back toward the airflow is fully gone, so the nose stays exactly where you point it and AoA only changes from player input. The **grip assist** (velocity-follows-nose, `GRIP_RATE`) is untouched — that's what still prevents stalls ("flies where you point"). **`cl0` must stay > 0** (still the precondition that makes grip safe). `PHUGOID_DAMPING` (2.1) deliberately **kept** — it only damps hands-off vertical bob, isn't nose-leveling, and was in the approved build; revisit only if it reads as altitude self-leveling.
3. **Better climb + longer stamina (Eagle only)** — `flapClimbForce 300 → 400`; stamina widened to `maxStamina 140 / staminaFlapCost 6 / staminaRegen 9` (≈23s sustained flapping, was ~11s). Kept off the Crow on purpose: changing Crow stamina shifts the 1-v-4 (flight==balance) — left for the matchup pass. Endurance buff suits the eagle's energy-fighter identity.
4. **Floor + obstacles restored** — the map was always built, but **spawn at Y=2000 put the floor 2000 studs down (a distant speck) and the spires far below** → Chad reported "no floor… nothing to collide with." **`SPAWN_HEIGHT 2000 → 600`** (~170 m AGL): you now start with ground reference and spires looming, then climb into the tall sky and stoop back (the intended energy loop). 16k world is still wide-open so this does NOT reintroduce "too easy to crash."
5. **HUD: AoA indicator + control hint** — `GameUI` gained an **AoA readout** (bottom-left under SPD/ALT; green→amber→red as it nears/exceeds the stall angle, pushed via new `_G.SetAoA(deg, stallDeg)` from `BirdController.pushUI`) and a persistent bottom-center hint **"Hold SPACE to free-look · move the MOUSE to pan the camera."**

`build.ps1` green after the batch. **Committed on `master`.** Eagle feel is now the approved baseline — **don't regress it.**

### Queue delta from this session
- **NEW #9 — mouse-wheel camera zoom (Chad's one remaining eagle ask).** Add scroll-wheel zoom in/out to the chase camera in `BirdController` (the camera distance is `cameraState.currentDistance`, driven from `CAM.baseDistance + speed * CAM.speedDistanceFactor` in the camera step ~line 291). Bind `UserInputService.InputChanged` / `Enum.UserInputType.MouseWheel` to a user zoom offset/factor that folds into `targetDistance`, clamped to a sane min/max. Chad: *"that is almost it for the eagle."* Small, self-contained, do it first next session.
- Eagle flight tuning (old #2) is now **satisfied/player-approved** — further flight work is the Crow side and the 1-v-4 matchup.

---

## Status (2026-06-29) — session 10: eagle QoL pass — ✅ HUMAN-VERIFIED & TAGGED CHECKPOINT

**Chad flew this build and confirmed it passes his flying-model check — the eagle flight kernel is human-verified and locked in.** Tagged **`v1.0-eagle-flight`** (annotated) on `master` and pushed to `origin` — this is the safe revert point for the verified eagle flight model. Six camera/control/feel items from live Chad notes landed; all `build.ps1`-verified and now player-approved. None touch the aero kernel's core lift/drag math or balance numbers (only camera, control mapping, the dive-flap fade, and a new HUD gauge).

**Is the main (eagle) kernel "done"?** Yes for the eagle. `FlightPhysics` (grip model + real lift curve + drag polar + powered climb + dive-flap fade), the eagle `Profiles.Eagle` numbers, the control scheme, and the camera are all human-verified. The kernel is **class-agnostic**, so the Crow flies the same engine — what remains is **not kernel work** but **Crow tuning + the 1-v-4 matchup** and the non-flight systems (lose-lose collision, AI obstacle avoidance, perf). Don't reopen the eagle kernel without a new Chad ask.

1. ✅ **Mouse-wheel camera zoom** (queue #9) — see above.
2. **Camera rides a little above; rises modestly as you zoom out.** `updateCamera` scales the chase height ratio from `Camera.heightFactor (0.35 — a little above, even zoomed in)` up to `Camera.zoomTopDownHeight (0.55 — a happy medium, not extreme top-down)` across the zoom range (fraction measured from `baseDistance`, so the angles stay close zoom-in↔zoom-out, per Chad's follow-up). Tune those two keys for the exact angle.
3. **Loop-crest camera smoothing.** The chase cam whipped as the eagle flipped over the top of a loop. `updateCamera` now measures the bird's facing angular rate (rad/s) and, when it spikes, softens the follow-lerp (down to `Camera.crestDamp=0.75` reduction at `Camera.crestAngRate=3.5` rad/s) so the camera glides through the flip. **Camera-only — flight is untouched** (mechanics unaffected, per Chad's "without breaking the flying mechanics").
4. **Time-scaled pitch (W/S).** Keyboard pitch was binary ±1. Now a TAP gives a small AoA nudge (`Controls.pitchTapFraction=0.30`) and HOLDING ramps to full authority over `Controls.pitchRampTime=0.55s`; release snaps to 0 (nose holds — no auto-level). State in `BirdController.pitchRamp`, applied in `onFlightStep` step 1c, reset in `resetInput`. Lets you fine-tune attitude without losing strong authority on a sustained climb/dive. **PLAYTEST-PROVISIONAL feel change** (eagle is approved — verify it still feels good).
5. **Incidence gauge (body pitch vs horizon — NOT AoA).** Chad clarified he wants the **bird body's pitch attitude against the world horizon at 0°**, measuring nothing aerodynamic (no AoA/lift/stall). `BirdController.pushUI` computes `pitchDeg = deg(asin(orientation.LookVector.Y))` and pushes it via **`_G.SetIncidence(deg)`**. `GameUI` has a clean dial (bottom-left, right of SPD/ALT): a fixed horizontal line = the horizon (0°), a bright neutral-cyan **pointer rotates to the body's nose-up/down angle** (`Rotation = -deg`), hub + signed one-decimal numeric below. **No stall ticks, no color-coding** (removed per "measure nothing else"). Gauge construction wrapped in a `do` block (keeps transient locals out of the main chunk's budget); resets to "--"/level during the death→respawn gap. *(The `FlightPhysics.aoaDeg` field still exists and is correct — it's just no longer shown.)*

6. **Flapping in a dive now fades at the top end (Chad).** Flap thrust already applied along the nose in a dive; now (`FlightPhysics` dive branch) it keeps full bite through low/mid dive speed and ramps down to `Flight.FLAP_DIVE_FLOOR (0.1)` over the top `Flight.FLAP_DIVE_FADE_BAND (0.4)` of `diveSpeedCap` — "hard to flap fast at a full stoop; gravity carries the high end." **Level/climb flapping is untouched** (no cruise/climb regression). Both profiles share the `Flight` knobs.

New `GameConfig` keys: `Camera.heightFactor`, `Camera.zoomTopDownHeight`, `Camera.crestAngRate`, `Camera.crestDamp`; `Controls.pitchTapFraction`, `Controls.pitchRampTime`; `Flight.FLAP_DIVE_FADE_BAND`, `Flight.FLAP_DIVE_FLOOR`. **Committed on `master` and tagged `v1.0-eagle-flight` (pushed to `origin`).** The QoL knobs above remain tunable, but the build as-tagged is the player-approved baseline — **don't regress it.**

### Queue delta from session 10
- Queue **#9 (mouse-wheel zoom) — DONE & verified.**
- **Eagle flight kernel — DONE & human-verified (tag `v1.0-eagle-flight`).** All remaining flight work is the **Crow side and the 1-v-4 matchup**, which is balance/tuning on the shared kernel, not kernel changes.
- Still open (unchanged): lose-lose collision tuning (#3), AI obstacle avoidance (#8), parallel-Luau Actors (#6b, gated behind "only after it's fun"), and the assorted smaller findings (#7).

---

## Status (2026-06-23) — original v1 skeleton notes

A complete v1 skeleton exists as real, version-controlled Luau source under `src/`, wired for [Rojo](https://rojo.space) via `default.project.json`. **It has NOT been run in Roblox Studio yet** — there is no Luau toolchain in this environment, so nothing has been syntax-checked or playtested. Treat "it runs cleanly" as unverified until you open it in Studio.

### 🔎 Static desk-check pass (2026-06-23, second session) — three fixes landed
With no toolchain to run, every module was read end-to-end and reasoned through as if executing the first Studio frame. Three concrete issues were found and fixed (incremental, contracts untouched):

1. **Collision formula contradicted its own design target — FIXED.** The old `processCollisions` added a *self-harm* term to each bird computed from **its own offensive** `collisionDamageDealt`. For the eagle that offensive number is large (60), so a single full-speed crow ram did `30 + (60×0.45) ≈ 57` to the eagle → it died in **~2 rams**, not the documented ~4. Reworked to the transparent model **"each bird receives the OTHER's `collisionDamageDealt`, scaled by relative speed, times its OWN `collisionDamageTaken` vulnerability."** Retuned `Eagle.collisionDamageTaken 0.45→0.85` so a full-speed crow ram does ≈26 → **~4 rams kill the eagle**; `Crow.collisionDamageTaken` stays 1.4 so the ramming crow (takes 60×1.4≈84) dies — a true trade. Matchup math is now spelled out inline in both `GameConfig` and `GameServer.processCollisions`. **Still PLAYTEST-PROVISIONAL (queue #3) — but it now matches the written intent.**
2. **Pitch keys were inverted vs the documented control scheme — FIXED.** `BirdController` bound `W=+1`, which the engine turns into **nose-UP**, contradicting the file's own docstring ("W nose-down to dive/accelerate, S nose-up to climb"). Flipped to `W=-1` (nose down/dive), `S=+1` (nose up/climb). *This is a feel call — if it plays wrong in Studio, swap the two `value`s back; it's a two-character change.*
3. **A solo Studio player could spawn nothing — FIXED.** The round loop only spawns when BOTH an Eagle and a Crow player exist, so pressing Play with one client left you in an empty sky — blocking the #1 smoke test. Added `GameConfig.Debug.soloFlight` (default **true**): when a full match can't be fielded, whoever is present spawns and flies (AI crows + possession included), with no scored round, and it transitions cleanly into a real match the moment a second team joins. Set `soloFlight=false` for production. The round loop was also restructured so the intermission countdown only runs when a match is actually possible (no more 8s "Intermission…" with nobody to play).

**No flight-aero numbers were touched** — those genuinely need playtest (queue #2). See "Open desk-check notes" at the bottom for non-blocking observations worth watching on the first run.

### ✅ Integration task #1 is DONE in code (2026-06-23) — Studio smoke test is now the top priority.
The standalone-bird-model vs character mismatch has been **fully reconciled on both sides**. What changed:
- **`GameServer.spawnBird`** now tags every bird Model *before parenting* with `OwnerUserId` (number), `Team` (string), and `Possessed` (bool), and sets `MaxHealth` on the `Body` part (alongside the existing `Health`). Setting attributes before `model.Parent = …` guarantees the client's `ChildAdded` sees them.
- **`GameServer.onSwapCrow`** now flips the `Possessed` attribute on both the demoted and promoted Models (not just the in-memory `entry.possessed`).
- **New `GameServer.autoRepossess(squad)`** — when a crow's possessed bird dies, control is handed to a surviving squadmate automatically (sets `Possessed=true`, takes network ownership). Called from `applyDamage`'s death branch. Without this, a crow player whose active bird died would be stuck with nothing to fly until they manually pressed 1–4. (This also partially addresses open-question #2 / queue item #5.)
- **`BirdController`** — the entire `CharacterAdded`/`HumanoidRootPart`/`Humanoid.PlatformStand` path is gone. It now: waits for `Workspace.Birds`, finds the Model with `OwnerUserId == player.UserId and Possessed == true`, drives its `Body` `CFrame`+`AssemblyLinearVelocity` with a local `FlightPhysics` engine **seeded from the body's live state** (no snap on swap), and re-acquires on `ChildAdded`/`ChildRemoved` + each Model's `Possessed` attribute change. `TeamAssigned` is connected synchronously (before the `WaitForChild` yield) so the round-start event is never missed; folder wiring is deferred in a `task.spawn`.
- **`GameUI`** — reads speed/altitude/health from the possessed bird's `Body` (and its `Health`/`MaxHealth` attributes) instead of `player.Character.HumanoidRootPart`.
- **`GameUI` moved `StarterGui` → `StarterPlayerScripts`** (in `default.project.json`). This is a *required* consequence of the standalone-model design: with `CharacterAutoLoads=false` Roblox never copies `StarterGui` into `PlayerGui` (that copy is gated on character spawn), so a HUD script left in `StarterGui` would silently never run. `GameUI` builds its own `ScreenGui` and parents it to `PlayerGui`, so it works fine from `StarterPlayerScripts` (which loads on join regardless of character). Verified against Roblox docs/DevForum.

**Verified by inspection (not yet in Studio):** `BirdBuilder` builds `Body` as an unanchored `PrimaryPart` with all other parts welded / Motor6D'd to it, so it's a single assembly — driving `Body` moves the whole bird and `SetNetworkOwner(Body)` covers it. **Next agent: open Studio and confirm it actually flies (queue item #1 below).**

| File | Lines | State |
|------|-------|-------|
| `src/shared/GameConfig.luau` | ~217 | **Solid.** Research-backed tunables; the shared contract. Authored directly, coherent. |
| `src/shared/FlightPhysics.luau` | ~250 | **Solid.** 6DOF engine (lift/drag/stall, banking turn, two-turn-param model, stamina). Authored directly. |
| `src/shared/BirdBuilder.luau` | ~240 | Subagent-built. Procedural Eagle/Crow models + `AnimateWings`. Skim before trusting. |
| `src/shared/Boids.luau` | ~229 | Subagent-built. `computeSteering` + `steeringToInput`. Skim. |
| `src/server/GameServer.server.luau` | ~980 | Subagent-built. Authoritative combat, collisions, AI crows, rounds. **Largest risk surface.** Now also tags birds with the client-contract attributes + auto-repossess. |
| `src/client/BirdController.client.luau` | ~470 | Flight loop, camera, free-look, input. **Integration mismatch FIXED** — drives standalone bird Models via `Workspace.Birds` attributes. |
| `src/client/GameUI.client.luau` | ~415 | Full HUD. **Integration mismatch FIXED** — reads from the possessed bird's `Body`. |

---

## ⚠️ THE ONE DECISION ALREADY MADE — read before touching the client

The server (`GameServer`) deliberately sets `player.CharacterAutoLoads = false` and represents each player's bird(s) as **standalone Models in `Workspace.Birds`** — NOT as a Roblox Character with a `HumanoidRootPart`.

**This is the correct architecture and is now canonical.** Do not revert it. Reason: a Crow player controls **4 separate bird bodies** with possession-swapping — a single Roblox Character cannot represent that. The eagle is just the 1-body case of the same model.

**This was integration task #1 and is now DONE in code** (see the Status section above). The implemented contract — the canonical source of truth both sides now honor — is:

### The bird-discovery attribute contract (IMPLEMENTED)
On every bird Model in `Workspace.Birds`, set *before parenting* by `GameServer.spawnBird`:
- `OwnerUserId` (number) — `player.UserId` of the controlling player (`0` if none).
- `Team` (string) — `"Eagles"` / `"Crows"`.
- `Possessed` (bool) — `true` on the single bird the player actively flies; updated by `onSwapCrow` and `autoRepossess`.
On the `Body` part (the `PrimaryPart`): `Health` (number) and `MaxHealth` (number) attributes.
Network ownership of the possessed bird's `Body` goes to the player via `SetNetworkOwner`; AI crows are `SetNetworkOwner(nil)` (server-owned).

The client (`BirdController`) drives the Model whose `OwnerUserId == player.UserId and Possessed == true`, re-acquiring on folder `ChildAdded`/`ChildRemoved` and on any owned Model's `Possessed` attribute change. **Do not break this contract — grep `OwnerUserId` / `Possessed` before touching spawning or possession.**

**Smoke-test it in Studio first**, with one Eagle and one Crow player (use a second Studio player or a bot) — nothing else can be tested until birds actually fly.

---

## Prioritized work queue

> **⭐ SESSION-7 NORTH-STAR (do FIRST — full detail in the session-7 Status block above): real-scale raptor flight toward "the best flight model on Roblox."** (1) Eagle ceiling ≈ 2 km, (2) much bigger test arena (crashing too easily), (3) dive acceleration tuned to real raptor stoop speeds. These share a **world-scale ↔ gravity ↔ calibration crux** — gravity (196.2) is the linchpin of the whole lift/drag model. **Ultrathink, read + AUGMENT `RESEARCH.md` with fresh deep-research, decide a scale convention first, then recalibrate and re-verify `stall < spawn < cruise`.** Flight feel is good & committed (`f58c465`) — don't regress it. THEN the items below (flight feel itself is now player-approved, so old queue #1/#2 are largely satisfied).

1. **Re-test in Studio (DO THIS FIRST).** Two playtest fixes + TWO review/systems batches (session 4 + session 5) landed unrun. Build with `.\build.ps1` (resolves clean — but it does NOT syntax-check Luau, so Studio is the real test). **Solo test** (`GameConfig.Debug.soloFlight`, default true): press Play, you should spawn + fly. Confirm the reported bugs are gone: (a) the **eagle cruises with stall margin** and only stalls when you yank the nose at low speed; (b) **crashing into the ground or pressing R respawns you** within ~2s without stop+F5. Then confirm no spawn/swap snap (NetOwner gate), alt-tab doesn't fly the bird away, and the HUD empties between lives. **Full match:** 2-player local server (Test → Players = 2) → P1 Eagle, P2 Crow squad; verify collisions, scoring, and that AI crows now hold altitude (thermal fix). **NEW session-5 systems to validate in this same pass:** (c) birds now **collide with spires/ground** instead of tunneling — fly head-on into a spire (should crash+respawn) and graze one (should slide, survive); (d) the **anti-cheat envelope is live** (`GameConfig.Security.enabled`) — confirm normal aggressive flying/diving NEVER trips a `[AntiCheat]` warn in the Output; if it false-positives honest play, raise the thresholds or set `enabled=false` while feel-testing; (e) AI crows shouldn't suicide into spires constantly (their boids don't avoid obstacles yet — see new queue #8). **Note:** W noses DOWN (a feel call — flip the two `value`s in `BirdController.keyBindings` if it plays wrong).
2. **Tune flight feel** (`FlightPhysics` + `GameConfig.Profiles`). The session-3 numbers (eagle `liftCoefficient 2.0`, `flapThrust 520`, spawn `0.9×`, soft-stall floor `0.15`) are a reasoned first pass, not final. Verify energy-fighter (eagle) vs angles-fighter (crow) feel emerges; watch dive recovery, stall feel, turn radii. **Honor the calibration invariant** (open-questions #6 / `[[research-flight-balance-findings]]`): stall speed must stay below spawn & cruise.
3. **Tune the lose-lose collision** (`GameServer.processCollisions` + `GameConfig`). Biggest *unverified* design (no research backing). Target: ~4 full-speed crow rams kill an eagle while each ramming crow dies. See open-questions memory.
4. ✅ **Real obstacle collision — DONE (session 5).** `BirdCollision.luau` swept-Spherecast; AI inline + client graze-slide + `processCrashes` authoritative. See session-5 status. **Remaining:** Studio-verify it feels right and tune `CRASH_SPEED`; AI boids still don't *avoid* obstacles (new queue #8).
5. ✅ **Anti-cheat envelope — DONE (session 5).** `GameServer.processAntiCheat` + `GameConfig.Security`. See session-5 status. **Remaining:** Studio-verify it doesn't false-positive honest aggressive flight; tune `Security` thresholds; consider also validating the **dive-stoop damage bonus** server-side (it currently reads the replicated `AssemblyLinearVelocity` in `onAttackRequest` — a hardened version would gate the multiplier on the server-observed descent rate too).
6. **Performance at scale.** (a) ✅ **Spatial hash — DONE (session 5):** `SpatialHash.luau` + `birdIndex`, backing `findNearestEnemy`/`processCollisions`. (b) ⬜ **Parallel Luau Actors** — move per-crow Boids+aero to Actors; `Boids`/`FlightPhysics`/`SpatialHash` are all instance-free so they run as-is in the desync phase; snapshot serial → compute parallel (sharded Actor pool) → batch CFrame writes serial. Gate behind an agent-count threshold. Refs: create.roblox.com/docs/scripting/multithreading. **Only after it's fun.**
7. **Smaller review findings (do opportunistically while in the relevant file).**
   - ✅ `GameServer`: Eagle promotion on leave (`promoteToEagleIfNeeded`) + attacks restricted to the possessed bird — DONE (session 5). Still open: swap handoff seeds the AI engine from possibly-stale replicated state (minor pop).
   - ⬜ `FlightPhysics`/`GameConfig`: `stallRecoverRate`, `AEROBATIC_MIN_SPEED`, `climbCeilingBonus` are declared+documented but **unused** — implement or delete. (Left for a flight-feel iteration: wiring them in *changes feel*, so it wants a playtest in the same loop as #2, not a blind edit.)
   - ⬜ `BirdController`: free-look stuck if a swap happens while Space is held; bursty `reacquire` briefly tears down a valid drive (cosmetic, self-correcting).
   - ✅ `BirdBuilder`: `AnimateWings` no longer writes an `IdlePhase` attribute every frame (weak Lua table) — DONE (session 5). Still open: wing-smoothing alpha isn't frame-rate-independent.
   - ⬜ `Boids`: vertical pitch error uses raw world-Y of unit vectors (azimuth-biased); optional `math.asin` elevation-angle version.
8. **NEW — AI obstacle avoidance.** Now that spires are lethal (queue #4), the boid crows will fly into them — `Boids.computeSteering` has no obstacle term. Add a forward `Spherecast` (reuse `BirdCollision`/the server's `getCollisionParams`) that injects an avoidance steering vector away from an impending hit. Without it, AI crows will attrite themselves on terrain and skew the 1-v-4. Verify severity in the Studio pass before building.
9. ✅ **Mouse-wheel camera zoom — DONE (session 10, code-complete, build-green, UNPLAYTESTED).** `BirdController.InputChanged` now handles `Enum.UserInputType.MouseWheel`: scroll up pulls the cam IN, down pushes OUT, accumulating into `cameraState.userZoom` (studs). The camera step folds it into `targetDistance` and clamps the final distance to `[CAM.minDistance, CAM.maxDistance]`; `userZoom` itself is re-clamped each frame against the speed-driven base so the wheel range stays meaningful at any speed (zoom-in intent is preserved across speed changes). New `GameConfig.Camera` keys: `zoomStep=6`, `minDistance=10`, `maxDistance=120`. No balance impact. **Studio-verify** the wheel zooms smoothly and the clamps feel right (tune the three keys if needed).

---

## How to work here (process)
- **Refine incrementally, don't regenerate.** The codebase is modular for exactly this. Change one module/feature at a time and Studio-test it.
- **Honor the thesis:** any flight-number change is a balance change and vice-versa (`feedback-flight-balance-inseparable` memory). Reason about the 1-eagle-vs-4-crow matchup on every tuning edit.
- **Keep contracts stable:** `GameConfig` keys, the `FlightPhysics` API, and the Remotes list are consumed across files — grep before renaming. The Remotes contract is documented in `CLAUDE.md`.
- **Update memory** (`C:\Users\Chad\.claude\projects\D--EvC2026\memory\`) when a design question gets resolved or a new constraint appears.
- WebSearch/WebFetch are allowlisted in `.claude/settings.json` (the deep-research workflow needed them).

## Open desk-check notes (non-blocking — watch on first run, don't pre-fix blind)
Observations from the static read that are NOT bugs but worth eyeing once it's live:
- **Eagle level-flight at cruise — re-check after the thrust bump.** `flapThrust 380→520` (`/mass 12 ≈ 43`) now exceeds the ~34–41 studs/s² cruise drag decel, so the eagle should hold/slowly gain at cruise instead of decaying into a stall. Confirm it doesn't feel *too* sluggish or *too* floaty; tune `flapThrust`/`parasiticDrag` (queue #2, reason about the matchup).
- **Stamina budget is tight by design.** Eagle: 100 max, 9/s flap cost, 7/s regen → ~11s of sustained flapping then must glide/thermal to recover. Intended energy management; verify it's fun, not frustrating, on the first flight.
- **~~`rec.birds` stale refs~~ — FIXED (session 3):** `applyDamage` now prunes the dead model from `rec.birds`. (Was what blocked solo respawn.)
- **~~Brief spawn rubber-band~~ — FIXED (session 3):** the client now waits for the server-set `NetOwner` attribute before driving the Body, so it no longer fights the server during the ownership-transfer window.
- **Solo-flight + a joining 2nd player:** when the second team joins mid-solo the new bird flies for the ~8s intermission before the scored round clears & respawns everyone. Expected, not a leak.

## ▶️ How to continue this work — use the loop-orchestrator skill + deep-research
`D:\EvC2026\loop_skill\` is a self-contained **Claude Code Skill (`loop-orchestrator`)** for running disciplined, externally-verified improvement loops, and it ships a **`profiles/roblox-game.md` profile written for this exact game.** The intended way to develop each module from here is to drive it through that loop rather than ad-hoc edits:
1. **Read the skill** — `loop_skill/.claude/skills/loop-orchestrator/SKILL.md`, then `references/sops.md` and `profiles/roblox-game.md`. (It's directory-scoped to `loop_skill/`, so read the files directly as guidance for `src/` work, or install globally by copying the skill dir to `~/.claude/skills/`.)
2. **Research half** — compose the **`deep-research`** skill for each module's open question (flight feel, the lose-lose collision, anti-cheat envelope, raycast collision, parallel-Luau scaling — see the queue). Feed conclusions into the loop's PLAN step. The session-3 multi-agent pass already gathered Roblox SOPs + citations for the big items (see queue #4–6) — start from those.
3. **Loop per module** — FRAME (measurable "done" + budget) → PLAN one change → ACT → **VERIFY against ground truth (`.\build.ps1` resolves AND a Studio playtest)** → SCORE → REFLECT → DECIDE. One system per iteration (SOP-4); never weaken the verify to pass (SOP-7); checkpoint the place file before risky systemic changes. Ground truth is **pressing Play** — there is no headless Luau toolchain here.
See the `[[reference-loop-orchestrator-skill]]` memory.

## Continuation prompt (paste into a fresh session if needed)

> **SESSION 11 — EAGLE FLIGHT KERNEL IS DONE & HUMAN-VERIFIED (tag `v1.0-eagle-flight`); move to the CROW + the 1-v-4 matchup.** You are continuing **Eagles vs Crows** (physics aerial-combat on Roblox/Luau). Read `CLAUDE.md`, `docs/HANDOFF.md` (**session-10 Status block first**), `docs/RESEARCH.md`, and the memory index `MEMORY.md` — especially `[[flight-vertical-envelope]]`, `[[flight-kernel-v2]]`, `[[feedback-flight-balance-inseparable]]`, `[[project-open-questions]]`. **Through session 10 Chad flew the build and confirmed it passes his flying-model check — the EAGLE flight kernel is locked in and tagged `v1.0-eagle-flight` on `master` (pushed to `origin`); that tag is the safe revert point. Do NOT regress or reopen the eagle kernel without a new Chad ask.** The kernel is **class-agnostic** (Eagle/Crow share `FlightPhysics`; all asymmetry is in `Profiles.*` numbers), so the remaining flight work is **balance/tuning, not kernel changes**. Settled invariants: grip model + `cl0 > 0` keep it stall-free — **never set `cl0 = 0`**; auto-leveling stays OFF (`STABILITY_RATE = 0`, `recoverNoseDownRate = 0`); `GRAVITY_G = 2.0`; keyboard-only (`Controls.mouseSteer = false`). **Your job: the CROW side and the 1-v-4 matchup.** Work the queue in order: **lose-lose collision tuning (#3)** — ~4 full-speed crow rams kill an eagle while each ramming crow dies (no research backing yet — playtest it); then **AI obstacle avoidance (#8)** — boid crows have no obstacle term and will attrite on the (now lethal) spires, skewing the 1-v-4; then **parallel-Luau Actors (#6b)**, gated behind "only after it's fun." Honor **flight==balance**: reason about the 1-eagle-vs-4-crow matchup on every number. Develop via the **loop-orchestrator** skill (roblox-game profile) + compose **deep-research** for the research half; ground truth is **Studio Play with Chad** (`.\build.ps1` resolves but does NOT syntax-check Luau); refine incrementally, don't regenerate.
>
> **SESSION 9 — PLAYTEST THE REAL-SCALE RECALIBRATION (then sweep `GRAVITY_G`).** You are continuing **Eagles vs Crows** (physics aerial-combat on Roblox/Luau). Read `CLAUDE.md`, `docs/HANDOFF.md` (especially the **session-8 Status block**), `docs/RESEARCH.md` (**§v3**), and the memory index `MEMORY.md` — particularly `[[project-realscale-flight-goal]]`, `[[flight-vertical-envelope]]`, `[[flight-kernel-v2]]`. **Session 8 implemented the real-scale recalibration** (committed `0e6982d`, pushed to `origin`): gravity is now derived from `METERS_PER_STUD=0.28 × GRAVITY_G` (the ONE sweep knob, default **2.0**), every gravity-coupled force scales by `GRAV_SCALE`, and the world is rebuilt to real 2 km scale (ceiling 7143, spawn 2000, 16k floor, sparse spires). **The `stall<spawn<cruise` invariant is PROVEN invariant to `GRAVITY_G`** (Eagle stall 61 / Crow stall 45 at any value — the g and ρ cancel), so the knob can't break it; **never set `cl0=0`** (it's what makes grip safe). It is **build-green but UNPLAYTESTED.** Your job: **press Play in Studio (`.\build.ps1` first) and fly the eagle with Chad**, then **sweep the single `GRAVITY_G` local** for majesty-vs-snappy (1.0 = true real ≈35 studs/s²; up = punchier). Confirm the checklist in the session-8 block: good grip/climb/momentum feel intact, dive *builds* over a long stoop, no longer "easy to crash," climb-to-altitude isn't tedious (else raise `Thermals.strength`), AI crows hold altitude, anti-cheat doesn't false-positive. **Honor flight==balance** (a 2 km sky reshapes the 1-v-4). Commit the chosen `GRAVITY_G` once Chad approves it. THEN return to the queue (lose-lose collision #3 → AI obstacle avoidance #8 → parallel-Luau #6b). Develop via the **loop-orchestrator** skill (roblox-game profile); ground truth is **Studio Play with Chad**; refine incrementally, don't regenerate. Keyboard-only right now (`Controls.mouseSteer = false`).
>
> **SESSION 10 — EAGLE FLIGHT IS LOCKED IN (player-loved); pick up the small QoL + the Crow/matchup work.** You are continuing **Eagles vs Crows** (physics aerial-combat on Roblox/Luau). Read `CLAUDE.md`, `docs/HANDOFF.md` (**session-9 Status block first**), `docs/RESEARCH.md`, and the memory index `MEMORY.md` — especially `[[flight-vertical-envelope]]`, `[[flight-kernel-v2]]`, `[[project-realscale-flight-goal]]`. **Session 9 was a live playtest Chad LOVED** ("one of the coolest flight experiences… no joke") — the eagle flight model is approved and **must not regress**. That session reversed Q/E yaw, **eliminated auto-leveling** (`STABILITY_RATE = 0`, both `recoverNoseDownRate = 0`; grip assist + `cl0 > 0` are what keep it stall-free — never set `cl0 = 0`), buffed eagle climb/stamina, lowered `SPAWN_HEIGHT` to 600 (floor + spires now present), and added a HUD AoA readout + free-look hint. `GRAVITY_G` is settled at **2.0**. All committed on `master`. **Start with queue #9 — mouse-wheel camera zoom** (small, self-contained, Chad's one remaining eagle ask; details in the queue). Then the queue: lose-lose collision #3 → AI obstacle avoidance #8 → parallel-Luau #6b. Most remaining *flight* work is now the **Crow side and the 1-v-4 matchup**, not the eagle. Develop via the **loop-orchestrator** skill (roblox-game profile); ground truth is **Studio Play with Chad**; refine incrementally, don't regenerate. Honor flight==balance on every number. Keyboard-only right now (`Controls.mouseSteer = false`).
>
> *(Older session-5/6/7 continuation prompts retained below for history.)*

> *(Session-8 prompt, for history.)* SESSION 8 — ULTRATHINK. Flight feel was player-approved (`f58c465`); north-star was real-scale raptor flight (2 km ceiling, bigger arena, real dive accel) sharing a world-scale↔gravity↔calibration crux (default gravity 196.2 ≈ 5.6 g at 0.28 m/stud). Resolved by the recalibration above.
> You are continuing "Eagles vs Crows", a physics aerial-combat game on Roblox (Luau). Read `CLAUDE.md`, `docs/HANDOFF.md`, and `docs/RESEARCH.md`, plus the project memory index `MEMORY.md`. The v1 skeleton is built (`src/`, Rojo) and has been playtested twice. Bug/feel fixes landed in sessions 3–4, and **session 5 added four code-complete-but-UNPLAYTESTED systems: real raycast obstacle/ground collision (`BirdCollision`), a server anti-cheat envelope (`processAntiCheat` + `GameConfig.Security`), a spatial-hash perf foundation (`SpatialHash`), and server-robustness cleanups** (see the session-5 Status block). Nothing since the 2nd playtest has been run in Studio. **Develop each module by driving it through the `loop-orchestrator` skill in `loop_skill/` (use its `roblox-game` profile) and composing the `deep-research` skill for the research half** — see "How to continue this work" in HANDOFF. **Start by pressing Play in Studio (`.\build.ps1` first)** and validating the session-5 systems (queue #1 has the checklist) plus the still-unverified path-tracking flight model — then work the queue (flight-feel tuning #2 → lose-lose collision #3 → AI obstacle avoidance #8 → parallel-Luau #6b). Refine incrementally; do not regenerate the codebase. Honor the core thesis: flight physics and asymmetric balance are one system, verified against the 1-eagle-vs-4-crow matchup every tuning edit.
