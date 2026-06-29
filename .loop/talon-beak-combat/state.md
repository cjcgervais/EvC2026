# Loop: Talon/Beak active-defense combat model (the lose-lose ↔ parry rework)

> Source of truth (SOP-9). Frame filled once; append to the Iteration Log every cycle.

## Frame
- **Slug:** talon-beak-combat
- **Goal:** Replace the symmetric speed-scaled collision-damage model with the asymmetric model Chad specified — Eagle = 3 hits with two active, hold-to-extend, directional lethal-on-contact weapons (talons/beak); Crow = 1 hit whose only attack is a suicide ram — and tune it so the 1-eagle-vs-4-crow matchup is winnable by skill from both sides.
- **Profile:** roblox-game
- **Architecture:** ReAct (plan→act→observe; ground truth = running it in Studio). Escalate to a balance sweep only after the structure is verified fun.
- **Reflection mode:** reflexion (playtest failures carry forward).
- **Started:** 2026-06-29

### The combat contract (the design we agreed — see HANDOFF session 11)
- **Health:** Eagle survives exactly **3 unparried rams** (HP bar kept but tuned so 1 ram = ~1/3 of maxHealth). Crow dies in **1** committed contact.
- **Crow offense:** suicide RAM only (no active weapon). A committed eagle↔crow contact (relSpeed ≥ COLLISION_SPEED_MIN) ALWAYS kills the crow; the eagle takes **1 hit only if the contact zone was NOT actively covered** by the correct extended weapon.
- **Eagle weapons (server-authoritative, hold-to-extend, directional, lethal-on-contact while extended):**
  - **TALONS** — LEFT mouse, front/underside cone. Extend window **4s**, cooldown **2s**.
  - **BEAK** — RIGHT mouse, head-on/frontal cone. Extend window **2s**, cooldown **4s**.
  - One extension window safely catches at most **ONE** crow; further crows in the same window die but land hits. Rear/above & any uncovered angle = always vulnerable.
- **Win/lose/tie:** Eagle wins = all 4 crows dead & eagle alive (≤2 hits). Crows win = eagle takes 3rd hit (≥1 crow alive). Tie = eagle's 3rd hit coincides with the last crow's death.
- **AI caveat (feeds queue #8):** the PLAYER-controlled crow has NO obstacle avoidance (player steers it into the eagle, may crash); formation/AI crows DO avoid obstacles → #8 avoidance term gated on `not possessed`.

### Success criteria (measurable — SOP-1)
- [ ] SC1: Eagle dies on exactly the 3rd unparried ram (HP tuned: ram damage = ceil(maxHealth/3)); a crow dies in 1 contact.
- [ ] SC2: Extend talons + take a front/below ram → eagle survives, crow dies. Take a rear/above ram (or talons on cooldown) → eagle loses 1 hit, crow dies. Same for beak head-on.
- [ ] SC3: Server owns the timers — talons L-hold ≤4s then 2s cooldown; beak R-hold ≤2s then 4s cooldown; HUD meters reflect server state; a client can't fake "always extended".
- [ ] SC4: One extension catches ≤1 crow; a simultaneous 2-crow ram lands ≥1 hit.
- [ ] SC5: Round resolves correctly for all three outcomes (eagle win / crow win / tie).
- [ ] SC6: `.\build.ps1` green, no runtime errors across a full match, and Chad signs off that the parry is readable and the matchup is winnable both ways.

### Budget (SOP-2)
- max_iterations: 8
- no_improvement_streak: 3
- effort tier: high (systemic combat rework + balance)
- enforced by: self + `.\build.ps1` each iteration; Studio Play with Chad is the behavioral gate.

### Ground truth (SOP-3)
- **Verify command / check:** `.\build.ps1` resolves (NOT a Luau syntax/behavior check) → then Studio Play with Chad against the SC checklist.
- **Metric:** matchup winnable-both-ways (qualitative, Chad-judged) gated by the checkable SC1–SC5.
- **Baseline:** iter 0 = current symmetric speed-scaled `processCollisions` (eagle 100 / crow 25, collision dmg both ways, beak/talon = flat damage on click). Does NOT implement the agreed model.

### Planned iteration arc (one meaningful change each — SOP-4)
1. Discrete 3-hit model + round win/lose/tie resolution (no weapon state yet — every ram is a hit).
2. Server-authoritative two-weapon extend/cooldown state + client L/R hold input (Remotes contract change).
3. Directional contact resolution in `processCollisions` (zone cones + one-catch-per-window) replacing symmetric damage.
4. HUD: eagle hit pips + two weapon extend/cooldown meters.
5+. Tuning passes with Chad (window/cooldown/zone/closing-speed), informed by the background balance research.

---

## Iteration log
<!-- Append one block per iteration. -->

### Iter 0 — 2026-06-29 (FRAME)
- **Change:** Frame written; design agreed with Chad; background balance-research agent launched + returned. No code yet.
- **Verify:** n/a (baseline = current symmetric model).
- **Decision:** CONTINUE — awaiting Chad's green-light on the spec + assumptions before iter 1.

#### Research conclusions (feed the tuning step, iter 5+) — cited brief in agent a84ca8827b582d621
- **Aim for a win-rate target (~50% eagle), not "fair"; expect the matchup to tilt toward the *coordinated* (crow) side at high skill** (DBD ~60% kill-rate precedent). The "1" side needs *offensive agency* — our eagle's active lethal weapons fix Evolve's core 4v1 failure mode. Watch for **passive stalling**: an eagle that boom-and-zooms forever is the bored-defender failure — a Round clock / forced engagement counters it (`GameConfig.Round`).
- **>50%-uptime single-angle defense is the classic "always-on" trap (For Honor).** Our **talon 67% uptime IS in the danger zone**; it's only OK because the gaps are exploitable by multi-angle simultaneity. **Beak 33% is the healthy ratio.** So the load-bearing balance mechanic is exactly our **one-catch-per-window** rule.
- **NEW LEVER — add vulnerable activation lag (startup):** parry games give the defense ~12 frames of zero defensive property before it's active (AI Limit) so it can't be *reactively flicked up the instant a ram lands*. Add a small `extendStartup` (~0.15–0.2s) so the talon/beak is a **read/commitment, not a twitch-react** — this is what tames the 67% uptime. (Candidate new `GameConfig` knob.)
- **Defense budget = uptime × angular coverage.** Talon's high uptime should pair with a **narrow-ish cone**; if we ever raise talon uptime, shrink its zone. Whiffing the wrong weapon must leave the eagle fully exposed (no partial mitigation).
- **Tuning target (SC-level):** *sequential* rams are reliably defended (eagle beats the patient crow), but **2+ simultaneous rams from different zones leak ≥1 hit** (SC4). Cooldown ≥ a crow's reposition time so a defended ram opens a real punish window.
- *Caveats from the agent:* the DBD 60% figure is community-sourced (approximate); there is no canonical "ideal uptime %" — the >50% threshold is inferred from For Honor's defense-meta literature.

### Iter 1 — 2026-06-29 (discrete 3-hit model + tie resolution)
- **Change (one):** Switched eagle↔crow contact from symmetric speed-scaled mutual damage to the asymmetric discrete model. `GameConfig`: Eagle `health 100→99`, new `GameConfig.Combat = { eagleHits = 3 }`. `GameServer.processCollisions`: kept the loop/guards/speed gate; replaced the damage block — identify eagle vs crow, crow ALWAYS dies (`applyDamage 1e9`), eagle takes `health/eagleHits = 33` per ram (no parry yet). `RoundLoop`: detect both-sides-dead → new `"tie"` result; `resolveRound` tie branch (no score, "draw" notify).
- **Verify:** `.\build.ps1` → green (wiring resolves). NOT yet Studio-tested — that's the behavioral gate, pending Chad.
- **Metric:** SC1 (3 rams kill eagle / crow dies in 1) + SC5 (win/lose/tie) now structurally implemented; SC2/SC3/SC4 (parry, weapons, multi-catch) still TODO (iters 2–3).
- **Checkpoint:** pre-change baseline is the committed `master` (tag `v1.0-eagle-flight` is the deeper revert point). No commit taken yet — will commit once Chad Studio-confirms.
- **Reflection:** Parry gating deliberately deferred so this layer is testable alone: every committed ram costs a hit. If Studio shows rams not registering as exactly 3, suspect COLLISION_SPEED_MIN (90) vs actual crow closing speed, or COLLISION_COOLDOWN double-counting.
- **Decision:** CONTINUE — Studio-verify SC1/SC5 with Chad, then iter 2 (server-owned talon/beak extend+cooldown state + L/R hold input).

---

### Iter 2 — 2026-06-29 (active-defense mechanic, end-to-end + AI opponent)
- **Reframe:** Merged planned iters 2+3+(minimal)4 into one delivery — weapon *state* and *zone parry* are each invisible alone, so the smallest playtestable unit is the whole mechanic + an on-screen meter. Also built the AI-opponent testing infra Chad asked for (he has no second human).
- **Change A (AI opponent):** `GameConfig.Debug.aiCrowOpponents=true`. New `GameServer.spawnAICrowSquad`/`clearBotSquad`/`ensureBotCrowSquad` — an ownerless, all-AI, `aggressive` crow squad (keyed `__BOT_CROWS__` in Squads). `squadGoal` hunts the nearest eagle from any range when `aggressive`. `autoRepossess` guards player-less squads. RoundLoop solo branch keeps a fresh wave of 4 alive vs a lone human eagle; scored branch clears them. Bots count for nothing in scoring (round logic keys off human PlayerData).
- **Change B (mechanic):** `GameConfig.Combat.weapons` (talon: 4s/2s/100°/0.15s startup; beak: 2s/4s/50°/0.12s). Server: `newWeaponState`/`stepWeapon`/`updateEagleWeapons` (Heartbeat, server-owned timers, mirrors Talon/Beak Meter+Active attrs to the eagle Body), `onWeaponHold` (new `WeaponHold` C→S remote, eagle-only), `tryParry` (active+past-startup+not-caught+within-cone → catch). `processCollisions` now parry-gates: caught → crow dies / eagle unharmed; else → eagle takes 1 hit + crow dies. Client `BirdController`: L/R mouse hold → `setWeaponHold` (edge-fired), released in resetInput, re-asserted in acquire from physical button state. `GameUI`: two weapon meter bars (green=covering, blue=ready, amber=cooling), eagle-only.
- **Verify:** `.\build.ps1` green (4 builds across the layers). NOT Studio-tested — behavioral gate pending Chad.
- **Metric:** SC2/SC3/SC4 now implemented; with SC1/SC5 from iter 1, all structural SCs are in. SC6 (Chad sign-off + winnable both ways) is the open gate.
- **Checkpoint:** baseline still committed `master` / tag `v1.0-eagle-flight`. No new commit until Studio-confirmed.
- **Reflection / watch-items for the playtest:** (1) right-click (beak) may fight Roblox default camera — should be fine under MouseBehavior.LockCenter, verify. (2) talon 67% uptime may feel oppressive — the startup lag + one-catch rule are the intended brakes; tune windows/cones if the eagle is unhittable or can't survive. (3) bot crows don't yet *avoid* spires (queue #8) so some will crash mid-hunt — acceptable for combat practice, but it thins waves. (4) confirm a rear ram always lands (cone blind spot) and a covered front ram is negated.
- **Decision:** CONTINUE — Studio playtest with Chad (solo Eagle vs AI wave) against SC1–SC5, then tune (iter 3+).

---

### Iter 2a — 2026-06-29 (HOTFIX: Studio froze on load)
- **Symptom:** Chad pressed Play; Studio hung hard (had to kill the process). A freeze = a no-yield infinite loop in a coroutine, not a Luau error (build can't catch it).
- **Root cause:** `squadGoal` for the new aggressive bot squad called `findNearestEnemy(possessed, 1e9)`. `SpatialHash:nearest` → `forEachInRadius` computes `span = ceil(1e9/64) ≈ 15.6M` and loops `(2·span+1)² ≈ 1e14` cells with no yield. The `task.spawn(RoundLoop)` coroutine hung the whole scheduler the first Heartbeat after a bot squad existed + roundActive flipped true. (pcall around updateAICrows can't catch an infinite loop.)
- **Fix:** new `findNearestEnemyLinear` (direct scan over `Birds`, no hash/radius); aggressive squads hunt with it. Audited all other `:nearest`/`forEachInRadius`/`findNearestEnemy` calls — all bounded (engageRadius 45, attack reach, collision queryR). `.\build.ps1` green.
- **Reflection (SOP-6):** NEVER pass a map-spanning radius to a uniform-grid query — cost is O(radius²/cell²). For "nearest across the whole map" use a linear scan (bird counts are tiny) or a real KNN, not the broad-phase hash. Build green ≠ runtime-safe here; infinite loops slip the only automated gate.
- **Decision:** CONTINUE — re-handed to Chad for the Studio playtest (should now load).

---

### Iter 2b — 2026-06-29 (bots couldn't engage: obstacle avoidance #8 + spawn-near + enemy HUD)
- **Playtest feedback:** Studio loaded (freeze fixed), but "no AI crows attacked — a bird crashed 3×." Bots spawned but crashed into terrain before reaching the eagle (the AI obstacle-avoidance gap, queue #8). Also asked for a real environment + enemy HUD indicators.
- **Change A — AI obstacle avoidance (#8):** `BirdCollision.lookAhead` (forward Spherecast probe). `GameServer.avoidObstacle` returns a steer-away dir (surface normal + tangential slide) + urgency; blended into the boids steer in `updateAICrows` (weight×urgency). `GameConfig.Squad.avoidance` knobs. AI-only by construction (updateAICrows never runs the possessed crow) → honors Chad's rule. 
- **Change B — bots engage:** `spawnAICrowSquad` now spawns the wave ~700 studs off the eagle (was random map corner) so it finds the player fast.
- **Change C — enemy HUD indicators:** `GameUI` tracks `myTeam`; new marker pool — a box+range over each on-screen enemy bird, an edge arrow pointing at each off-screen one (WorldToViewportPoint each frame). Hidden between lives.
- **Verify:** `.\build.ps1` green. Studio re-test pending Chad.
- **Reflection:** Avoidance weight 3.5 / lookahead 1.2s are first guesses — may over-swerve (crows veer off the eagle) or under-avoid (still clip spires). Tune in the next playtest. Spawn-near 700 may feel like crows "appear" — acceptable for testing; revisit for real matches.
- **Decision:** CONTINUE — Studio playtest; pending separate decision on "real environment" scope (asked Chad).

---

### Iter 2c — 2026-06-29 (environment v4: terrain landmarks + bright/high-contrast lighting)
- **Ask (Chad):** real terrain (mountains/canyons) + scale/ground reference; brighter + higher contrast so it renders from further away; features for OODA-loop orientation.
- **Change — lighting:** `SetupLighting` v4 — Brightness 3 + ExposureCompensation + ColorCorrection (Contrast .18 / Sat .12) + subtle Bloom; Atmosphere density 0.3→0.18 (low) so distant features render crisply; FogEnd effectively off (atmosphere governs distance).
- **Change — map:** `BuildMap` v4 (LARGE anchored parts, NOT voxel terrain — no LOD cull at distance, full colour control, no per-voxel loop = freeze-safe; ~26 parts). Brighter ground + a Lake + Desert basin (ground landmarks); a 14-mountain perimeter RING at R=6600 (soft world edge / horizon); 5 interior rock buttes (canyon/cover) kept clear of the ±1200 spawn zone; **4 tall Neon CARDINAL BEACONS** (red=N, blue=E, gold=S, white=W) at R=4200 — glowing orientation refs visible from far (the OODA core). AI avoidance (#8) keeps crows from crashing on all of it.
- **Verify:** `.\build.ps1` green. Studio re-test pending Chad — judge brightness/contrast/render-distance + whether the landmarks aid orientation, and whether terrain re-introduces crash-frustration (tune density/positions).
- **Reflection:** Chose parts over voxel Terrain deliberately (render-far + freeze-safety); can swap to Terrain for an organic look if Chad wants it. Bloom/contrast values are first guesses. Mountain ring is soft bounds, not walls.
- **Decision:** CONTINUE — Studio playtest of the full package (combat + AI opponent + enemy HUD + environment).

---

### Iter 2d — 2026-06-29 (eagle CONTROL rework: banking smoothing + mouse-aim autopilot)
- **Ask (Chad):** banking is all-or-nothing → smooth/tone-down input; add a mouse-aim mode — a reticle in a screen zone the eagle continuously flies toward (autopilot), keyboard (smoothed, full deflection) OVERRIDES it per-axis, free-look (Space) suspends it; point the beak + right-click to strike. NOTE: this is a NEW ask, so it's in-bounds vs the v1.0-eagle-flight lock — and it's CONTROL-layer only (BirdController input assembly); the FlightPhysics aero kernel is untouched.
- **Change — banking smoothing:** generalized the pitch tap→ramp into `rampAxis` and applied it to roll + yaw too (new `Controls.bankTapFraction=0.22 / bankRampTime=0.50`). A tap eases the bank in; holding ramps to full — no more instant ±1.
- **Change — mouse-aim autopilot:** new `Controls.mouseAim=true` (+ aimZoneScale/Deadzone/Expo/Pitch·Roll·YawGain). `computeMouseAim` reads the ABSOLUTE cursor, clamps it to a circular screen zone, and maps the offset → pitch/roll/yaw steering the nose toward the reticle (persistent; centre = straight). A reticle ScreenGui (zone ring + dot) is drawn by BirdController; OS cursor hidden while flying. Per-axis OVERRIDE: a pressed key uses its smoothed value, an unpressed axis follows the cursor. Free-look (Space) → LockCenter orbit, aim suspended + reticle hidden. Old spring-stick `mouseSteer` superseded (left in config, gated off).
- **Verify:** `.\build.ps1` green. Studio test pending Chad — judge banking refinement, aim sensitivity (aimZoneScale = the main dial: bigger = less sensitive), reticle size/zone, and that keyboard override + free-look feel right. Watch: GuiInset alignment of the dot (OS cursor hidden so only the reticle reads, so minor offset is invisible); right-click beak while aiming.
- **Decision:** CONTINUE — Studio playtest of controls + the full combat/AI/environment package.

---

### Iter 2e — 2026-06-29 (mouse-aim corrected: target-follow + additive keyboard + zoom/scale)
- **Correction (Chad):** the mouse-aim is NOT a joystick-yoke. It's a TARGET POINT whose distance from screen-centre ramps the input (centre=beak heading/fine, edge=full); the code flies the beak there via a coordinated qweasd combo. Keyboard is ADDITIVE (augments to tighten/dodge, dominates when gross), not a per-axis override. Tune soft/smooth/flighty. Also: zoom out further + scale up birds to see them.
- **Change — aim model:** keyboard+aim now SUMMED & clamped (was per-axis override). Zone enlarged `aimZoneScale 0.34→0.80` (full deflection near the screen EDGE; most of the screen = fine aim → less sensitive). Added `aimResponse=7` — the applied aim EASES toward target (`aimApplied` lerp) for the soft/flighty feel. `aimExpo 1.7→2.0`, gains softened (pitch .85). 
- **Change — visibility:** `Camera.baseDistance 26→40`, `maxDistance 120→340`, `zoomStep 6→16` (zoom way out). New `GameConfig.Visual.birdScale=1.8` applied via `model:ScaleTo` in spawnBird — VISUAL only (collision/reach still use profile.bodyRadius → no balance change).
- **Verify:** `.\build.ps1` green. Studio pending Chad — judge flighty feel + sensitivity (aimZoneScale/aimResponse the dials), zoom range, bird size. Watch: visual-vs-hitbox mismatch at 1.8× (cosmetic), ScaleTo on welded model (pcall-guarded).
- **Decision:** CONTINUE — Studio playtest.

---

### Iter 2f — 2026-06-29 (whole-screen aim + coordinated level turn / split-S)
- **Ask (Chad):** cursor deflection across the WHOLE screen; a full sideways deflection held at mid-level should carve a coordinated turn that HOLDS altitude; a full-down deflection commits to a descending split-S (camera in tow).
- **Change:** computeMouseAim now PER-AXIS over the whole screen (`aimZoneScale 0.8→1.0` = full deflection at the screen edge; the dot tracks the true cursor). Added altitude-holding BACK-PRESSURE: up-elevator ∝ |bank| (`aimTurnPitchComp=0.5`) so a level side-aim banks-and-pulls into a coordinated level turn; the vertical aim still wins pitch so full-down commits to a descending half-loop/split-S. Reticle simplified to a fixed centre crosshair (beak neutral) + a dot tracking the cursor across the whole screen.
- **Verify:** `.\build.ps1` green. Studio pending Chad — the key dial is `aimTurnPitchComp` (raise if a full bank still sinks, lower if it climbs). Camera crest-damp (session 10) should keep the split-S camera smooth.
- **Decision:** CONTINUE — Studio playtest.

---

### Iter 2g — 2026-06-29 (mouse-aim = ATTITUDE COMMAND, fixes the looping)
- **Bug (Chad):** "the bird will loop toward and away." Root cause: my mapping fed the cursor offset straight to control RATES (constant deflection = constant rotation = it loops over the top). Wrong model.
- **Fix:** rewrote computeMouseAim as an ATTITUDE-COMMAND controller. The cursor sets a TARGET bank + pitch ATTITUDE (from the normalized per-axis offset × aimMaxBankDeg/aimMaxPitchDeg, + back-pressure aimTurnHoldDeg∝|bank| to hold altitude). Proportional control (aimBankP/aimPitchP) drives toward it using the bird's CURRENT attitude (rootPart.CFrame: asin(LookVector.Y)=pitch, asin(-RightVector.Y)=bank); error NULLS as the nose aligns → a held cursor settles into a steady coordinated turn/climb/dive and HOLDS, no loop. Centre=wings-level, full-down=steep dive/split-S. Keyboard still additive; aimApplied easing kept for flighty feel.
- **Config:** replaced rate gains (aimRollGain/aimPitchGain/aimTurnPitchComp) with aimMaxBankDeg=80, aimMaxPitchDeg=70, aimTurnHoldDeg=14, aimBankP=1.6, aimPitchP=2.2.
- **Verify:** `.\build.ps1` green. Studio pending Chad. Dials: aimTurnHoldDeg (altitude-hold in turns), aimBankP/aimPitchP (how snappily it seeks the attitude — lower=floatier), aimMaxBankDeg/PitchDeg (how hard the extremes command). Watch for oscillation (lower P or raise aimResponse if it hunts).
- **Decision:** CONTINUE — Studio playtest.

---

## Footer (keep current)
- **Current best:** iter 2g — combat + AI opponent + enemy HUD + environment + ATTITUDE-COMMAND mouse-aim (no looping) + zoom/scale, build-green, Studio-unverified. SC1–SC5 implemented; SC6 (sign-off) open.
- **no_improvement_streak:** 0
- **Status:** RUNNING (iter 2g awaiting Studio verify with Chad)
