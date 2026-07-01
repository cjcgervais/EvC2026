# RESEARCH — Real corvid mobbing → AI crow behavior (2026-07-01)

**Purpose.** Ground the 1-eagle-vs-4-crow AI in real corvid mobbing ethology instead of eyeballed
boids weights. Deep-research pass (fan-out search → fetch 23 sources → 3-vote adversarial verify).
The workflow's final *synthesis* step was cut off by a session token limit, so this doc preserves the
**18 verified claims + 7 refuted** verbatim and adds the synthesis + parameter plan by hand.

Run stats: 6 angles · 23 sources · 103 extracted claims · 25 adversarially verified · **18 confirmed,
7 killed**. Source list at bottom.

> ⚠️ **A refuted claim ≠ the opposite is true.** The 7 "killed" claims either failed 2/3 skeptic
> votes or 3 verifiers abstained (several abstains were the token-limit cutoff, not real doubt).
> Treat killed claims as *unverified*, not disproven. The flight-biomechanics quantitative angle in
> particular never reached confirmed claims before the cutoff — we have STRONG behavior data, WEAK
> hard flight numbers. A follow-up research pass on wing-loading / speed numbers is worth doing.

---

## THE ONE REFRAME THAT CHANGES THE DESIGN

**Mobbing is NOT flocking. Real corvids SWITCH steering modes when they mob.**

- In transit flocks they use **topological** interactions (coordinate with a fixed *number* of
  neighbors) → maximizes group cohesion.
- When **mobbing** they switch to **metric** interactions (coordinate with whoever is within a fixed
  *physical distance*, ~5 m ≈ 14 body-lengths) → lets each bird "behave more independently, allowing
  them to focus more attention on the predator." (Nature 2019; PMC6858344, both 3-0 verified.)

**Implication for our code:** during a mob, **cohesion should DROP, not rise**, and each crow should
act as a semi-independent attacker orbiting/harassing the eagle — NOT a tight formation charging in a
single vector. My earlier instinct (crank `goalWeight` so they all seek the eagle harder) is exactly
backwards: it makes 4 birds fly the *same* line into a point → the pile-up + terrain overshoot Chad
saw ("made 3 crash"). The fix is **orbit + staggered dive-bomb passes + high separation**, not a
bigger goal scalar.

---

## VERIFIED FINDINGS (confirmed, with vote + source)

### Mobbing tactics (Q1)
- **Group dive-bombing harassment, not sustained contact.** "A group of crows will come along and
  harass it—dive-bombing and screeching—until it's forced to fly away." (popsci, 3-0)
- **Circle + dive-bomb + noise.** Mobbing behavior = "flying about the intruder, dive bombing, loud
  squawking..." (Wikipedia, 3-0). "fly up to meet it, dive-bombing the predator and giving it a
  noisy escort out of town." (Audubon, 2-0)
- **They DO make contact, but to drive off, not kill.** "repeated, high-speed dive-bombing runs ...
  physical contact by pecking or pulling feathers" (biologyinsights, 2-1). But: "it's more aimed at
  driving away a predator than causing it injury." (AllAboutBirds, 3-0). → **harass-then-peel-off**,
  never suicidal sustained grappling.

### Spacing & coordination (Q2)
- **Metric interaction range ≈ 5 m (~14 body sizes)** in mobbing jackdaw flocks — a fixed physical
  radius, not nearest-N. (Nature 2019, 3-0; PMC6858344, 3-0)
- **Metric mode → independent attackers focused on the predator** (vs topological cohesion in
  transit). (PMC6858344, 3-0) → each crow orbits/attacks somewhat on its own around the target.

### Flight asymmetry (Q3) — ⚠️ WEAK / PARTLY REFUTED
- **"Crows out-maneuver eagles (superior turn radius/accel)" was REFUTED 0-3.** The secondary source
  asserting the crow's agility neutralizes the raptor was NOT verifiable. Do **not** treat "crows are
  simply more maneuverable" as established fact. (Our *design* can still make the crow the angles
  fighter — that's a game-balance choice — but the biology claim didn't survive.)
- No hard cruise/max-speed/wing-loading numbers reached the confirmed set before the token cutoff.
  Wing-morphology primary sources were fetched (ResearchGate wing-morphology; Wilson J. Ornithology
  wing-loading) but their claims weren't verified in time. **→ open follow-up research item.**

### Psychology — boldness (Q4)  ← the antidote to "scared" crows
- **Higher perceived risk → MORE aggressive mobbing, not fleeing.** Birds "approached a stuffed
  predator significantly more closely, and mobbed it at a higher intensity" where risk was
  experimentally increased. (PMC2918767, 3-0)
- **In 97% of crow-raven interactions, crows were the aggressors.** (NatGeo, 3-0) Crows initiate and
  press; they do not flee a larger bird.
- **Per-individual risk drops sharply as mob size grows** ("decreases exponentially"), so swarming is
  the rational choice. (PMC6832194, 3-0)
- **Cooperation amplifies effect + lowers individual risk**, making group mobbing profitable even
  when dangerous. (PMC2918767, 3-0)
- **Intensity is calibrated to threat:** larger assemblages vs a high-risk predator; more *intense*
  individual risk-taking vs a low-risk one. (Behavioral Ecology 2017, 3-0) → mob size/commitment can
  scale with the eagle's apparent threat.

### Boids implementation (Q5)
- Boids = separation + cohesion + alignment, each with weight/distance/angle; **weighted linear sum
  is sufficient** in practice — no complex arbitration needed. (red3d/Reynolds GDC99, 3-0 ×3)
- **Separation = summed repulsive force from near neighbors** — this is the exact mechanism that
  fixes "crash into each other." (red3d, 3-0)

---

## REFUTED / UNVERIFIED (do not rely on)
- ✗ "Crows mob in tight groups of 2–5" (0-3) — group size not pinned; don't hard-code 2–5.
- ✗ "Crows out-maneuver eagles / superior turn radius" (0-3) — see Q3 caveat above.
- ✗ "Mobber agility neutralizes the raptor's advantage" (0-3).
- ⚠️ 4 more ("strength in numbers driver", weighted-sum detail, "dive-bomb not grapple", "cooperative
  ≥2 birds") ended 0-0 **all-abstain — these are the token-limit casualties, not genuine doubts**;
  they're corroborated by other confirmed claims above.

---

## SYNTHESIS → PARAMETER & BEHAVIOR RECOMMENDATIONS (hand-authored)

**Model: a per-crow MOB state machine layered on the existing boids, replacing straight goal-seek.**
Each AI crow runs its own small FSM; separation + a metric neighbor radius run underneath in all
states so they never collide.

### States
1. **APPROACH** — far from eagle. Seek the *orbit shell* (eagle position offset outward to
   `orbitRadius`), not the eagle centre. Bold: no flee, ever.
2. **ORBIT / SHADOW** — within `orbitRadius`. Hold standoff distance and **circle** the eagle
   (radial-keeping + tangential term, consistent handedness per crow) at/above the eagle's altitude.
   This is "flying about the intruder," and it's what keeps them in the fight without ramming.
   Spread bearings so 4 crows surround from different angles (metric-independent, low cohesion).
3. **DIVE-BOMB (attack run)** — on a **staggered per-crow timer (take turns!)**, one crow commits a
   fast pass *from above* through the eagle, throws its strike (existing combat), then →
4. **PEEL-OFF / RECOVER** — after closest approach (hit or miss), break away, regain altitude/energy,
   return to ORBIT. This is the harass-then-peel-off that prevents suicide.

### Boids weights DURING a mob (the reframe: cohesion DOWN, separation UP)
| Term | Transit/formation | **Mob mode** | Why |
|---|---|---|---|
| **Separation** | 1.5 | **high (~2.0–2.5)** | metric ~14-body-length gap; stops crashing into each other |
| **Cohesion** | 1.0 | **LOW (~0.3–0.5)** | metric mode = independent attackers, not a tight flock |
| **Alignment** | 1.0 | **low (~0.3)** | they're converging on a target, not matching headings |
| **Goal-seek** | (was 1.0) | mediated via **orbit target**, not raw eagle pos | prevents the single-vector ram/overshoot |

### New tunables to add (`GameConfig.Squad.mob = {...}`)
- `orbitRadius` (studs) — standoff shell the crows circle at. Scale to map/speeds (start ~180–260).
- `orbitRadiusJitter` — per-crow variation so they don't share one ring.
- `neighborMetricRadius` — fixed metric separation radius (~14 body-lengths, ≈ 14×2.2 ≈ 30 studs+,
  tune up for spacing).
- `attackFromAboveBias` — prefer entering the dive-bomb from above the eagle.
- `attackPeriod` + `attackStagger` — how often a crow dive-bombs, phase-offset per crow so they take
  turns (never all-4-at-once, which is the pile-up).
- `peelOffDistance` / `recoverTime` — break-off geometry after a pass.
- `boldness` — mob-mode weight set (high separation / low cohesion / no flee). Never add a flee state.

### Incremental build order (ONE change + playtest between, per SOP)
1. **Increment 1 — "Mob, don't ram": orbit standoff + high separation + bold (no flee).** Crows hold
   station around the eagle and circle at `orbitRadius`, separation keeps them apart. **Playtest gate:**
   do they now surround & circle instead of crashing/fleeing? (No teeth yet — that's fine.)
2. **Increment 2 — staggered dive-bomb passes (take turns) from above + peel-off.** Adds the pressure/
   harassment and ties into the existing strike/collision combat. **Playtest gate:** does it feel like
   a real 1-v-4 mob — waves of passes, not a suicide charge?
3. **Increment 3 — balance:** attack cadence, orbit radius, damage/collision trades vs the eagle's
   S13 energy/dive-rest buffs. flight==balance on every number.

---

## SOURCES (23 fetched; primary = peer-reviewed / Reynolds canon)
- Nature 2019 — jackdaw metric-vs-topological mobbing: https://www.nature.com/articles/s41467-019-13281-4 (primary)
- PMC6858344 — same, open access: https://pmc.ncbi.nlm.nih.gov/articles/PMC6858344/ (primary)
- PMC2918767 — perceived risk → bolder mobbing: https://pmc.ncbi.nlm.nih.gov/articles/PMC2918767/ (primary)
- PMC6832194 — per-individual risk drops with mob size: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6832194/ (primary)
- Behavioral Ecology 2017 — intensity vs predator danger: https://academic.oup.com/beheco/article/28/6/1517/4110204 (primary)
- Reynolds GDC99 steering behaviors (boids canon): https://www.red3d.com/cwr/steer/gdc99/ (primary)
- Frontiers Ecol&Evol 2023: https://www.frontiersin.org/journals/ecology-and-evolution/articles/10.3389/fevo.2023.1198248/full (primary)
- arXiv 2409.03849 (flocking/flight): https://arxiv.org/pdf/2409.03849 (primary)
- ResearchGate — wing morphology in 3 birds of prey: https://www.researchgate.net/publication/7298614 (primary; flight numbers — FOLLOW UP)
- Wilson J. Ornithology — wing-loading & aerodynamics: https://bioone.org/journals/the-wilson-journal-of-ornithology/volume-116/issue-3/03-070/ (primary; FOLLOW UP)
- popsci, NatGeo, Wikipedia (mobbing), AllAboutBirds, Audubon, biologyinsights (secondary/behavior)
- gdx-ai, Buckland SteeringBehaviors.h, polarith orbit, slsdo, SimpleBoids (impl references)
- naturedocumentaries, naturalwonders (field-obs blogs)

*Full machine output (all claims/quotes/votes) archived in the task output; this doc is the durable record.*
