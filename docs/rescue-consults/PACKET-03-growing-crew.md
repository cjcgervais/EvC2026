# Fable Consult — PACKET-03: THE GROWING CREW (shaping Chad's S34 vision)

> Fable 5 design consult, S34 (2026-07-14). Decodes Chad's stream-of-consciousness vision (see
> `VISION-S34-chad.md`) into a sequenced, buildable design, grounded against the live code. Companion to
> Packets 01/02 and the S33 built state (groves, living riders, fit-once arc, BLAZING, stamps, FTUE
> soft-fail, wayfinding — playtested "its good!"). Consult agent `a5581c2a41f64d84c`.

## 1) SYNTHESIS — the pillars, and the one heart
**Emotional core: THE ONES YOU SAVED HELP YOU SAVE MORE.** The eagle starts alone; by rescue 10 it's a
flying rescue *team* — a pile of brave, grown, coordinated squirrels catching their own friends out of the
air. Kindness compounds, visibly, on your back. That's the screenshot, the story, and (via the multiplier)
literally the math.

Pillars (extend the bible's P1–P4):
- **P5 COURAGE IS VISIBLE** — rescued squirrels GROW (size = confidence); growth is why newbs dare to leap. Presentation/narrative, never a stat that gates the kid floor.
- **P6 THE CREW CATCHES TOO** — with a crew, riders lean out and collectively catch incoming leapers; the back becomes a second catch surface. The slow-mo TALON catch stays the sacred, superior ritual (P1 untouched); crew catches are the CHAIN layered around it.
- **P7 THE SCORE IS A MULTIPLICATION SENTENCE** — every tally the child sees is a real `a × b = c`. Banking decisions ARE math decisions. Stealth education.
- **P8 THE ENVIRONMENT IS THE MISSION** — one sacred loop (scan→dive→catch→deliver); the WORLD varies it (fox, fire+cannon, flood). Missions change how you FLY, never how you CATCH.
- **P9 DRAMA COUNTS TO TEN** — music/stakes/spectacle escalate on a visible 0→10 counter; 10/10 in good time is the finale.
- **P10 COMPANIONS ARE EARNED WITNESSES** — helper birds join because they SAW you do something great (Perfect Tens); story-glue for the idle squad/formation tech.

## 2) THE COORDINATED CATCH — "CREW CATCH" (designed against the built systems)
**Rule (5-yo-legible):** the FIRST catch of a chain is the sacred talon ritual, exactly as built. While a
catch/climb beat is busy — or within a ~2.5s chain window after one — a new trigger fires a **CREW CATCH**:
the newb leaps for the BACK, the 2-3 riders nearest the incoming side lean out arms-wide (a firefighter's
net), the leaper lands in their arms → quick POMF + gold poof + **"CREW CATCH!"** stamp → settles straight
into its seat (no climb; the crew pulled it aboard).

Code-grounded (verified by the consult):
- The ONLY blocker to overlapping catches is one client line: `canCatch = haveRoom and not catch` in
  `scanSquirrels` (~1649). **The server already accepts overlapping catches** (`CatchSquirrel.OnServerEvent`
  gates only on capacity + a distance sanity check) → CREW CATCH v1 needs ZERO server work.
- The leap machinery is target-agnostic: `triggerCatch`'s fit-once intercept just aims at `talonPos() +
  vel·airtime`; a crew catch is the same solve aimed at `seatCFrame(nextSeat)`'s predicted position.
- Riders are already individuated (`riders[i]` w/ phase/look/settle, posed in `updateRiders`) → the "reach"
  is one new `PoseSquirrel` pose applied to the 2-3 nearest riders during the beat + a "cheer" pose on contact.
- **Grammar protection:** crew catches use the LIGHT grammar — NO slow-mo/desat/camera envelope; POMF + poof
  + stamp only. The 0.25× ritual stays reserved for the talon beat (never wears out; the two never fight for
  the presentation channel; sidesteps re-entrant `catchEnv()`/`rescueCam.env` entirely).

**Rider GROWTH (the courage arc):** each rider grows a step every crew catch after it boarded
(`Model:ScaleTo`, ~3 stages 1.0→~1.25 — cap 1.25 or the seat grid overlaps; widen seat factors +10% if
Chad wants chunkier) + a chest-puff pose + "+COURAGE" micro-stamp. Stage-3 veterans lean furthest in a crew
catch — "the big ones catch the little ones" told by animation alone.

**Kid floor / skill ceiling (same mechanic):** Floor — crew catch is automatic/guaranteed; a wobbly grove
pass now yields 2 catches where the busy-catch lock silently ate the 2nd trigger today (a real built
robbery, converted into the headline feature). Ceiling — one committed line through a grove clipping 2-3
trigger spheres → talon ritual + crew chain → **DOUBLE!/TRIPLE!** + style-meter continuity (the S33 groves
exist exactly to make this line flyable). Chain count feeds the math layer.

## 3) THE MATH MECHANIC — "Perfect Ten" (headline feature, 3 nested layers)
- **Layer 1 (5-7) SKIP-COUNTING:** on deliver, riders hop off one-per-beat (0.35s), each ringing a rising
  note + ticking a big-digit total 10…20…30… — the child skip-counts by tens unprompted. (Display currency
  = **acorns = points/10** so every number is small/round; server `basePoints=100` stays, HUD divides.)
- **Layer 2 (7-12) THE MULTIPLICATION SENTENCE:** replace flat `deliverBonus = n×25` with **n × n acorns**,
  shown as a self-assembling card: *"7 squirrels × 7 = **49!**"* with squirrel icons forming a 7×7 area
  array. **n² is the genius knob:** two trips of 5 = 50 vs one brave trip of 10 = 100 → the push-your-luck
  "one more before the waterfall?" decision becomes a computable math lesson (multiplication beats addition).
  10×10=100 = the hundred chart; `carryCapacity=10` was already built for this. n² only ever ADDS (min 1).
- **Layer 3 (10-20) THE TIME FACTOR** (Chad's "10/10 in good time"): HUD goal **"PERFECT TEN"** (10 rescues,
  par clock). 10/10 with time to spare → a final **TIME FACTOR** multiplier on the round total, staged as one
  last multiplication: *"Round 380 × TIME FACTOR ×2 = **760!**"* Tiers ×2/×3/rare ×4 (small whole numbers so
  the kid verifies in-head — that verification IS the teaching). Older players optimize the full stack:
  style × rarity × batch² × time-factor — genuine multiplication strategy.
- **Lives in:** `RescueServer` scoring (n², perfect-ten tracker, time-factor tiers — server-authoritative
  ~30 lines) + `GameUI` (hop-off sequencer, sentence card, tally). No flight code. Autonomously buildable;
  Chad validates READABILITY, not feel.

## 4) ENVIRONMENT-VARIED MISSIONS — the framework
SHARED = catch grammar, riders/crew, style, scoring/math, round loop, updraft, valley shell. PER-MISSION =
one hazard driver + deliver geometry + critter-placement rule + ≤1 special verb. A mission = a data table
`GameConfig.Missions[name]` consumed by `RescueServer` (world-gen already isolated in `buildWorld`/
`buildWaterfall`; hazard behavior in the triage branch — the seams exist).

| Mission | Hazard | How FLYING changes | Special verb | Cost |
|---|---|---|---|---|
| Waterfall Meadow (BUILT) | triage timer | free routing | — | 0 |
| **FOX ON THE HILL** ← build 2nd | ONE ground-locked patrol boid (reuses Boids + AI-update, Y-locked) | priority routing: fox approach flares a grove orange + squirrels frantic → fly THERE first; fox arrival = squirrels spook up-tree & relocate (never harmed; costs time not lives) | none | tiny |
| FIRE + WATER CANNON | fire-cell grid (bible Phase-1) | fetch-and-strike lap: grab cannon at rim pool (rides talons, same `TALON_LOCAL` attach) → dive-bomb burning grove → ONE douse | the douse dive (aim-the-dive on the locked kernel) | med-large |
| RISING RIVER (invented) | flood plane rises on schedule | altitude-ordered rescue (lowest rock first) + water-skim style | none | small-med |
| NIGHT LANTERNS (later) | darkness | scan/memory flying by beacon-light; owl tie-in | none | small |

**Cheapest first beyond the waterfall = THE FOX** (reuses Boids + poses + beacon states, adds a nameable
character, changes routing not catching, seeds the mission-table plumbing; fox never wins on screen — P3).

## 5) HELPER BIRDS / STORY / UNLOCKS
Substrate verified idle-but-intact: `Squad.formations` tight/loose (F), Boids→FlightPhysics AI path,
possession-swap (`aiCrowOpponents=false` only stops crow SPAWNING). Helper birds = formation companions on
the same class-agnostic Profile kernel, staged weakest-first so the eagle's catch stays supreme: **JAY the
SPOTTER** (pings hidden squirrels, zero catch), **HERON the FERRY** (auto-collects treetop-only squirrels,
light grammar, small value), later **OWL** (night). F toggles tight/loose as shipped; possession stays
unexposed. **Unlock = witnessed heroism (Perfect Tens), not currency** — welds the math chase to the
companion chase. Story = **THE RANGER'S NOTEBOOK** (a crayon page per mission, 3 star-stamps: rescues/
style/Perfect-Ten; ~1 UI screen; the "it has a story" parent hook). Chapter order = the mission table.

## 6) DRAMA + MUSIC — escalation grammar
One number drives all drama: `deliveredThisRound + carry` (progress to Perfect Ten). Music = layered stems,
volume-crossfaded (plain `Sound`, no new tech): base wind → +pizzicato@1st catch → +rhythm@4 → +brass@7 →
@8-9 strip to drums+heartbeat (the S33 last-20s drum, now tied to PROGRESS) → 10th catch = the round's
deepest talon ritual (max `big`) → orchestra hit + fireworks on the tally multiplication. **The crew is the
choir:** rider chatter/pose energy scales with crew size (hooks into `updateRiders`). Stamps stay sequenced
(S33 #6). Gray-box now with pitched placeholders; real stems are an asset pass.

## 7) SEQUENCED ROADMAP (build-cost ↓, reuse ↑, fun/effort ↑)
| # | Slice | Cost | Reuse | Validates |
|---|---|---|---|---|
| **1** | **CREW CATCH v1** (+ rider growth + DOUBLE!) | S | ★★★★★ | **Chad's Play — FUN gate** |
| 2 | MATH DELIVERY (hop-off skip-count → n² sentence → Perfect-Ten time factor) | S-M | ★★★★ | autonomous; Chad checks readability |
| 3 | Music escalation layers (count-to-ten stems, crew choir) | S | ★★★★ | autonomous; Chad checks the swell |
| 4 | Mission framework + THE FOX | M | ★★★★ | Chad's Play — routing-pressure fun |
| 5 | Helper bird #1 (Jay) + Ranger's Notebook v1 | M | ★★★★ | autonomous build + feel-check |
| 6 | Fire grid + water cannon | L | ★★★ | Chad's Play — the douse dive |
| 7 | Rising River / Night (data-table missions on #4's plumbing) | S each | ★★★★★ | autonomous |

### THE ONE NEXT BUILDABLE SLICE: **CREW CATCH v1**
Smallest increment, most magic: it fixes a real built defect (the single-slot `not catch` lock silently
robbing chain triggers), it IS the emotional core made playable, and it reuses ~everything (trigger scan,
fit-once arc retargeted to a seat, rider array + poses, stamp sequencer, S33 groves).
- **Kid floor:** automatic/guaranteed; a wobbly grove pass yields 2 catches, not 1 + a silent nothing.
- **Skill ceiling:** one committed grove line = talon ritual + crew chain = DOUBLE!/TRIPLE! + style continuity.
- **Code:** `BirdController` rescue (parallel `crewCatches` list, relaxed predicate, light grammar),
  `BirdBuilder.PoseSquirrel` (+reach/cheer), `GameConfig.Rescue` (+~6 keys), `GameUI` stamps. Server optional
  (1 rate clamp). Locked kernel/camera/aim UNTOUCHED (crew catch has no slow-mo/camera envelope by design).
- **Play-gate Q:** *"Did a double-catch through a grove make you laugh — and did you go looking for a triple?"*
- **Guardrails:** talon ritual exclusive to chain-openers (staleness protection); cap growth 1.25 until the
  seat grid is re-fit; crew catches never fire the slow-mo channel.

*Heart of the packet: the little one leaps — and it's not the eagle that catches her. It's everyone the
eagle already saved, arms out, together.*

## Two code findings worth surfacing regardless of direction
1. The client `not catch` lock in `scanSquirrels` (~1649) discards legitimate triggers during the ~1.7s
   catch+climb beat — a hidden robbery in grove chains EVEN TODAY. CREW CATCH v1 converts it into the feature.
2. The server `CatchSquirrel` handler already supports overlapping catches → CREW CATCH v1 needs no server work.
