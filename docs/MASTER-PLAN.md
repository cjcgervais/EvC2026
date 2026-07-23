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

## ★ CHAD DIRECTIVES — S42 (2026-07-21): THE FUN VERDICT (read before picking a packet)

Chad flew the kid-legibility Stage 1+2 build: *"EvC2026 is addictive and fun and it has
levels to it. Its actually fun!… very happy with the latest progress. Need to shore it up,
optimize, plan and build."* The core loop (catch → carry → bank vs the fire clock) is
**CONFIRMED FUN** — don't re-litigate it. His directives, mapped onto this plan:

1. **"Definately need to have levels unlock"** → **Phase C is a Chad REQUIREMENT**, the
   post-Phase-B headline. C1 (persistence + level track) is the flag to march toward.
2. **"little squirrel sounds and music even the better"** → **B5's squeak SFX + music
   polish (C5's escalation item) are ENDORSED** — schedule, don't defer. Respect the S37
   stateless per-frame audio architecture; "don't reopen audio" = the flap saga, not new SFX.
3. **"could be fun on mobile too"** → **B7 has a positive Chad signal** (still design-gated,
   CHAD decides the touch analog of the aim law — but no longer speculative; run the Fable
   design consult sooner rather than later so implementation packets exist before Gate C).
4. **"shore it up, optimize"** → a **SHORE-UP packet precedes new features**: land the
   pending Stage 1+2 commit, push `updraft` (if Chad approves), perf-envelope check (§3.4,
   fire tick-ms + particle budget with flicker/plume live), Stage 3 of the kid-legibility
   plan, then B4/B5.
5. Kernel note of record: slight kernel "incorrectness" (the tight mouse-curl) **is a
   feature** — never correct toward realism (memory: `feedback-kernel-incorrectness-is-a-feature`).
6. **"Other levels can have frogs or snakes other n types of animals?" — YES (S42):** each unlocked
   valley gets its own CRITTER CAST → packet C2.5 below. The catch loop is animal-agnostic
   (trigger → leap → talon), so new animals are model + pose + leap-arc + SFX variety, never
   new mechanics. Frogs are the natural second animal (a frog LEAPING to your talons is the
   mechanic at its best).

---

## ✅ S43 PROGRESS (2026-07-21) — shore-up done, Stage 3 two-thirds done, B7 opened

Worked directive #4's order literally (shore up BEFORE features). All on `updraft`, each red-teamed,
ladder Tier-4 105 → **128** tests.

- **§3.4 IS NOW MACHINE-PINNED** — `tests/perf.spec.luau` (particles / lights+shadows / allocation-free
  sync / reported timing). It found a real breach on day one: worst `FireGrid.step` 4.37ms vs the ≤1.5ms
  budget → optimized to ~1.1-2.0ms worst, `recomputeCutOff` 5.7× faster, **proven bit-identical** across
  10 seeded rounds + the red-teamer's stronger per-tick harness. Rule of record: assert WORK
  deterministically, only REPORT wall-clock (Lune ms ≠ Roblox ms).
- **Kid-legibility Stage 3a (critter FEAR) + 3c (fire ROAR) are LIVE and unflown.** 3b (world-dims) is
  deliberately LAST and a **CANDIDATE FOR CUT** — it is the only channel that can fight the legibility
  Stage 1+2 won, so Chad's Play decides whether that global-Lighting risk is ever spent.
- **B7 opened:** the consult is written (`docs/rescue-consults/B7-touch-design.md`) and **P1 is BUILT
  INERT** (`TouchAimAdapter` + parity oracle). Structural finding: the aim law consumes ONE input, so
  touch is a delta-source ADAPTER, never a new control law.
- **Mobile perf ceiling, from our own gate:** 30 non-shadow PointLights are the low-end cliff;
  `Fire.maxVisualBurning` 30→12 is the ONE master dial (moves flipbook+emitter+light together).

**▶ BLOCKED ON CHAD (nothing else is):** ① the Play (3a+3c; also decides 3b build-or-cut) ② **DRAG or
TAP** — the one B7 question; P1 was built ahead on Fable's DRAG recommendation and is discardable at
zero cost if the answer is TAP. Then: B7-P2 proof-of-feel → B4 → B5 → Phase C (C1 levels).

---

## ★★ S47 STRATEGY RE-MASTER (2026-07-22) — THE QUALITY PIVOT (read before picking any packet)

Chad halted the loop at S46: the game is an untextured gray-box treated as shippable, every
perceptual fix costs him 7–8 passes, and he is *"fighting mediocrity rather than testing
something competitive."* The full diagnosis is `docs/CONSULT-VISUAL-QUALITY.md`; the answer is:

1. **`docs/VISUAL-QUALITY-BAR.md` is now a gate document** — the written definition of "good"
   (target look, per-set-piece definition-of-done, perf budget, honesty rule). Player-visible
   work either meets it or is flagged `PLACEHOLDER(expiry)`. Scope honesty: **this game is
   being built to publish.**
2. **PHASE V (VISUAL FOUNDATION, §5.5 below) is the ACTIVE phase** — it runs before the
   B-remainder (B5/B6) and Phase C. C3's art pass is largely absorbed by it.
3. **The execution model is inverted (§8)** — grind sessions run on **Opus** (Sonnet for
   mechanical packets); **Fable supervises**: design brackets, screenshot audits, red-team
   adjudication, gates. Chad flies at phase gates only, always after a Fable image-audit pass.
4. **The instrument gap is closed with images, not flights** — a screenshot harness (M2) gives
   Fable eyes; visual iteration happens at zero Chad cost. Chad ratifies the target look FROM
   SCREENSHOTS at Gate V-LOOK, then flies once at Gate V.
5. **"Renders in slow" (REOPENED) is deliberately parked until after the world rebuild (M1/M4)**
   — the world that's slow to draw is the world the rebuild replaces wholesale; diagnosing
   Auto-graphics behavior on geometry we're about to delete is waste. Boot-to-drawn is measured
   at Gate V with the existing probe; if still slow, a dedicated DRAWN-clock diagnosis packet
   runs then (per `feedback-when-a-fix-fails-reinstrument`).
6. **The 7 unjudged S45/S46 changes** stay live and fold into the Gate V flight checklist per
   the ★CHAD-Q answer. *(S47's "V0 fixes the z-fighting now" exception was OVERRULED by Chad
   in S48 — the flashing map is LANDFILL; the z-fight dies with it. §5.5 S48 re-cut.)*

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
  Kernel untouched — presentation + the existing collision seam only.
  `[model: opus | gate: tests + batched Play]`
- **B4 — ⚠️ SUPERSEDED (S47) — DO NOT BUILD AS WRITTEN.** "Grove trees become collidable" now
  directly violates Chad's S45c decision (`Rescue.treeCollision` stays `"off"` — the ghost
  forest is a DESIGN DECISION) and would re-entangle collision with scoring, which S46's B4.2
  deliberately decoupled. Canopy-threading pays via the B4.2 style scorer instead. Any revival
  of tree collision or trail corridors requires an explicit Chad re-ask first.
- **B5 — Leap variety + saved-crowd.** 3-4 leap styles (cannonball/swan/flail/cool-guy —
  extends the built `PoseSquirrel` rig) + delivered squirrels persist as a visible crowd on
  the meadow (the crowd IS the scoreboard) + **squirrel squeak SFX (bible line 19 — the audio half of the "want": you
  HEAR a hidden squirrel squeak under the canopy before you see it; spatial Sound on the stranded model, Fable S41
  found this dropped from the plan).** ⚠️ S47: the squeak-SFX line is ABSORBED by Phase V packet M6a — don't
  rebuild it here; B5's remaining scope is leap styles + the saved-crowd. `[model: opus | gate: batched Play]`
- **B6 — FTUE script.** Green-corner spawn, one guided beacon, 1.5× spheres (hooks exist),
  guided first delivery, then the "whoomph — GO!" round start. No tutorial screens.
  `[model: fable designs, opus implements | gate: Gate B Play]`
- **B7 — INPUT TRACK: touch + gamepad — ⚠️ DESIGN-GATED, runs as its own track.** Zero exists
  today and the free-cursor mouse-aim law has no touch analog — this is a design problem that
  touches LOCKED territory (CS registry) and CANNOT be autonomously decided. Fable design
  consult + Chad decision FIRST; implementation packets get written only after. Do not let
  this block B1-B6. `[model: fable consult → CHAD | gate: design approval]`

## 5.5 PHASE V — VISUAL FOUNDATION (S47, ACTIVE): build the game we'd actually publish

> The quality pivot. Exit criteria: the world meets `docs/VISUAL-QUALITY-BAR.md` §2 on every
> row, inside the §3 perf budget, verified by machine gates + Fable image audits — and Chad has
> flown it ONCE (Gate V) and called it a game he'd show someone. **Two gates:** **Gate V-LOOK**
> (Chad ratifies the target look from screenshots — in chat, no Studio) and **Gate V** (one
> flight: look in motion + load time + the surviving S45/S46 backlog + audio). Batching rule:
> art passes are BATCHED (one-change-at-a-time remains law for kernel/logic only). Every packet
> still config-gated with a kill switch.
>
> **🧭 S48 RE-CUT — MAP-FIRST.** Chad halted the S48 loop on V0: the old V0→V1→V2 order put
> three plumbing packets ahead of the first visible map improvement, and the first two invested
> in the rejected gray-box map. **V0 is CANCELLED** (built clean, then reverted — full record in
> the S48 ledger block; the pairwise-coplanarity TEST idea survives, applied to the new world's
> remaining Parts). **V1 is CANCELLED as an extraction** — the new world is written natively as
> a pure module, which inherits everything the extraction existed for; its S47 side-effect
> surface list becomes the new module's birth contract. Old V2/V3/V4 are re-cut below as
> M2/M1+M3/M4. The master-loop SKILL now carries a **HEADING gate** so plan order can never
> again outrank the heading.
>
> **HEADING:** *build the REAL map — Terrain + lighting first (code-only, zero assets), meshes
> when sourced; every packet leaves the published look visibly closer.*

- ~~**V0 — Kill the flashing.**~~ **CANCELLED S48** — polish on the rejected gray-box map
  (LANDFILL). Built clean, then reverted; record in the S48 ledger. The z-fight dies with the
  gray box when `Map.worldV2` replaces it. The pairwise-coplanarity test idea carries into M1's
  Part gate.
- ~~**V1 — WorldGen extraction.**~~ **CANCELLED S48** — an extraction of builders we are
  replacing. The new world (M1) is written natively as a pure module, which inherits the
  extraction's whole purpose (headless Tier-4 geometry gates + edit-mode building for the
  harness). The S47 side-effect surface list — `Workspace.Gravity = GameConfig.Flight.GRAVITY`
  first, Lighting/Atmosphere/CC/Bloom properties, attribute publish timing (`CanopyCount` /
  the B4.2 race), folder identities clients `WaitForChild` on ("Map", "RescueWorld"), live
  handles (`worldFolder` parents fox flares/squirrels; FireGrid consumes groves+deliverPos),
  Thermals' y=0 ring, injected RNG seed — is M1's birth contract, gated from day one.
- **M1 — TERRAIN VALLEY + LIGHTING RIG v1 (the heading packet — the map Chad asked for). ✅ DONE S49 (commit-ready).**
  Built `src/shared/WorldGen.luau` as a PURE `plan(cfg)` (data — heightAt bowl, water+floors, catch floor,
  lighting, datumSamples, birth contract) + THIN `build(target,cfg)` applier, behind `Map.worldV2` (default
  ON). Red-team caught + FIXED a P3 void-death regression (hidden ±8000 catch slab at −120 restores the
  legacy "solid everywhere" guarantee) + a lake grass-lid + flag-off honesty; Finding 5 (dropped GroundDetail
  closure cue) deferred to M3. Tier-4 221/221 · rojo PASS · luau-lsp 0 NEW. APPEARANCE unverified (Terrain
  never engine-built — that's M2's job). Original scope below.
  New pure shared module `src/shared/WorldGen.luau` — a FRESH build, not an extraction —
  behind `GameConfig.Map.worldV2` (kill-switch honesty: `false` restores the untouched legacy
  gray-box path exactly, `Terrain:Clear()` on flag-off; legacy path retained until Gate V
  passes). Contents, all Roblox-native / **zero assets**:
  ⓐ **Terrain valley bowl** — sculpted painted ground (`FillRegion`/`FillBlock`/`FillWedge` +
  `PaintRegion`; grass/leafy-grass/rock palette per the Ember Valley bible), a terrain mountain
  RIM replacing the primitive mountains, rivers/lake/sea as Terrain water **with solid floors**
  (see invariant ②). ⓑ **Lighting rig v2** — skybox, golden low sun, `Atmosphere` haze for
  aerial depth, subtle Bloom/ColorCorrection.
  *Design brief (Fable S48):* the valley reads as a bowl; the playable floor stays at the
  current datum with only minor relief — **relief spends on the mountain ring**; the fire-grove
  annulus, spawn core, pad approach and perch band sit on near-flat ground.
  **Invariants (from old V4 — each a LOGIC change wearing art clothes, each with its machine
  gate):**
  ① **Ground datum:** sample terrain surface height at every load-bearing site (groves, pad
  approach, spawn core, perches, thermal y=0 ring) within a stated band of the old datum —
  spawn Y / `deliverPadY=250` / fire annulus / anti-cheat / crash numbers are all tuned to it.
  ② **Water P3 gate:** `BirdCollision.luau:41` sets `IgnoreWater=true` — terrain water is
  INVISIBLE to the swept sphere; a bird would dive through and the −40 failsafe would KILL it.
  Every water body gets a solid floor far above −40 (+margin). Gate: no reachable terrain
  column has a surface-to-solid gap crossing the failsafe.
  ③ **Canopy contract:** the procedural groves are KEPT, re-seated on the terrain at datum —
  `Canopy` parts / `CanopyCount` / B4.2 scoring untouched until M4 meshes. Gate: CanopyCount
  equal before/after + the B4.2 inversion test re-runs on the new geometry.
  ④ **Style-economy drift:** before/after headless proximity sample over the fixed reference
  path within an accepted band (`styleProxDist=40` was tuned flat).
  Plus: the pairwise-coplanarity gate (V0's test idea) over whatever PARTS remain (pads,
  perches, discs) — Terrain itself cannot z-fight. Measured for the record: terrain fill
  wall-clock; client join/replication delta with `StreamingEnabled=false`; memory.
  `[model: opus | gate: tests (datum + water-P3 + canopy + drift + Part-coplanarity + contract)]`
- **M2 — THE EYES (screenshot harness).** `tools/Capture-World.ps1`: build place → launch
  Studio via run-in-roblox → script builds the world via WorldGen in EDIT mode, steps
  `workspace.CurrentCamera` through 8 standard vantage points (spawn, 600-stud overview,
  grove interior, waterfall approach, dive line, fire line, delivery run, horizon) →
  PowerShell `CopyFromScreen` captures each → `captures/S<n>/`. **Spec hardenings (S47
  red-team):** ① camera↔capture sync via the SENTINEL-FILE handshake Smoke-Boot already
  proved (`tools/Smoke-Boot.ps1` pattern) — never a blind cross-process timer; run-in-roblox
  closes Studio when its script ends, so the script waits on the capture ack. ② preflight
  for DPI scaling / foreground window / occluding dialogs. ③ vantage COORDINATES are
  committed config — changing them is its own reviewable diff, so no session can frame
  flattering shots. ④ honesty note carried to every audit + Gate V-LOOK: stills are
  EDITOR-quality renders; Chad's Auto-graphics Play may draw less (the reopened render
  question) — the boot probe at Gate V is the authority on that. ⑤ **named fallback if
  capture defeats N attempts: Chad records ONE flythrough, ever** (the consult's Q5 option)
  — the strategy does not silently depend on an unproven tool. Point it at the NEW world
  (`worldV2` on); ONE sheet with the flag off is the legacy "before" record. Note: WorldGen
  being a pure module (M1) is what makes edit-mode building possible — M1 must land first.
  `[model: opus | gate: harness produces a sheet Fable can audit]`
- **M3 — LOOK-DEV ITERATE → GATE V-LOOK.** Fable image-audits the M1 world against
  `VISUAL-QUALITY-BAR.md` §2, iterating terrain/lighting CONFIG in batches (art passes batch;
  ≤3 audit rounds per the SKILL, then surface) to a Fable PASS. A/B contact sheets vs the
  legacy sheet. One capture at LOW quality level (the reopened render question — the boot
  probe at Gate V stays the authority). Then **Gate V-LOOK: Chad ratifies the look from
  screenshots, in chat, no Studio** — and the **mesh-source decision (old D1) is put to him
  THERE, batched, with a recommendation** (default: he drops a Synty-style pack into
  `assets/`; alternative: he approves specific creator-store IDs — publisher/license verified
  per bar §1.5 before any `.rbxm` is committed; the S43 asset-ID tombstone applies).
  `[model: fable audits | gate: image gate → Chad ratification in chat]`
- **M4 — MESH PROPS (the asset pass).** Blocked-on: the Gate V-LOOK asset decision. Mesh
  trees/rocks/set pieces + the waterfall rebuilt to its DoD (motion + spray + mist + sound)
  per the ratified look; ingestion path per bar §1.5 (committed `.rbxm` →
  `ReplicatedStorage.Assets`); triangle counts vs the §3 asset budget, enforced by headless
  count gates; ghost trees stay ghosts (Chad's `treeCollision` decision LOCKED). **Canopy
  contract re-gate:** mesh trees keep the `Canopy` name/tag contract with a mesh-aware radius
  path — `CanopyCount > 0`, equals the client-index count, B4.2 inversion test re-runs.
  Screenshot audit per region. `[model: opus | gate: tests + image audit]`
- **M5 — SET-PIECE & FX POLISH.** Fire look restyled on the LOCKED §3.3 budgets; beacons/gem/
  wayfinder harmonized with the palette WITHOUT regressing kid-legibility contrast; sky
  finalized. `[model: opus | gate: image audit]`
- **M6 — AUDIO LAST-MILE (the ban on empty tables), split by risk (S47 red-team):**
  **M6a** `[model: sonnet | gate: smoke]` — fill `Fire.roarAssetIds`, `Rescue.squeakAssetIds`
  from the verified free/licensed candidates in bar §1.5 (config-only; the plumbing is built
  and inert-until-ID); smoke-verified loadable. **M6b** `[model: opus | gate: tests+smoke]` —
  the music bed, ONLY if it touches `BirdController`'s audio band (register headroom 20/floor
  8, the ping-law source gate, the emitter-inventory SOP all apply — exactly what Sonnet must
  never touch). Audio saga stays CLOSED — new content, no reopened design. Chad auditions at
  Gate V, swaps = one config number.
- **M7 — CRITTER/EAGLE READ PASS (post-Gate-V, optional).** Palette/silhouette polish of the
  procedural rigs per the `EvC2026_Art` sheets; mesh Tier-3 stays deferred per
  `bird-art-pipeline-decision` (at altitude the world is ~95% of pixels).
  `[model: opus | gate: image audit]`
- **GATE V — the ONE flight.** Look in motion · boot-to-drawn vs the <5s budget (probe on) ·
  the surviving S45/S46 backlog items · audio audition. Checklist ≤ 12 items, prepared by
  Fable — the full backlog + look + boot + audio breaches the cap, which forces the ★CHAD-Q
  below to be answered first.
- **★ CHAD-Q — ANSWERED (b), Chad 2026-07-22 at strategy ratification:** items 2 (coreDetail
  altitude patches), 6 (B4.2 grove skim-vs-plow) and 7 (cylinder shapes) are **written off as
  individually unjudgeable — superseded by the world rebuild (V4 at ratification; now M1/M4).** Their MECHANICS survive (the
  altitude cue via terrain relief/detail, canopy-style pay via invariant ③, the pad/mesa
  shapes via the new set pieces) and are judged as part of the NEW world at Gate V — just not
  as attributable verdicts on the S45/S46 diffs. **Gate V folds in items 1 (wayfinder-empty),
  3 (carry reset on R), 4 (sky gem occlusion) + audio audition only.** No pre-V4 flight.

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
- **C2.5 — VALLEY CRITTER CASTS (Chad S42: "frogs or snakes other n types of animals").** Each
  valley = its own animal identity: valley 1 squirrels · valley 2 "Frostfall" candidates =
  frogs (big showy leap arcs — the mechanic's hero animal) / snow hares · later valleys =
  snakes (dangle-from-the-talon carry read), turtles (slow leap = easier kid-floor catch),
  possums/raccoons (already in the bible as rescuers). Per-animal = `BirdBuilder.Build<X>` +
  poses + leap-arc/SFX flavor on the SAME `RescueRules` catch loop — zero new mechanics, and
  every new model class ships its `models.spec` geometry test (A-RULE). Rarity tiers + The Den
  give each cast collection value. `[model: fable designs the cast per valley, opus implements | gate: batched Play]`
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

## 8. Execution model v2 (S47 — Fable supervises, Opus/Sonnet build, Chad decides)

- **The harness is `/master-loop`, and the default DRIVER is an Opus session.** Chad launches
  grind sessions with the main model set to **Opus** (`/model`); Fable is reached as a
  subagent (`model: fable`) ONLY at its brackets. Fable-driven sessions (like S47) are for
  strategy, phase gates, and plan surgery — short and rare.
- **Role routing (the token contract):**
  - **Fable (supervisor):** plan/strategy edits · design specs for `[model: fable designs]`
    packets · **screenshot contact-sheet audits** (the image gate — a genuinely Fable-value
    task) · red-team adjudication when findings conflict · gate-checklist preparation. Fable
    NEVER implements unless a subagent has failed twice (log the token cost).
  - **Opus (builder):** all implementation packets, diagnosis work, red-team execution.
  - **Sonnet (mechanic):** packets tagged `[model: sonnet]` — output fully determined by a
    written spec: ledger/HANDOFF sync, test scaffolds from a given spec, bootstrap scripts,
    config plumbing, asset-ID wiring. Never design, never kernel-adjacent, never balance.
  - Never silently upgrade a tag. Downgrading (opus→sonnet) needs the packet to be genuinely
    mechanical — when in doubt, Opus.
- **Token guardrails:** orientation reads = the plan's active-phase section + the HANDOFF cold
  start box ONLY (not whole files); code lookup via Explore subagents; implementation always
  in subagents; Fable audits from contact sheets (≤10 images), not from code dumps.
- **Chad-flight economics (the scarcest resource):** Chad flies ONLY at phase gates; every
  gate is preceded by a PASSING Fable image audit; checklists ≤ 12 items. **A packet whose
  only gate would be "Chad looks at it" is illegal outside a gate** — it carries a machine or
  image gate, or it waits. Decisions (not flights) may be brought to Chad anytime, but
  batched, with a recommendation, never as homework (no more empty-asset-ID handoffs).
- **The honesty rule (S46, standing):** every report states which halves were verified —
  LOGIC (tests) / APPEARANCE (images) / FEEL (flight). "Green" alone is banned; 205 passing
  tests shipped a flashing meadow.
- **Chad's gates:** Gate V-LOOK (screenshots, in chat) → Gate V (one flight; includes the
  S45/S46 7-item backlog + audio audition) → then the B-remainder/Phase-C gates as before
  (Gate C precondition: B7 resolved). Everything else machine- or image-gated.
- **Failure policy:** unchanged — fix trivially or revert, never leave the tree red, one
  cohesive checkpoint per packet, ledger every iteration (`.loop/rescue-phase0/state.md`).
