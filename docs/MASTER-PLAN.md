# MASTER PLAN — Eagles to the Rescue: from Phase-0 slice to a leveled, functioning game

> **Status: ACTIVE — this is the work queue of record** (S40, 2026-07-15, Chad's directive:
> *"stop chasing bugs; hatch a proper implementation plan that actually works and produces a
> leveled functioning game; automate it"*). It supersedes the HANDOFF COLD-START queue and
> `program.md`'s item list as the source of what to build next. The executing harness is
> **`/master-loop`** (see §7); the SOP core is still `/evc-loop` (LOCKED specs, one change at a
> time, ASK-gated git).
>
> **How to edit this plan (Chad):** it's just markdown. Reorder/delete/add packets, change a
> `gate:` to move a decision to yourself, or write `SKIP` next to anything. The loop re-reads
> this file at every iteration and works top-down within the current phase. Nothing here is
> load-bearing except the packet IDs (the ledger cites them).

Grounding: this plan is derived from two audits (2026-07-15): a full built-vs-bible gap
analysis with a 14-bug autopsy, and a **proven** headless-verification feasibility run
(Lune v0.10.5 executed the unmodified `FlightPhysics` + `GameConfig` outside Roblox,
exit-code gated). Key findings folded in throughout; the bible remains
`docs/EAGLES-TO-THE-RESCUE-plan.md`.

---

## 1. The thesis (why this plan is shaped this way)

The 14-bug autopsy of every playtest bug Chad chased says: **~10 of 14 were pure
logic/state-machine/arithmetic bugs** (acquisition race, capacity silence, double-fire,
late-deliver phase gate, false finale arithmetic, seat pops, music ratchet…), ~2 were
visibility-invariant bugs (empty-map beacon, invisible fox), and only ~2-3 were genuine
feel calls (catch zoom, TALON_LOCAL). The recurring bug FACTORY is **the same logical fact
living in two authorities** — client and server each have their own catch gate formula, their
own carry count, their own claim state — and every divergence became a Studio bug hunt.

Therefore the plan's first phase is not features. It is:

1. **A headless test tier (Lune)** — run the pure logic on every change, exit-code gated.
2. **Extraction of the rescue rules into ONE shared pure module** — one gate formula, one
   capacity truth, one scoring function, one phase machine — consumed by both client and
   server, tested headlessly, with the 10 historical logic bugs encoded as a permanent
   regression suite.

After that, features land ON a substrate where the machine catches the logic bugs and
**Chad's Play is reserved for what only Chad can judge: fun.** Feel gates get batched at
phase boundaries (the S39 ANIMATION-BATCH pattern, generalized).

**Invariants inherited unchanged:** kernel/camera/aim law LOCKED (CS-1..CS-9 registry in
HANDOFF); rescue is built AROUND them; non-lethal always (P3); kid-floor + skill-ceiling in
the same mechanic; one packet = one commit-ready checkpoint; git commit/push ASK-gated.

---

## 2. Verification ladder v2 (the definition of "verified")

Every packet must exit GREEN on the ladder below. Tiers 1-3 exist today; **Tier 4 is new
and proven feasible** (Lune v0.10.5, `lune-0.10.5-windows-x86_64.zip` from
`github.com/lune-org/lune/releases`, bootstrapped exactly like Rojo; `@lune/roblox` supplies
Vector3/CFrame/Color3/Enum; the loader pattern — flat `environment` globals, string-require
shim, preloaded sources — is on record in the S40 feasibility report and ships in packet A1).

| Tier | What | Catches |
|---|---|---|
| 1 | `rojo build` | wiring, script-class mapping |
| 2 | `luau-lsp analyze` (0 NEW vs baseline) | broken requires, nil fields, renamed contracts |
| 3 | `selene` (best-effort) | lint smells |
| **4** | **`lune run tests/`** — pure-logic specs, exit-code gated | **state machines, scoring math, gate formulas, phase transitions, seat allocation, economy/fire simulation — the 70% class** |
| 5 | Chad's Studio Play | feel, fun, readability — **batched at gates only** |

**Rule: a bug found in Tier 5 that Tier 4 could have caught gets a failing test written
FIRST, then the fix.** The regression suite only grows.

What Tier 4 can never test (honest limits): replication/`SetNetworkOwner`, camera/aim feel,
real frame budget, Remotes round-trips. Those stay Tier 5 — but they were never the churn.

---

## 3. Numbers workbook (the math of record — derived, then simulation-verified)

These are the derivations behind the plan's key numbers. Where marked SIM, packet tests
assert the property by running the actual module headlessly (not by trusting the derivation).

### 3.1 The catch-gate chain (the five knobs that must move together — was bug 2c)
One eligibility function (packet A2), both authorities:

```
R_eff   = triggerRadius · ftueMult · (1 + scoopSpeedGain · closing/glideSpeed)   -- CLIENT trigger radius
eligible = dist ≤ R_eff  AND  closing ≥ closingGateFrac · glideSpeed  AND  carry < capacity
server:   dist_at_receipt ≤ triggerRadius · catchGateMult + speed · catchGateLatency   -- LOOSE envelope, NOT R_eff-derived
```
LIVE values (the behavior-preserving source of truth — `GameConfig.Rescue`, `RescueServer:552`, `BirdController:1898-1916`):
triggerRadius **42** (`GameConfig.luau:752`; the `or 28` at `RescueServer:539` is only a fallback literal, NOT the
live value — Fable S41-A2 caught this), catchGateMult **3.5**, catchGateLatency 0.25, scoopSpeedGain 0.25,
closingGateFrac 0.30 (ftueGateFrac same), ftueRadiusMult 1.5, glide ≈ eagleGlide() (130), birdScale 2.3.
⚠️ the scoop term uses TOTAL airspeed (`flightEngine.speed`, `BirdController:1916`), not `closing/glide` as §3.1's
formula box abbreviates. Transcribe from the LIVE lines, never from the doc — the parity-oracle test enforces this.
⚠️ **A2 AMENDMENT (pins the keystone against re-breaking bug 2c) — DO NOT re-derive the server gate from R_eff.**
The server gate is DELIBERATELY looser than the client radius: `catchGateMult 3.5` exists because the S36 diag
observed *legit* catches at server-dist **80–110** (replication lag + the 2.3× eagle flies on after the client
triggers — `RescueServer:533-537`). A "behavior-preserving" extraction that implements the old `R_eff + speed·latency`
line RE-TIGHTENS the gate (~117 vs the live ~212 @ maxSpeed) and resurrects the "8–9/10 don't count" class — the one
bug that violated the sacred guaranteed catch (P1). The ONE shared function must keep `catchGateMult` as a term and
carry birdScale 2.3 inside it, not as a server-side surprise. Fable pins the exact envelope in A2's design spec first.
**SIM property (kills bug-class 2c permanently):** for every client-eligible catch, sweep speed × latency (≤250 ms) ×
approach angle AND assert the server function accepts across the **observed 80–110 server-dist band** (not just the
geometric latency slack). Zero false rejects allowed.

### 3.2 Acorn economy (what a round pays → level thresholds)
Current formulas (already server-authoritative): catch = 100 · rarity · style(≤3) ·
energy(1/1.5/2); deliver = n² · 10 · combo(≤6); perfect-ten time factor ×2/×3(≥30s)/×4(≥60s);
acorns = points/10, quantized before factors (bug-12 invariant).

Envelope (SIM will refine): casual round (8 catches, style≈1.2, one 8-deliver, combo≈2)
≈ **~230 acorns**. Skilled perfect-ten (10 catches, style≈2, energy mix, 10-deliver combo 4,
×3 time factor) ≈ **~1,700 acorns**. Ratio skilled:casual ≈ 7:1 — steep but acceptable while
solo; revisit before leaderboards. Deliver dominates catch income (~4:1) — correct, n² is the
headline math moment; the incentive "fill to 10, then bank" is strictly optimal (n² superadd:
10² > 5²+5²) which matches the intended risk decision (keep chaining vs bank before the fire).

**Level track starting values (Chad-tunable, C1):** valley 2 "Frostfall" at **2,500** cumulative
acorns (~6-10 casual rounds or ~2 great ones), valley 3 at 9,000, valley 4 at 25,000, then
×~2.5 per step. Property: a purely-casual player levels at least every ~25 minutes early on.
**SIM:** Monte-Carlo 500 simulated rounds across skill profiles through `RescueRules.score`;
assert yield bands and threshold pacing.

### 3.3 Fire-cell grid (Phase B centerpiece — sized to pressure, not punish)
Geometry: valley radius 1600; burnable forest annulus ≈ r 300-1400. Cell = **60 studs** →
~54×54 bounding grid, **~1,900 burnable cells**. States GREEN→SMOLDER(15-25s)→BURNING(~20s)
→EMBER(inert). Tick **2 Hz**, server, pure module (`FireGrid.luau`) + thin visual layer.

Target pressure: seeds ignite ~t=10s; by round end the fire has *threatened* ~35-50% of grove
area and cut off **2-5 squirrels** (triage is real, hopelessness never). Front must reach a
grove ~500 studs downwind by ~t=100s → front speed ≈ 5.5 studs/s ≈ 1 cell / 11 s. Expected
neighbor-ignition delay = 1/(2Hz · p) = 11 s → **p_downwind ≈ 0.045/tick**; crosswind ≈ p/3;
upwind ≈ 0 (the per-round wind vector reshapes the burn = replayability with one number).
Perf budget: ≤ **1.5 ms**/tick server; ≤ **30** BURNING cells visualized (1 flipbook billboard
+ 1 smoke emitter + 1 PointLight each, hard-capped; EMBER = free tint swap; trees never deform).
**SIM (the showpiece):** run `FireGrid` headless over 100 seeded (wind, seed-cell) rounds;
assert coverage %, cut-off counts, and front-speed all inside the bands above. **The fire is
tuned by simulation before it ever renders a flame.**

### 3.4 Standing perf envelope
Server: fire ≤1.5ms + existing rescue scan (SpatialHash-backed, near-linear). Client: particle
cap unchanged; tree part count reviewed at C3 (art pass) with an explicit instancing budget.

---

## 4. PHASE A — STABILIZE: make the game machine-verifiable (all autonomous, no feel gates)

> Exit criteria: ladder v2 green including Tier 4; the 10 historical logic bugs encoded as
> passing regression tests; client & server consume ONE rules module; open bugs F3 + claim
> guard class closed by construction. **Gate A** (end of phase): a single sanity Play — nothing
> should FEEL different; this phase is behavior-preserving.

- **A0 — Config/intent reconcile.** `GameConfig.activeMission` is `"fox_on_the_hill"` but the
  fox is SHELVED (S39) — flip to `"waterfall_meadow"` (byte-identical to the shipped round).
  Blocked-on: Chad's S39 commit landing first (don't stack diffs into his pending batch).
  `[model: opus | gate: tests]`
- **A1 — Tier 4 bootstrap. ✅ DONE S40 (commit-ready).** `tools/Bootstrap-Lune.ps1` (clone of
  Bootstrap-Rojo, pin v0.10.5) · `tests/_loader.luau` (Roblox-module→Lune bridge) · `tests/_harness.luau`
  (exit-code harness) · `tests/kernel.spec.luau` (spawn/glide/flap invariants + no-NaN storm over 200
  frames, Eagle+Crow) · `tests/run.luau` (spec discovery + exit gate) · `verify.ps1` Tier 4 wiring,
  UNAVAILABLE-degrading. Tier 4 GREEN (5/5, exit 0). NOTE for A2+: in Lune 0.10.5 `luau.load` auto-injects
  std libs and DOES consult `__index`, so the loader only supplies Roblox datatypes + script + require (not
  the "flat everything" the older note implied). `[model: opus | gate: tests]`
- **A2 — `RescueRules.luau` extraction (the keystone). ⏳ A2.1 DONE S41 (commit-ready); A2.2/A2.3/A2.4 queued.**
  A2.1 landed the INERT pure module + full regression suite (Tier-4 35/35 GREEN incl. the PARITY ORACLE 1,000-pt
  exact-equality sweep vs the old inline formulas + the §3.1 SIM zero-false-reject + §3.2 economy Monte-Carlo casual
  ~294 / skilled ~1964, ratio 6.68). `acceptEnvelope` honors the amendment (never re-derives from effectiveRadius).
  Design spec: `docs/rescue-consults/A2-RescueRules-design.md`. NEXT: A2.2 server consumes → A2.3 client consumes →
  A2.4 sticky seats (F3, the one intentional behavior change, lands alone). Original scope below.
  preserving refactor of: catch eligibility (§3.1 unified formula — replaces the client's
  closing-frac check at `BirdController:1891-1928` AND the server's distance-slack gate at
  `RescueServer:530` with the SAME function), capacity (one counter of truth), claim/dedup
  (the S35c guard, now testable), combo/streak (`:553-565`), scoring + deliver payout +
  quantize + time factor (`:548-566,604,659-676`), stable per-rider **seat map** (fixes open
  bug F3 by construction — a rider's seat never re-indexes), round phase machine
  (intermission→active→grace→results + triage hook). Spec files encode historical bugs
  2a/2b/2c/6/8/9/10/11/12 as regression tests + the §3.1 SIM property + §3.2 economy SIM.
  Split into 3-4 commits (module+tests · server consumes · client consumes). This is the
  highest-leverage packet in the plan. `[model: opus, fable designs the module API first | gate: tests]`
- **A3 — Acquisition FSM hardening.** Extract the possess/acquire state machine (the S34 race,
  `trackModel`/`reacquire`) into a testable pure FSM: attributes arriving in ANY order must
  reach ACQUIRED; backstop poll becomes a tested transition, not a band-aid. `[model: opus | gate: tests]`
- **A4 — Visibility invariants (the V-class). ⏩ PARTLY DONE S40 — UPGRADED to headless MODEL-BUILD
  validation.** Chad's S40 quality demand ("quality standards before I judge it", after invisible
  squirrels + a paddle-talon reached him) forced this early and bigger than scoped: @lune/roblox builds
  the REAL BirdBuilder models headlessly, so the gate now checks GEOMETRY, not just descriptors.
  DELIVERED + GREEN: `tests/models.spec.luau` (squirrel visible/non-degenerate; **beacon must not occlude
  the squirrel** — teeth proven: S39 beacon FAILS it; eagle has talon joints) + `tests/talon.spec.luau`
  (forward-kinematics **grasp-closure gate** — open/close/converge + rest-pose preservation; a rotating
  paddle fails by construction). Still TODO under A4: fox-class marker check + one-results-stamp check
  (bugs 5/8/14). `[model: opus | gate: tests]`
- **A5 — Audio contract checks.** The flap-saga regressions as tests: the per-frame projection
  is a pure function (volume == 0 the frame effective flap is 0; monotone with throttle; dive
  fade applies); static check that no sample id is reused by ≥2 looped Sounds (the SFX_SWOOSH
  rule). DO NOT touch the shipped audio design — tests only. `[model: opus | gate: tests]`
  ⚠️ **A5 RE-SCOPE (S41 finding — DEFERRED, do NOT build as written):** the "no sample id reused by ≥2 looped
  Sounds" rule is WRONG for the shipped design — `flapSound` (`BirdController:1284`), `windSound` (`:1326`) and
  `musicBed` (`:2192`) ALL intentionally share `SFX_SWOOSH` (musicBed pitched into a rumble bed). The flap-saga was
  closed by the STATELESS PER-FRAME VOLUME PROJECTION (Chad-confirmed; memory: "don't reopen audio"), not unique
  samples. A naive rule would red the approved design. The REAL invariant to test is "each looped SFX sound's Volume
  is driven every frame and is never `:Stop()`-gated" (silence = arithmetic) — but that needs the projection
  extracted to a pure fn (scope) or a careful source-scan, and must not pressure the shipped audio. Re-scope with
  Chad before building; A5 is NOT a Phase-A exit blocker.
- **A4-remainder note (S41):** the fox-class marker check is MOOT while the fox is shelved (A0 set
  `activeMission="waterfall_meadow"`; the fox subsystem is inert). Bug-8 (deliver phase gate) is already covered by
  A2's `phaseAccepts` regression test. Only a "results stamped exactly once" guard (bug 14) might still add value —
  defer until a results-flow packet, not a Phase-A blocker.
- **A6 — Tier 4.5 smoke boot. ✅ BUILT S41 (commit-ready) — but SCOPED DOWN by a hard tool limit.** Wired
  `run-in-roblox` v0.3.0 (`tools/Bootstrap-RunInRoblox.ps1`, pinned, `tools/bin/` gitignored) + `tests/smoke/boot.smoke.luau`
  + `tools/Smoke-Boot.ps1` (build → launch Studio headlessly → sentinel-gated, time-boxed, UNAVAILABLE-degrading) +
  `verify.ps1 -Smoke`. **KEY FINDING (verified live S41): run-in-roblox 0.3.0 runs the script at PLUGIN security in
  EDIT mode (`IsRunning=false`) — it does NOT start a Play/Run session, so the game's `.server` scripts stay DORMANT.**
  Therefore the smoke CANNOT observe the live server round (squirrel population, Remotes, client-overrides-server
  visuals, at-distance readability) — those four "machine-blind" classes stay Tier 5 (Chad's Play) or need a future
  **Open Cloud Luau-execution packet** (real running server in the cloud; write it if this gap keeps burning). What the
  smoke DOES cover, and lune Tier 4 canNOT: it loads the shared modules and builds the REAL models in the REAL Roblox
  engine — catching load/compile/build errors + geometry regressions that `@lune/roblox`'s approximation misses. **It
  already earned its keep on first run:** it caught that `talon.spec`'s eagle-build call `Build(Profiles.Eagle, Vector3)`
  passes under lune's lenient Vector3 but ERRORS in real Studio (`displayName is not a valid member of Vector3`) — a
  lune-vs-engine discrepancy (the game's real call is `Build("Eagle", profile)`; see A-FINDING below). GREEN S41
  (modules load · squirrel 20 parts/extents 13 · eagle 20 Motor6D joints). `[model: opus | gate: tests, best-effort]`
- **A-FINDING (S41, for A2/spec-hardening):** lune's `@lune/roblox` is LENIENT where real Roblox is STRICT — indexing
  an unknown member on a Vector3 returns nil in lune, throws in Studio. `talon.spec`/`models.spec` eagle-build calls
  rely on this leniency (`Build(Profiles.Eagle, Vector3)` builds a non-eagle that still passes). Not fixed now (the
  gate is green and out of A6's scope), but when A2 touches the specs, correct the build calls to the game's real form
  `Build("Eagle", GameConfig.Profiles.Eagle)` and consider running key specs through BOTH lune (fast) and the smoke
  (faithful) so leniency can't hide an engine error again.
- **A-RULE (Fable S41):** the "self-red-team suffices for cosmetic packets" carve-out is exactly where S39 slipped.
  STANDING RULE: any packet that adds a NEW visual element class ships a matching `tests/models.spec` geometry test in
  the SAME checkpoint — not a habit, a gate.

## 5. PHASE B — THE ROUND (bible Phase 1: the fire makes it a game)

> Exit criteria: a full round vs a living fire with triage, non-lethal crashes, FTUE, and
> leap variety — fire tuned by simulation to §3.3 bands before Chad ever sees a flame.
> **Gate B (the big one):** Chad plays the fire round — "did the fire change your route, and
> did losing squirrels to it feel like triage, not theft?"

- **B1 — `FireGrid.luau` (pure) + SIM tuning.** The §3.3 module: cell states, wind-weighted
  spread, cut-off detection (grove surrounded → countdown), 2 Hz stepper — NO rendering, NO
  instances. Tier-4 sims assert the §3.3 bands over 100 seeded rounds. Hangs off the mission
  framework as `hazard.kind="fire"` (the built `resolveMission` seam, inert-by-default).
  `[model: fable designs, opus implements | gate: tests+SIM]`
- **B2 — Fire server wiring + visuals (budgeted).** RescueServer drives FireGrid; visual layer
  hard-capped per §3.3 (30 burning cells max, flipbook+1 emitter+1 light, EMBER=tint). Replaces
  the fake `triageAt` random balloon-lift with real spatial cut-off (countdown ring → Ranger
  Balloon pre-collect, never harm). Perf diag prints tick-ms. `[model: opus | gate: tests, perf diag]`
- **B3 — Crash→bounce.** Complete the non-lethal contract: cartoon bounce + feather poof +
  1.5s dazed recovery (reuse graze-slide; `nonLethalTerrain` already suppresses lethality).
  Prerequisite for canopy collision. Kernel untouched — presentation + the existing collision
  seam only. `[model: opus | gate: tests + batched Play]`
- **B4 — Canopy collision + first trail cuts.** Grove trees become collidable (`CanQuery`),
  3-4 gray-box named trail corridors under the canopy (the skill layer's geometry). Depends
  B3. `[model: opus | gate: batched Play]`
- **B5 — Leap variety + saved-crowd.** 3-4 leap styles (cannonball/swan/flail/cool-guy —
  extends the built `PoseSquirrel` rig) + delivered squirrels persist as a visible crowd on
  the meadow (the crowd IS the scoreboard) + **squirrel squeak SFX (bible line 19 — the audio half of the "want": you
  HEAR a hidden squirrel squeak under the canopy before you see it; spatial Sound on the stranded model, Fable S41
  found this dropped from the plan).** `[model: opus | gate: batched Play]`
- **B6 — FTUE script.** Green-corner spawn, one guided beacon, 1.5× spheres (hooks exist),
  guided first delivery, then the "whoomph — GO!" round start. No tutorial screens.
  `[model: fable designs, opus implements | gate: Gate B Play]`
- **B7 — INPUT TRACK: touch + gamepad — ⚠️ DESIGN-GATED, runs as its own track.** Zero exists
  today and the free-cursor mouse-aim law has no touch analog — this is a design problem that
  touches LOCKED territory (CS registry) and CANNOT be autonomously decided. Fable design
  consult + Chad decision FIRST; implementation packets get written only after. Do not let
  this block B1-B6. `[model: fable consult → CHAD | gate: design approval]`

## 6. PHASE C — THE LEVELED GAME (bible Phase 2: progression, persistence, the valley)

> Exit criteria: acorns persist, valleys unlock on the §3.2 track, rares fill The Den, and
> Emberpine looks like a place. **This phase delivers "a leveled functioning game."**
> **Gate C:** soft-launch readiness Play (a complete, charming product: catch + fire + collection).
> **Gate C precondition (Fable S41 audit):** B7 (touch + gamepad) must be RESOLVED and IMPLEMENTED before Gate C —
> the bible makes touch/gamepad "first-class from MVP" (ages 5–12 is a mobile audience); soft-launching mouse-only
> abandons most players. B7 stays design-gated/CHAD but is no longer optional for soft-launch.

- **C1 — Persistence + level track.** DataStore profile (cumulative acorns, rescued log, den),
  §3.2 thresholds as a `Levels` config table (Chad-tunable), valley-unlock flow. Valleys 2+
  reuse the world-gen with new seeds/palettes until the art pass. Economy SIM re-run against
  real formulas = the threshold check. `[model: opus | gate: tests]`
- **C2 — The Den (collection book).** Rares persist as named pets; collection UI; login greet.
  Rarity stays rescue-only, never purchasable. `[model: opus | gate: batched Play]`
- **C3 — Emberpine art pass (staged, budgeted).** Stylized-chunky canopy (instancing/imposter
  budget written BEFORE art lands), real waterfall dressing, named clearings/grottos. The one
  deliberately expensive packet — split into sub-passes, each perf-checked. `[model: opus | gate: batched Play]`
- **C4 — Fire look + audio tiers.** Visual/audio escalation on the (already tuned) grid.
  `[model: opus | gate: batched Play]`
- **C5 — Round polish orbit.** Music escalation polish (deferred S36 item), stamps/results
  screen final pass, rare polaroid capture. `[model: opus | gate: Gate C Play]`

## 7. PHASE D — META (bible Phase 3: only after C ships)

Not decomposed yet — decompose when reached (plans rot; packets are written one phase out).
Headlines: squirrel decoration + den visiting · plane parts + workbench + RC formation
squadron (Boids/Squad reuse) · duos + ping wheel + Double Rescue · Rescue Pass (compliance
rules in the bible §monetization) · server-side style/speedTier recomputation (the anti-cheat
seam noted in the audit — MANDATORY before any leaderboard/multiplayer surfaces).

---

## 8. Execution model (how the loop runs this plan)

- **The harness is `/master-loop`** (built S40 via /agent-builder): orient → pick the top
  unblocked packet in the current phase → (design-heavy? Fable architect consult first) →
  implement via **Opus subagent(s)** with the packet as spec → red-team (subagent) → ladder
  v2 → ledger + HANDOFF → commit-ready checkpoint (ASK-gated) → next packet. It STOPS at
  phase gates, on LOCKED-spec risk, and on anything only Chad can decide (B7).
- **Model policy (Chad's token directive):** Fable orchestrates, designs module APIs, audits
  design-critical packets (the S37 before/after bracket pattern), and adjudicates red-team
  findings. **Opus does the bulk implementation** — packets arrive as tight specs with
  acceptance tests, which is exactly the shape Opus executes well. Mechanical packets (A4, A5,
  bootstraps) may run entirely on Opus.
- **Chad's gates, batched:** Gate 0 = fly the pending S39 animation batch → approve its commit
  (already prepared). Gate A = one sanity Play after Phase A (should feel IDENTICAL). Gate B =
  the fire round. Gate C = soft-launch readiness. Plus the B7 design decision. Everything else
  is machine-gated.
- **Failure policy:** unchanged from `program.md` — fix trivially or revert, never leave the
  tree red, one cohesive checkpoint per packet, ledger every iteration
  (`.loop/rescue-phase0/state.md` continues as the ledger of record).
