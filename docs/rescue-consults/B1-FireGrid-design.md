# B1 — FireGrid.luau design spec (Fable, Phase-B "before" bracket)

> Implementation spec for MASTER-PLAN packet B1: the PURE fire-cell-grid module, tuned by headless
> simulation to the §3.3 bands BEFORE it renders (B2 is the visual layer). Built by Opus from this.
> The fire is the clock made visible — it only advances cell states + flags cut-off groves; NO damage
> path exists (P3 non-lethal; squirrels leave by talon or the already-shipped Ranger Balloon triage).

## 0. Load-bearing derivation fix (pinned)
Spread must be ACTIVE from SMOLDER through BURNING (a smoldering cell throws embers). If only BURNING
cells spread, front ≈ 1.9 studs/s (3× too slow) AND the front percolation-stalls. Active window
35-45s ≈ 70-90 ticks → per-downwind-neighbor ignition ≈ 97%, period ≈ E[delay] = 11.1s →
front ≈ 60/11.1 ≈ 5.4 studs/s ✓. SMOLDER→BURNING is severity/visual only; EMBER is inert. The SIM
asserts MEASURED front speed, so a wrong spread gate turns test #3 red — enforced, not trusted.

## 1. Module shape — src/shared/FireGrid.luau (PURE, --!nonstrict)
Plain serializable state table (no metatable methods — trivially loadable in lune, hashable for the
determinism test). Embeds its OWN Park-Miller LCG (`s=s*48271 % 2147483647`, same as
rescuerules.spec:28-29) — NO Roblox.Random, so lune and Studio produce bit-identical sequences.
States: GREEN=0 SMOLDER=1 BURNING=2 EMBER=3.
- `FireGrid.new(cfg, seed, wind, groves, deliverPos) -> grid`
- `igniteAt(grid,x,z)`, `seedUpwind(grid,count)` (seeds on the UPWIND rim so the burn sweeps across)
- `step(grid, dt) -> ticksRun` (accumulates dt, runs whole 1/tickHz ticks; server calls from its 0.25s loop)
- `stateAt(grid,x,z)`, `cutOffGroves(grid) -> {bool}` (monotone), `stats(grid)`, `burningCells(grid,maxN)` (B2 seam)
- Grid: cellSize 60, half 1620 → N=54, flat 1-based arrays. Burnable mask = annulus 300≤r≤1400 MINUS
  padClearRadius 400 around deliverPos (the pad at ~(1150,0) is sacred). Expected burnable ~1490 (band 1300-2000).
- Cut-off = multi-source BFS from non-burnable rim through GREEN cells only (SMOLDER/BURNING/EMBER block);
  a grove with no flood-reached cell is cut off. O(2916) every cutoffCheckEvery=4 ticks, cached. Monotone
  (EMBER blocks too → a cut-off ring never embarrassingly cancels).
- Determinism: all draws from the embedded LCG in fixed order (active array asc, then N/E/S/W). N4 neighborhood.

## 2. GameConfig.Fire block (the §3.3 math as config; insert after Missions)
cellSize 60 · gridHalf 1620 · tickHz 2 · annulusInner 300 · annulusOuter 1400 · padClearRadius 400 ·
smolderMin 15 · smolderMax 25 · burnTime 20 · spreadP 0.045 (THE front-speed dial: E[delay]=1/(2·0.045)=11.1s
→ ~5.4 studs/s) · crossFrac 0.333 · igniteAt 10 · seedCount 2 · cutoffCheckEvery 4 · maxVisualBurning 30.
Wind weighting for source→neighbor dir d, wind w, a=d·w: a≥0 → p=spreadP·(crossFrac+(1−crossFrac)·a);
a<0 → p=spreadP·crossFrac·(1+a). Hits p(1)=0.045, p(0)=0.015, p(−1)=0. N4 only (N8 doubles p, breaks derivation).

## 3. SIM — tests/firegrid.spec.luau (register FireGrid in _loader.luau:35-40 MODULES)
100 seeded (wind, ignition) rounds through a harness world (4 groves r130 gap520, 12 squirrels), driven
t=0→roundSeconds in 0.5s steps, seedUpwind at igniteAt. Named assertions (bands ARE the spec):
1 burnable mask 1300-2000 + pad never burnable · 2 determinism (same seed→same 240-tick hash; seed+1 differs) ·
3 front speed per-round 4-7, mean 4.8-6.2 · 4 reach ≥450 by t=100 in ≥90/100 (no-stakes floor) ·
5 upwind stays green (no ignited cell >120 studs upwind, all rounds) · 6 grove threat mean [0.35,0.50], per-round
[0.15,0.70] · 7 cut-off mean [2,5], ≥85/100 in [2,5], NO round >7 (triage-not-theft) · 8 hopelessness guard
(≥1 grove not cut off until final 20s, every round) · 9 pad sacred (no ignition within padClearRadius) ·
10 monotone states + cut-off never un-cuts · 11 perf proxy (activeCount ≤600, attempts ≤2400/tick) ·
12 burningCells ≤30, all BURNING, newest-first · 13 inert pin (waterfall_meadow.hazard.kind=="triage").
Tuning dials if bands miss: spreadP (front/reach), seedCount/spacing (threat/cut-off), crossFrac (envelopment).

## 4. Mission hook — hazard.kind="fire", inert-by-default
The shipped triage branch self-gates on `(hz.kind or "triage")=="triage"` (RescueServer:1037) → a fire
mission silences the fake triageAt balloon-lift with ZERO edits there. New `ember_valley` mission (activeMission
STAYS "waterfall_meadow" → byte-identical shipped round; flip one string at Gate B). Server: per-ROUND
`FireGrid.new` after startRound (unlike the fox's once-at-boot — EMBER/wind reset each round); `FireGrid.step`
in the 0.25s loop; a newly cut-off grove starts a cutoffGraceS countdown (B2 ring) then lifts its squirrels via
the EXISTING expireSquirrel Ranger Balloon (RescueServer:390, non-lethal, verbatim). Thread groveIndex onto perch
records (buildWorld :264-275) for squirrel→grove lookup. Fire wind is FICTIONAL — never touches FlightPhysics
SetWind/WIND_BASE; kernel + camera untouched. B2 seam = burningCells()/stateAt(); NO Instances in B1.

## 5. Commit split + top risk
Commit 1: FireGrid.luau + GameConfig.Fire + loader row + firegrid.spec (inert, game byte-identical).
Commit 2: ember_valley mission + RescueServer fire branch + perch groveIndex (activeMission unchanged; #13 pins it).
TOP RISK: SIM green but felt pressure wrong (wallpaper fire vs doom fire). Guard = two-sided bands (tests 4,6-mean
= must reach/threaten; tests 5,7-rail,8,9 = never hopeless/never theft/pad sacred). Gate-B feel verdicts become
GameConfig.Fire nudges that re-run the SAME SIM with bands moved in the same commit — feel and machine never diverge.

## 6. Pillar check
The fire = the clock made visible (P2 pressure, zero kernel touch): no damage path in the module, loss is
points-opportunity not a life (P3), the hopelessness rails guarantee there's always a grove to save — scary, not unfair.
