# A2 — RescueRules.luau design spec (Fable, S41 "before" bracket)

> The implementation spec for MASTER-PLAN packet A2 (the keystone extraction). Produced by the
> rescue-gameplay-architect (model: fable), verified against LIVE source. The Opus implementer builds
> from this; the "after" bracket (a Fable faithfulness audit) closes the packet. Transcribe from the
> LIVE lines cited here, NEVER from MASTER-PLAN's formula boxes (three stale numbers already found —
> triggerRadius is 42 not 28, the scoop uses total airspeed not closing, and `R_eff + speed·latency`
> is the exact formula that re-breaks bug 2c). The parity-oracle test (§6) enforces this.

Ground-truth corrections found this pass:
- LIVE `GameConfig.Rescue.triggerRadius = 42` (`GameConfig.luau:752`; `or 28` at `RescueServer:539` is a dead fallback).
- Scoop widening uses `flightEngine.speed` (total airspeed) at `BirdController:1916`, not closing speed.
- The server accept envelope is `triggerRadius·catchGateMult + speed·catchGateLatency` (`RescueServer:552`),
  a LOOSER band than the client predict radius — it must NOT be re-derived from effectiveRadius (that is bug 2c).

---

## 1. Module shape
New PURE module `src/shared/RescueRules.luau` → `ReplicatedStorage.RescueRules` (src/shared mapping already covers it;
no project.json edit). `--!nonstrict`. Purity: no Instances/services/clock/task; inputs are numbers/strings/tables/Vector3
(datatype ops only). Every fn takes `cfg = GameConfig.Rescue`; all `or`-fallback literals move INTO the module verbatim.

Public surface:
- `eligibility(args) -> Verdict` — the ONE catch-eligibility function both authorities call (mode "predict"|"accept").
- `effectiveRadius(cfg, speed, glideSpeed, catchCount?)` — client predict radius (ftue mult · scoop widening on TOTAL speed).
- `closingGate(cfg, glideSpeed, catchCount?)` — client closing-speed floor.
- `acceptEnvelope(cfg, speed)` — server LOOSE band `triggerRadius·catchGateMult + speed·catchGateLatency`. THE amendment term.
- `hasRoom(carried, inFlight, capacity)`, `phaseAccepts(phase) -> {catch,deliver}`.
- `claimActive(claims, id, now, cfg)` / `markClaim(claims, id, now)` — S35c TTL dedup (caller passes `now`).
- `comboOnCatch(cfg, now, lastCatchAt?, combo?, loadCombo?) -> (combo, loadCombo)`.
- `speedTier(cfg, closing, glideSpeed) -> "BLAZING"|"SWIFT"|""`, `catchScore(cfg, rarityMult, styleMult, speedTier)`.
- `deliverPayout(cfg, carry, loadCombo?) -> {points,n,combo}`, `perfectFactor(cfg, timeLeftAtTenth) -> 2|3|4`,
  `quantizeAcorns(cfg, score)`, `finaleApply(cfg, score, factor) -> {preFactorScore, finalScore}` (quantize FIRST).
- `seatAssign(occupied, capacity) -> seat?`, `seatRelease(occupied, seat)`, `highestOccupied(occupied)` — F3 sticky seats.
- `PHASES`, `phaseDuration(cfg, phase)`, `phaseStep(phase, timeLeft, dt, cfg) -> (phase, timeLeft, transitioned)`,
  `triageTick(bucket, dt, timeLeft, strandedCount, hazard) -> (bucket, expire)`.

Verdict = { eligible, reason ("ok"|"phase"|"gone"|"full"|"tooFar"|"tooSlow"), dist, closing, speed, radius, gate }.
Reason precedence: phase → gone → full → tooFar → (predict) tooSlow → ok. The verdict carries dist/closing/radius so the
client scan loop branches (soft-fail / full-hint / tell) read the verdict instead of recomputing.

## 2. The §3.1 amendment, honored (do not resurrect bug 2c)
`mode="predict"` (client per-frame): band = effectiveRadius + closingGate + hasRoom. TIGHT, feel-shaped.
`mode="accept"` (server at receipt): band = acceptEnvelope ONLY (no effectiveRadius term, no ftue, NO closing gate — the
live server never checks closing) + hasRoom(ps.carry,0,cap) + squirrelState=="stranded" + phaseAccepts(phase).catch.
Structural guards: acceptEnvelope never calls effectiveRadius and takes no catchCount; catchGateMult stays a named term
with the birdScale-2.3 provenance comment; the SIM superset property + the empirical 80–110 band test pin it in Tier 4.
At live values: envelope(0)=42·3.5=147 ≥ max predict radius (~79); at speed 260, 147+65=212 (covers the 80–110 legit band).

## 3. Migration map — see the two tables in the ledger / Fable transcript. Server owns authoritative carry/score/claim/
phase; client owns predictive trigger/tells/FX/seat-geometry/riders. Divergences killed: (1) the two unrelated gate
formulas, (2) capacity compared differently each side, (3) deliver phase window duplicated (buzzer-grace bug 8),
(4) the time-factor ladder duplicated at RescueServer:640-643 vs :689-694, (5) speedTier fracs.

## 4. Regression suite `tests/rescuerules.spec.luau`
Add `RescueRules` to `tests/_loader.luau` MODULES; load real GameConfig, assert against LIVE cfg values (never re-typed
literals). Cases: 2a capacity-silence (named "full"), 2b chained-catch (cap 10), 2c amendment unit (`acceptEnvelope(cfg,0)==
triggerRadius·catchGateMult` = 147, fails if re-derived) + accept at dist 80/110, 6 claim TTL edge + idempotent accept,
8 phase predicates, 9 combo ramp/reset/peak-hold, 10 deliver payout 10→4000 + superadditive + no-lie n/combo, 11 factor
boundaries + banked==finale identity, 12 quantize-before-factor, F3 sticky-seat out-of-order + no-shared-index sweep,
phase machine two full cycles + triageTick inert/fire/never-below-minStranded. SIM: §3.1 sweep (speed×latency×angle,
zero false rejects, + empirical 80–110 band) and §3.2 economy Monte-Carlo (casual ~150–350, skilled ~1200–2200, ratio<10:1,
seeded). Also fix talon.spec/models.spec eagle-build calls to `Build("Eagle", GameConfig.Profiles.Eagle)` and add a
RescueRules load-line to tests/smoke/boot.smoke.luau.

## 5. Commit split (each independently ladder-green)
1. **A2.1** — RescueRules module + rescuerules.spec + smoke load-line + talon/models spec-call fix. INERT (no game refs) →
   runtime byte-identical. Includes the PARITY ORACLE (§6).
2. **A2.2** — server consumes (gate/score/combo/payout/factor/quantize/phase/triage). Behavior-preserving; keep catchDiag.
3. **A2.3** — client consumes (scan-loop verdict rewrite + claims + speedTier + deliver predicate).
4. **A2.4** — sticky seat map (the packet's ONLY intentional behavior change: cosmetic seat stability) — separated so
   Gate A's "nothing feels different" stays clean for A2.1–A2.3.
Order: module inert first; server before client (server diag + untouched client formula cross-check the extraction live);
the one real change lands last, alone.

## 6. Top risk + guard
Risk: transcribing from the DOC not the LIVE lines, and dropping load-bearing `or`-fallbacks. Guard (all in A2.1):
(1) PARITY ORACLE — the spec restates the OLD inline formulas verbatim (copied from BirdController:1898-1916 and
RescueServer:551-552,570-588,625-643,685-697 with line cites) and asserts EXACT equality over a 1,000-point randomized
sweep. (2) Config-not-literals in every assertion. (3) The SIM superset + 80–110 band as permanent tripwires.
Secondary: phaseStep must not resample wall-clock — the live task.wait cadence + pushAll rhythm stay at the call site.
