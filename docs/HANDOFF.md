# HANDOFF — Eagles vs Crows

Read this first. It tells the next agent exactly where the project stands, the one decision that's already been made for you, and the prioritized work queue. Pair it with `CLAUDE.md` (architecture + contracts), `docs/RESEARCH.md` (why the numbers are what they are), and project memory (`MEMORY.md` index).

---

## ▶▶ S48 COLD START — MAP-FIRST (the strategy of record; this box supersedes every queue below)

**HEADING:** *build the REAL map — Terrain + lighting first (code-only, zero assets), meshes when
sourced; every packet leaves the published look visibly closer.*

**LANDFILL registry (never invest ANY effort — polish, fix, extract, harden, test):**
- The **flat-primitive gray-box map** (BuildMap plane + GroundDetail patches + primitive
  mountains/lake/sea + the S45b scatter). Rejected wholesale by Chad, S46+S48. It survives only
  as the untouched legacy path behind `Map.worldV2=false` until Gate V passes, then dies.

**How to run:** `/model` **Opus** → `"run the master loop"`. The SKILL now has a **HEADING gate**
— answer its 3 questions (heading / landfill / plumbing-ratio) in the ledger at every packet pick.
Git commits are NO LONGER ASK-gated (Chad S49) — auto-commit each verified packet.

**▶▶ S49 STATE — the REAL MAP is built AND CHAD ACCEPTED IT ("it looks really good I saw it").**
The map-first pivot landed: gray box → an accepted terrain+lighting valley in one session. APPEARANCE
now VERIFIED (Chad booted it in Studio — the integrated scene, groves/waterfall re-seat on the new
terrain). Next lever = **M4 meshes** (his asset pick). M2 auto-capture is unreliable (run-in-roblox
script-timeout on the dwell sequence — it builds+caught the extents bug but emits 0 images); use Studio
boot / a flythrough for future look-checks. Details in the S49 box below + the ledger.

**(historical) ▶▶ S49 STATE — the REAL MAP is built (terrain+lighting), UNSEEN, awaiting Chad's look.**
M1 + M1.5 replaced the gray box with a finished Terrain valley: peaked double-ring rim + west pass,
river → plunge pool → de-boxed lake, shorelines, micro-relief mounds + landmark outcrops, material-
patchwork meadow, golden-hour rig + terrain color palette; hidden −120 catch slab keeps P3 (no
void-death). M2 built the screenshot harness. All committed (`f732f8d` M1, `5edf32b` M2, + M1.5).
Tier-4 228/228. **APPEARANCE UNVERIFIED — nothing has rendered.** Chad is the TERMINAL accept/reject
gate (memory `feedback-chad-terminal-accept-reject`): he judges the finished valley whole, no iteration.
**▶ CHAD, to advance:** (1) SEE it — `powershell -NoProfile -ExecutionPolicy Bypass -File
tools\Capture-World.ps1` (PNGs → `captures\S49\`), or boot Studio (`Map.worldV2` is ON by default).
(2) ACCEPT/REJECT the terrain+lighting valley. (3) The named next unblock is **M4 meshes** (trees/
waterfall/skybox) — needs your ASSET pick (drop a Synty-style pack into `assets/`, or approve verified
creator-store IDs per bar §1.5). Open Q the capture resolves: does the EDIT-mode Studio viewport follow
the scripted camera? If shots are the editor default view → the one-flythrough fallback.

**The queue is MASTER-PLAN §5.5, re-cut S48 (map-first M-series):**
**M1 ✅ DONE S49 (commit-ready, uncommitted — ASK).** `src/shared/WorldGen.luau` built: PURE `plan`
(data) + THIN `build` applier, behind `Map.worldV2` (default ON — new valley is the map now; false =
untouched legacy path, one-word revert). Terrain valley bowl (flat Y≈0 floor to r=3400, rock rim to
1800), golden lighting rig, ValleyLake+WestSea with solid floors, and a hidden ±8000 catch slab at
Y=−120 (red-team caught a P3 void-death regression past the rim — the legacy ±8000 baseplate had
guaranteed solid-everywhere; the catch slab restores it 80 studs above the −200 failsafe). Tier-4
**221/221** · rojo PASS · luau-lsp 0 NEW. **APPEARANCE UNVERIFIED** — the Terrain has never rendered in
an engine; first look is M2. Gate-V checklist items accrued (see ledger S49 tail): M3 must restore a
spawn-core closure cue (the S45 GroundDetail scatter is NOT in worldV2 — uniform disc risks the old
featureless plane), a Studio smoke should confirm the applier builds terrain, and Gate V flies the P3
edge. →
**M2 ✅ HARNESS BUILT S49 (committed; capture pending Chad's run).** `tools/Capture-World.ps1` +
`tests/capture/world.capture.luau` build the worldV2 valley in EDIT mode and screenshot 8 fixed vantages
(stdout `M2READY` + 2.5s dwell, since run-in-roblox is one-way; TERRAIN+LIGHTING only — set-dressing is
edit-mode-dormant). Tier-4 223/223. **▶ CHAD, to advance:** run
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\Capture-World.ps1` (lands PNGs in
`captures\S49\`), OR just boot Studio to eyeball M1. **Open Q the run resolves:** does the EDIT-mode
Studio viewport follow the scripted `workspace.CurrentCamera`? If the shots are the editor default view,
the fallback is one recorded flythrough. Once a sheet exists → **M3** Fable image-iterates it. → **M3**
Fable image-iterates the look → **Gate V-LOOK** (Chad ratifies from screenshots in chat; the mesh-source
question is asked THERE with a recommendation) → **M4** mesh props (blocked on that answer) → **M5**
polish → **M6** audio → **Gate V** (the ONE flight).
Read M1's invariants in the plan before building — the water-P3 landmine (①–④) is real.

**Decisions taken by Fable at the S48 consult (`docs/CONSULT-QUALITY-BUILD-STRATEGY.md` — don't
re-litigate):** D1 = Terrain+lighting NOW, meshes later (unblocked, biggest lever; mesh sourcing
asked at Gate V-LOOK, batched, with a recommendation — never as homework). D2 = the eyes are KEPT
but sequenced BEHIND the first map packet (the S48 failure was plumbing leading the phase, not the
harness existing). D3 = V0 + V1 CANCELLED (V0 polished landfill; V1's extraction value is
inherited by writing WorldGen natively pure). D4 = whole valley bowl at once (Terrain generation
is code — a corner slice saves nothing; the staged part is meshes, which come later anyway).

**S48 halt record (history):** Chad halted mid-loop on V0 — *"why are we fixing a rejected asset?
I want a plan for a better map."* V0 was built clean, then REVERTED (record in the S48 ledger
block + git reflog). The tree's pending batch (SKILL heading gate, plan re-cut, this box,
consult doc, `assets/` audio) awaits Chad's ASK-gated commit.

*The S46 "loop paused" box and the S47 Phase-V cold-start below remain accurate as HISTORY only.*

---

## 🛑 STOP — THE LOOP IS PAUSED. READ `docs/CONSULT-VISUAL-QUALITY.md` FIRST.
**Chad halted autonomous work at the S46 close (2026-07-22) and asked for a STRATEGY CONSULT with a
Fable model before any further building.** His charge, in his words: *"Everything looks cheap and
broken… we have to start building for quality and good runtime at the same time… It feels like this
project is treated as a dead end… Every fix I try to get done takes 7 or 8 passes."*

**Do not pick up the queue below and start building.** The queue is still accurate as a work inventory,
but the *method* that produced it is what is under review. Three things a new agent must know up front:

1. **The flashing ground is OUR bug, diagnosed:** all 133 `GroundDetail` patches sit at `Y=0.6` with
   `Size.Y=4`, so every top face is coplanar at **Y=2.6** and overlapping patches z-fight
   (`GameServer.server.luau:336-343`). Fix is 3 lines or one config word — **deliberately not applied**,
   pending the consult.
2. **⚠️ "RENDERS IN SLOW" IS REOPENED — I closed it prematurely.** Chad is back on Auto graphics and
   reports it *still* takes forever. The S45c fixes were real and stay, but the cold-start box below
   still describes this as solved+confirmed; **that claim is falsified.** And beware the S44/S45 trap
   for a fourth time: *"the world arrives late"* and *"the world flickers once it is here"* are
   probably TWO defects behind one complaint. Separate them before touching anything.
3. **The whole game is untextured primitives** — zero MeshParts, textures, decals or SurfaceAppearance
   anywhere in `src/`. This is a gray-box prototype that has been treated as shippable for ~14
   sessions. **Read the consult packet for the full audit.**

---

## ▶▶ COLD START — READ THIS FIRST (work inventory; current as of S47 close, 2026-07-22)

### 🎨 S47 — THE QUALITY PIVOT (supersedes the S46 "loop paused" state)
The strategy consult happened (Fable, 2026-07-22). **The work queue is now MASTER-PLAN §5.5
PHASE V** — visual foundation: V0 z-fight kill → V1 WorldGen extraction → V2 screenshot
harness → V3 look-dev slice → **Gate V-LOOK (Chad ratifies the look FROM SCREENSHOTS)** →
V4 Terrain+mesh world conversion → V5 polish → V6 audio last-mile → **Gate V (ONE flight,
includes the 7-item backlog below + audio audition)**. `docs/VISUAL-QUALITY-BAR.md` is now a
GATE document; execution model v2 (plan §8): Opus drives, Sonnet does mechanical packets,
Fable supervises via image audits; a packet whose only gate is "Chad looks at it" is illegal
outside a phase gate. Reports state which halves were verified (LOGIC/APPEARANCE/FEEL).
The sections below remain accurate as state; their queues are superseded by Phase V.
**RATIFIED by Chad 2026-07-22 (same day), committed.** Backlog question answered **(b)**:
of the 7 unjudged items below, 2/6/7 are WRITTEN OFF as superseded by the V4 world rebuild
(their mechanics are re-judged as part of the new world); only **1, 3, 4 + audio** fold into
the Gate V flight. No pre-rebuild flight. ~~Next session: model → Opus, "run the master loop" →
V0.~~ **(SUPERSEDED S48 — V0/V1 cancelled; the queue is the M-series in the top box → M1.)**

*The session sections below are the historical log, newest first. **This box is the authoritative
current state.** The older "COLD START — Session 32" box further down is superseded; ignore its queue.*

### What the game is right now
**EAGLES TO THE RESCUE** — fly a signed-off eagle over a burning valley, dive into a slow-mo auto-catch
to scoop squirrels onto your back, carry up to 10, deliver at the waterfall. 2-minute rounds.
`Rescue.enabled=true`, `activeMission="ember_valley"`. **Combat is SHELVED** (S32) — but note it is
shelved *by player count, not by config*; see the landmine list. Chad's S42 verdict on the core loop
was **"addictive and fun… actually fun!"** — **do not re-litigate the loop.**

### 🔴 "RENDERS IN SLOW" — **REOPENED at the S46 close. The section below is NOT the final word.**
*S45c's two fixes (CastShadow, the Glass Sea) were real and stay. But Chad, back on **Auto** graphics
on 2026-07-22: it **still takes forever**, and the world **flashes** once it arrives. The "solved and
confirmed" framing this box carried for one day is **falsified**. See `docs/CONSULT-VISUAL-QUALITY.md`
§2.1 and §2.3 — the flashing is a separately-diagnosed z-fighting bug of our own making, and conflating
it with the load-time problem would repeat the exact S44/S45 error a fourth time.*
*The arc below is still the best worked example in this repo of diagnosing the wrong clock — read it
for method, not for a verdict.*

### 🔴 (historical) the probe FLEW. It is **RENDERING**, not replication or streaming.
S44 blamed the boot intermission and shipped a fix; Chad re-flew and it was **still slow**, so that
explanation is **falsified and closed** (BootDiag measured when instances EXIST, not when they are
DRAWN). The probe has now flown and the numbers settle it. **Chad's flight, 2026-07-21:**
```
[client] 0.001s  workspace.StreamingEnabled = false   |  graphics quality: ?
[client] t=01s   RescueWorld=249  Squirrels=0    Map=211  Birds=-1
[client] t=05s   RescueWorld=249  Squirrels=660  Map=211  Birds=134
[client] t=10s   RescueWorld=249  Squirrels=616  Map=211  Birds=134
[client] t=20s   RescueWorld=249  Squirrels=660  Map=211  Birds=134
```
**Read it:** `StreamingEnabled = false` ⇒ **streaming is RULED OUT.** `RescueWorld=249` on the CLIENT at
**t=1s** and flat forever after — matching the server's 249 — ⇒ **every tree is fully replicated one
second in and the counts NEVER climb.** `Map=211` = the original 78 + S45b's 133 ground patches, also
flat from t=1s. Squirrels populate at 1.324s exactly as designed. **Per the probe's own decision rule
(counts climbing = replication; counts present but invisible = rendering): the geometry is all there
and the engine is not DRAWING it.** Also ruled out earlier: ZERO external assets (nothing downloads),
and **Studio cold-cache** — Chad's back-to-back Play/Stop/Play was *"just as slow"* on the second run.

**REMAINING SUSPECT, now the only one standing: quality-scaled render distance.** Roblox's Automatic
graphics mode starts conservative and ramps, and draw distance scales with the level — parts present
but not drawn until the level climbs or you fly closer. **The probe printed `graphics quality: ?`**
because both properties were read inside ONE pcall, so a single missing property blinded the whole
read. **S45c fixes that** (per-property pcalls, and quality is now sampled at EVERY mark — a level that
CLIMBS while the counts stay FLAT is the complete diagnosis).
### ✅ CONVICTED, and Chad confirmed the cure: **QUALITY-SCALED RENDER DISTANCE**
He ran the A/B — **Graphics → Manual → max — and the problem VANISHED** ("that fixed it!"). Combined
with the counts above, the chain is closed: the parts are all present, Roblox's **Automatic** mode was
throttling how far it would draw them to protect the frame budget, and raising the level lifted the
throttle. **His slider fixes it for HIM ONLY — every player lands on Automatic**, so the shippable fix
is to stop spending the frame budget. Shipped (`Map.cheapScenery`, false = the pre-S45c look):
- **`CastShadow = false` on Map parts.** `addPart` never cleared it, so **all 78 cast shadows** —
  including a **16,000-stud baseplate** and **45 mountains up to 3,400 tall**. RescueServer's builder
  has *always* set false, so the trees cast nothing: this was an **inconsistency, not an art choice.**
- **The Sea stops being GLASS with Reflectance 0.25.** It is 6,000 × 18,000 studs — **108 million
  square studs** of transparent reflective surface across the whole western horizon, blended every
  frame it is visible (from 600 studs up, always). At 11,000 studs it reads identically as
  SmoothPlastic. *(Bloom + the lake/rivers were left alone — smaller, and more visually load-bearing.)*
**Source gates gate both** (`compile.spec`), because each fix is ONE line and nothing looks different
when it regresses. ⚠️ **The first CastShadow gate was VACUOUS and the mutation test caught it** — it
matched the word "CastShadow" in its own explanatory comment, so a mutant with the assignment deleted
passed. Gates now strip `--` lines before matching. **Lesson: a source gate must read CODE, not prose.**
**✅ CHAD CONFIRMED IT (2026-07-21): flown on the shipped fix — *"yep graphics worked."* THE RENDER
SAGA IS CLOSED.** `Rescue.bootDiag` is now **OFF** (its answer is preserved in the knob's comment):
the diagnostic did its job and noise buries the next one. Turn it back on only for a NEW startup
question — and if you do, remember it measures when things **EXIST** vs when they are **DRAWN**, which
are different clocks; conflating them cost S44 an entire session.

**The three-session arc, for the record:** S44 blamed the boot intermission (real, but not the cause) →
S45 falsified it in two words from Chad ("newest build, still slow") → S45b found a *genuine second
defect* with the same symptom (the featureless spawn core, fixed and kept) → S45c's probe flight
convicted the actual cause. **Three plausible mechanisms, two of them real bugs, only one of them THE
bug.** The thing that finally worked was measuring the right clock and asking Chad what he was *doing*.
⚠️ Note `GameServer:266`'s `pcall(Workspace.StreamingEnabled = false)` is a **silent no-op** (read-only
at runtime) — harmless now that the probe confirms the place file already has it off, but it proves
nothing and should not be cited as if it did.

### 🎯 SEVEN CHANGES ARE LIVE AND UNJUDGED — this is the FIRST thing to do next session
**Chad has not flown anything since the render fix.** Five shipped in S45 (the render saga ate that
session) and two more in S46, all built autonomously and all kill-switched. **One flight clears the
whole backlog** — it is by far the cheapest value available, and nothing below should be built on top
of unjudged work. Items 6–7 are the S46 pair; their full detail + playtest asks are in the S46 blocks
further down. ⚠️ **6 and 7 interact** — see the note under item 7.
1. **🧭 The wayfinder** (`Rescue.wayfindEmpty`) — the gold ribbon now points at the nearest squirrel when
   your talons are empty. It was gated on carrying ≥1, i.e. **dark at every moment anyone is lost.**
   *Ask: from spawn, does it tell you where to go within a frame? Does it ever strobe between groves?*
2. **🌍 Core ground detail** (`Map.coreDetail`) — the ±1200 spawn box was a **uniform plane with no
   altitude cue**, which is why he dove into the ground every start. Multi-scale patches, provably
   non-queryable (crash surface bit-identical). *Ask: can you judge your dive now?* ⚠️ Note this was a
   REAL defect but **not** the cause of "renders slow" — don't let the render fix take credit for it,
   or vice versa.
3. **🐿️ Carry reset on bird loss** (`Rescue.carryResetOnLoss`) — *Ask: carry ~5, press **R**, catch 6
   more; all six must count.*
4. **💎 The sky gem** is now LIVE too (below) — *Ask: does it ever occlude a critter up close? The spec
   says it geometrically cannot; if it does, that is a real bug.*
5. NaN score guard · FireVisuals smolder-pool teardown leak — no player-facing test needed.
6. **🌲 B4.2 tree style scoring** (`Rescue.treeStyleScoring`) — canopy-threading finally pays, without
   any tree becoming solid. *Ask: does SKIMMING the crowns out-score flying THROUGH them? And does the
   catch beat still ESCALATE, or does every catch now look like your biggest one?*
7. **🛠️ S46 cylinder axis fix** (`Rescue.cylinderAxisFix`) — trunks were 7-stud pancakes and the safe
   pad was a wall; both are now the shapes they were meant to be. *Ask: does the deliver run feel like
   arriving somewhere? Are any saved squirrels standing on the rim pool?*
   ⚠️ **6 and 7 are entangled by Chad's own choice.** He was offered three sequencings and picked
   "ship live now", knowing the cylinder fix reshapes the mesa/pad/pool — which are `CanQuery=true` and
   feed the style meter's ray fan. **So B4.2's original control ("mesa line-riding feels exactly as
   before") is VOID.** Judge B4.2 on GROVE behaviour (skim vs plow), not on the waterfall.

### Flag decisions Chad made at the S45c close — both are now settled, don't re-open them
- ✅ **`Rescue.skyGem = true` — LIVE.** He flew it: *"yes on gems."* The spec that used to assert it
  ships false now asserts the **revert** still works (a config-only `false` restores the Stage-1 gem).
- 🔒 **`Rescue.treeCollision` STAYS `"off"` — a DESIGN DECISION, not an oversight.** Offered the flip,
  he chose the ghost forest: *"trees I dont collide with which is a positive. Makes it more simple."*
  **Do not flip it back without asking him.**
  ⚠️ **The cost, so nobody rediscovers it as a bug:** that one switch is two things at once. Trees are
  non-queryable, and `computeProximity` (the style meter) only sees `CanQuery=true` parts — **so the
  style meter cannot charge near trees, and the canopy-threading verb, the game's headline
  skill-ceiling mechanic, currently pays nothing.** His simplicity and that scoring are in direct
  conflict *while they share a flag*.
  ▶ ✅ **DONE in S46 (B4.2)** — the two are decoupled. The scorer got its own source (canopy POSITIONS
  via `SpatialHash`, not raycast hits), so canopy-threading pays **without** any tree becoming a
  collision surface. `treeCollision` now does exactly one job: collision. See the S46 block below.

### Still inert, still needing Chad
- **`Controls.touchAim`** — B7-P1 built inert; **blocked on Chad answering DRAG vs TAP.**
- `Fire.roarAssetIds` and `Rescue.squeakAssetIds` are EMPTY ⇒ the fire and the squirrels are **silent**;
  each needs a Toolbox asset id pasted (both print a 30-second how-to in Output at boot).

### Queue, in order
0. **Get Chad's verdict on the SEVEN live-but-unjudged changes above.** Two sessions of autonomous
   work is now stacked up behind one flight. Cheapest value in the queue by a wide margin, and
   everything below risks building on unjudged ground.
1. **PHASE C — progression/levels.** ⭐ **Chad's standing #1 directive since S42** ("Definately need to
   have levels unlock"). *He was offered a start at the S45c close and chose to wrap up instead — so
   this is NOT yet explicitly green-lit; confirm before building.* Nothing persists today (no DataStore
   anywhere in `src/`). Design is done: cumulative acorns as currency, one DataStore profile, and **a
   first unlock inside 5 minutes (~400 acorns) so round 2 has a reason to exist** — the 2,500-acorn
   valley gate is a 4th-session reward and fatal as the first rung. Increment 1 = pure `Progression`
   module + DataStore wrapper + total-acorns HUD line + that one unlock, `Rescue.persistence` gated.
2. **🌊 REVIVE THE WATERFALL UPDRAFT** — ⭐ *strongest technical candidate, and newly urgent.*
   `Rescue.updraftStrength = 210` is read by **NOTHING** in `src/` (grep-confirmed): the column is pure
   decor and applies zero force. That was always true, but S46's geometry fix makes it matter — the
   deliver run now clears the pad rim (~y 258) instead of slipping through the old thin mesa blades at
   ~230, and the updraft is precisely the mechanic meant to carry you up there. **It is the causal
   partner of the change just shipped**, it is self-contained, and it restores a designed payoff beat
   rather than inventing a new one. Client-side force (the column position is already built).
3. **Event-driven spawn-on-join** — READY, was held back so it couldn't muddy the render probe. That
   probe is done, so this is unblocked. The 1.906s to the Birds folder is purely GameServer's 2s poll
   cadence; `onPlayerAdded` does not spawn. Worth ≤2s of dead air.
4. **Round-arc display** — `roundIndex` is tracked but never shown, rounds are otherwise identical
   forever, and `Random.new(20260713)` is a FIXED seed, so round 1 is byte-identical every session.
   Cheapest possible retention work and it is the display plumbing Phase C's numbers will live on.
5. `leaderstats` — the platform-native scoreboard every Roblox player looks for; no seam exists today.
   Rides along with Phase C (same numbers, one packet).

### 🌲 S46 — B4.2: TREE STYLE SCORING, decoupled from tree COLLISION (LIVE, needs Chad's eye)
Queue item 2, built autonomously. `Rescue.treeStyleScoring = true` (kill switch; `false` is provably
byte-identical to pre-S46 — the index is never even built). **The ghost forest is untouched**: no tree
became queryable, `BirdCollision` / the swept sphere / the kernel / camera / aim law were not touched,
and a gate asserts `treeCollision` is still `"off"` so collision can never sneak back in via scoring.
- **Mechanism:** the scorer stopped asking the raycast fan (which cannot see `CanQuery=false` parts)
  and got its own source — canopy **positions** in a `SpatialHash`, scored by `RescueRules.shellCloseness`.
- **⚠️ THE RED-TEAM BLOCK THAT REWROTE THIS PACKET — do not "simplify" it back.** My first version used
  `max(0, centreDist - radius)`, which returns 0 everywhere **inside** a canopy ⇒ closeness 1.0 through
  the whole crown. Trees are GHOSTS, so that pays **maximum for barging straight through a tree** and
  less for threading between them — an exact inversion of the mechanic, and it would have pinned
  `styleMult` at its 3.0 cap on nearly every catch (the grove disc saturates, and every treetop perch
  approach flies through it). **The line is the canopy SURFACE:** distance is `|centreDist - radius|`,
  falling off on BOTH sides. `tests/rescuerules.spec.luau` has this as "THE INVERSION GATE".
- **Also caught by red-team:** a Roblox **Ball's radius is half its SMALLEST axis**, not half X.
  Canopies are `Size=(d, d*0.8, d)`, so `Size.X/2` would have scored a sphere **25% wider than the one
  drawn** — an invisible skirt, i.e. an actual feel lie. `RescueRules.canopyRadius` does it right.
- **Own knobs on purpose:** `treeStyleProxDist=16`, `treeStyleSweetSpot=3`. `styleProxDist=40` was tuned
  for a 10-ray fan against BIG terrain; reusing it for ~170 overlapping 45-stud balls would drown the
  ground line-riding feel Chad already signed off. **Tune trees there, never in `styleProxDist`.**
- **Race closed:** the client waits for `RescueWorld`'s server-published `CanopyCount` before building
  its build-once index. Scanning a half-replicated forest would bake in a short one permanently and
  silently, per client — the invisible class S44/S45 burned two sessions on.
- **Verify:** Tier-4 **200/200** (was 193; 7 new gates), rojo PASS, register headroom 20 → **19** (floor 8).
  luau-lsp FAIL is **pre-existing** — confirmed by stashing this change and re-running: byte-identical
  16 findings, zero new. **All 5 new gates were mutation-tested and each was killed by its own named
  test** (inversion, radius, flag-deleted, radius-inlined, count-dropped).
- ▶ **CHAD'S PLAYTEST ASK (this is the whole point — I cannot judge it):**
  1. Fly fast and **skim the top of a grove's crowns** → the STYLE bar should climb hard.
  2. Fly the same speed **straight through the middle** of those canopies → it should climb *much less*.
     If plowing pays as well as skimming, the inversion is back and `treeStyleScoring=false` reverts it.
  3. **Does the catch beat still ESCALATE?** `styleMeter` also drives the camera (pull-in, cant, FOV,
     desat) — that is by design, but if every catch now looks like the biggest one, `treeStyleProxDist`
     is too generous. This is the one knob I'd expect to want tuning.
  4. ~~Ground/mesa line-riding should feel **exactly as before**~~ — ⚠️ **THIS CONTROL IS VOID.** The
     S46 cylinder fix (below) reshapes the mesa/pad/pool, which are `CanQuery=true` and therefore feed
     the style meter's ray fan. Chad chose to fly both changes together knowing this. Ground-only
     line-riding (away from the waterfall) is still a valid control; the mesa is not.

### 🛠️ S46 — CYLINDER AXIS FIX (LIVE, Chad green-lit; visible world change)
A Roblox `Cylinder`'s axis is **local X**. Four world-gen sites passed the intended height in **Y** and
*also* applied the stand-up rotation `CFrame.Angles(0,0,rad(90))` (local X → world Y), so height and
cross-section swapped. **4 of the repo's 8 cylinder sites were already correct** (`UpdraftColumn`,
`FoxFlare`, `FireVisuals.buildRing` — which carries an explicit comment saying so — and `goldRing`);
that 4-vs-4 split inside one codebase is what proved it a typo pattern, not a style.

| part | was | now |
|---|---|---|
| `Trunk` | 7 tall, 60–115 **wide** (a pancake under a floating canopy) | a real 60–115-stud trunk |
| `Mesa` ×6 | six ~260-tall blades, 43.7 thick | six stacked discs, radius 130→65 |
| `SafePad` | a 200-tall, 6-thick **wall** | a 200-diameter landing pad |
| `RimPool` | a 120-tall glass **wall** | a 120-diameter pool |

- **Kill switch `Rescue.cylinderAxisFix`** (`false` = the pre-S46 world, byte-identical — the pure test
  pins all four legacy vectors literally). The two always-correct sites do **not** take the legacy
  path, so the switch cannot break what was never broken.
- **The class is closed, not just the four instances.** `uprightCylinder` owns Size + Shape + rotation
  together, so a caller cannot get the axis wrong, forget the rotation, or hand-roll a new cylinder.
- **Gates:** `Enum.PartType.Cylinder` must appear exactly once in `RescueServer`; the four fixed sites
  are pinned **by literal argument order** (the pure permutation test alone is near-worthless — the bug
  lived entirely in arg order at the call sites). **7 mutations run, all killed by their own gate.**
- ⚠️ **`codeOnly()` now strips `\r`.** The working tree is CRLF, so any gate anchoring a pattern on
  `\n` matched nothing and went **vacuous rather than failing loudly**. Cost one red test to find; the
  fix is in the shared helper so it can never bite another gate.
- ▶ **CHAD'S PLAYTEST ASK:**
  1. **The deliver run** — carry a load and deliver. You now clear the pad rim (~y 258) and fly in over
     a green disc, instead of passing through the old thin blades at ~230. It should feel like arriving
     somewhere. If it feels like smacking a cliff, that is the dead updraft (landmine below), not the
     geometry. Knob: `deliverRadius` / reviving `updraftStrength`.
  2. **Look at the crowd after a deliver** — the rim pool is a real 120-wide disc centred on the pad, so
     seats between r=45 and r=60 now land on **water**. If saved squirrels are standing on the pond,
     that is a placement follow-up (move the pool to the waterfall lip), not a regression.
  3. **Fly a grove low** — trunks are poles now. Still ghosts (`treeCollision="off"`), so you pass through.
  4. **One-word revert proof:** `cylinderAxisFix = false` must restore exactly today's look.

### 🚨 Landmines — real, unfixed, deliberately deferred
- ✅ **CYLINDER AXIS BUG — FIXED in S46 (Chad green-lit it).** See the S46 block above. Left here only
  as a pointer: the class is now closed by `uprightCylinder`, and `compile.spec` asserts
  `Enum.PartType.Cylinder` appears **exactly once** in `RescueServer` so no hand-rolled cylinder can
  reintroduce it.
- 🆕 **Two S46 placement follow-ups, exposed (not caused) by the cylinder fix — logged, not bundled.**
  Both were invisible while those parts were walls, and both are cosmetic:
  - **The rim pool is now a pond on the pad centre.** `RimPool` is radius 60 centred on `deliverPos`,
    2 studs proud of the pad. Crowd seats live in the annulus `crowdRadiusMin=45`…`crowdRadiusMax=85`,
    so seats between r=45 and r=60 (~30% of the annulus area) now land on **water**. Surgical fix:
    move the pool to the waterfall lip, or raise `crowdRadiusMin` to 60.
  - **~3% of under-canopy perches now sit inside a trunk.** `plantPerchTree` offsets them uniformly by
    ±20 in XZ at y = 22–38; with a real trunk (radius 3.5 spanning y 0→h) any offset with |dx|,|dz|
    both < 3.5 is inside wood. Trunks are `CanQuery=false`, so this is **visual occlusion only** — but
    "I can't see the squirrels" is the S44 complaint class, and the sky gem descends into the trunk
    with the critter. Surgical fix: a polar offset with `r = 8 + rng*12`.
- 🆕 **`updraftStrength = 210` IS AN ORPHAN — the waterfall updraft applies NO FORCE.** Confirmed by
  grep: nothing in `src/` reads it. This was always true, but the S46 geometry fix makes it matter —
  the deliver run now clears the pad rim (~y 258) instead of passing through the old thin mesa blades
  at ~230, and the updraft is the mechanic that is *supposed* to carry you up there. **It is not
  blocking** (you spawn at 600 and the valley is 1600 wide, so altitude is cheap), but the intended
  payoff ride is currently decor. **Strong candidate for the next packet** — it is the causal partner
  of the change just shipped.
- **⚠️ SOP (S46): never mutation-test with PowerShell `Get-Content`/`Set-Content`.** PS 5.1 reads
  UTF-8-without-BOM as Windows-1252 and writes UTF-8 **with** BOM, so a read-mutate-restore harness
  silently mojibaked 161 comment characters across 3 source files and added BOMs — a 254-line diff
  ballooned to 863. Caught by diffing `--stat` against the intent, repaired via `git checkout` + re-apply.
  Use `[System.IO.File]::ReadAllText` / `WriteAllText` with `UTF8Encoding($false)`, and **always
  `git diff --stat` after a scripted edit** — the tests stayed green throughout the corruption.
- **A 2nd player joining destroys the rescue round.** Nothing in GameServer is gated on
  `Rescue.enabled`; player #2 is auto-assigned **Crows**, which starts the combat round and calls
  **`clearBirds` on everyone** mid-round. **Detonates the first time Chad tests with his kid.**
  *(Chad S45: "forget second player for now" — deferred, not fixed.)*
- **Anti-cheat cascades to a KICK** from one network stall (rubber-band writes to a client-owned part,
  baseline frozen ⇒ a strike every Heartbeat). Invisible in Studio; real when published/mobile.
- **Deliver has zero spatial validation** — phase + `carry>0` only.
- **Fox missions visually pin relocated squirrels** at their old perch height (`HopBaseY` cached once).
- **14 orphan config knobs read by nothing**, incl. a dead `mouseSensitivity` block 54 lines above the
  live `aimMouseSensitivity`, and `updraftStrength` — **the waterfall updraft applies no force at all.**

### Invariants a new agent must not violate
- **The flight kernel, camera and aim law are SIGNED OFF and LOCKED** (CS-1..CS-9 registry below). Grep
  it before any control edit. Rescue is built AROUND them: triggers, presentation, world, meta.
  **When a complaint sounds like flight, check the WORLD first** — S45b's "I crash every start" was a
  map defect, and "raise the spawn / slow the dive" would have been a kernel change for a world bug.
- **BirdController's top-level chunk is register-capped.** Headroom was 199/200; it is now **20**, and
  `compile.spec` fails at a floor of 8. Pay for space (group locals into a table, or extract a module)
  before adding module-locals. ⚠️ Extracting the audio band **must carry the ping-law source gate** or
  that gate goes silently vacuous.
- **Adding a `src/shared/` module?** `default.project.json` maps them **individually** — miss it and
  `WaitForChild` hangs forever, killing the script silently. `compile.spec` now gates this.
- ONE change at a time · config-gate everything with a kill switch · **mutation-test every new gate** ·
  ground truth is Chad's Studio Play (`build.ps1` does not run or syntax-check Luau).

### Ladder at close: **Tier-4 193/193 · rojo PASS · luau-lsp 0 new · selene UNAVAILABLE(404)**
Branch `updraft`, working tree clean, everything committed **and pushed**.

### Two process lessons this session earned the hard way — both cost real time
1. **Never trust a gate you have not MUTATED.** Twice this session a new gate could not fail. The
   `default.project.json` mapping gap would have bricked the server silently (compile, luau-lsp and
   `rojo build` all stayed green), and the first `CastShadow` source gate **passed against a mutant
   with the assignment deleted** because it was matching the word in its own explanatory comment.
   **A source gate must read CODE, not prose** — strip `--` lines before matching.
2. **A real defect that produces the symptom is not proof you found the cause.** S45b's featureless
   spawn core was genuinely broken and genuinely worth fixing — and it was *not* why the world
   rendered late. Fix it, keep it, and keep measuring.

---

## ▶▶ S45b (2026-07-21) — 🌍 THE FEATURELESS CORE: why he flies into the ground

**Chad, after the commit above: *"I just always crash at the start… I nose down into the ground every
time"* — then the clarification that cracked it: *"im diving so the ground will render but it does so
too late."* He is not flying badly, and this is only partly a render bug.**

**THE FINDING, straight out of BuildMap's own comments.** `GameServer:297` states the mechanism
verbatim — ground patches exist to "break up the uniform grass so altitude/speed/heading read at a
glance from far up (**a flat green plain gives no perspective cue**)". Then **every landmark in the map
is explicitly excluded from the box the player occupies**:
| feature | where | the in-line comment |
|---|---|---|
| ground patches | ±2,200-5,200 | *"all clear of the ±1200 core"* (`:298`) |
| the river | between landmarks | *"not the spawn core"* (`:316`) |
| the buttes | ±1,300-2,600 | *"kept clear of the ±1200 spawn zone"* (`:369`) |
| lake / desert | r ≈ 3,000-3,800 | — |
| 3 mountain rings | r = 3,600 / 5,400 / 7,400 | — |

The eagle spawns at **random XZ inside ±1200, Y=600** (`:592`). So the one region the player flies is a
**2,400 × 2,400 stud UNIFORM PLANE**. That is the classic featureless-terrain problem: with no object
of known size and no texture gradient there is **no closure cue**, so altitude is unreadable until
Roblox's material texture resolves at short range — which from the cockpit reads *exactly* as **"the
ground rendered too late."** They diagnosed the mechanism correctly and then placed the cure everywhere
except where the patient was.

**THE FIX — `src/shared/GroundDetail.luau`** (pure module + `tests/grounddetail.spec.luau`, 7 gates):
a deterministic **multi-scale jittered-grid** scatter of flat patches across the core.
**Multi-scale is the whole technique** — a cue helps only while it subtends a useful visual angle, so
one patch size fixes exactly one altitude: **coarse** 4×4 @420-760 studs ("there is a floor", reads
from 600+), **mid** 6×6 @150-320 (through the dive), **fine** 9×9 @48-118 (**blooms in the last ~150
studs — the flare cue that is missing today**). 133 parts, all flat at Y=0.6.
**COSMETIC BY CONSTRUCTION:** every patch is emitted `CanQuery/CanCollide/CanTouch/CastShadow = false`,
so **BirdCollision's Spherecast cannot see them and the crash surface is bit-identical to today.** A
gate asserts that on every patch; the mutation (canQuery=true) turns it red.
**Rejected on ceiling, not taste:** bigger patches only (fixes 600 studs, still cueless in the last
200 — exactly where he hits) · Roblox Terrain (the real long-term "proper map" answer, but a different
replication/collision system, and not while the render question is open) · a texture/decal grid (needs
an asset ID — the one thing no headless gate here can verify, cf. the S43 roar tombstone) · raising
spawn or slowing the dive (**that is a FLIGHT change and the kernel is LOCKED — the defect is in the
world, so the fix belongs in the world**).
**The coverage gate is the load-bearing one:** it sweeps the whole core on a 60-stud grid and fails if
any point is >220 studs from a patch edge — *a hole is a corridor you can dive with no cue, i.e. the
original bug reintroduced by luck.* **It failed twice for real during development** (263 then 264
studs), which is how the apron and the band tuning were found. Now **worst gap 140 studs**. Knobs:
`Map.coreDetail` (kill switch = byte-identical map), `coreHalfExtent`, `coreDetailSeed`.

**⚠️ AND IT CAUGHT A BRICK I ALMOST SHIPPED.** `default.project.json` maps every shared module
**individually**, not the folder — so a new `src/shared/X.luau` is **not** in ReplicatedStorage, and
`require(ReplicatedStorage:WaitForChild("X"))` **blocks forever and kills the script silently**, with
compile, luau-lsp and `rojo build` all still green. New gate in `compile.spec` scans every
ReplicatedStorage require in `src/` against the project file's paths; mutation-tested by deleting the
mapping. **Any agent adding a shared module: add the project.json entry or the gate reds.**

**▶ HONEST SCOPE — this is NOT the render fix.** It is a code-confirmed defect in the MAP that produces
the same symptom, and it stands on its own. **The quality/streaming question is still unresolved and
the probe is still unflown.** If the ground still appears late after this, that is the render lane and
the probe flight is still the answer. Do not treat one as evidence about the other.

### Ladder: **Tier-4 191/191** · rojo PASS · luau-lsp 17 (the +1 vs 16 is the new module's
`Unknown require` sourcemap noise — the documented tool-noise class, and `rojo build` proves the
mapping resolves) · selene UNAVAILABLE(404).

---

## ▶▶ S45 (2026-07-21) — 🧭 THE WAYFINDER LAW · 🐿️ THE RESPAWN CARRY DESYNC · ⏱️ "still slow" is UNRESOLVED and now instrumented

**Chad: *"I dont even know where to fly at the start everything renders in so slow."* Five Fable-5
auditors ran in parallel (first-60-seconds / startup+render / code-health / game-design / correctness).
He then answered two questions that re-aimed the whole session:**
- **"Newest build, still slow"** → **S44's intermission fix did NOT resolve it. That explanation is
  FALSIFIED and closed.** Do not re-litigate it.
- **"Both — I'm just dropped in cold"** → no goal, no direction, nothing visible. A full onboarding hole.

### ① 🧭 THE WAYFINDER LAW — the compass was switched OFF at every moment anyone is lost (LIVE)
**Two auditors found this independently and both ranked it the #1 change in the game.** The gold
streamer (`updateWayfinder`, Fable §D "a diegetic compass, ZERO UI") is the **only** directional
mechanism that exists — and it was gated `#riders > 0` (`BirdController:2141`). So it was dark at
spawn and dark after **every** delivery: off at the ~6 moments per round you are empty-handed and
scanning. The other "direction" machinery is a **combat relic** — `GameUI:653-739` edge-arrows iterate
enemy *birds*, of which the rescue round has zero, so it is permanently dormant.
**Now:** empty-handed in an active round → the same certified ribbon points at the **nearest catchable
squirrel**, in **full 3D with no tip lift** (groves sit ~40° BELOW a Y=600 spawn frame — the whole
answer is "down there"; the waterfall ribbon keeps its horizontal+lift arc, byte-identical).
**Deliberately NEAREST, not "best"** — triage-by-rarity/danger/route is the skill ceiling (§3.2 pays a
skilled round 6.7×) and stays the player's. Policy is pure in `RescueRules.wayfindTarget` with
**hysteresis** (`wayfindSwap` 0.2) because the real failure mode is a ribbon that **strobes** between
two equidistant groves. Gates: carrying-path unchanged · kill switch · never-lies (no candidate or
non-active phase ⇒ dark) · hysteresis holds AND releases · a 60-step approach sweep changes hands ≤1×.
**Mutation-tested:** swap→0 reds the strobe gate; flag→false reds two. Knobs: `Rescue.wayfindEmpty`
(kill switch = byte-identical pre-S45), `wayfindSwap`, `wayfindTipLift`.

### ② 🐿️ THE RESPAWN CARRY DESYNC — the defect both auditors called "most likely to hit the next flight" (FIXED)
The server zeroed `carry` in exactly two places (startRound, successful deliver). **Nothing zeroed it
when the player's BIRD was destroyed** — while the client drops every rider on any teardown
(`teardownDrive → releaseRiders`). **Press R while carrying 7** → client shows 0/10, server still
believes 7. The next 3 catches fill the server to 10; **every catch after that is silently REJECTed as
FULL while the client plays the entire sacred catch beat and mounts a rider** (the reconciler only
trims DOWN, so it cannot heal it). First waterfall pass then pays for TEN squirrels never carried.
**That is verbatim the "8-9/10 of my catches don't get counted" complaint S35/S36 burned two sessions
chasing — reachable from one keypress.** Fixed by watching `Birds.ChildRemoved` (covers R, death,
crash, ownership reclaim — the same event the client keys its own reset off), pure rule
`RescueRules.carryOnReset`. **Invariant gated: a lost bird clears what you CARRIED and nothing you
EARNED** (score/delivered/rescued/perfect stamps survive — otherwise a desync fix becomes a
punishment). Knob `Rescue.carryResetOnLoss`.

### ③ Two more confirmed defects, both one-liners with teeth
- **NaN poisons the round score.** `math.clamp` is `v<min ? … : v>max ? …` and **every comparison with
  NaN is false**, so a NaN `styleMult` (client-supplied) sailed through both rails → `floor(NaN)=NaN`
  → `ps.score` is NaN for the rest of the round and the HUD renders **"nan" acorns**. Guarded in
  `catchScore` with the same `x ~= x` test `fireRoarVolume` already used.
- **`FireVisuals.destroy` leaked the S44 smolder pool** — the same create/teardown asymmetry class as
  the fire-roar bug. Masked on the normal path (the folder dies too), but the **mid-round failure path
  destroys the controller and KEEPS the folder** to "drop to logic-only fire" — stranding up to 14
  **Enabled** wisp emitters smoking at frozen positions while the real front moved on. Both
  mutation-tested.

### ④ 🚨 THE 200-LOCAL CLIFF IS LITERAL: BirdController's top-level chunk measured **199/200**
Not a function — the **module chunk**; every column-0 `local`, *including every `local function`*, is a
register that never goes out of scope. Measured by binary-search injection at Studio's exact compile
settings. **One free.** The next agent adding two module-locals (or one `local function` plus one
`local`) bricks the client. Banked +1 this session by deleting the write-only `renderConn`
(byte-identical; luau-lsp went 17 → 16). The rescue presentation band (lines 1199-2845) holds **87 of
the 199** and provably reads **none** of the LOCKED control state — the audit's costed extraction
ladder (`RescueAudio` +25, `RescucePresentation` +55) is in the queue below.

**RESOLVED THIS SESSION (step 2 of the ladder):** headroom is now **1 → 20**, measured. 23 module-locals
were grouped into **5 tables** — `RETICLE` (reticle colours), `FEATHER` (feather palette + pool size),
`RIDER` (back-rider animation constants), `music` (beat-clock state), `scan` (squirrel-scan latches).
Mechanical rename, values untouched, and verified non-shadowable (no local, parameter, or bare
reference to any of the five names exists anywhere in the file). **The cliff now has a tripwire:**
`compile.spec` binary-searches the real headroom at Studio's compile settings and **fails at a floor of
8** — while there is still room to think, instead of after the client refuses to run. Mutation-tested:
15 injected locals (headroom 5, still compiling) turns it red. The error message names the two ways to
pay for space and carries the ping-law warning.
**Remaining ladder if more is ever needed:** `RescueAudio` ≈ +25 (⚠️ **must move the ping-law source
gate with it or that gate goes silently vacuous**), `RescuePresentation` ≈ +55.

### ⑤ ⏱️ THE "STILL SLOW" HALF IS **UNRESOLVED** — and the probe to name it is already shipped, never flown
S44's BootDiag measured when instances **EXIST**, never when they are **DRAWN**. Those are different
clocks and the gap is the whole remaining question. Census (counted, not estimated): **~1,300-1,400
Workspace instances, ZERO external assets** (no meshes/textures/decals — so asset-download is ruled
out by construction). Leading suspect is **quality-scaled draw distance + the auto-quality ramp**
(inferred from symptom fit, not measured). Two hard facts found while looking:
`Workspace.StreamingEnabled = false` at `GameServer:266` is inside a `pcall` and **that property is
not scriptable at runtime — it is a silent no-op**, so the live session's true value is unverified;
and **78 Map parts are shadow-casting** (`addPart` never clears the default, while RescueServer's
builder always does). **Verdict: streaming should STAY off** — at ~1,400 instances there is nothing to
defer, and every gameplay-critical object (client-owned birds, attribute-driven squirrels, the
distance-keyed fire roar) would need `Persistent` anyway.
**⚠️ THE TRAP, named explicitly: do not ship another timeline "fix" before the probe flight.** That is
exactly what S44 did. The diagnostic is already in the build (`fc111fd`, `Rescue.bootDiag` is true).

**▶ CHAD'S PLAY (this is the ask):**
① **Fly once and paste the `[BootDiag]`/probe lines** — they print `StreamingEnabled`, the quality
level, and descendant counts at t=1/5/10/20/30s. That ONE flight decides between streaming-bound,
replication-bound, and render/quality-bound. **Also do the 60-second A/B:** Esc → Settings → Graphics
Mode **Manual → max**, re-fly. If the forest is all there at ~2s on max, it is quality-culling and the
answer is cheap.
② **The wayfinder:** from spawn, empty-handed — does a gold ribbon now tell you where to go, within a
frame? Does it ever strobe between two groves? Knobs: `wayfindSwap`, `wayfindTipLift`.
③ **The carry fix:** carry ~5, press **R**, then catch 6 more — all six must count.

**▶ NEXT (in order):** the probe flight decides the render lane → then **event-driven spawn-on-join**
(measured: the 1.906s to the Birds folder is purely GameServer's 2s poll cadence; `onPlayerAdded` does
not spawn — READY to ship, held back deliberately so it doesn't muddy the probe) → **`skyGem=true`**
(built, tested, still awaiting its verdict) → **`treeCollision="trunks"`** (built + gated; today
`="off"` makes every tree non-queryable, so **the style meter — the entire skill ceiling — cannot
charge near trees**, i.e. the advertised canopy-threading verb pays nothing) → **BirdController
extraction ladder** (the 199/200 cliff) → **PHASE C** progression.

**▶ HIGH-SEVERITY, NOT YET FIXED (from the audit, ranked):**
- **A 2nd player joining destroys the rescue round.** Combat is shelved *by player count, not by
  config* — nothing in GameServer is gated on `Rescue.enabled`. Player #2 is auto-assigned **Crows**
  (`pickTeamFor:487`), which flips the combat `RoundLoop` on, and `startRound:1958` calls **`clearBirds`
  on everyone** — deleting the rescue player's eagle mid-round — then runs a second round clock against
  `RescueRoundLoop`. **This detonates the first time Chad tests with his kid.** Fix is one guard + a
  Chad decision on what player #2 should actually be.
- **Anti-cheat cascade:** a rubber-band writes a CFrame to a *client-owned* part (overridden next
  packet) and the baseline is deliberately frozen, so one 2s network stall fires a strike **every
  Heartbeat** → reclaim at 3 → **kick at 6**, and reclaim is one-way with no recovery. Invisible in
  Studio (client and server hitch together); real on a published/mobile session.
- **Deliver has zero spatial validation** (`RescueServer:686`) — phase + `carry>0` only; the waterfall
  objective exists only client-side.
- **Fox missions visually pin relocated squirrels** at their OLD perch height (`HopBaseY` is cached
  once, never invalidated) — dormant under `ember_valley`, certain when Phase C rotates the fox in.
- **14 orphan config knobs read by nothing**, incl. a dead `mouseSensitivity` block **54 lines above**
  the live `aimMouseSensitivity` (the exact `musicPizzAt` trap S44 just closed), and `updraftStrength`
  — **the waterfall updraft applies no force at all**; thermals sit on a ring at radius 3200, outside
  the 1600-stud valley. The audit's fix: a `config.spec` **orphan gate** that fails when a knob's last
  reader dies.

### ⑥ Ladder: **Tier-4 182/182** (169 → 182; +13 new gates, all mutation-tested) · **rojo PASS** ·
**luau-lsp 17 → 16 (0 NEW)** · selene UNAVAILABLE(404). Nothing committed — awaiting Chad.
*(Chad's call this session: the 2nd-player landmine is DEFERRED — "forget second player for now". It
stays on the high-severity list above; it is dormant while he plays solo.)*

---

## ▶▶ S44 (2026-07-21) — 🔔 THE PING LAW (the 6× complaint, root-caused) · 💎 SKY GEM built INERT · 🔥 THE SMOLDER TELL is LIVE

**Chad opened with two complaints and asked for a huge Fable audit. Four Fable-5 auditors ran in
parallel (acquisition / audio / timeline+perf / claimed-vs-actual drift). Their findings drove both
changes below. Nothing is pushed; the ping law is LIVE, the sky gem is INERT.**

### ① THE PING LAW — why "fixed" five times and never fixed
Chad: *"I hear pinging after picking up 6. I asked for this only on 10/10 about 5 or 6 times now."*
**Root cause, confirmed independently by two auditors: "ping" names the ASSET**
(`electronicpingshort.wav`), not a function. S38 gated the music layers; S43 gated `catchChime`/
`playChord`. **SIX emitters shared that one wav**, and the S43 fix removed the *quietest*:
- `playGotcha` — **every catch, vol 0.6** (the chord it replaced was 0.5 — the "fix" made it LOUDER)
- `playWoohoo` — every catch · `playCount` + the deliver chord — on **partial** loads
- the **crew choir** — the only CONTINUOUS bell: every `2.4 − 0.14·(riders−1)` s from rider **1**
  (**1.70s at six aboard** — exactly "pinging after picking up 6")

**The reasoning error to never repeat: fixing the symbol whose NAME matched the complaint instead of
inventorying what actually emits.** One `grep SFX_PING` would have falsified it in ten seconds.

**The fix RE-VOICES, never silences** (a catch must still land): catch accent → bright two-note **talon
snap** (a closing talon IS a snap), woohoo → rising **rush of air**, crew chatter → high **chitter
clicks** (and that is the seam a real squeak asset drops into). Bells now exist in exactly three
places: the catch that FILLS the back, the waterfall jingle, the full-load payout. Scarcity is what
makes 10/10 the jackpot.

**Structural, so it cannot regress:** `RescueRules.soundClass` + `SOUND_EVENTS` is the pure policy;
the spec **sweeps every event × every carry** and fails if any can ring below a full load (a new event
is under the law automatically). Plus a **source-text gate**: `playSound(SFX_PING, …)` may not appear
inline in BirdController — the exact bypass that caused five regressions. **Both gates mutation-tested:
crew-choir-back-on-the-bell → 2 fails; inline ping at the catch site → source gate fails.**
`Rescue.sfxDiag=true` now prints every one-shot (event/class/vol/pitch/carry) — audio was the one
subsystem with no diagnostic, which is how six guess-cycles happened. A/B flags: `gotchaOnPing`,
`woohooOnPing`, `chirpOnPing` (all ship false).

⚠️ **Adding the seam pushed BirdController over Luau's 200-local cap and BRICKED the client.**
`compile.spec` caught it headlessly. Paid back by merging playGotcha+playWoohoo into one `playAccent`.
**BirdController has ~zero local headroom — budget one before adding any module-local.**

### ② THE SKY GEM — "I can barely see the squirrels" (built, INERT, `Rescue.skyGem=false`)
**Nothing renders late: all 15 squirrels spawn on the round's FIRST frame** (timeline lane ruled out
every mechanism). Chad simply cannot SEE them. Quantified at 70° FOV / 1080p (≈771 px/rad):

| signal | @600 | @1,140 (typical approach) | @2,000 |
|---|---|---|---|
| chevron gem | 3–4 px | **≤2.4 px** | subpixel |
| halo (flat, foreshortened) | 26 px | 13×6 px | 8×3 px |
| *(the retired shaft)* | 90 px | *47 px line* | 27 px |

…and **45% of perches are UNDER the canopy** (crowns span Y 25–80), so ~7 of 15 have **no sky signal at
all**. **This is a REGRESSION**: Stage 1's gate was the dive-in read only ("does your eye land on a
waving animal") — the word *range* is not in the d9630b0 diff. It traded the shaft's weak-but-real
long-range line for nothing.

**Vetted technique (SOP #8 — tombstones respected):** keep the certified Stage-1 gem, make it a
**per-frame distance projection** — constant ANGULAR size (~11.6 px at ANY range) + a lift that clears
the worst-case tree envelope (150) at distance, descending back onto the head as you close. Near ≤70
studs it is **byte-identical Stage 1**, so occluding the critter is geometrically impossible; the
descent itself guides you under the crown to the hidden half. Rejected on CEILING, not taste: emoji
billboard (S39 tombstone), fat cylinder (S40 tombstone), shaft revert (~1 px at range, still inside
the crown band), bigger halo (foreshortens; under the leaves), particles (10-stud engine cap),
Highlight (outlining a subpixel silhouette is subpixel).

**Headless gate asserts the READ, not opinion:** never-occludes-up-close (identity ≤70 studs),
visible-from-altitude (8–40 px across 260–2,600 studs; **worst 10.1 px vs Stage 1's 1.5 px @1,140**),
clears-the-canopy (gem bottom ≥150 for under-canopy perches), monotone/capped/never-pulls-down, and
**rare gems keep their 1.35× size advantage at range** — that last test FAILED first and caught a real
design flaw (every gem converged to one size far out, killing triage-by-value from altitude).

### ③ THE SMOLDER TELL — "it takes a while for me to see fire too" (LIVE, `Fire.smolderTell=true`)
**Convicted:** the burn seeds at `igniteAt=10`, then every cell smolders **15-25s** — and FireVisuals
rendered **BURNING ONLY**, so SMOLDER had *no visual representation at all*. First flame therefore
appeared ~25-35s in (clock **~1:35**) and accreted cell-by-cell at the ~1 Hz sync. Worse: **spread is
ACTIVE from SMOLDER** and Danger keys off any non-GREEN cell, so an **invisible front was propagating
and panicking squirrels for up to 25s** — Stage-3a fear pointing at something you could not see.

**The technique, vetted (SOP #8):** render the state as what it physically IS — **smoke, no flame**.
That preserves the smoke→flame **escalation** rather than flattening it, and it is why the obvious
alternative is a trap: **cutting `smolderMin/Max` races the ENTIRE front (smolder spreads) — a balance
change wearing a visibility costume.** A dim flame would flatten the escalation for the same cost.
`FireGrid.smolderCells` (read-only, LCG-free ⇒ **B1 determinism untouched**) + a pooled wisp set that
is deliberately cheaper than a flame: **no PointLight, no flame emitter, no marker geometry, no
flicker breathing** — one pale slow emitter on an invisible anchor.

**Perf re-pinned, not bypassed:** particles **1384 ≤ 1600** rail (the +224 is exactly the wisp pool),
**lights still 30 / 0 shadow-casting** (the mobile cliff did not move), **allocation-free 299→299 over
100 syncs**. Gates assert the READ *and* the cost: visible-during-the-window (14 wisps lit at t=8s with
20 smouldering cells and **zero flames** — the exact gap Chad reported), no-lights/no-flame-emitters,
**clean ignition handoff** (never wisp *and* flame on one cell), kill-switch restores the byte-identical
pre-S44 emitter tree, and a guard asserting `smolderMin/Max` were **not** quietly cut.

### ④ ✅ CHAD'S VERDICT (flown 2026-07-21): **"yes better now no ping"** — the six-session complaint is
**CLOSED**. Remaining, in his words: *"it just takes a while at the start for everything to render."*

### ⑤ BOOT DIAG — attribute the startup, don't guess at it (`Rescue.bootDiag=true`, LIVE)
The perf lane already ruled OUT a frame-rate cliff, which leaves three candidates that no amount of
code-reading can choose between: **(a)** Roblox replicating the whole place at join (`StreamingEnabled`
is false, so *everything* arrives before anything renders), **(b)** the client acquisition handshake
(Birds → Body → NetOwner), **(c)** the **6s INTERMISSION**, which deliberately CLEARS the valley of
squirrels and then bursts ~600 instances in a single frame at round start. Guessing here is precisely
how the ping survived five fixes — so both sides now print timestamped milestones and **one flight
names the cause.** Turn `bootDiag` off once it is named.
Also fixed while in there: the two **silent** one-shot `WaitForChild(…,30)` timeouts (audit finding)
now `warn()` loudly instead of leaving the rescue layer dead with zero console evidence.

### ⑥ ✅ THE STARTUP, NAMED ON THE FIRST FLIGHT (BootDiag output, 2026-07-21)
```
0.000s  round loop entered            0.004s  world built (trees + waterfall)
0.004s  INTERMISSION begins (6s) — the valley is now EMPTY of squirrels
0.001s  [client] Squirrels folder found (0 already in it)
1.906s  [client] Birds folder found — bird acquisition can begin
6.228s  ROUND ACTIVE — all squirrels populated in ONE frame
```
**Nothing renders slowly. The server builds the entire world in 4 MILLISECONDS.** The player has a
bird at **1.9s** and then flies an **empty forest for four more seconds** because the boot intermission
clears the valley by design; all 15 squirrels then appear in ONE frame at **6.2s**. From the cockpit
that is precisely *"it takes a while at the start for everything to render."* Cause (c), confirmed —
and (a) and (b) are both **ruled out by the timestamps**, not by argument.

**Fix:** `Rescue.firstIntermission = 1.0` — the boot intermission ONLY (round #1). Between rounds the
6s breather is correct and **untouched**: it is the pause after the results screen. Implemented as an
optional 3rd arg to the pure `RescueRules.phaseDuration(cfg, phase, roundIndex)`, so it is headless-
gated and every pre-S44 2-arg caller is byte-identical. Set the knob to nil = flat 6s everywhere
(config-only revert). Gates: round #1 short / rounds #2-6 keep the full breather / the 2-arg call is
identical to a nil roundIndex / active+grace+results do NOT depend on the round index (no collateral
retiming). Also fixed the intermission's `task.wait(0.5)` overshoot so a sub-0.5s value is honoured.

### ⑦ Ladder: **Tier-4 169/169 · rojo PASS · luau-lsp 0 NEW (17 pre-existing) · selene UNAVAILABLE(404)**

**▶ CHAD'S PLAY (only he can judge these):**
① **The ear:** carry 6+ and keep catching — every catch should land as a *snap/thump*, the crew as
chitter, and **the bell should appear ONLY as you hit 10/10**. If you hear ANY bell before 10, set
`Rescue.sfxDiag=true`, fly once, and paste the `[SFXDiag]` lines — they NAME the sound. No more guessing.
② **The sky gem:** set `Rescue.skyGem=true`, Play, and from spawn altitude ask "can I see where the
critters are?" Then dive one: the gem must shrink back onto its head and fade exactly as it does today
(if it ever occludes the critter at catch range, that is a BUG — the test says it cannot).
Knobs: `skyGemStudsPerStud` (bigger = larger on screen), `skyGemMaxSize`, `skyGemClearY`, `skyGemFarT`.
③ **The fire:** watch the clock from the round's start. Smoke should start curling out of the brush at
**~0:15-0:20** (seed +10s, wisps immediately), *then* flames grow out of that smoke — you should get to
watch the fire START instead of finding it already burning. Knobs: `maxVisualSmolder` (more/fewer wisps
— 14 shows the leading edge of a ~20-cell front), `smolderWispRate/Life/Y`. Kill switch:
`Fire.smolderTell=false`. ⚠️ If it still feels late, the honest next dial is `Fire.igniteAt` (when the
burn SEEDS) — NOT `smolderMin/Max`, which would speed the whole front and change the balance.

**▶ NEXT (in order):** **Chad re-flies the startup** — squirrels should now be there by ~1-2s instead of
6.2s. If it STILL reads slow, the next honest suspect is the **1.906s to the Birds folder** (GameServer's
solo-spawn loop waits on a 2s cadence) — NOT a render/perf fix, which the timestamps already exclude.
Then turn `Rescue.bootDiag` OFF. → his verdict on the sky gem + the fire timing → **B7-P2** touch proof-of-feel (Chad answered nothing on DRAG vs TAP yet) → **B4** canopy trails
→ **B5** leap variety → Stage **3b** only if pressure still missing → **PHASE C** persistence/levels.

**▶ DRIFT the audit found (not yet fixed):** `GameConfig:1178` claims ember_valley is "INERT-by-default"
while `:1124` makes it the ACTIVE mission (same file contradicts itself) · 4 dead music knobs
(`musicPizzAt/RhythmAt/BrassAt/HeartAt`) read by nothing, with a comment describing removed behaviour ·
HANDOFF S43 ④/⑤ still tell Chad to look for a roar-asset log line that cannot print (ids list is empty) ·
`_ScratchTele.server.luau` says "DELETE after; non-committed" but is committed and Rojo-mapped ·
CLAUDE.md still describes COMBAT as the product · two silent one-shot `WaitForChild(…,30)` timeouts in
BirdController leave the rescue layer dead (frozen 0:00 clock, uncatchable squirrels) with no warn/retry.

---

## ▶▶ S43 (2026-07-21) — 🧰 SHORE-UP (perf envelope pinned + fire tick 4× cheaper) · 🐿️🔥 STAGE 3a FEAR is LIVE

**Two loop items, both red-teamed, both committed on `updraft` (NOT pushed — push stays ASK-gated).**
Worked Chad's S42 directive #4 order literally: shore up FIRST, then the next kid-legibility stage.

- **① The §3.4 perf envelope is now MACHINE-PINNED** (`tests/perf.spec.luau`, 4 gates) with the LIVE
  flicker/plume config — the thing S41 changed and nothing measured: **~1160 alive particles** (rail 1600),
  **30 lights / 0 shadow-casting** (the biggest low-end + mobile cliff, directive #3), **zero per-sync
  allocation** (257→257 instances over 100 syncs). Timing is REPORTED, never asserted (Lune ≠ Roblox VM;
  a timing assert would be a flake factory).
- **② It immediately found a real breach and it got fixed:** worst `FireGrid.step` **4.37ms** vs the ≤1.5ms
  budget. Attributed (`recomputeCutOff` 1.745ms + a per-tick full-grid reach sweep), then three
  behavior-preserving edits → **recomputeCutOff 5.7× faster, worst step 4.37 → 1.1-2.0ms, mean 0.602 →
  ~0.30ms.** Honest framing: Lune numbers scatter run-to-run, so this is a ~4× worst-case REDUCTION, not a
  proven "inside 1.5ms" — that verdict is Roblox-side with `Fire.perfDiag=true`.
  **Equivalence PROVEN:** my digest (5 seeds × 2 winds × 240 ticks) and the red-teamer's stronger independent
  harness (full state after EVERY tick, 18 rounds × 300 ticks + zero-grove + BFS-hammered probes) both found
  **0 mismatches**. LCG bit-identical ⇒ the burn, and so balance, is bit-identical.
- **③ STAGE 3a — the critter's own FEAR is LIVE** (`Fire.urgencyTells=true`; false from boot = byte-identical
  round). Server stamps `Danger` 0/1/2 from `FireGrid.dangerAt`; the client renders it in **Stage 1's
  already-certified vocabulary** — pose ×2.2/×3.4, harder+faster hops, halo flash + fire-red at PANIC while
  the **chevron keeps its rarity hue** (urgency and triage-by-value stay on separate channels). Danger measures
  distance to any **non-GREEN** cell, so escalation is **monotone BY CONSTRUCTION**. The plant tell outranks
  fear in the ladder — the sacred anticipation beat is protected structurally.
- **Red-team on 3a found the good stuff:** a mutation attack (BURNING-only) turns 3 of 4 gates red, so they
  have teeth; and its Medium caught that my fear-leads-loss test probed the grove CENTRE while the game stamps
  at PERCH positions — the easy case, flattering the number. Hardened to the worst-case perch + a min-lead
  floor: **96/96 groves panicked first, mean 23.0s (was a flattering 40.7s), MIN 4s.**
- **④ STAGE 3c — THE FIRE ROARS** (`Fire.fireAudio=true` live). `RescueRules.fireRoarVolume` is a pure
  stateless curve — silent beyond 900 studs, full inside 200, `t^1.5` between so the roar SWELLS as you
  commit; the client recomputes Volume every frame from the distance to the nearest `FireCell`, so no burning
  cells ⇒ Volume 0 that same frame. **Red-team BLOCKED it first:** `teardownDrive` mutes wind+flap (with a
  comment naming exactly this bug class) but nothing muted the roar → crashing inside the fire band left it
  looping at FULL VOLUME through death/respawn. Fixed in both teardown paths.
  ⚠️ **ASSET IDS ARE THE ONE UNVERIFIABLE PART.** Roblox's 2022 audio-privacy purge privated most pre-2022
  third-party audio, so a web-sourced id is a coin flip and no headless gate can prove a sound loads. The
  client walks an ordered candidate chain and PRINTS the verdict per id; realistically it is **"id 1 or
  bust"** (`9046850948` is in the block Roblox itself uploaded as the curated public library; the other two
  are pre-purge and likely dead). If all fail: Studio → Toolbox → Audio → Copy Asset ID → paste FIRST in
  `Fire.roarAssetIds` → Stop and re-Play.
- **⑤ B7 TOUCH CONSULT + P1 BUILT INERT.** `docs/rescue-consults/B7-touch-design.md`. Structural finding: the
  whole aim law consumes ONE input — the pixel delta at `BirdController:2495` — so **touch is a delta-source
  ADAPTER above that line, never a new control law** (kernel + instructor byte-identical by construction).
  `src/shared/TouchAimAdapter.luau` + `tests/touchaim.spec.luau` are BUILT and **INERT** (`Controls.touchAim
  = false`, nothing requires the module): drag = mouse-parity swing, hold past a 60px band = the rim-pin
  analog, lift = zero forever. Gated by a PARITY ORACLE (summed deltas == displacement × gain).
- **Ladder: Tier-4 125/125 · rojo PASS · luau-lsp 0 NEW · selene UNAVAILABLE(404).** `updraft` is up to date
  with origin apart from this session's commits (the older "~20 unpushed" note was stale).

**▶ CHAD'S PLAY (only he can judge this):** fly `ember_valley`.
① **The Stage-3a read:** as the fire closes on a grove, do the squirrels *scare you into re-routing* — does a
red flashing, frantically-hopping critter say "GET HIM FIRST" without you thinking about it? (Design gate:
"did you change your route to grab the panicking one first — without thinking?")
② **The disclosed tradeoff:** late-round, MANY halos go red at once — can you still tell a rare (gold/rainbow
chevron) from a common at scan altitude, or did the red wash out triage-by-value? If so the fix is small
(fear on the chevron's *pulse* instead of the halo's *hue*).
③ **The plant tell at PANIC** now flares tell-bright but RED — does the "about to catch" beat still read?
④ **Smoke (perf, behavior-preserving):** set `Fire.perfDiag=true` — fire seeds ~10s, the wall sweeps downwind,
a cut-off grove rings then balloon-lifts ~8s later, `[Fire] tick … ms=` stays sub-ms. **Any behavioral
difference at all in the burn = revert** (the perf change claims bit-identity).
⑤ **The roar (3c) — ⚠️ S44 CORRECTION: `Fire.roarAssetIds` is EMPTY (see ⑥ below), so the fire is
SILENT and the log line named here CANNOT print. The rest of this item is stale; ignore it.** ~~FIRST check Output for `[FireAudio] roar asset 1/3 LOADED`~~ (if every id failed, the fix
is in the warning — 30 seconds in the Toolbox). Then fly at the grove from >900 studs: silence → a swell from
~900 → a deep roar inside 200. Knobs: `roarFarR / roarNearR / roarGamma / roarPitch / roarMaxVol`.
⑥ **The roar's regression test:** crash into terrain *inside* the roar band — it must go SILENT during the
death window and be correct after respawn (this is the red-team BLOCK that was fixed). Also orbit at ~400 and
toggle Space free-look: the roar should stay steady (it is bird-anchored on purpose — camera-anchoring would
warble it as you pan).

- **⑥ B5 + B5a (after Chad's "we can worry about sounds later, lets build"):** the **squeak layer** is
  built and gated (cadence keyed to Stage-3a Danger — calm 7s / worried 3s / panic 1.2s, so the EAR learns
  triage like the eye) but **silent: `Rescue.squeakAssetIds` is empty**. **THE SAVED CROWD is LIVE**
  (`Rescue.savedCrowd=true`): delivered squirrels now stay on the meadow, arriving one per hop-beat with a
  gold pop, cheering for ~2s — "the crowd IS the scoreboard". Before this a delivered squirrel was
  `:Destroy()`ed and the whole effort evaporated.
- **⚠️ AUDIO IS PARKED, DELIBERATELY.** Three web-sourced fire ids failed three different ways — wrong asset
  type, privated by the 2022 purge, and one that loaded perfectly and turned out to be **music** (Chad: *"I
  didn't really hear fire, I heard music"*). A load gate proves an asset RESOLVES, never that it is the right
  SOUND, so **both id lists are empty on purpose** and the next id must come from someone who can PREVIEW it
  (Studio → Toolbox → Audio). Chad's *"didn't hear any squirrels"* was NOT a bug — squeaks were simply
  unbuilt. Both mechanisms are done and gated; they go live the moment an id exists.

- **⑦ CHAD'S CHIME FIX + B4.1 + the beat guard.** The catch chord now rings **once at a full 10/10 load**
  instead of on every squirrel (`RescueRules.catchChime`; `chimeEveryCatch=true` restores the old).
  **B4.1 solid trees is BUILT and INERT** (`Rescue.treeCollision="off"`): the "lethal tree" fear was
  structurally impossible all along — `nonLethalTerrain` already forces both crash gates to 1e9, so a solid
  tree is a graze-slide surface, never a killer. Flipping it to `"full"` also retargets the existing style
  meter onto tree-skimming for free. And the terrain oof no longer stomps a sacred beat (catch / crew catch /
  hop-off) — it is suppressed by withholding the hit, so no full-screen OOF over a GOTCHA.

**▶ TWO THINGS ARE WAITING ON CHAD (nothing else is blocked):**
1. **The Play** — Stage 3a + 3c are LIVE and unflown (checklist above). His verdict also decides whether Stage
   **3b** (world-dims-orange) is built or **CUT**: it is the only Stage-3 channel that can fight the legibility
   Stage 1+2 won, so if he reports the pressure already lands, that global-Lighting risk is never spent.
2. **A PREVIEWED SOUND ID** (or two): a fire crackle for `Fire.roarAssetIds` and/or a squirrel squeak for
   `Rescue.squeakAssetIds`. Preview it in the Toolbox, copy the id, paste it first in the list, Stop and
   re-Play. Both loaders print a per-id verdict, and the squeak one now REJECTS anything over 3s as
   "ambience or music, not a squeak".
3. **DRAG or TAP** — the one B7 question. *On a phone, should your finger MOVE the cursor ring (DRAG, the
   recommendation — P1 is already built for it) or PLACE it (TAP)?* His one word decides whether B7-P2's
   one-line seam ships the built adapter or a tap variant. **Nothing past P2 gets built until he flies it.**

**▶ NEXT (in order):** **B7-P2** proof-of-feel (one-line seam at `BirdController:2495` + a bare flap slider;
Studio Device-Emulator; CHAD GATE) → **B4** canopy collision + trails (unblocked, no assets, no feel gate) →
**B5** leap variety + saved-crowd + squirrel squeak SFX (same asset caveat as 3c — batch the audio decisions)
→ Stage **3b** ONLY if his Play says pressure is still missing → **PHASE C: C1 persistence + level track**
(Chad's "levels unlock" requirement) → C2 The Den → C2.5 critter casts (frogs) → C3 art pass.
Mobile note for B7-P4: S43's own perf gate sets the ceiling — the 30 non-shadow PointLights are the low-end
cliff and `Fire.maxVisualBurning` 30→12 is the ONE master dial (it moves flipbook + emitter + light
together); the fire SIM stays server-side so the burn is bit-identical.

---

## ▶▶ S42 (2026-07-21) — 🎉 THE FUN VERDICT: kid-legibility Stage 1+2 PASSED · road-ahead directives logged

**Chad flew the S41 kid-legibility build (halo critters + fire-reads-as-fire, live on `updraft` uncommitted)
and delivered the strongest verdict of the project:** *"EvC2026 is addictive and fun and it has levels to it.
Its actually fun!… Realizing times to go fast and when to slow down and dont forget to watch the clock…
Actually very happy with the latest progress. Need to shore it up, optimize, plan and build."*

- **Core loop CONFIRMED FUN** (catch → carry → bank vs the fire clock). Kid-legibility Stage 1+2 Play gate =
  PASSED. Don't re-litigate the loop. Memory: `project-fun-verdict-road-ahead`.
- **Kernel note of record:** slight kernel "incorrectness" (the tight mouse-curl beyond plane-realism) **is a
  feature** — never correct toward textbook aerodynamics. Memory: `feedback-kernel-incorrectness-is-a-feature`.
- **Chad's directives folded into `docs/MASTER-PLAN.md` §CHAD-DIRECTIVES S42:** ① LEVELS UNLOCK is a
  REQUIREMENT (Phase C is the flag) · ② squirrel SFX + music ENDORSED (B5 squeak + music polish — schedule,
  don't defer) · ③ mobile interest (B7 — run the Fable touch-design consult sooner) · ④ SHORE-UP/OPTIMIZE
  before piling on features · ⑤ "other mediums" = vision note only.
- **Ladder run on the pending Stage 1+2 diff:** Tier-4 was 102/105 — 3 stale-assumption failures in
  `firevisuals.spec` (tests assumed the config default was still `flameStyle="static"`; S41 flipped the live
  defaults to halo/flicker for Chad's flight, which he approved). Fixed by pinning those tests to an explicit
  `staticCfg()` (static/revert-gate coverage KEPT; live default stays flicker). Now **Tier-4 105/105 · rojo
  PASS · luau-lsp 0 NEW (pre-existing baseline only) · selene UNAVAILABLE(404)**.
- **⚠️ HYGIENE:** the Stage 1+2 batch (7 files + `docs/KID-LEGIBILITY-PLAN.md`) is UNCOMMITTED and was never
  ledgered by the prior session — the S42 ledger entry backfills it. Commit proposed (ASK-gated); `updraft`
  has ~20 unpushed commits — consider pushing.

**▶ NEXT (the road ahead, in order):** ① commit Stage 1+2 (+ push if Chad approves) → ② Kid-legibility
**Stage 3** (visceral urgency: squirrel Danger escalation, world dims, fire roar — docs/KID-LEGIBILITY-PLAN.md)
→ ③ **B5** leap variety + saved-crowd + **squirrel squeak SFX** (Chad-endorsed) → ④ **B7 Fable touch-design
consult** (design only; Chad decides) → ⑤ **B4** canopy collision + trails → ⑥ **PHASE C: C1 persistence +
level track** (Chad's "levels unlock" requirement) → C2 The Den → C3 art pass. Shore-up items to fold in:
perf-envelope check with flicker/plume live (§3.4), B6 FTUE before soft-launch.

---

## ▶▶ S41 (2026-07-17) — 🔁 master-loop resumed: plan audited/hardened · A0 · empty-map self-diagnosis · A6 smoke boot

**Chad:** *"keep building eagle rescue, fully autonomous, one component at a time, audit our vision and our plan, this
harness, everything with Fable… I am tired of testing broken game components."* Then flew and reported **"no squirrels
or talon animations."** All S41 work is **UNCOMMITTED, ASK-gated, ladder-green** (rojo PASS · Tier-4 13/13 · luau-lsp
17=baseline/0 NEW).

- **Fable VISION+PLAN+HARNESS audit** (rescue-gameplay-architect, model fable): vision INTACT, stabilize-first is the
  right answer to "tired of testing broken." **4 plan-text hardenings applied** (docs only): §3.1 **A2 amendment** — the
  plan's server catch-gate was TIGHTER than the live gate; a verbatim A2 extraction would resurrect bug 2c ("8-9/10
  don't count"); pinned the live formula as source of truth. + Gate-C-requires-B7 + A6 packet + A-RULE/B5 squeak.
- **A0 DONE:** `activeMission` "fox_on_the_hill" → "waterfall_meadow" (fox shelved; subsystem inert).
- **Empty-map self-diagnosis:** `populateSquirrels` now per-squirrel pcall + prints `[Rescue] populated N/15` → an empty
  map is a 1-glance Output verdict, not a test session. **Static sweep found NO code cause of "no squirrels"** (spawn/
  beacon/BuildSquirrel/enabled/dual-server all healthy) → almost certainly a **STALE/UNSYNCED Studio build**.
- **A6 Tier-4.5 smoke boot BUILT** (Chad-approved): `run-in-roblox` v0.3.0 launches Studio headlessly. **Hard limit
  found:** it's EDIT-mode/plugin-security (no Play/Run) → can't observe the live server round; repurposed to a
  REAL-ENGINE load+build gate (modules load + real models build — catches what lune's approximation misses). GREEN.
  It immediately caught a lune-vs-Studio discrepancy (see MASTER-PLAN A-FINDING). Live-runtime classes stay Tier 5 /
  a future Open Cloud packet. Run: `.\tools\Smoke-Boot.ps1` or `.\verify.ps1 -Smoke`.

**▶ UPDATE (S41 cont.) — PHASE A ≈ COMPLETE → GATE A.** Chad committed the S39-41 batch (Play-confirmed
`[Rescue] populated 15/15` — the "no squirrels" was a stale build) then said "keep going." The autonomous loop ran
the whole **A2 RescueRules keystone** (A2.1 module+35-test suite incl. parity oracle · A2.2 server consumes · A2.3
client consumes · A2.4 sticky-seat F3 fix) — each red-teamed CLEAR, Tier-4 35/35, real-engine smoke green, all
committed on updraft (NOT pushed). Client+server now share ONE catch/score/seat/phase module; the two-authority
gate-divergence bug factory is closed. **A3 (acquisition FSM) still queued; A4-remainder MOOT (fox shelved); A5 audio
DEFERRED (specced rule conflicts w/ the intentional shared-SFX_SWOOSH design — re-scope, don't reopen audio).**
**▶ S41 cont.2 — GATE A PASSED ("feels good") → PHASE B started, B1 COMPLETE.** The loop then designed + built the
fire: **B1 FireGrid** — a pure fire-cell-grid module (`src/shared/FireGrid.luau`) SIM-tuned to the §3.3 bands over 100
seeded rounds (front 5.2 studs/s, grove-threat 42%, cut-off 3.8, never total theft), Fable-designed + Fable-after-audited
(one fix applied: seed a fire LINE via seed-geometry, not crossFrac), + inert mission wiring (`ember_valley`; the shipped
round is byte-identical). Both commits red-teamed CLEAR, Tier-4 **48/48**, real-engine smoke green, committed on updraft
(UNPUSHED). Cut-off squirrels rescue on the existing non-lethal Ranger Balloon. **▶ NEXT = B2** (fire VISUALS — the
`burningCells` render layer + cut-off countdown ring; the fire becomes visible/flyable) → then **Gate B** (Chad flies
`ember_valley`: "did the fire change your route; did losing squirrels feel like triage, not theft?"). B1 design +
consults in `docs/rescue-consults/B1-FireGrid-design.md`; full detail in the ledger.
<!-- superseded Gate-A note below -->
**▶ (Gate A, now passed):** Chad flew ONE round to confirm nothing FELT different (Phase A was behavior-preserving) + the
F3 seat fix. The 10-point checklist is at the top of the current ledger block (`.loop/rescue-phase0/state.md`).
After Gate A: push (if wanted) + Phase B (the fire round) or A3. Deferred-to-push per SOP.

---

## ▶▶ S40 (2026-07-15) — 🗺️ THE MASTER PLAN + /master-loop (READ THIS FIRST — new work model)

**Chad's directive:** *"stop chasing bugs / go back to the drawing board / create the master plan / automate the
build, Opus where it saves tokens, keep it tunable."* Delivered (docs + harness only — ZERO game-code edits; the
S39 batch diff is untouched):

- **`docs/MASTER-PLAN.md` — the work queue of record** (supersedes the COLD-START queue below + `program.md`'s
  item list). Phases: **A STABILIZE** (Lune Tier-4 headless tests + `RescueRules` pure-module extraction — grounded
  in a 14-bug autopsy: ~70% of all playtest churn was headless-testable logic) → **B THE ROUND** (fire-cell grid,
  simulation-tuned before it renders; crash→bounce; trails; FTUE; touch=B7 CHAD-GATED) → **C THE LEVELED GAME**
  (persistence, level track, The Den, art pass) → **D META**. Includes the numbers workbook (catch-gate chain,
  acorn economy → level thresholds, fire-spread math) — derived AND asserted by headless SIM once A1 lands.
- **Headless verification PROVEN:** Lune v0.10.5 (bootstrapped in `tools/bin/`, gitignored) ran the unmodified
  `FlightPhysics`+`GameConfig` 200 frames, exit-code gated. Loader pattern on record in the plan §2 + the S40
  feasibility report. This becomes verify.ps1 **Tier 4** (packet A1).
- **`.claude/skills/master-loop/SKILL.md` — the executing harness** (/master-loop): per packet = design (Fable,
  per the plan's `[model:]` tags) → implement (OPUS subagents — Chad's token policy) → red-team → ladder → ledger →
  ASK-gated checkpoint. Stops at phase gates / Chad decisions / LOCKED-spec risk. Plan is Chad-editable live.
- ⚠️ Known config/intent mismatch: `activeMission="fox_on_the_hill"` vs fox SHELVED → packet **A0** (blocked until
  the S39 commit lands, to keep diffs separate).

**▶ NEXT:** Gate 0 = Chad flies the S39 animation batch (below) → approves the S39 commit (prepared) + an S40 commit
(plan + skill + this block) → then run **`/master-loop`** and Phase A executes autonomously.

### ▶ S40 VISUAL-QUALITY (2026-07-17) — Chad set a QUALITY BAR; the machine now enforces it
Chad flew S39 and rejected it: *"all the talons do is change angles… how does an eagle catch something in talons?
Also… its just a light cylinder. I dont even see squirrels. This is supposed to be an autonomous programmatic build.
It needs to have quality standards before I judge it."* Root cause both bugs reached him: S39 used a Fable CODE-audit
as the visual read — code can't see pixels. Response = build a real VISUAL gate + fix both, all machine-verified:
- **QUALITY GATE (the meta-ask):** @lune/roblox builds the REAL BirdBuilder models headlessly →
  `tests/models.spec.luau` (squirrel visible/non-degenerate; **beacon-must-not-occlude-squirrel**, teeth proven —
  the S39 beacon FAILS it) + `tests/talon.spec.luau` (**grasp-closure gate**: forward-kinematics on the joint chain
  asserts the fist OPENS→CLOSES→CONVERGES + rest-pose preserved; a rotating paddle fails by construction). Nothing
  structurally broken/invisible reaches Chad again.
- **FIX 1 — squirrels VISIBLE:** the S39 beacon was a fat opaque 110-tall column centered +40 (base -15) that
  ENGULFED the squirrel. Now ONE config source (`GameConfig.Rescue.beaconWidth/Height/beaconBaseY`), a THIN beam
  ABOVE the head (+8), and the client fades it to invisible up close (transparency-only; no more per-frame fattening).
- **FIX 2 — a REAL talon grasp:** Fable-designed articulated rig (14 Motor6Ds: split toes + hallux, open→wrap→clench),
  Opus-implemented, gate-verified (open 1.09 → closed 0.27, a 4× collapse). The gate caught a curl-sign inversion
  before Chad ever saw it. Gated `Rescue.talonAnim` (false = instant revert).
- **Verify:** Tier-4 13/13 GREEN · rojo-build PASS · luau-lsp 0 NEW (17 = baseline). UNCOMMITTED, ASK-gated.
- **▶ CHAD'S PLAY (the only thing the machine can't judge — beauty/feel):** ① fly low over squirrels — do you SEE
  them now (animated, not a cylinder)? ② on a catch, does the open hand read in slow-mo and the fist read as
  GRABBING the squirrel (registration = `TALON_LOCAL`; gate proves the fist closes, not where the squirrel sits)?

### ▶ S40 A1 (2026-07-17) — 🟢 Tier-4 headless testing is LIVE (first master-loop packet, commit-ready)
Ran `/master-loop` on Chad's "continue to build … programmatically looping with fable consults." Under Gate 0
(S39 batch unflown), the only Gate-0-safe packet is **A1** — pure tooling, all-new files + a `verify.ps1` edit
(not in the S39 diff), machine-gated, foundation for the whole STABILIZE phase. **DONE + GREEN:**
- `tools/Bootstrap-Lune.ps1` (pins Lune v0.10.5; `tools/bin/` gitignored) · `tests/_loader.luau` (runs the
  UNMODIFIED src/shared modules outside Roblox) · `tests/_harness.luau` · `tests/kernel.spec.luau`
  (spawn/glide/flap + **no-NaN storm, 200 frames, Eagle+Crow**) · `tests/run.luau` · `verify.ps1` **Tier 4**
  (`lune run tests/run.luau`, exit-gated, UNAVAILABLE-degrading).
- **Ladder:** rojo-build PASS · **Tier-4 PASS 5/5** · selene UNAVAILABLE(404) · luau-lsp = documented baseline
  ONLY (A1 edits no `src/` → 0 NEW). The gate has teeth (a real bug produced 5 FAILs + exit 1 mid-build).
- **A1 commit is prepared + separable** from the S39 game-code commit (no shared files). Self-red-team CLEAR.
- **STOP = Gate 0:** every remaining Phase-A packet (A0 config flip, A2 RescueRules keystone, A3 acquisition FSM)
  refactors/depends on S39-dirty files → they unblock only once the S39 commit lands. Fly S39 → commit → the loop
  runs A0→A2→A3→A4→A5 autonomously (A2 lands with its regression specs, gated by the now-live Tier 4).

---

## ▶▶ S39 (2026-07-15) — 🎬 ANIMATIONS PASS built (supersedes S38 CLOSE's "NEXT")

**Chad's directive:** *"build out the games animations now. Forget the fox for now. I want eagles talons (use fable
for this) to be animated when catching squirrels. Also give me animated squirrels jumping to be helped."* + three
PROCESS asks. **All built, build-GREEN, Fable-bracketed (before+after), UNCOMMITTED on `updraft`. One commit prepared,
ASK-gated. This is an ANIMATION BATCH awaiting Chad's Play.**

**Process fixes (Chad's asks) — DONE:**
- `.claude/settings.json`: `Bash`+`PowerShell` broadly allowed (git commit/push still `ask`) → the autonomous loop no
  longer prompts for bash; commit still asks.
- `program.md`: **ANIMATION-BATCH exception** to the FUN-GATE (cosmetic anim/visual work is NOT a per-item Play gate —
  build the whole batch, Fable audits stand in for the feel-read, STOP for Play once the batch is ready). **🦊 FOX
  SHELVED + dropped from the queue** (Chad "forget the fox"). Fable before/after audits codified as loop steps 2 & 5.

**What landed (the batch — cosmetic Motor6D presentation, kernel/camera/aim/CS all untouched):**
- **#16a EAGLE TALON CATCH ANIM.** `BirdBuilder` eagle legs rewritten as a Path-A rig (per side: `<Side>HipJoint` +
  `<Side>FootJoint` Motor6Ds, world-pivot form; a new `Foot` hub; toes weld to it). New `BirdBuilder.AnimateTalons`.
  Driven from `stepCatch`: REACH down-and-forward + toes open during the leap → GRAB (clench) on the pomf → re-TUCK
  during the climb. Rest pose (`Transform=I`) byte-identical to the old static weld; only the possessed eagle is
  driven (crows/riders/other birds unchanged). Gated `GameConfig.Rescue.talonAnim=true`.
- **#16b SQUIRREL JUMP ANIM.** New `"leap"` pose in `PoseSquirrel` (athletic push-off → arms reaching overhead for
  the talons), replacing the static `"starfish"` in both the sacred and crew leap branches.
- **#16c DROP THE ICONS** (Chad "drop the icons lets go with animated squirrels"). Removed the floating "🐿️!" emoji
  BillboardGui from stranded squirrels (`RescueServer.buildBeacon`). **🐞→✅ REGRESSION FIXED (S39 cont.2):** Chad
  "map is empty / no squirrels" — Fable-5 diagnosed it was NOT a crash; the deleted billboard was `AlwaysOnTop` +
  constant-pixel + 1400-stud, the ONLY long-range/through-canopy read → squirrels spawned but were invisible from the
  air. FIX: the beacon is now a BRIGHT TALL pulsing neon SHAFT (server pillar 3.2 wide × 110 tall, transp 0.15, center
  +40; client tell-loop idle/tell/frantic all widened + held tall — the client overrides the beacon each frame, so
  BOTH had to change). Emoji icon stays gone; a light shaft is the "fly to the glow → see the animated squirrel" read.
  If still hard to spot: raise height / lower transparency, or re-add a non-emoji dot. Studio check:
  `print("SQ:", #workspace.Squirrels:GetChildren())` → ~10-11.

**Fable-5 "after" audit = NOTES (no BLOCK/REVISE):** faithful to spec, pivot-math verified (valid single-root tree,
no cross-through, ScaleTo holds). **One WATCH = Chad's-Play call, deliberately NOT pre-tuned:** `TALON_LOCAL` (where
the squirrel freezes on contact) sits a touch aft of the clenched feet → the grab could read slightly ahead of the
squirrel (masked by the feather burst + hit-stop + climb). Fix if it reads off: nudge `TALON_LOCAL` forward/down or
raise the clench pull-back. Full checklist + revert in `.loop/rescue-phase0/state.md` (S39).

**▶ NEXT:** Chad flies the S39 animation-batch checklist (does the GRAB land inside slow-mo? does the JUMP read?) →
keep/nudge the one registration knob → commit. Then the deferred queue (music polish · sticky per-rider seats F3 ·
feel-knob values · Fable Packet-04). **Autonomous loop:** `program.md` #16 done; fox shelved.

---

## ▶▶ S38 CLOSE (2026-07-15) — (superseded by S39 above for "NEXT"; audio/fox context still valid)

**All committed on `updraft` (NOT pushed). HEAD = `17c3deb`.** Fox mode is LIVE (`GameConfig.activeMission = "fox_on_the_hill"`). `audioDiag` OFF.

**What landed S37→S38 (all Chad-played + committed):**
- 🔊 **THE FLAP-AUDIO SAGA IS CLOSED.** After ~6 patch attempts, root causes were: the WIND loop reused the flap
  sample (pulsed like flapping), the sample never stopped (rang for seconds), AND the music heartbeat at 8-10 was a
  low thump that "sped up" (read as flapping). Definitive fix (Fable-5 audit): the flap is now a **STATELESS
  PER-FRAME PROJECTION** — one looped Sound, never Stopped, `Volume = (flapVolBase+flapVolPow·pow)·(eff·foldFade·exert)·am`
  recomputed each frame → silence is arithmetic, "persists after stop" is impossible. **DO NOT reintroduce a
  triggered/timer flap sound, and NEVER loop `SFX_SWOOSH` for wind/music (it pulses like flapping).**
- 🎵 **MUSIC = carry-driven, jingle ONLY at a full 10/10** (was delivered+carry, which ratcheted up + beeped after
  delivery). Build layers removed. Wind = a smooth low speed-rush (windMaxVol 0.5). Chad-confirmed better.
- ⏰ **FAST-TEN TIME BONUS** revealed at the perfect-10 delivery (banked; tallied at round end). 🏁 **ROUND-OVER
  SCREEN** (acorns count up, 8s) for EVERY round. 🛎️ **BUZZER GRACE** (`phase="grace"`, 4s) so a delivery made just
  before 0:00 still counts + its ceremony finishes. Carry count bumps immediately on catch (counts in-flight).
- 🦅 **HUD** (S37): SPD/ALT + AoA + HP/FLY bars hidden in rescue; flap indicator + 🐿️ count bottom-center.

**🦊 THE FOX — BUILT + Chad-FLOWN: "the fox works but I don't really see the point of it yet."** The mechanic is
technically correct (patrol → grove flare → frantic-but-catchable → scatter = time cost; beacon-visible; inert-by-
default). **The GAP is PURPOSE/stakes: it doesn't yet change how you play or reward beating it.** ▶ If the fox is
resumed, that's a DESIGN pass (why should the player care? — a real reward for beating it, a real cost for losing,
or it gates/pressures the perfect-ten). NOT a code bug. Consider `rescue-gameplay-architect` on the purpose.

**⏸️ DEFERRED (Chad's call):** change flap from the sticky Shift/Ctrl throttle to a **HOLD-LMB "flap or no flap"**
for kid-simplicity (LMB free in rescue; touches LOCKED CS-7 → grep the registry + red-team; also makes the audio
trivially correct since eff→0 on release).

**▶ NEXT (Chad, S38 close): "start on something else with a clear context."** The audio is DONE — do not reopen it.
Options: the FOX PURPOSE design pass · rider-growth/Packet-04 meta · Phase-1 world (real canopy collision) · the
hold-LMB flap · or a fresh Chad direction. Full turn-by-turn detail in `.loop/rescue-phase0/state.md` (S37/S38 cont.1-10).

---

## ▶ COLD START — Session 32 (2026-07-13): 🦅🔥🐿️ EAGLES TO THE RESCUE — Phase-0 PLAYABLE SLICE BUILT (build-green, red-teamed, UNPLAYTESTED)

**THE GAME IS NOW "EAGLES TO THE RESCUE."** Chad greenlit the direction (see `docs/EAGLES-TO-THE-RESCUE-plan.md`, the creative bible) and, while away, gave FULL AUTONOMY to build the Phase-0 playable slice in the sandbox with a Fable consult at every turn. Done this session. **This SUPERSEDES the UPDRAFT proximity-flight loop below (Chad flew UPDRAFT, called it DULL) and combat (shelved).** Read the bible + `docs/rescue-consults/PACKET-01/02` (Fable design specs) + the `project-rescue-phase0` memory FIRST.

**One line:** dive a hero eagle under a burning forest; terrified squirrels LEAP for your talons in slow-motion (always caught — skill is the APPROACH, never the grab); carry them on your back UP the waterfall updraft to safety. Non-lethal, cute, ages 5-20. Built entirely AROUND the LOCKED flight kernel/camera.

**✅ CHAD PLAYTESTED THE SLICE (S32, 2026-07-13/14) — the direction WORKS.** Verbatim: *"okay its good I like the little chime, its a little hard to snatch the squirrels, a bigger map and bigger catch trigger would be good, of course the squirrels can jump into the eagles talons. And we can animate them crawling up to his back lets say he can carry 10 squirrels that latch onto him for a later phase."* So: the catch chord + the jump-into-talons LAND. Applied his two asks (see queue #0). His carry-10 + crawl-up-and-latch idea = a LATER PHASE item (#9).

**▶ STANDING LOOP ORDER (Chad-directed S32): RUN THIS AS A LOOP — do not wait for instruction.** Invoke **`/evc-loop`** and work the RESCUE QUEUE below ONE item at a time (propose → LOCKED-spec gate → red-team → build → `verify.ps1` green → log the ledger → checkpoint commit-ready), **looping until the queue is exhausted or Chad returns.** Everything except FUN can be built/tuned autonomously; **FUN needs Chad's Play** (the gate). Do NOT drift back to combat. Build AROUND the LOCKED kernel/camera always. A Fable consult packet per turn (`docs/rescue-consults/`) is the standing method.

### ▶ S33 (2026-07-14): QUEUE #1-#8 BUILT + CHAD PLAYTESTED — committed. NEXT = the catch/latch animation.
A cleared-context agent ran `/evc-loop`, built queue **#1-#8** (each a verified checkpoint), Chad played
it, one fix landed, and it's **committed on `updraft`** (two commits per the red-team split). Detail per
item in `.loop/rescue-phase0/state.md` (Session S33). luau-lsp = documented baseline ONLY (0 new) across
the batch; CS-1..9 untouched (only client presentation + `RescueServer` world-gen + Rescue config).

**✅ CHAD PLAYTESTED S33 (2026-07-14):** *"its good! I like the squirrels, they need some work but so far
so good… It zooms in too much when you catch a squirrel, we need it to not do that… we can have an
animation later where the squirrel jumps to you if you fly close enough, then eagle catches with talon
then squirrel scrambles up to the eagle's back… The waterfall mechanism worked."*
- ✅ waterfall/deliver works; squirrels liked (gray-box polish deferred).
- 🔧 **FIXED the catch zoom:** `camPullIn` 0.15→0 + `camFovDelta` -5→0 (both read as zoom); slow-mo now =
  desat + cant + hit-stop, no zoom. Committed.
- **▶ NEXT (Chad's stated vision — the headline next task):** the CATCH/LATCH ANIMATION — squirrel jumps
  to you when close → eagle catches with TALON → squirrel SCRAMBLES UP to the eagle's back. This is a
  catch-beat presentation upgrade + exactly queue **#9 (crawl-and-latch)**; the #2 living-rider system is
  the built substrate. Plus general **squirrel-model polish**. Then the remaining feel-knob values + #10.
- Note the #GATE report-back (§E) is still worth capturing on the next play (saves/round, tell seen, etc.).

### ▶ S34 (2026-07-14): #9a CATCH-AND-LATCH ANIMATION BUILT (build-green, red-teamed CLEAR, UNPLAYTESTED)
A cleared-context agent ran `/evc-loop` and built Chad's headline S33 vision — the scramble-up. Previously
the caught squirrel TELEPORTED from the talon onto its back seat at the hit-stop; now it visibly SCRAMBLES
up the eagle's flank over ~0.5s (`Rescue.climbDur`) before latching in as a living rider.
- **Change (client rescue PRESENTATION only — NO control/camera/kernel/CS/balance touch):** new
  `"scramble"` pose in `BirdBuilder.PoseSquirrel` (hand-over-hand climb); `stepCatch`'s post-contact `else`
  branch rewritten into a real-time CLIMB phase that flies the presentation squirrel along a quadratic
  Bézier IN THE EAGLE'S LOCAL FRAME (talon → `seatLocalPos(catch.seatIndex)`, control point out to the
  flank so it hugs the body), posed `"scramble"`, THEN hands off to the #2 living-rider system; new
  `seatLocalPos`/`bezier3`/`TALON_LOCAL`/`SCRAMBLE_FREQ` helpers; landing hop halved (climbs in vs drops in).
  New `GameConfig.Rescue.climbDur = 0.5`.
- **Red-team `aec63756fe450f097` → CLEAR** (no BLOCK/REVISE). `seatIndex`-stability + env-stranding attacks
  both FAIL (code correct); CS-1..9/aim/camera/kernel/flight-numbers untouched; teardown mid-climb leaks
  nothing. 2 NOTEs for Chad: bundled hop-halving (`RIDER_HOP_DUR*0.5`); ~+0.3s longer catch-active window
  (PvE-only, not a 1-v-4 lever, tunable via `climbDur`).
- **Verify:** rojo-build PASS; luau-lsp = documented baseline ONLY (0 new); selene UNAVAILABLE (404). Green.
- **Git:** #9a committed `4aa3d0b`; **#9b CARRY-10 also built + committed this session** (Chad: "go ahead") —
  `carryCapacity` 3→10 + grid-packed seats (`SEAT_COLS=4`, stacking toward the tail). Both on `updraft`, NOT
  pushed. Ledger detail + the 6-point playtest checklist: `.loop/rescue-phase0/state.md` (S34).
- **▶ NEXT:** *(superseded by the S34-LATE block below — Chad returned, the Growing-Crew direction landed,
  and Packet-03 now sequences the queue.)*

### ▶ S34 (cont.): 🐞 ACQUISITION RACE FIX — intermittent "unplayable on replay" (build-green, UNPLAYTESTED)
Chad hit an INTERMITTENT bug: *"good the first try then the next two… moves all around, eagle wavers, cant
control the mouse aimer, unplayable."* Root cause = the client sometimes never ACQUIRED/possessed its eagle,
so `onFlightStep` early-returned (`:2110`) → no mouse-lock, no camera, no flight loop → default camera spins
+ free mouse + server-driven waver. The hole was in `trackModel`: it attached the possession watcher only if
`OwnerUserId` was ALREADY ours and only watched `Possessed` — but attributes replicate separately from the
Model, so a late `OwnerUserId`/`Possessed` set attached no watcher and never re-triggered acquire. This is
the known-fragile acquisition path (integration task #1), NOT the S34 rescue-presentation edits.
**Fix (client lifecycle only — no control/kernel/aim/camera-LAW / CS touch):** `trackModel` watches
`AttributeChanged` unconditionally on every bird, re-acquiring on `Possessed`/`OwnerUserId`/`NetOwner`;
`reacquire` wrapped in `pcall` (+ `warn("[EvC] acquire() error…")`) with an `acquiring` flag; a 0.5s BACKSTOP
poll self-heals any residual race (gated on `not acquiring` so it can't restart an in-flight NetOwner wait).
Build-green, luau-lsp baseline-only. **▶ Chad: fly 3-4 times (Stop between) — it should acquire EVERY time.
If it ever recurs, check Output for `[EvC] acquire() error`.**

### ▶ S34 LATE (2026-07-14, Chad present + directing): THE GROWING CREW — 5 more commits (all build-green, red-teamed where risky, UNPLAYTESTED unless noted)
Chad returned mid-S34, approved the visual pass, riffed a major vision (verbatim in
`docs/rescue-consults/VISION-S34-chad.md`) → Fable consult produced **`docs/rescue-consults/PACKET-03-growing-crew.md`**
(the sequenced roadmap: crew catch → math delivery → music → fox mission → helper birds → fire+cannon). Landed:
- **`b154a47` bigger eagle + squirrels, slower/heightened climb — Chad-APPROVED in Play.** `Visual.birdScale`
  1.8→2.3, `squirrelScale`→4.4, `climbDur`→1.1; talon/seat offsets now multiply by birdScale (fixes embedded seating).
- **`6c262f4` PACKET-03 docs** (the Growing-Crew design + Chad's raw vision).
- **`62bc7a0` staged DIVE-WING FOLD — Chad-LOVED ("its wonderful").** `AnimateWings` unfolds through smooth staged
  sweep/anhedral keyed to nose-down depth; cosmetic Motor6D.Transform only, kernel byte-identical.
- **`77780f4` ENERGY BONUS** (Chad's locked plan item): high-closing-speed catches now SCORE (extends the built
  SWIFT/BLAZING tiers into `pts = base × rarity × style × energy`), kid-visible energy→points readout.
- **`fea86a1` BOOM-AND-ZOOM REWARDS:** hidden speed-scoop (`scoopSpeedGain` widens effRadius with speed — a quiet
  facilitator) + **COMBO x2..x6** (server-authoritative streak inside `comboWindow=4s` multiplies catch score;
  pulsing COMBO banner) → "bank now or keep the chain?" is a real choice.
- **`685127b` CREW CATCH v1 (Packet-03 headline slice; fixes Chad's live bug "not all gotchas are being counted").**
  The single-slot `not catch` lock in `scanSquirrels` silently dropped chained triggers during the ~2s beat. Now
  catches OVERLAP: the sacred slow-mo TALON catch is byte-unchanged and stays the one-at-a-time hero beat; a
  squirrel triggering while it's busy becomes a **CREW CATCH** — LIGHT grammar (no slow-mo/camera env), ~0.42s arc,
  settles straight onto the back ("the crew hauled it aboard"). Same authoritative `CatchSquirrel` → scores + feeds
  the combo. Red-teamed CLEAR (`a466c6bed31a21866`). NOTE for Chad: crew catches skip the #9a scramble-up by design —
  confirm it reads as "hauled aboard," not a pop-in.
- **▶ NEXT (Packet-03 order): rider GROWTH (+COURAGE — crew-catch survivors grow, cap 1.25) to complete slice 1,
  then slice 2 MATH DELIVERY (skip-count hop-off → n² multiplication sentence → PERFECT-TEN time factor — replaces
  flat `deliverBonus n×25` at `RescueServer:538`), then music escalation / fox mission per the Packet-03 table.**
  *(→ done in S35, below.)*

### ▶ S35 (2026-07-15, autonomous loop): docs repaired + #12 RIDER GROWTH + #13 MATH DELIVERY BUILT (build-green, red-teamed w/ fixes, UNPLAYTESTED, **UNCOMMITTED**)
A cleared-context agent found the S34-late commits undocumented (that session closed without a ledger/HANDOFF
write), reconstructed the trail (this box, the ledger, memory), then built the next two Packet-03 slices:
- **#12 RIDER GROWTH (P5 "courage is visible"):** every rider already aboard grows a step when a CREW CATCH
  lands (`Rescue.courageStep=0.08` × `courageStages=3` cap ×1.24; eased `Model:ScaleTo` over 0.35s + proud
  re-settle hop + seat lift so grown riders sit ON the back). Client presentation only. "+COURAGE" micro-stamp
  deferred (stamp discipline).
- **#13 MATH DELIVERY (Packet-03 §3, all 3 layers):** SERVER — deliver pays **n × n × acornValue(10)** (n²
  acorns; `deliverBonus` retired), PERFECT-TEN tracker + TIME FACTOR ×2/×3(≥30s left)/×4(≥60s) applied once at
  `endRound`, round total QUANTIZED to whole acorns first so the finale sentence is exactly true (red-team B1).
  CLIENT — deliver = a HOP-OFF CEREMONY (one rider per `hopBeat=0.35s`, rising note, tally ticking i×n — each
  hop one ROW of the n×n array, 7…14…21…49) → the sentence card "🐿️ n × n = 🌰 n²!"; HUD score now in 🌰 ACORNS
  (points÷10); results shows "PERFECT TEN!" + "🌰 pre × TIME FACTOR f = 🌰 fin!". Gates: no catches/deliver/
  rider-reconcile during the ceremony; deliver phase-gated (red-team R1); teardown clears it.
- **Red-team `a7c1563d4d5e1fe9f`:** 1 BLOCK (false finale math → FIXED by quantize) + 2 REVISE (phase gate →
  FIXED; commit split → the git plan) + notes (grown-pile squish is Chad-gated; a triage-race sentence-off-by-one
  is a logged Phase-0 transient). Everything else survived attack; CS-1..9 untouched.
- **Verify:** rojo-build PASS; luau-lsp = documented baseline ONLY (0 new); selene UNAVAILABLE (404). Green.
- **Git: UNCOMMITTED — a TWO-commit plan (growth, then math) is in `.loop/rescue-phase0/state.md` (S35),
  awaiting Chad's approval (ASK-gated).** The S35 playtest checklist (7 points — growth read, skip-count,
  sentence readability, PERFECT-TEN in-head verification, ceremony teardown, CS re-confirm) is there too.
- **▶ NEXT: #14 music escalation (autonomous), #15 mission framework + THE FOX (Chad's Play gates the fun),
  and Chad flies the S35 checklist → §E report-back → Fable Packet-04.**

### ▶ S35b (2026-07-15): Chad PLAYTESTED → 2 feedback fixes BUILT (build-green, red-teamed REVISE→fixed, UNPLAYTESTED, UNCOMMITTED)
Chad's verdicts: ✅ combo ×6 works, ✅ hop-off skip-count + acorns "all good", ✅ CS re-confirm; growth visible.
⚠️ "around 7 to 10 alot of the catches dont get counted still" + the crew catch "should be squirrels".
- **🐞→✅ CAPACITY SILENCE (the "not counted" root cause):** at 7-9 riders + catches in flight the eagle is
  FULL → `canCatch` false → a real catch line gave NOTHING (and squirrels still planted no-payoff TELLs).
  Now: squirrel always waves "come back!", a debounced **"WINGS FULL! 🐿️N/10 → carry them to the
  WATERFALL!"** stamp explains why (suppressed while any catch beat is live), tells gated on real room.
- **✅ CREW CATCH v2 ("should be squirrels"):** the newb now leaps to the BACK SEAT (live-seat arc, not the
  talon); the tail-most riders lean out ARMS-WIDE (new `"reach"` pose), it lands in their arms, the whole
  crew CHEERS, and **"CREW CATCH! +1"** pops on its own channel by the carry meter — every catch visibly
  counted. Growth (#12) fires on the same beat: the ones who catch, grow.
- **Red-team `a3228414e496a4539` REVISE → F1/F2/F4 fixed; F3 = known cosmetic one-seat pop when crew+sacred
  overlap (playtest gate; fix = sticky per-rider seats, follow-up). CS-1..9/kernel/balance clean.**
- Also noted: talon-grab micro-anim = future queue item; slow-mo+climb still play on every CHAIN-OPENER
  (sacred) catch — if an isolated catch shows no climb, that's a bug to report.
- **Git: still UNCOMMITTED** — 4-commit plan (or one combined, Chad's call) + the S35b playtest checklist in
  `.loop/rescue-phase0/state.md`.

### ▶ S35c (2026-07-15): 🐞→✅ THE REAL "not counted" BUG — double-fire on the same squirrel (CLAIM GUARD)
Chad's decisive repro: *"went down from 9 to 8 after a catch"* = a phantom rider reconcile-trimmed = a
silent server reject. **Root cause = a Crew Catch v1 REGRESSION:** no trigger ever CLAIMED the world
squirrel, and the server's Destroy replicates a frame late — so the frame after a sacred catch fired, the
SAME squirrel re-triggered as a crew catch (same id), the server rejected the duplicate, and the client's
second (ghost) squirrel became a phantom rider. The old `not catch` lock had accidentally prevented this;
v1 removed it. **Fix:** `claimedIds[id]` stamped first-thing in BOTH triggers + the scan loop skips claimed
squirrels (`Rescue.claimTTL=3` frees a genuinely-rejected squirrel). One fire per squirrel, ever. The ghost
double-squirrel was likely Chad's "something strange when a crew catch fires." Build-green (0 new),
self-red-teamed, UNPLAYTESTED. **Gate: carry only ever +1 per squirrel, never down except deliver.**

### ▶ S35d (2026-07-15): ✅ CHAD PLAYTESTED — PASS. COMMITTED.
*"flew it it seems good got all my squirrels ! lets commit here and handoff to the next agent?"* — the
claim guard holds; the whole S35 batch (growth · math delivery · full-feedback · crew catch v2) is
Chad-approved and **committed on `updraft` (2 commits: server scoring, then client/config/UI+docs). NOT
pushed.** Sound-id finding from his Output: **`rbxasset://sounds/swoosh.wav` = "Asset is not approved"
(×70)** → pomf/hup/whip are half-silent; the PING chime resolves. → swap SFX_SWOOSH in the audio pass.
**▶ NEXT AGENT: run `/evc-loop` → #14 MUSIC ESCALATION (Packet-03 slice 3, autonomous — count-to-ten
stems + crew chatter; include the SFX_SWOOSH replacement) → #15 MISSION FRAMEWORK + THE FOX (slice 4,
Chad's Play gates the routing fun). Known cosmetic follow-up: sticky per-rider seats (red-team F3 one-seat
pop). Then Fable Packet-04 off Chad's next §E report.**

### ▶ S36 CLOSE (2026-07-15, autonomous program.md loop via /agent-builder + Fable-5 audits) — READ THIS FIRST
Launched the **`program.md`** loop (registered + committed `c926b25`), worked the queue with **Fable-5
(model: fable) audits** bracketing the build work, then handled a run of Chad playtest feedback.
**COMMITTED on `updraft` (NOT pushed):**
- `424868e` **#14a** SFX_SWOOSH → `rbxasset://sounds/action_falling.ogg` (fixes the ×70 "Asset not approved").
- `46473a9` **#14b MUSIC ESCALATION** — `updateMusic`/`fadeMusic`: gray-box swell on `delivered + #riders`
  (wind→pizzicato@1→rhythm@4→brass@7→heartbeat@8-9, tempo tightening) + crew-choir chirp scaling. Pre-audit
  GO-WITH-CAVEATS, post-audit KEEP.
- `e39c8c9` **#15a MISSION-FRAMEWORK SCAFFOLD** (inert) — `GameConfig.Missions` data table + `Rescue.activeMission`
  selector + `RescueServer.resolveMission()` routing hazard/deliver/placement through `mission.*` (fallbacks =
  current literals → `waterfall_meadow` plays byte-identical). Architect found THE FOX is a genuinely NEW
  server-AI subsystem (RescueServer has no flight loop) → fox is its own iteration (seam map in ledger S36).
- `1e85fba` **CATCH-GATE FIX (Chad-confirmed "got all my squirrels")** — the recurring "catches around 8-9/10
  don't count": a flag-gated diagnostic proved every drop was `REJECT:dist` (the big fast eagle 106-110 studs
  out when the catch reached the server, over the flat `triggerRadius*2.5=105` gate → client phantoms →
  premature "full"). Fixed with a VELOCITY-AWARE gate `triggerRadius*catchGateMult(3.5) + speed*catchGateLatency(0.25)`.
  Red-team CLEAR. `catchDiag` flag left in, OFF.
- `660f337` **COMBO "MULTIPLIES THE DELIVERY" (Chad-confirmed)** — combo no longer multiplies per-catch
  (silent); the PEAK combo of a load is banked and the deliver pays **n × n × combo** acorns; the sentence card
  reveals it ("n × n × 🔥C = n²C"), rendered from server-authoritative `deliverN`+`deliverCombo` so it can't
  lie (red-team B1 fix). Balance note for Chad's ear: comboMax=6 → a chained trip-of-10 pays ~12× a safe
  two-trip (knob `comboMax` if too dominant).

**UNCOMMITTED at close (tree GREEN, luau-lsp = baseline only) — pending Chad's Play + commit approval:**
- **Flight audio v4** (`GameConfig` wing/wind keys + `BirdController.updateWingSound`): flap whoosh + speed-scaled
  WIND layer. ✅ **S37: BOTH "flapping won't stop" bugs FIXED** (Fable-bracketed, red-teamed). (1) **flap-in-dive**
  — whoosh fades on a `foldFade` from `orientation.LookVector.Y` across the dive-wing-fold band. (2) **"turned
  down the flapping and it stayed"** — root cause: the sticky flap throttle HOLDS with no decay (LOCKED feature),
  so releasing Shift kept the S36 held-throttle whoosh going forever. Per a **Fable consult** the whoosh now
  follows an AUDIO-ONLY **exertion envelope** (Shift attacks τ0.10 / release decays τ0.20 → whoosh STOPS ~0.5s
  after you stop actively flapping; trigger-gated at `effortGate`, never cuts a playing stroke). **S37 cont.2:
  after Chad STILL heard flapping on turn-down, the Fable "maintenance beat" (soft cruise-hold whoosh) was
  REMOVED — it was the pattering he heard. Now exactly ONE flap-sound path, gated on actively holding Shift;
  not held → no flap sound.** **S37 cont.3 — THE ACTUAL WALL: after a 4th "still flapping" report, root cause
  found = the flight WIND LOOP, not the flap whoosh. `windSound` reused the flap sample (SFX_SWOOSH) on
  Looped=true, scaled to speed → it PULSED like wingbeats whenever fast / in a dive (indistinguishable from
  flapping). Fix = `windMaxVol` 0.38→0 (wind OFF). Now the ONLY whoosh is a real wingbeat while Shift held.**
  Restore speed-wind only with a DISTINCT smooth asset. Remaining continuous sound = the quiet low music
  rumble (`musicBed`/`musicWindVol` 0.10) — flagged; kill via `musicWindVol=0` if it also reads as flapping.
  Red-team F1 fixed (wind mutes on `teardownDrive`). Build-green. ⚠️ **Now needs Chad's Play**. Separable (audio = GameConfig + BirdController).
- **HUD declutter** (`GameUI` only): score→top-left, timer-only top-center, combo under it, instruction line
  auto-fades after first catch (S36 "spread to corners"); **S37 (Chad asks): rescue now HIDES SPD/ALT + ANGLE
  OF INCIDENCE + the HP/FLY bars; the FLAP throttle indicator moves to BOTTOM-CENTER; the 🐿️ carry count +
  crew-pop sit BOTTOM-CENTER just above it** (all clear the auto-fading control-hint line). UNCONFIRMED by
  Chad's eye. Cleanly separable (HUD = GameUI only). Commit note (F2): enumerate the bundled S36 HUD edits in the body.
- **REBIND to mouse thumb buttons: CLOSED** — Roblox can't read MB4/5; Chad chose KEEP Shift/Ctrl.

**▶ NEXT AGENT:** (1) ✅ flap-in-dive bug FIXED (S37) — let Chad fly audio v4 + the HUD (checklist in ledger
S37), commit both (2 commits by file). (2) Then **#15b THE FOX** — the next big queue item (new server-AI patrol subsystem;
`rescue-gameplay-architect` seam-map is in ledger S36: mirror `GameServer.updateAICrows`/Boids Y-locked, grove
flare + squirrel frantic/relocate P3, then `red-team-reviewer`, then Chad flies the routing fun). Then the §E
report-back → Fable Packet-04. **Music swell + combo balance are still Chad's ear to certify when he next flies.**

### ▶ RESCUE PHASE-0 QUEUE (work top-down in the loop)
- **#0 [DONE S32]** bigger trigger (`triggerRadius` 28→42) + easier snatch (`closingGateFrac` 0.40→0.30) + bigger map (`valleyRadius` 1000→1600, `treeCount`→68, `squirrelCount`→15). *(Chad's two asks — applied; he re-plays to confirm.)*
- **#1 [DONE S33] GROVES** (Fable §B5): `RescueServer.buildWorld` clusters perch-trees into `groveCount=4` groves (`grovePerchCount=5`, `groveRadius=130`, `groveMinGap=520`) + backdrop scatter; squirrels spawn ONLY on the 20 grove perches → catch chains + style continuity.
- **#2 [DONE S33] LIVING BACK-RIDERS** (Fable §C): per-rider breathing bob (off `flapPhase`) + lean + independent look-around + hop-and-settle on landing + a `ridedive` starfish-arms pose + `ride`-arm sway. Cosmetic, no rig change. *(Tail-flick/head-look via joints DEFERRED = a rig change → own item.)* #9's prereq now in place.
- **#3 [DONE S33 — structural half] SLOW-MO FEEL** (Fable §B2): the leap arc is FIT-ONCE at launch, correcting to the live talon only inside the converge window (snap hidden in the burst) → no per-frame homing. ⚠️ `slowmoScale` 0.25→0.45 is a Chad-gated feel knob, LEFT at 0.25 pending his Play.
- **#4 [DONE S33] TELL VISIBILITY** (Fable §A3): `tellLeadTime` 0.40→0.60 (≈78 studs warning) + a LOUD plant pose (arms cocked, deep crouch) + a beacon FLARE on the active tell.
- **#5 [DONE S33] BLAZING ESCALATION** (Fable §D): a per-catch "bigness" (tier+style) drives a bigger feather burst + bigger gold ring + GOLD/bigger GOTCHA + DEEPER slow-mo (env-scaled desat/camera, FOV-clamped).
- **#6 [DONE S33] STAMP SEQUENCING** (Fable §B4): GOTCHA(0) → tier+STYLE sub-stamp at +0.4s (STYLE only when >×1.5) → woohoo audio 0.5s post-snap-back. ≤2 visual stamps, always staggered.
- **#7 [DONE S33] FTUE SOFT-FAIL** (Fable §D): easier `ftueGateFrac=0.15` during the first catches + a "come back!" `waveBig` reaction when you enter the sphere too slow (no fail sound, never silence).
- **#8 [DONE S33] WAYFINDING** (Fable §D): while carrying ≥1, a faint gold `Beam` streamer arcs from the eagle toward the waterfall (diegetic compass, zero UI).
- **#9a [DONE S34] CRAWL-AND-LATCH ANIMATION:** the caught squirrel now SCRAMBLES up the eagle's flank from the talon to its back seat (real-time CLIMB phase in `stepCatch` + `"scramble"` pose + `Rescue.climbDur=0.5`), then latches in via the #2 living-rider system. Build-green, red-teamed CLEAR, UNPLAYTESTED. *(Chad's S33 headline vision.)*
- **#9b [DONE S34] CARRY-10:** `carryCapacity` 3→10 (moves both the server carry gate + client) + `seatLocalPos` reworked into a GRID (`SEAT_COLS=4` across the spine, the rest stacking toward the tail) so 10 riders pile on the back. Build-green, self-red-teamed, UNPLAYTESTED. *(Chad: "go ahead no need for later phase.")*
- **#11 [DONE S34-late] CREW CATCH v1** (Packet-03 slice 1 core) + energy bonus + combo x2..x6 + speed-scoop + dive-wing fold + bigger eagle — see the S34-LATE block above. UNPLAYTESTED except where marked Chad-approved.
- **#12 [DONE S35] RIDER GROWTH (+COURAGE)** — riders grow a step per crew catch witnessed (eased ScaleTo, cap ×1.24) + re-settle hop + seat lift. Build-green, red-team-covered, UNPLAYTESTED, uncommitted.
- **#13 [DONE S35] MATH DELIVERY** — n²-acorn deliver + hop-off skip-count ceremony + sentence card + acorn HUD + PERFECT-TEN quantized time factor. Build-green, RED-TEAMED (B1/R1 fixed), UNPLAYTESTED, uncommitted.
- **#14 [DONE S36] MUSIC ESCALATION** (Packet-03 slice 3) — gray-box swell crossfaded on `delivered + carry` progress-to-ten (wind → pizzicato@1 → rhythm@4 → brass@7 → heartbeat@8-9, tempo tightening) + crew-choir chirp scaling + the SFX_SWOOSH approved-id fix. Build-green, Fable-5 audited both ends (KEEP), UNCOMMITTED. **The SWELL is Chad's FUN gate** (listen checklist in the ledger S36).
- **#15 MISSION FRAMEWORK + THE FOX** (Packet-03 slice 4 — Chad's Play gates the routing-pressure fun).
  - **[SCAFFOLD DONE S36] mission framework:** `GameConfig.Missions` data table + `Rescue.activeMission`
    selector + `RescueServer` resolver routing hazard/deliver/placement through `mission.*` (fallbacks =
    current literals → `waterfall_meadow` is byte-identical to today). Inert-by-construction, build-green,
    committed. Flipping `activeMission` is the whole mission switch.
  - **[BUILT + FLOWN S38 — THE FOX #15b] ✅ built, committed, Chad-flown: "works but I don't see the point yet."
    The MECHANIC is done; the GAP is PURPOSE/stakes (a real reward for beating it / cost for losing). Next fox work
    = a DESIGN pass, not a bug. See the S38 CLOSE block at the top.**
  - _(historical build detail below)_ ✅ built + red-team CLEAR + Fable-5 bracketed, INERT-by-default.
    New server-AI patrol subsystem (2D kinematic seek — deliberately NO Boids/FlightPhysics import = strongest
    kernel-safety proof). `Missions.fox_on_the_hill` (all tunables in `hazard`); `BuildFox` rascal; RescueServer
    `stepFox` (den→approach→sit→return on ONE Heartbeat, phase-gated) + orange grove-flare + `Frantic=true`
    (separate attr → squirrels STAY catchable, you RACE the fox) + `relocateSquirrel` scatter (TIME cost, P3
    non-lethal); client renders frantic (fast pose + urgent beacon). **▶ Chad's FUN gate: set
    `activeMission="fox_on_the_hill"`, restart Play** — did the flare make you DROP your line and race there?
    Full detail + playtest checklist + tune knobs in ledger S38. Revert = `activeMission="waterfall_meadow"`.
- **#10 PHASE-1 WORLD:** real trunk/canopy collision + a dedicated valley that skips the combat `BuildMap` (currently kept as floor+backdrop); then line-riding style measures the canopy the player threads.
- **#GATE [needs Chad's Play — NOT loopable, DO THIS NEXT]:** fly the Packet-02 §A checklist → *"grin at the 3rd catch + push your luck for one more before the waterfall?"* + capture the §E report-back → Fable Packet 03. Also report which gray-box sound ids resolved (Packet 01 §E). This is the only step the loop cannot self-certify.

**What's built (branch `updraft`, UNCOMMITTED — build PASS, luau-lsp clean vs the documented baseline, red-teamed):**
- `GameConfig.Rescue` (all Fable numbers) · `Debug.aiCrowOpponents=false` (no combat crows) · `Updraft.enabled=false` (its line-riding scorer is now the rescue STYLE meter).
- `BirdBuilder.BuildSquirrel` + `PoseSquirrel` (gray-box bean-with-eyes; wave/plant/starfish/ride).
- **NEW `src/server/RescueServer.server.luau`** (mapped in `default.project.json`) — gray-box valley (trees + waterfall mesa + SOLID safe pad + updraft VFX), 11 beacon squirrels on perches, 2-min round + score + carry(3)/deliver, triage balloon-lift in the last 60s, own `RescueRemotes` folder. COEXISTS with GameServer (which still spawns + net-owns the flyable eagle; combat code untouched).
- `BirdController` rescue section — detection + 0.4s latched tell + ballistic arc-intercept catch (relative-velocity→0 IS the slow-mo, per Fable) + client slow-mo presentation (ColorCorrection desat + a PURE beat-time camera post-transform, identity when idle — CS-untouched) + feathers/POMF/hit-stop/GOTCHA + back-riders + waterfall deliver + style meter (reuses `computeProximity`).
- `GameUI` rescue HUD (timer/score/saved/carry/style + GOTCHA/DELIVERED stamps); combat HUD hidden in rescue.
- **P3 non-lethal terrain:** gated effective CRASH_SPEED=1e9 on both collision sites (stored 45 untouched; combat byte-identical if un-shelved); Y<-200 failsafe kept.
- gray-box sound (rbxasset + PlaybackSpeed; silent-fallback if an id doesn't resolve — Chad reports which did).

**Red-team (agent `a7c586eaa7111a3ea`) → 2 BLOCK + 2 REVISE, ALL FIXED:** BLOCK1 death-mid-catch stranded the global desaturation → `resetRescuePresentation()` in `teardownDrive`. BLOCK2 rescue world non-solid vs the coexisting solid combat map → made mesa/pad/rimpool solid (queryable); **trees stay VISUAL for Phase 0 per the bible's stated scope — the ONE known open design item** (Phase-1 = real trunk/canopy collision + a dedicated valley that skips the combat `BuildMap`; combat map currently kept as floor+backdrop). REVISE3 client-trusted catch → server distance gate + PHASE-0-TRUST note. REVISE4 carry desync → idle reconcile to server carry. A confirmation re-review ran (agent `a9575b3903d52b563`).

**LOCKED-spec integrity:** CS-1..CS-9 untouched. The camera decoration is a pure beat-time post-transform on the chase OUTPUT, verified byte-identical when `rescueCam.env=0`; it never reads input or feeds the aim/control frame. No kernel/aim-law edit.

**Git:** on `updraft`. The slice is committed (`b35ce43`); the S32 playtest tweaks (#0) + the standing loop-order handoff are a second commit. NOT pushed (Chad's call — push is remote-facing). Ledger/session log: `.loop/rescue-phase0/state.md`. **Loop discipline:** each queue item lands as its own commit-ready checkpoint (git commit stays ASK-gated).

*(Everything below is prior history — UPDRAFT and combat — SUPERSEDED by the rescue direction above, retained for the record. The flight-kernel detail remains authoritative.)*

---

## ▶ COLD START — Session 31 CLOSE (2026-07-13): 🪶 NEW DIRECTION GREENLIT — "UPDRAFT" (non-lethal proximity-flight), COMBAT SHELVED

**THE GAME PIVOTED. Chad greenlit "UPDRAFT" — a non-lethal PROXIMITY-FLIGHT SCORE game — and SHELVED the aerial-melee-kill loop.** Read **`docs/UPDRAFT-strategic-plan.md`** (the full plan) + the `project-updraft-direction` memory FIRST. How we got here: iterating combat catchability (talonPickBias, strikeReachBonus, crow-lead, auto-strike, feather/spiral juice — all built, `sandbox/flight-feel`) did NOT make combat fun; Chad concluded the PREMISE was wrong ("going in circles is tiring… melee on small targets is really hard… bird-killing isn't great for kids"). A `deep-research` pass on the Roblox market (108 agents, fact-checked) + a Fable 5 synthesis produced UPDRAFT.

**UPDRAFT in one line:** *become a bird, score by flying dangerously CLOSE to terrain/waterfalls/friends' wingtips* — "almost hit the world" (terrain never dodges) replaces "hit the bird." Superflight's proven loop on our loved kernel; non-lethal reuses the built feather-burst + spiral-tumble as "dazed, lose your combo." Research basis: 2026 Roblox algorithm rewards 28-day RETENTION + friend-bringing; first-session fun is THE lever (kernel is fun in 60s); flight-as-reward is PROVEN (Superflight/Flying Wings); pet-collection REFUTED; ~73% under 18; no flight game in top-20 = open lane; monetization = cosmetics only (all monetization specifics were refuted → inference).

**Core loop = LINE-RIDING:** proximity meter → combo → BANK at a thermal (energy currency, built) or LOSE it in a feather-tumble. Progression = bird skill-CLASSES (Crow/Eagle built) + medal lines gating regions + PB ghosts. Social = Slipstream/flock bonus + ghost races (reuse squad/possession tech). Sandbox = a LAYER (Nests → Course Maker), later. 

**▶ IMMEDIATE NEXT = UPDRAFT Phase 0 (build FIRST, ~1-2 wks): "is line-riding fun?"** Strip combat remotes/UI; add a **proximity scorer** (reuse `BirdCollision` spherecast + a wider probe radius — nearly free) + combo + bank-on-thermal + crash→feather-burst/tumble (both built) + score HUD + spawn-in-air FTUE, on the EXISTING mountain map, no new art. **Gate: Chad plays 30 min and wants line #2.** Then P1 progression → P2 social sky → P3 launch dressing (+Fledgling Mode for <9s = a kernel profile) → P4 Course Maker. Do NOT rebuild combat / pet-collection / a new map first.

**Git state (S31 CLOSE):** flight kernel GRADUATED to `master` @ `6686a0c` (pushed, tag `v1.2-free-cursor-flight-kernel`) — the fixed crown jewel. The parked combat experiments + combat-gameplay-architect + juice are COMMITTED on `sandbox/flight-feel` (the exploration record). **UPDRAFT work starts on a new `updraft` branch.** The `combat-gameplay-architect` agent is parked (combat shelved); the `flight-controls-architect` + flight-feel harness still apply to the kernel.

*(Everything below is the prior combat/kernel history, retained for the record — the kernel detail is still authoritative; the combat "frontier" framing is SUPERSEDED by UPDRAFT above.)*

---

## ▶ COLD START — Session 30 CLOSE (2026-07-13): ✅ SEALED FREE-CURSOR FLIGHT KERNEL — next frontier = COMBAT

**🔒 THE MOUSE-AIM / FREE-CURSOR / CASCADE / CAMERA FRONTIER IS DONE AND CHAD-LOVED ("its perfect… commit this as a sealed flight kernel").** Tagged **`v1.2-free-cursor-flight-kernel`**; committed `37e66c0` on **`sandbox/flight-feel`** (pushed to origin). **⇒ WORK FROM `sandbox/flight-feel`** — it carries the sealed kernel PLUS the dev instruments (F7/F6 step-response + strike telemetry, both inert). Do NOT reopen the aim kernel without a fresh Chad ask — it now joins the eagle flight kernel as signed-off.

**What the sealed kernel IS (the S30 rework, in build order):** a **screen-referenced FREE cursor** (`aimFreeCursor=true` bypasses BOTH the nose-cone + screen-circle clamps → the reticle roams the whole screen) + an **output-side inversion guard** (`aimRollCeilingDeg=85` fades bank-DEEPENING roll near the ceiling so a far-corner cursor can't roll the bird inverted — no auto-level/CS-5; recovery/leveling untouched; sign = deepening ⟺ `rollP·curBank<0`) + **heading-rate damp** (`aimHeadDamp=0.45`, the missing axis on the roll law) + **knife-edge FF taper** (`aimBankFFTaperDeg=55` — the S27 sec(bank) anti-dip FF explodes at the 65-85° banks the free cursor unlocks and pumped the nose up/down; tapered off past ~combat bank, loved anti-dip in normal turns intact) + **camera LAG-FOLLOWS the cursor** (`aimHeadingLag=2.2`; the camera catch-up is what visually re-centres the cursor — NOT the bird-follow Fable first proposed; Chad corrected that) + **centred boresight framing** (`chaseLookUp=0.25`: raise the chase look target along camUp → aim rests at screen CENTRE, bird sits lower) + **free-look HOLD** (CS-4 REVISED: hold Space, release resumes aim). Chad's model, confirmed twice: cursor free on screen; eagle follows the cursor; camera lag-follows the cursor and is what visually re-centres it (he is never pulled back to centre by force).

**▶ NEXT FRONTIER — COMBAT (the sleeper-hit path; see the `project-sleeper-hit-direction` memory + the Stage-7 box below).** Two architect consults this session (flight-controls-architect + a Fable game-design pass) set the direction: **the CROW COMMANDER (squad possession) is the actual product**; sequence = **(0) unblock combat contact → (1) juice the contact [hit-stop/feathers/screech/Trade slow-mo] → (2) seat-swap match structure → (3) crow-commander verbs → (4) population/bots-fill → (5) onboarding → (6) meta.** **Stage 7 strike telemetry RAN + ATTRIBUTED the contact-rate problem (Chad-flown 80s capture):** crow **PURSUIT-CURVE** (dive-bombs the eagle's *current* pos with no lead → passes close to 10-25 studs but NEVER reaches the ~7-stud contact sphere, 7/7) + eagle **BEAK-CONE** too narrow / mis-picked (the wide belly talon was never auto-selected). Pre-registered next dials, each ships inert: **crow dive-bomb target LEAD** (crow-side fix; ⚠️ balance-flip-gated — each landed ram ≈33 dmg, raise `diveBomb.attackPeriod` first if it over-delivers) and **talon/beak cone/axis** (eagle-side). Full decision table + the frontier queue are in the Stage-7 COLD START box below. **Continue via `/flight-feel-loop` or `/evc-loop`; propose combat dials through `flight-controls-architect`, red-team, ship inert, Chad flies.**

**Git state:** `sandbox/flight-feel` @ `37e66c0`+ pushed to origin + tag `v1.2-free-cursor-flight-kernel`. ✅ **The sealed kernel is now GRADUATED to `master` @ `6686a0c` (S31, 2026-07-13, pushed)** — a clean commit carrying the kernel MINUS the dev instruments (F7/F6 scratch block, `_ScratchTele`, Stage-7 strike telemetry all excluded per the S29 pattern). **`sandbox/flight-feel` remains the COMBAT working branch** — it keeps the instruments (Stage-7 telemetry re-arms via `GameConfig.Combat.strikeTelemetry`). Ledger: `.loop/flight-feel/results.tsv` (every S30 dial logged; the KEEP rows ARE the sealed kernel).

*(The detailed S30 screen-cursor architecture + staged plan that produced this — now REALIZED — is retained below for the record.)*

**THE FABLE ARCHITECTURE (full detail: this session's consult; the design is technically grounded — Fable read the kernel/aim/camera).** Invert ownership:
- **Cursor = player-owned SCREEN state** (`aimCursorPx`, only the mouse writes it; clamp the stored value so no windup; NEVER re-centres). Full-screen authority; the nose-cone + screen-circle clamps are bypassed in this mode. Pixel-true; angle from an unproject at a FIXED ref FOV (dive/zoom FOV can't change hand-feel).
- **Camera FOLLOWS THE CURSOR with LAG — CHAD-CORRECTED 2026-07-13 (Fable had this WRONG: it is NOT camera-follows-bird).** KEEP the Stage-1 camera-eases-onto-aim behavior: the camera lag-chasing the cursor is what VISUALLY re-centres it — the player NEVER manually re-centres. Chad wants MORE lag (lower `aimHeadingLag`) so the cursor is FREED and not yanked back to centre fast. The eagle ALSO follows the cursor (deflection = turn command); the camera does NOT follow the bird. So the change vs today is: FREE the cursor (remove cone+circle) + tune the lag looser + the inversion guard + the porpoise/heading-damp — NOT inverting the camera onto the bird.
- **Deterministic cascade:** ray = controlFrame ⊕ unproject(cursorPx) → `localTarget` (body frame) → **the KEPT S26 servo core** (same gains/signs/FF/stall-gate — that's the loved SNAP; a cursor *flick* is still a world-referenced error step the high-gain servo closes at plant rate). Determinism proof: outer-loop eigenvalues are 0 and −(K+λ) — **no oscillatory outer mode at all**; the porpoise is purely the inner attitude loop → fixed by heading-rate damp (Stage A).
- **Two structural repairs:** (1) **control-frame / render-camera SPLIT** — the aim currently reads the *rendered* camera (`camera.CFrame`, incl. shake + followSmoothing lerp) INSIDE the loop = a real defect; hoist the deterministic chase pose pre-shake/pre-lerp and read THAT. (2) **inversion envelope replaces the cone's job on the OUTPUT side** (soft one-sided roll ceiling ~100–110° that only fades bank-*deepening* authority + an inverted-recovery completion of `levelAssist`) — full cursor authority, but the no-auto-level upside-down-rest (CS-5) can't be *driven* by aim; loops (bank≈0) and keyboard aerobatics (CS-1) untouched.

**⚠️ CORRECTED 2026-07-13: NO manual re-centre (Fable's Stage-C feel-call is REJECTED).** Chad does NOT want a screen-stick he re-centres by hand. He wants the CAMERA (via lag) to re-centre the cursor FOR him — the cursor only *appears* to return to centre because the camera lag-follows where he pointed. So the camera target stays the AIM/cursor (Stage 1), tuned with MORE lag so the cursor roams free (he's "not getting pulled back to centre quick"); the eagle flies a coordinated cascade toward the cursor; the porpoise is killed by the cascade's heading-damp instruction. This is closer to TODAY's model than to Fable's inversion.

### ▶ STAGED PLAN (one knob, flyable, revertable, ships inert — every flag-off = byte-identical to the prior Chad-flown baseline)
| # | Stage | Knob (identity) | Gate |
|---|---|---|---|
| **A** | **Heading-rate damp** (= roadmap Stage 2 `aimHeadDamp`, unchanged) — **THE porpoise fix Chad is complaining about, AND the precondition for the whole model. START HERE.** | `aimHeadDamp` (0) | F7 30° step: overshoot+reversals fall, settle ~halves, rim-pinned turn-rate UNCHANGED (eagle+crow). "Nose lands and stays." |
| **B** | Control-frame extraction (aim reads the deterministic chase pose, not the rendered camera) | `aimUseControlFrame` (false) | Zero felt change; command jitter RMS drops. If he feels anything, STOP+attribute. |
| **C** | **Screen-referenced cursor** (the structure) — cursorPx state, unproject ray, clamps bypassed, camera→followDir in-mode, disc rim ≈ today's circle | `aimScreenCursor` (false) | **CHAD-GATED** (supersedes CS-8; the recentre-to-fly-straight call). Cursor pixel-still in a hard turn = independence proof. |
| **D** | Stick-gain calibration (`aimHeadingLag` re-meant as turn-rate slope; start at 4.0) | `aimHeadingLag` (4.0) | one-knob live sweep 3–5. |
| **E** | Inversion envelope (roll ceiling, then inverted recovery — two flights) | `aimRollCeilingDeg` (180), `aimInvertedRecover` (0) | Chad + red-team gated; rim-hold never rests inverted; loops untouched. |
| **F** | Authority widening (disc → margin↓ → full rect = "whole screen") | `aimCursorEdgeMarginPx`↓ then `aimCursorRectClamp` (false) | only after E proves the envelope. |
| **G+** | roadmap Stages 3–6 (retire in-loop ease, ≤5° skid-snap, yaw kick, gain schedule) — re-tune AFTER C/D | per roadmap | optima depend on the new error dynamics. |

**IMMEDIATE NEXT = Stage A (`aimHeadDamp`, ships inert at 0).** It fixes the live porpoise complaint, is the roadmap's already-queued Stage 2, and is the outer loop's stability precondition. Propose via `flight-controls-architect`, red-team, implement inert, Chad flies with F7 before/after. Then B (zero-feel enabler), then the C gate. **Pre-registered watch (from Fable):** C drifty near centre → deadzone 0.006 is now a *rate* deadzone, nudge →0.012; slow weave → raise headDamp, never lower λ; any cursor motion NOT from the mouse = a leaked writer (bug).

---

## ▶ COLD START — Session 30 (2026-07-12): COMBAT FRONTIER OPENED — Stage 7 STRIKE TELEMETRY (built, inert, needs Chad's capture)

**Strategic pivot (Chad's ask + two architect consults — flight-controls-architect + a Fable game-design pass).** The eagle flight/aim/camera is signed off; the frontier that decides "sleeper hit vs tech demo" is **combat contact rates + the 1-v-4 + the wrapper**. Fable's headline: *the crow COMMANDER (squad-possession) is the actual product, currently under-served.* The agreed sequence: **(0) unblock combat contact → (1) juice the contact [hit-stop/feathers/screech/Trade slow-mo] → (2) seat-swap match structure → (3) crow-commander verbs → (4) population/bots-fill → (5) onboarding → (6) meta.** Chad chose to start at (0). Full consult in this session's synthesis; worth a `project` memory.

**Why telemetry FIRST (not a number).** The contact-rate complaint is symmetric — "hard to hit them" AND "they don't hit me" — which points at a shared cause: **maneuvering-merge geometry**, not any strike/damage number. Prime suspect (architect): the crow dive-bombs the eagle's *current* position with **no lead** (`GameServer` crow-goal ~1497) → a pure-pursuit curve that arcs behind a turning eagle and slides past *outside* the ~7-stud contact sphere, never reaching the `COLLISION_SPEED_MIN=90` ram gate. Eagle misses for the mirror reason (cones sweep a curving target for a frame or two). **Every combat number is a guess-on-a-guess with nothing instrumented — so Stage 7 measures before we tune.**

**What Stage 7 IS (built this session, on `sandbox/flight-feel`, build-green, ZERO new analysis findings):** a dev instrument gated by **`GameConfig.Combat.strikeTelemetry` (default `false` = byte-identical to today)**. When armed it batch-logs (~1 Hz, per-event, never summarized) to the server output:
- **`MERGE` rows** (a new ≤48-stud eagle↔crow near-miss scan, per living eagle only — a handful of pairs/frame, self-pruning, fully inert when unarmed): `minSep` (closest approach), `relAtMin`, `gatePass` (relAtMin≥90), `CONTACT`/`MISS`.
- **`STRIKE` rows** (gated read-only hook in `updateEagleStrikes`' offensive pass): every armed-strike frame, hit AND clean miss — `dist`, `reach`, `axisDot`, `coneCos`, `covered`, `windowPhase`, `hit`.
Red-teamed (BLOCK→resolved): the wide scan is provably zero-cost unarmed + bounded to few eagles (not O(n²)); the pair-state self-prunes (no leak); it only READS — the ram/cooldown/`tryStrikeCatch`/damage path at `processCollisions` is byte-identical armed or not. Touches **no CS-1…CS-9, no client control law, no camera, no damage number.**

### ▶ PRE-REGISTERED DECISION TABLE (falsifiable — read the rows against THIS; do not narrate-to-fit)
| Row pattern at closest approach | Attribution | Next knob (ships inert) | Refuted if |
|---|---|---|---|
| `MERGE MISS`, `minSep` clusters 12–30, `gatePass=true` | **Crow pursuit-curve** | crow dive-bomb target lead (=0) | `minSep` routinely <9 |
| `MERGE`, `minSep<9` but `gatePass=false` | **Speed-gate starvation** | `COLLISION_SPEED_MIN` | `relAtMin` mostly ≥90 |
| `STRIKE`, `covered=false`, `dist≤reach` | **Cone/axis geometry** | `talonAxisPitchDeg` / cone | `covered=true` whenever in reach |
| `STRIKE`, `covered=true`, `dist≤reach`, but `windowPhase` shows strike not live | **Timing/uptime** | strike duration/startup | window live at the covered frame |
| `MERGE CONTACT` (`minSep<9`) + `gatePass=true` + a `STRIKE covered=true,dist≤reach` yet **no death** | **NULL — contact-path bug** | audit `processCollisions`/`tryStrikeCatch`; no number moves | (this is the falsifier) |
| rows don't cluster | **Inconclusive** | re-instrument finer; do NOT tune | — |

### ▶ CHAD'S CAPTURE CHECKLIST (Stage 7 — arm the instrument, do NOT judge feel)
1. **Serve `sandbox/flight-feel`** (`.\serve.ps1` on this branch — it also carries the F7/F6 aim instrument). In `GameConfig.Combat` set **`strikeTelemetry = true`**, Play SOLO (bot crows spawn).
2. **Armed-vs-unarmed A/B (the red-team acceptance gate):** fly one 1-v-4 armed, one unarmed — combat must feel IDENTICAL and no spurious crash/anti-cheat deaths appear only when armed. If armed differs → the instrument leaked; report before reading data.
3. **Fly a normal turn-fight ~60-90s**, then read the server Output: `[EvC strikeTelem] --- N rows ---` blocks. Paste a representative flush back. We attribute via the table above, then the ONE next dial (crow lead / cone axis / speed gate) ships inert and you fly it.
4. **Disarm** (`strikeTelemetry = false`) when done — it's dev-only, never a live round.

### ▶ CAPTURE RESULT (2026-07-12, Chad's 80s solo bot-fight) — BOTH sides attributed
- **CROW SIDE = PURSUIT-CURVE, CONFIRMED (7/7 passes).** Every `MERGE` row is `MISS`: crows closed to `minSep` 10.1 / 12.2 / 22.8 / 24.7 / 28.3 / 41.3 / 46.3 studs — **none reached the 6.7-stud contact sphere.** Even lethal-closure passes (`relAtMin` 149 / 227 / **327**, `gatePass=true`) slid past by 12–23 studs. Textbook pursuit-lag (aims at the eagle's *current* pos, no lead) → "flies in front of me but never hits me." **Next dial (pre-registered): crow dive-bomb target LEAD, ships inert at 0.** ⚠️ red-team balance-flip watch: each landed ram = health/eagleHits ≈ 33; dial lead up a hair, raise `diveBomb.attackPeriod` FIRST if it over-delivers.
- **EAGLE SIDE = beak-cone geometry + spacing.** Most `STRIKE` rows are `dist=-1 / axisDot=-2` (no crow within reach when he fired — beak spammed into empty air). On the one pass a crow WAS in reach (`dist` 22–26 ≤ 28), `axisDot` was 0.10–0.80 vs the needed `coneCos 0.819` → **outside the narrow 35° beak cone every frame.** Also: **the auto-pick was `beak` 100% of the time — the wide 70° belly TALON was never selected** (`enemyZone` only picks talon when the crow is more below than ahead). Candidate dials (later, one at a time): widen/re-aim the beak cone, or fix the talon-vs-beak auto-pick so the workhorse belly cone actually gets used.

### ▶ NEW AIM DIAL QUEUED — Chad's realization (2026-07-12): "free the mouse-aim cone across the WHOLE screen, lean on camera lag"
Chad, watching the capture: *"there is a restriction cone on the mouse aim. It would be better to let it fully operate on the whole of the screen… eliminate the cone to truly free the mouse aim and have the camera lag."* This is the `aimLeadScreenFrac` nose-cone (~0.95 / 52°). It is **on-roadmap** (the end-state = freed cursor + decoupled deterministic-lag camera, which Stage 1 just landed) — BUT ⚠️ **`aimLeadScreenFrac 0.95` is the LOAD-BEARING overshoot limiter**: S28 widening it (0.95→1.8) let the bird roll through vertical and **rest UPSIDE DOWN** (no auto-level). So this is a Chad-gated, red-team-gated, ONE-knob flight-feel dial — propose via `flight-controls-architect`, do NOT widen it blind. It may now be safe *because* the camera decouple changed the regime (his exact intuition), but that must be flown one step at a time. See [[research-coordinated-flight-instructor]].


**Git:** S29 committed to master (`356c430`) **and PUSHED to origin/master** (carried the S24→S29 batch). Stage 7 lives on `sandbox/flight-feel`, **uncommitted** (gated on Chad's capture → then commit here; cherry-picks cleanly to master since GameServer/GameConfig are identical across the two branches). Ledger: `.loop/flight-feel/results.tsv` (Stage 7 row = PENDING-CHAD-CAPTURE).

---

## ▶ COLD START — post-Session 29 (2026-07-12): FLIGHT-FEEL HARNESS built (skill + subagent + instrument)

**What S29 did (a NEW harness, not an aim retune — ZERO flight behavior changed).** Chad's directive: build an agent to carry the aim/camera/strike work under the non-negotiable discipline (plan mode · one dial · he flies everything · honest ledger), informed by a Fable 5 consult + two SEADS source docs (`docs/roblox_crows_eagles_consult.md`, `~/Downloads/Flight Controller Cascade Physics.txt`). Built, build-green, acceptance-tested:
- **`.claude/skills/flight-feel-loop/`** — the tuning loop (specializes evc-loop): ONE gated dial per iteration (propose → locked-spec gate → red-team → implement inert → build → INSTRUMENT → Chad flies → keep/revert → ledger). Roadmap in `references/roadmap.md`; ledger template in `templates/ledger.tsv`.
- **`.claude/agents/flight-controls-architect.md`** — read-only specialist that proposes EXACTLY one dial (math + predicted instrument signature + felt change + CS interactions + revert). Loads NEXT session (agents register at startup). Its acceptance test proposed Stage 2 (`aimHeadDamp`) correctly and caught two doc-staleness bugs (now fixed).
- **Stage 0 step-response INSTRUMENT** (the ONLY code change) — F7 lateral / F6 vertical step injectors + settle/overshoot/reversals/camera-gap tracker, in the delimited scratch block of `BirdController` + `_ScratchTele`. Inert / zero-diff when unused.

**Root cause pinned (why S26–S28 thrashed):** the horizontal aim channel damps ROLL-rate (settles *bank*), not HEADING-rate (settles the *nose*) → sail-past; the loved vertical channel damps pitch-rate and never overshoots. Fix = the vertical channel's medicine on the right axis (Stage 2 `aimHeadDamp`, ships inert at 0). Both SEADS docs independently prescribe the cascade + measured-rate damping + low-smooth-outer-gain + ≤5° skid-snap + target-derivative yaw-kick, and independently REJECT exactly what S28 did (hard clamps / fighting controllers across a seam).

**IMMEDIATE NEXT ACTIONS (Chad):**
1. **F7 zero-diff confirm (~2 min):** press F7 in level flight → the aim steps 30° and a metrics row prints (`axis,stepDeg,settle_s,overshoot_deg,reversals,camTau_s`); F6 = the loved vertical channel (baseline). With F7/F6 unused, normal feel must be identical. This is Stage 0's gate.
2. **CS-8 sign-off (gates Stage 1):** Stage 1 (camera decouple — camera follows the AIM with deterministic lag) keeps the world-cursor MATH but changes the FELT behavior (cursor re-centres as the camera catches it), reversing the logged 2026-07-02 world-cursor hang-out decision. It IS the new spec, but needs an explicit go before flying.
Then run `/flight-feel-loop`: it proposes Stage 1 (if CS-8 approved) or Stage 2 (`aimHeadDamp`, ready now, ships inert).

**Corrections logged (do NOT re-derive wrong):** live `aimBankDeadzone = 0.006` (≈0.34°), NOT the 0.10/5.7° the source docs assumed → Stage 4 skid-snap is a genuine SEAM (the S28b risk), not a free deadzone coincidence, and is Chad+red-team-gated; `headRate01` normalizer = `/profile.pitchRate`; the ×3.46 dive bonus is LEGACY (`onAttackRequest`), the live strike is fully flat; reuse dead `COLLISION_SPEED_REF=260` as the strike anchor; do NOT build plant-inversion FF / rate-PI / inertia probe / micro-planet orbital physics (none map to this CFrame kernel).

**Verify state:** build PASS; luau-lsp = 17 findings, ALL pre-existing (none in the instrument block); selene UNAVAILABLE (its 0.28.1 GitHub asset 404s — pre-existing infra, unrelated to this diff). Working tree = the S29 harness + instrument, on top of the still-uncommitted S28e-off aim state. UNCOMMITTED (git gated on Chad).

*(The S28 aim-loop cold-start box below remains the authoritative detail for the aim law itself — the harness governs HOW to work it, the roadmap says the order, the box says where the aim law sits today.)*

---

## ▶ COLD START — read this box first (post-Session 28 CLOSE, 2026-07-02)

**⚡ CHAD'S CLOSING SPEC (playtest 5, 2026-07-02, tokens out until ~7:40pm — THE acceptance criteria for all future aim work, verbatim-ish):** *"A small deflection should have the reticle SNAP to the cursor. Right now the reticle lags behind then snaps over in a jolt. The bird might lazily go upside down after that when it resolves its terrible route to my aim. The bottom circle bias remains. If I want to make a loop with mouse by pitching up it is severely limited and merely climbs. The extent of the displacement of the mouse should offer full pitch deflection, or if to the side full bank and pitch with a little yaw… maybe not full deflection, as then it might break the model — but definitely FOCUS ON FIXING THE SMALL DEFLECTIONS, the mouse aim should work. For full control deflections I can rely on the keyboard, as can any user — but the mouse should be able to NEAR that with sustained movement."* → Priority order: (1) small-deflection snap, (2) sustained mouse displacement approaches (not equals) full deflection incl. a mouse loop (currently "merely climbs" — suspects: the aoaHead stall gate + S26e speed-scaled pitch floor capping an unpowered loop; a POWERED loop should already commit — verify with him), (3) the bottom bias (camera-above geometry, boresight-centering candidate below), (4) lazy-inversion.
**⚠️ FIRST STEP NEXT SESSION — SYNC CHECK before believing playtest 5:** it is UNVERIFIED whether Chad's last flight ran the reverted tree or a STALE build (Rojo serve/build timing) — "lags then snaps over in a jolt" + "lazily go upside down" matches the pre-revert WIDE-CONE tree exactly, and the reverted tree is git-verified byte-identical to the S27 baseline he previously flew without these reports. Rebuild/serve, confirm the sync (e.g. read `GameConfig.Controls.aimLeadScreenFrac` == 0.95 in Studio), have him fly the true baseline, THEN diagnose. If the true baseline still lags-and-jolts on small deflections, prime suspects in order: `aimResponse` 13 ease (lag then catch-up shape), the S27 `aimBankFeedforward 0.35` ("climbs"), deadzone/expo shaping. ONE knob per flight, him at the wheel — no structures (three failed this session; standing rule below).

**🛑 S28 FINAL STATE (playtests 3+4, 2026-07-02): lead OFF **and** cursor-cone REVERTED — the aim loop is now VERIFIED byte-identical to the S27-close baseline (git-diff-checked), + the one confirmed win (free-look-exit fix).** Playtest 4 caught that my "low-risk" cone widening (`aimLeadScreenFrac` 0.95→1.8) was itself a regression: the 33.6° nose-cone is a LOAD-BEARING overshoot limiter (it drags the cursor along when the nose swings past, capping the error) — widened, small deflections rubberbanded harder and the bird could roll through vertical and REST UPSIDE DOWN (no auto-level + levelAssist gates off inverted). Reverted to 0.95; do-not-widen warning written into the config. **Corrected root cause for the two remaining geometry complaints (Chad's diagnosis was right):** the bottom-biased cursor region AND the RMB-zoom reticle-floating-above-target are ONE thing — the chase camera sits ABOVE the bird and its look axis does not run along the boresight, so the reticle projects ABOVE screen centre (less up-room in the screen-centred circle; anything nearer than the far boresight point projects below the reticle). The candidate fix is **aim-camera boresight centering** (pitch the aim camera's axis to converge on the reticle point) — a camera-framing change, NOT an aim-law change — OFFERED to Chad as the next single Chad-gated live-flown step; not implemented without his go. Chad on S28e@0.28: *"no its terrible, reticle is porpoising, rubberbanding and lagging in short displacements."* That is THREE structures failed by his feel test in one session (cascade v1, cascade v2/asin, turn-rate lead) — each mathematically grounded, each build-green and red-team-verified, each WORSE in his hands. `aimLeadTime = 0` ⇒ `hPred = rgt` exactly ⇒ the S26 servo law byte-for-byte; the lead machinery stays dormant for a possible Chad-in-the-loop micro-tune (0.08-0.12) ONLY. **STANDING LESSON (now three-times-proven): static analysis + red-team cannot certify FEEL. Do not ship another aim-loop structure change; the only converging path is one-knob-at-a-time live-tune from the loved baseline with Chad flying every step.** What SURVIVES S28 as confirmed or low-risk wins: **S28c free-look-exit jump fix (Chad: "the reticle doesn't jump" ✅)** + its 0.4 s failsafe · **cursor bound freed** (`aimLeadScreenFrac 1.8`: screen-centred circle is the working bound — answers his "biased toward bottom / mouse bound by the flight model"; needs his quick confirm) · **S28d verify-tier fix** (defs pinned; real diagnostics; baseline recorded) · the S27 FF + sensitivity (still in, still good) · `docs/RESEARCH-coordinated-flight.md` (the theory stands; the failures were in translating it to feel).

<details><summary>▶ (S28e detail — the rejected lead law + the rejected cascade, kept for the do-not-retry record)</summary>

**⚡ S28e — the turn-rate-lead attempt (REJECTED at aimLeadTime 0.28).** Chad's 2nd playtest KILLED the S28/S28b cascade: *"over-delivering on big deflections, going up and around the cursor, porpoising… on small deflections the eagle won't turn enough — yawing but not banking — lost its snappiness… the circle is biased toward bottom… the mouse seems bound by the flight model… coordination means figuring this out mathematically so yaw, bank and pitch are balanced so the reticle snaps to the cursor quickly and then gets it right to centre. However you tuned it now fights that."* (The blend seam mushed 10-20° inputs; the slew-limited bank fought the aggressive pitch. The ONE confirmed S28-round success: **the free-look-exit jump is FIXED** — S28c `snapToChase` clamp gate, KEPT.)
- **S28e — ONE law, turn-rate LEAD (the cascade + mode blend + its 6 knobs are DELETED).** The S26 servo shape is fully restored (it IS the snap); the single structural addition: the horizontal error is PREDICTED `aimLeadTime` (0.28 s) ahead using the eagle's ACTUAL heading rate from clean kernel body rates — `hPred = rgt − ψ̇·τ·cosB·cosΔψ·washout` — and roll/yaw steer from the prediction. This is the horizontal analogue of the vertical channel's (loved) pitch-rate damping: heading-rate feedback where roll-rate damping couldn't act. Nothing differentiates the mouse (S27c jitter class impossible).
- **The three red-team-mandated corrections (a first S28e draft was BLOCKED; rev2 re-verified CLEAR):** (1) **error-space scaling** `cosB·cosΔψ` — without it the lead over-anticipates ~2× at combat banks (mid-turn unload bounce); (2) **rim WASHOUT** — while the cursor is pinned against the screen circle (= the sustained-turn command) the lead fades to 0 (`aimLeadWashRate` 6/s), so rim-pinned turns run the pure S26 law at full plant rate (eagle ~1.8 / possessed crow ~3+ rad/s — the crow's turn identity preserved; a constant lead would have silently HALVED sustained turns); when the throw ends the cursor drops inside the circle (world-fixed) and the full lead shapes the arrival — exactly the sail-past case; (3) **keyboard MUTE** — the lead fades to 0 while any flight key is held (mirrors the CS-1 gate) so nothing pre-charges a counter-turn into the loved key-release seam. Plus: `snapToChase` got a 0.4 s time failsafe (the dot-test chases a moving target and could wedge ON in fast crow turns, suspending the cursor circle indefinitely).
- **Cursor freed (Chad's "biased toward bottom / mouse bound by the flight model"):** `aimLeadScreenFrac 0.95→1.8` — the NOSE-cone (centred on the nose, which projects BELOW screen centre) stops binding; the cursor's working bound is now the screen-centred `aimCursorAreaFrac` circle alone ("my circle on my screen" — deflect and it holds); the ~52° cone + `aimMaxLeadDeg` 70 remain as frontal-hemisphere safeties.
- **Knobs:** `aimLeadTime 0.28` (slips past on big swings → 0.35; stops short/mushy → 0.2; **0 = pure S26, one-knob A/B**) · `aimLeadWashRate 6` (short flicks overshoot → 9-10; rim pumping → lower).

### ▶ S28e PLAYTEST GATES (red-team-derived, priority order)
1. **Big-swing arrival at deep bank:** throw the cursor ~90°, release — nose lands ON the cursor, no sail-past, no unload-bounce, no up-and-around. *Slips:* `aimLeadTime` →0.35. *Stops short:* →0.2.
2. **Small/medium deflections:** the S26 snap must be fully back (same code path; the lead only bites once a real turn rate exists). Jitter must stay dead.
3. **Short sharp flick-and-release** (red-team WATCH-1): a fast small throw may still carry a touch past while the washout re-arms → `aimLeadWashRate` →9.
4. **Rim-pinned sustained turn, eagle AND a possessed crow:** full turn rate, no pulsing (the washout = pure S26 at the rim); crow — also try dragging *just inside* the rim: any rate cliff vs pinned? (surgical fix ready: engage washout at ~0.9·rim).
5. **CS-1 seam:** held-S loop straight; a full keyboard turn then release with the cursor near the nose → progressive roll-out, NO slam (the mute + ramp).
6. **Hands-off banked with cursor centred (explicit Chad Q — red-team F4):** the bird now actively rolls out and holds the cursor heading (S26 only wing-levelled). Wanted, or too much auto?
7. **Cursor region:** circle centred (bottom bias GONE), mouse deflects and HOLDS anywhere in it; free-look exit still jump-free (plus at most a ≤0.4 s crisp-camera blip after exiting mid-turn).

**S28 EXECUTED Chad's standing directive — the coordinated-flight rework is DONE and in the tree.** Research first (as directed): the `deep-research` workflow ran the full brief (5 angles → 21 primary sources → 102 claims extracted → 25 adversarially verified → **22 confirmed 3-0, 3 over-claims refuted**; synthesis completed cleanly this time) → **`docs/RESEARCH-coordinated-flight.md`**. Then the ONE change: **`computeMouseAim`'s roll/yaw per-axis PD servos are REPLACED by a coordinated-turn CASCADE** (the researched structure). **STATUS: build-green (rojo PASS; luau-lsp analyzes CLEAN, exit 0, via direct Git-Bash invocation — the `verify.ps1` tier FAIL is the documented pre-existing PS crash), red-teamed (REVISE → both findings addressed), UNPLAYTESTED, UNCOMMITTED.** The whole point of S28 rides on ONE playtest gate: **does the rubberband die** (reticle no longer sails past the cursor on big turns) **while the small-input snap stays identical**?

**What changed (S28), in one breath.** For LARGE HORIZONTAL aim errors only: horizontal heading error → **sqrt-controller** (ArduPilot: linear small = snappy; √(2A·err) large = deceleration into the target bounded by `aimTurnAccel` ⇒ cannot overshoot) → commanded turn RATE (capped at the profile's own `pitchRate` — plant-scaled; a possessed crow keeps its agility) → **ONE commanded BANK** `φ_d = atan(V·ψ̇_d/g)` (the coordinated-turn inversion, speed-scaled), clamped to `aimMaxBankDeg` and **slew-limited** (`aimBankSlew`) so the command respects the roll loop's lag (Jung & Tsiotras: an outer law blind to that lag is structurally low-damped = the sail-past) → roll servos the **BANK onto the command** (bank error, NOT cursor error — the commanded bank rolls OUT before arrival), yaw coordinates ∝ the same single turn command, and the pitch channel (PD + speed-scaled P + stall gate + the KEPT S27 `sec(bank)−1` feedforward) is the elevator that pulls the turn — **bank+yaw lead, elevator sustains** (Chad's sequence, confirmed verbatim in the literature). Below `aimDirectConeDeg` (10°) — and for near-vertical errors (loops) and inverted flight — **the S26 direct law runs VERBATIM**: small-input snap, loop commitment, straight flight all numerically IDENTICAL to the baseline Chad loved. Nothing differentiates the mouse anywhere ⇒ no jitter amplification (the S27c failure, solved structurally). New knobs (`GameConfig.Controls`, each documented in-config with its tuning direction): `aimDirectConeDeg 10 · aimTurnP 2.5 · aimTurnAccel 2.0 · aimMaxBankDeg 70 · aimBankSlew 2.0 · aimBankGain 3.0`.

**UNCHANGED (red-team-verified):** the world-cursor model + both circle clamps (CS-8), CS-1 gate (re-derived: the new `aimBankCmd` state can't leak authority through or across it), CS-5 (no auto-level: the cascade acts only under mouse-aim with a live >10° error; idle ⇒ direct law only), the whole pitch channel, free-look/CS-2, dive/CS-9, deadzone/expo shaping, the `aimResponse` ease, the kernel, and the AI crows (Boids/GameServer never route through `computeMouseAim` — the 1-v-4 mob is unaffected). Sign structure re-derived from vector primitives (the S25 lesson): all consistent.

### ▶ S28 PLAYTEST CHECKLIST (fly the EAGLE in mouse-aim — the rubberband gate is #1)
1. **THE GATE — rubberband dead?** Swing the cursor hard left/right (60°+). The reticle should sweep smoothly at the eagle's real rate, **decelerate as it closes, and land ON the cursor — no sail-past, no bounce-back, no pulsing.** *Still sails past:* **lower `aimTurnAccel`** (2.0 → 1.4; a gentler bounded deceleration starts the roll-out earlier). *Brakes too early / big catch-up feels mushy:* raise `aimTurnAccel` toward 3.0 or `aimTurnP` toward 3.2.
2. **Small-input snap IDENTICAL + jitter gone?** Deflections under ~10° must snap exactly like the S26 baseline (they run the same code path), and small mouse movements must NOT "jump around" (nothing differentiates the mouse anymore). *Any new small-input weirdness:* suspect the blend boundary — raise `aimDirectConeDeg` (more old-feel range).
3. **The coordinated LOOK (Chad's spec):** a big turn should read as bank+yaw INTO the turn, then the nose pulling smoothly along one clean arc — "deterministically coordinated." The porpoise stays fixed (the S27 FF is unchanged underneath).
4. **CS-1 re-confirm (LOCKED):** hold any flight key with the cursor far off-nose → ZERO cursor pull; a held-S loop stays straight.
5. **Suspension transitions (red-team R1 fix gate):** mid-hard-turn, tap Space (free-look) and back, and hold/release RMB zoom — resuming mouse-aim must NOT kick the roll the wrong way (the bank command now re-seeds from the live bank on every suspension).
6. **Loops unaffected:** top-edge cursor → loop commits exactly as before (vertical errors run the direct law). Also try a hard LATERAL cursor while climbing steeply (45–65°) — red-team W2: the flattened heading error is exaggerated there; over-banking is bounded by the 70° cap but report the feel.
7. **Sustained rim-pinned turn:** steady rate, no pulsing. The cascade caps commanded bank at 70° — if the max-rate turn feels NERFED vs before, raise `aimMaxBankDeg` toward 72 and/or `aimTurnP`.
8. **Slow-speed turns:** S26e/f protections unchanged, and the cascade inherently demands LESS bank when slow (`φ_d ∝ V`) — slow turns should sustain at least as well as S26f.
9. **Possess a crow (1–4), repeat gates 1 + 7.** The turn-rate cap is profile-scaled (crow `pitchRate` 3.6 keeps its snap), but **`aimBankSlew` is SHARED** — red-team W3: the crow's faster roll (5.0 vs 3.2) no longer shows in large-error turn ENTRY. **Chad Q (ask-don't-guess): should `aimBankSlew`/`aimMaxBankDeg` be per-profile (e.g. slew ∝ rollRate) so the crow's agility identity fully survives under mouse-aim, or are uniform instructor numbers fine?**
- **A/B fallback in one knob:** `aimDirectConeDeg = 999` degenerates the whole cascade to the pure S26 direct law everywhere.
- ✅ **VERIFY TIER FIXED (S28d) — the "pre-existing luau-lsp crash" is ROOT-CAUSED and DEAD.** It was never PowerShell: `verify.ps1` fetched `globalTypes.d.luau` from luau-lsp's **`main`** branch — defs a year newer than the pinned 1.32.1 binary — and the parser died SILENTLY (0xC0000409 / bare exit 127, no output) in ANY shell, intermittently. Fixed: the fetch URL is now **pinned to the 1.32.1 tag** (lockstep comment in `verify.ps1`; bump with Bootstrap-Verify's Version) and the matched defs are in `tools/bin/`. The tier now emits REAL diagnostics for the first time. **Baseline of record (2026-07-02): 18 findings, ALL pre-existing** — 7 nonstrict TypeErrors on dynamically-added `cameraState` fields (BirdController 576-629), 1 inference noise at GameConfig:48, 10 lint notes (unused locals / same-line statements) — **ZERO in the S28 cascade code**. The tier exits 1 on this baseline: judge a diff by NEW findings vs this set, not by exit 0. (Also fixed: the S27-flagged duplicate `invertPitch` key — the dead legacy copy at the old virtual-stick block is deleted; the live key sits with the aim knobs.)

</details>

**FRONTIER:** Chad confirms the baseline feel is back (+ the freed cursor circle) → then either (a) his-hands micro-tune of `aimLeadTime` from 0.08, or (b) park the aim loop and move to the queue (combat contact rates first — crows mob but still don't hit him; the queue is in the S25/26 box below). Commits: S24/S25 mob commits (`ff76de9`+`19116a8`) **still UNPUSHED**; S27 committed `958d712`, S28 cascade committed `2e3e70e`, and the working tree holds the S28e-off/S28c-failsafe/S28d/cursor-freed state **UNCOMMITTED** (commit split proposed at close).

<details><summary>▶ (S27 close — EXECUTED in S28) The original S28 research directive, retained for the record</summary>

**⚡ STANDING DIRECTIVE FOR THE NEXT SESSION (S28): run the COORDINATED-FLIGHT research brief below BEFORE touching aim code.** This is Chad's explicit correction of S27. The porpoise half is fixed and KEPT, but the mouse-aim instructor still **rubberbands** — the reticle sails PAST the cursor on large turns and JITTERS on small inputs — and Chad's verdict is that this proves the problem was *not well researched*: *"I didn't just want deep research on the porpoising fix, I wanted deep research on coordination of a flight model… research coordinated flight as a whole as it can be applied here… this rubberbanding makes it clear the solution was not well researched. Prepare a deep research prompt for the next agent in a clear context… a holistic solution to achieving coordinated flight via (instructor)."* **The brief is in the box `### ▶ S28 RESEARCH DIRECTIVE` below. Do that first.**

**Where the code sits (post-S27 CLOSE).**
- **KEPT (Chad-confirmed "porpoising seems better"):** the S27 **bank-proportional pitch FEEDFORWARD** — `Controls.aimBankFeedforward = 0.35`, `pitch += (sec(bank)-1)·gain` before the AoA gate, upright-gated, zero at wings-level, mouse-aim-only. Grounded in `docs/RESEARCH-instructor-turn.md` (ArduPilot `PTCH2SRV_RLL` + Science Robotics tail-twist). This is ONE correct piece of coordinated flight (elevator pays the turn's altitude) — the S28 research must place it in the full model, not discard it blindly.
- **REVERTED (S27b + S27c — the myopic patches that "fixed one thing and ruined another"):** raising `aimPitchDamp`(0.64→0.80) / `aimRollDamp`(0.58→0.72) added arrival lag and didn't kill the horizontal sail-past; the S27c derivative-on-error `aimHorizLeadDamp` amplified mouse jitter → small-input "jumping around." Both are **reverted to the S26 values Chad tuned + loved**. Lesson logged in memory. The one S27b change KEPT is `aimAnglePerPixel 0.0035→0.0024` (his standalone "cursor too sensitive" ask; orthogonal to coordination).
- **STATUS:** build-green, UNCOMMITTED. The aim loop is back at the S26-loved baseline + the porpoise FF + the sensitivity tweak. Do NOT keep knob-twiddling the 3-servo instructor — the S28 research is the path.

### ▶ S28 RESEARCH DIRECTIVE — hand this to the `deep-research` skill verbatim-ish (COORDINATED FLIGHT via the instructor)
**The real problem (why S27's servo patches can't win).** `BirdController.computeMouseAim` is **three INDEPENDENT per-axis PD servos** (roll PD, pitch PD, yaw P) each separately reaching for the shaped cursor error. That is a position-servo, not a coordinated-turn law, so: it overshoots HEADING (bank→turn→heading is a double integrator — roll-rate damping settles the *bank*, not the *heading*, so the nose sails past for a split second); per-axis damping to fix that adds arrival lag (kills the small-input snap); and derivative-on-error amplifies mouse jitter (small-input "jumping around"). Every servo patch trades one symptom for another — that's the tell that the *structure* is wrong.

**Chad's target behavior (the success spec — quote):** *"I move the cursor and the reticle snaps straight to it with very minimal lag upon small inputs; with larger inputs the flight model should be coordinated such that the reticle may have its limits given the flying ability of the eagle, but it should catch up to the cursor with deterministically coordinated flight… coordinated flight is achieved in a plane [by] yaw and bank together then elevator… this makes a flight line smooth. We need smooth coordinated flight."* So: **snappy for small errors; for large errors, rate-limited by the eagle's real agility but a SMOOTH, DETERMINISTIC, COORDINATED catch-up with NO overshoot and NO jitter.**

**Research questions (gear the WHOLE study at coordinated flight, not one symptom):**
1. How do real systems turn a desired aim DIRECTION (world/screen point) into a smooth coordinated turn that arrives WITHOUT overshoot? Cover (a) **bank-to-turn (BTT) autopilots** (aircraft/missile: roll to commanded bank, coordinate yaw, pull load factor); (b) **proportional-navigation / pursuit guidance** (commanded turn rate ∝ line-of-sight rate) as the OUTER law that sets the bank; (c) how **War Thunder / IL-2 / flight-sim mouse "instructors"** actually map the aim point to coordinated stick+rudder+elevator (the FULL instructor, not just pitch).
2. The **coordinated-turn law** itself: for a desired heading change, what bank / coordinating yaw (rudder) / elevator (load factor n=1/cos φ) hold it, and in what SEQUENCE/coupling (bank+yaw lead, elevator sustains)? Express it as a per-frame controller a game can run.
3. **Arrival without overshoot under RATE LIMITS** (finite eagle roll/pitch/yaw rates): how do guidance laws settle a rate-limited vehicle ON target deterministically — model-reference / critically-damped second-order reference model, trajectory (S-curve) shaping, time-to-go / terminal guidance? The crux is Chad's spec: snappy-small, smoothly-rate-limited-but-non-overshooting-large.
4. **Feedforward vs feedback split:** what belongs in FEEDFORWARD (the required bank/yaw/elevator for the commanded turn rate — open-loop, no phase lag, deterministic → the smooth "flight line") vs a small feedback TRIM (null residual aim error) — so it's not a servo hunting. (The KEPT S27 bank→pitch FF is one FF piece; place it in the whole.)
5. **Axis DECOUPLING:** our 3 servos fight each other. How is a coordinated-turn controller structured so roll/yaw/pitch are COUPLED (ONE turn command drives all three consistently) instead of three servos each chasing the cursor?
6. **Constraints the recommendation MUST fit:** no-auto-level 6DOF grip kernel (velocity-follows-nose; CS-5/CS-6, do not touch the signed-off kernel), WORLD-anchored cursor (CS-8), CS-1 aim-gate (keyboard overrides), and it must be MOUSE-AIM-ONLY, **zero at wings-level** (signed-off straight-flight feel untouched). Biological anchor (optional, honest): the eagle's bank+tail/yaw-then-AoA sequence (S27 research) is the same intuition — but the LAW comes from guidance/BTT literature; don't fabricate biological constants.

**DELIVERABLE:** a concrete recommended CONTROLLER STRUCTURE for `computeMouseAim` — the outer guidance law (aim direction → commanded turn rate/bank) + the coordinated inner law (bank+yaw+elevator coupling) + the arrival/rate-limit shaping that yields snappy-small / smooth-rate-limited-large with NO overshoot or jitter — concrete enough to implement against our kernel, and explicit about what to REPLACE (the 3 independent PD servos) vs KEEP (world-cursor model, the bank→pitch feedforward). ⚠️ Note the S27 process lesson so the next agent doesn't repeat it: the search+verify phases are gold, but the final synthesis agent hung on a schema-retry loop — if it stalls, TaskStop it and synthesize from the journal's verified claims (they're all written to `journal.jsonl`).

**After the coordination rework lands: the NEW FRONTIER QUEUE below** (contact rates first — crows mob but still don't hit him). THE MOB WORKS (S24/S25 playtest-confirmed; commits `ff76de9`+`19116a8`, **still UNPUSHED**).

</details>

---

<details><summary>▶ (S26 CLOSE) The research directive that produced the S27 fix — retained for the full brief</summary>

**⚡ CHAD'S STANDING DIRECTIVE (S26 close, NOW EXECUTED in S27).** Session 26 closed with one residual and an explicit ask: *"when I try to use the mouse to turn HARD is when that porpoising happens — it seems to go down to keep the speed. I wish it would not dip down as it turns, because in the heat of the moment that throws you off target and it matters when trying to merge with the crows… I want a round of DEEP AND RELEVANT RESEARCH on this instructor problem with this specific mouse cursor authority setup."* → done in S27; see `docs/RESEARCH-instructor-turn.md` + the S27 session block.

### ▶ THE RESEARCH BRIEF (state it to deep-research verbatim-ish)
**Problem:** a War-Thunder-style mouse-aim "instructor" (virtual pilot) over a 6DOF no-auto-level flight kernel NOSE-DIPS / porpoises in hard banked turns at low-to-mid speed. Physics: bank tilts the lift vector, vertical lift = L·cos(bank) < weight → the bird descends unless AoA/pitch-up compensates; lift ∝ v². **Our instructor compensates with ERROR FEEDBACK ONLY** — a PD pitch loop (P=8.2 on the shaped cursor vertical error, D=0.64 on body pitch-rate) — and two recently-added stability concessions deliberately WEAKEN that pull exactly when the turn needs it: (a) S26e speed-scaled P-gain (×[0.35..1] vs profile glideSpeed — slow = soft pull), (b) a stall-guard easing the nose-up pull across a 7° AoA band below stall (bypassed while flap-powered). Roll is PD (7.5/0.58) + a wings-leveling assist; yaw coordinates at 1.55. The cursor is a WORLD-anchored direction (CS-8, LOCKED — Chad re-chose it over a screen-stick 2026-07-02); camera heading-lag 4.0; the aim gate CS-1 zeroes all of this while any flight key is held.
**The telling asymmetry:** our AI-crow autopilot HAS a coordinated-turn FEEDFORWARD (`turnPitchUp`: up-elevator ∝ bank, applied as it banks, before error develops) and the bots hold altitude in turns; the player instructor has NO feedforward — it pulls only after the sag shows up as cursor error, then the stability concessions soften the pull → dip.
**Research questions:** (1) How do real mouse-aim instructors (War Thunder, IL-2 autopilot, drone/RC flight controllers) hold altitude through hard banked turns — bank-proportional pitch feedforward (∝ tan θ or 1/cos θ), gain scheduling vs airspeed, or continuous AoA governors (vs our band-gate)? (2) Best practice for adding feedforward to a PD error loop WITHOUT re-introducing the porpoise (feedforward doesn't fight damping the way P-gain does — verify). (3) How to reconcile altitude-hold feedforward with the stall boundary at low speed (the crow merge fight lives there) — AoA-limited feedforward? (4) Any interaction with the world-anchored cursor model (the pull must not curve flight when the cursor is centred — cursor-on-nose must stay straight; CS-1/CS-8 constraints).

**⚡ CHAD'S FRAMING + BIOLOGICAL ANGLE (added at S26 close — the load-bearing steer for this research):** the correct coordinated turn = **BANK + coordinating YAW for stability, THEN elevator (pitch/AoA) to SUSTAIN the turn and pay the altitude the bank costs.** Chad's explicit ask: **deep-research what a REAL EAGLE's coordinated turn actually looks like** (raptor turn dynamics — bank angles, how they use tail/AoA to hold a thermalling or attacking turn, load factor vs airspeed, wing morphing) **and translate THAT into the instructor tuning IF PRACTICABLE.** Hard constraints on the fix (non-negotiable):
> - **If faithful eagle-dynamics mapping is too complex, fall back to the SIMPLEST tuning that removes the dip** — a small bank-proportional pitch feedforward term is acceptable as the simple form.
> - **It MUST NOT break the lock-ins** (CS-1 aim gate, CS-5 no-auto-level, CS-6 grip/cl0>0, CS-8 world-cursor, the signed-off eagle flight feel, kernel invariants). Whatever lands must be MOUSE-AIM-ONLY and **zero at wings-level** (straight flight and the loved feel untouched).
> - **SURGICAL only** — it may not change the experience beyond fixing the hard-turn nose-dip. No broad re-tune riding along.
> - Prefer real research that "suits our purposes" (raptor flight dynamics literature / coordinated-turn aero); if none maps cleanly, SAY SO and take the simple feedforward. Don't invent a biological justification that isn't in the sources (anti-reward-hacking).

**Likely landing zone (to verify, not assume):** `pitch += bank-feedforward · aoaGovernor` in computeMouseAim, gated to mouse-aim only, zero at wings-level so straight flight is untouched; the AI autopilot's `turnPitchUp` (up-elevator ∝ bank) is the in-repo precedent and the simple-fallback shape. Note the **yaw channel already coordinates** (`aimYawGain`) — the missing piece is the sustaining ELEVATOR-vs-bank coupling, exactly Chad's "then pitch the elevator to sustain the turn."

**Where it stands (post-S26).** THE MOB WORKS (S24/S25 playtest-confirmed; commits `ff76de9`+`19116a8`, **UNPUSHED**). S26 aim-QoL live-tune rounds a→f all Chad-validated incrementally ("really good… way better… yes it's good"): restored screen-centred cursor clamp (`aimCursorAreaFrac 0.5` + fit-inside-screen hard cap, 48px margin) · `mouseAimDistance 230` · `aimHeadingLag 4.0` (**preference REVISED for the record: he does NOT like heading lag — tight camera; memory updated**) · gains `roll 7.5 / pitch 8.2 / yaw 1.55`, damps `0.64/0.58` · S26e speed-scaled pitch gain (`aimLowSpeedGainFloor 0.35`, `aimSpeedGainRef 1.0`) · `aimStallBandDeg 7`. **CS-1 RE-CONFIRMED LIVE** ("keyboard overriding the mouse for full deflection works great"). Residual = the hard-turn nose-dip above (the research directive). **After the instructor: the queue below (contact rates first — crows still don't hit him).**

*(The S25/26 detail box below is retained for the blow-by-blow.)*

</details>

---

## ▶ (S25/26 detail) COLD START — post-Session 25/26, 2026-07-02

**🎉 THE MOB WORKS — S25 PLAYTEST-CONFIRMED (playtest 7, 2026-07-02).** Chad: *"yep they stayed around me and mob me now, I saw one chasing me, saw one crash, their turns are tight I can't get in their circle easily. Especially the last one that stuck around me — it would fly in front of me. I killed one of them but it is hard to get a kill… I feel that the crows are mobbing now, but they are not hitting me and it is hard to hit them — I did get a kill, it took a great deal of setup and focus."* The sign fix (S25) + independent-attacker blend (S24) are validated; committed as two commits (see SESSION 25). **The frontier is now COMBAT CONTACT RATES + eagle-experience polish** — see the NEW FRONTIER QUEUE below.

### ▶ NEW FRONTIER QUEUE (from Chad's playtest-7 notes, priority order)
1. **Cursor circle + aim zoom-out (S26, IN TREE, needs his Play — second attempt).** Chad: *"cursor goes all the way to the edges and corners; my cursor circle should be centered, about 5/8 of the screen"*; and (after choosing to KEEP the world-anchored CS-8 model over a screen-stick — explicit AskUser decision 2026-07-02): *"we will try zooming back ~50% from the bird in mouse aim — I need to see more around me in the turn."*
   - **Attempt 1 FAILED his play and is REVERTED:** shrinking the NOSE-cone (`aimLeadScreenFrac 0.95→0.625`) can't shrink the visible circle (the cone follows the nose, which heading-lag puts off-centre mid-turn) and made the rubber-band worse (nose caught the cursor ~40% faster → pulsing). Do not retry.
   - **What's in the tree now:** (a) **RESTORED the screen-centred cursor clamp** — `Controls.aimCursorAreaFrac` (his June-30 player-confirmed 7/8→3/4→1/2 tune) had been silently UNREAD since the nose-chases-cursor rewrite (`git log -S` verified: born `b54986c`, dropped `b094984`); reimplemented CAMERA-relative in `computeMouseAim` (faithful to the original screen-space radial clamp — red-team verified) and set to **0.625** (his 5/8). (b) `Camera.mouseAimDistance 135→200` (his +50% zoom-out). Red-team REVISE→addressed; both build-green.
   - ⚠️ **Disclosed tradeoff (red-team #1):** in a sustained FAST turn the lagging camera + the centred bound eat into usable cursor lead → max-rate turns can soft-cap (eagle brushes it; a possessed CROW's 2.1 rad/s hits it harder). The centred circle and the cursor-hangs-out lag are in direct tension. Knobs: `aimCursorAreaFrac` up, or `aimHeadingLag` up (trades against the loved hang-out feel).
   - **S26c LIVE-TUNE ROUND (Chad flew attempt 2: "it's a lot better… already much better", then dialed):** zoom `mouseAimDistance 200→230`; **PREFERENCE REVISED "for the record": he does NOT like the aim heading lag** ("I wanted it tighter; the reticle should snap tighter to the cursor") → `Camera.aimHeadingLag 1.4→2.6`; reticle catch-up gains `aimRollGain 6.5→7.5`, `aimPitchGain 7.2→8.2`, `aimYawGain 1.4→1.55`, damps in ratio (`0.58→0.64`, `0.52→0.58`); cursor circle "a little smaller — it still hits the upper flat limit of the screen and the turn direction gets hard to control there" → `aimCursorAreaFrac 0.625→0.5` **+ a code hard-cap fitting the circle radius INSIDE the screen** (half-height − 48px margin; an area-fraction circle can be taller than the screen, and the flat-topped rim was the controllability bug). The heading-lag "hangs-out" feel is no longer protected (memory updated).
   - **S26c PLAYTEST GATES:** (1) rim-pinned sustained turn — steady rate, no pulsing (the tighter camera should make this BETTER); (2) circle fully round, never flat against any edge; (3) reticle snap reads tight (else `aimHeadingLag` up more); (4) CS-1 re-confirm (held-S loop straight); (5) zoom 230: eagle readable + no camera-in-rock along mountain walls (no occlusion popper exists); (6) possess a crow, repeat gate 1.
   - **S26d (Chad live): "really good"** → `aimHeadingLag 2.6→4.0` (more turn authority feel in mouse+keyboard combos). **CS-1 RE-CONFIRMED LIVE: "the keyboard overriding the mouse for full deflection works great."**
   - **S26e — low-speed instructor porpoise (Chad: "at slower speeds the instructor causes oscillations up and down in the turn; maybe lift?").** Diagnosis: NOT lift (kernel signed-off; the plant is fine) — the aim pitch loop was SPEED-BLIND (full S26c gain at any airspeed; weak slow wings + AoA riding the 4° stall band = pump). Fix: pitch P-gain scaled by airspeed vs profile glideSpeed, clamped to `[aimLowSpeedGainFloor 0.5, 1]`; D-damp unscaled → relatively better damped when slow; **at/above glide speed the tuned snap is numerically IDENTICAL.** Knobs + escalation path documented at `Controls.aimLowSpeedGainFloor/aimSpeedGainRef` (next levers: floor→0.35 or `aimStallBandDeg` 4→7). Client-only, kernel untouched. Needs his slow-turn Play.
2. **Combat contact rates — BOTH sides too low.** Crows mob but *"they are not hitting me"* (are dive-bomb passes converting to rams? relSpeed≥90 gate vs the ~140 pass speed against an evading eagle) and *"it is hard to hit them"* (tight-turning crows vs talon/beak cones — S17 reach may need another look now that targets actually maneuver). This is the first REAL 1-v-4 balance data; tune deliberately, one knob at a time (`attackPeriod`, ram gate, strike cones/reach).
3. **Off-screen enemy direction arrows (HUD feature).** Chad: *"in a turn fight it would help to have little arrows on my screen edge to denote their direction from my view."* New GameUI element; client-only.
4. **Free-look → mouse-aim snap-back lag while maneuvering** — Chad: *"still a bit of an issue"* (S21 improved it, not fully). Known residual; investigate the exit-transition easing.
5. **Speed-scaled camera zoom** — Chad: *"at lower speeds required to turn fight the crows I need to be zoomed out a bit more."* Consider camera distance scaling toward the low-speed end (Camera config; watch CS interactions).

**Where it stands (detail).** Chad's 5th playtest: *"crows are not mobbing, they scatter and fly away"* → S24 stopped tuning and read the wiring. His 6th playtest (same day, on the S24 fix): *"still flying away right from spawn, I can only catch them, they don't engage me"* → **S25 found THE root cause (below). Playtest 7 confirmed it.** S24+S25 committed as two commits; S26 (cursor circle) is in the tree awaiting his Play.

**S25 — THE ROOT CAUSE: AI horizontal steering was SIGN-INVERTED since the beginning.** The kernel applies `CFrame.Angles(pitch, yaw, roll)` about local axes ⇒ **+roll raises the right wing (banks LEFT), +yaw swings the nose LEFT** (verified from the rotation math; the client key map A=+1 "bank left", the mouse-aim's negated horizontal command, and the server autopilot's leveling all use this convention). But `Boids.steeringToInput` computed `yawError` (+1 = target RIGHT) and fed it **un-negated** into roll/yaw ⇒ every AI crow turned AWAY from its goal — and "goal dead astern" is the **stable equilibrium** of an inverted controller, so crows flew calmly straight away from the eagle forever. This explains ALL six playtests: flee-from-spawn ("I can only catch them" — straight-line flight is catchable), the dive-bomb attacker fleeing *faster* (goal=eagle + raised speed cap), and the old strong avoidance sending crows "18-20 km away"/into terrain (avoidance steer passes through the same inverted mapping — "steer away from wall" became "turn toward wall"). Red-team re-derived the math from primitives, confirmed the stability analysis, and found **no counter-evidence** — no playtest ever showed crows demonstrably approaching; "they ring the eagle" was agent assertion, never a Chad quote. **Fix: 2 lines** — `input.roll = clamp(-yawError)`, `input.yaw = clamp(-yawError*0.35)` (pitch was already correct and is untouched). Single call site (`updateAICrows`); nothing compensated for the old sign, so nothing double-turns; player input never routes through `Boids`.

**S24 (same tree, DEMOTED to secondary by S25):** two real wiring defects — the `clumpSpread` flag was a no-op (no code ever read it; all 4 bots ring one ~19° sector) and mob mode never dropped the flocking blend (alignment/cohesion stayed on; research says independent attackers, cohesion DROPS). Fixed via `Squad.mob.steering = {spacing=30, cohesionMul=0, alignmentMul=0, separationMul=1.4}` passed as formationCfg while mobbing (+ `alignmentMul` support in `computeSteering`). Real defects, kept — but they were analyzed on top of an inverted controller, so S24's "scatter root cause" framing was wrong; the crows never sat on the ring long enough for flock-drift to be the driver. `mob.steering = nil` restores the old blend to A/B the sign fix in isolation.

### ▶ S25 PLAYTEST CHECKLIST (aiCrowOpponents: fly the EAGLE vs the bot mob) — expect the FIRST real mob
⚠️ **Framing: with steering finally pointing TOWARD goals, every mob number (ring 180, attackPeriod 1.4, keep-up 128, bank cap 66°, S17 strike lethality, ram trades) is effectively UNTUNED — it all goes live for the first time. Expect to tune, not to judge the model.**
1. **Do they ENGAGE from spawn?** The wave spawns ~700 out and should now fly AT you, ring you at ~180 studs, and press — no fleeing. *Still flee from spawn:* report immediately — that would falsify the sign diagnosis (red-team says it can't, but ground truth is your Play).
2. **⚠️ BALANCE FLIP WATCH (red-team F3 — lead item):** ~1-2 *accurate* 140-stud/s dive-bomb passes continuously + rams landing for the first time (each ram = big damage) may flip the 1-v-4 hard crow-favored. *Too relentless:* raise `diveBomb.attackPeriod` (1.4 → 2.0-3.0) FIRST; then lower `attackSpeedMul`.
3. **⚠️ KNIFE-EDGE FALL WATCH (now genuinely live):** ring crows will now actually sit ~3° under the 66° bank cap chronically. If a crow rolls past vertical and spirals in while turning with you: **WIDEN `orbitRadius`** (180→200+), do NOT lower `maxBankCos` (understeer coupling: holdable iff v ≤ √(79·R)).
4. **Do they SURROUND you?** After ~20-30 s, attacks from different bearings — or one sector? *One sector:* pre-registered fallback = per-crow bearing offsets in `mobOrbitTarget` (small, surgical).
5. **Ring-mate sling watch:** a crow flung off-station when two pass close (<60 studs) → lower `mob.steering.separationMul` or raise `boids.goalWeight`.
6. **Terrain/avoidance regression:** avoidance now steers the RIGHT way for the first time — crows should arc around spires. Watch for any new weirdness near walls (the 3.0 weight was tuned against the inverted sign).
- **Fallbacks:** `mob.steering=nil` → old flock blend (A/B the sign fix alone); `diveBomb.enabled=false` → pure orbit; `mob.enabled=false` → no mob; `aiFlight.enabled=false` → raw boids (don't).
- ⚠️ Verify-harness note: `verify.ps1`'s luau-lsp tier FAILs via a **pre-existing** silent luau-lsp crash under PowerShell (reproduced on clean HEAD; direct invocation with sourcemap+defs analyzes CLEAN, exit 0). Don't attribute that FAIL to your diff.

*(Prior S22/S23 cold-start detail retained below.)*

---

## ▶ (S22/S23) COLD START — post-Session 22/23, 2026-07-02

**Where it stands.** **S16-S23 were COMMITTED + PUSHED to `origin/master` on 2026-07-02** (Chad: *"commit everything and push to remote and merge to main"* — master IS main; no feature branch). That batch = crow dive-bomb [S16] · eagle strike-lethality [S17] · mob flight retune [S18-19] · aim snappier + eagle dive/flap top speeds [S20] · free-look exit fast-return [S21] · eagle glide-coast/energy retention [S22] · RMB-zoom visible reticle [S23]. All build-green + red-teamed where load-bearing. ⚠️ **Committed but still largely UNPLAYTEST-CONFIRMED** — Chad felt out the eagle-flight/camera/aim asks live (S20-S23) but the mob (S18-19) + combat balance (S16/S17) were NOT validated in a real 1-v-4. Those playtest checklists (below in each session block) still stand — treat the balance numbers as PROVISIONAL and re-check the 1-v-4 next session.

**S23 — RMB awareness-zoom: show the boresight reticle AT the zoom centre (Chad ask, camera/HUD-only, needs his Play).** Chad: *"holding RMB zooms a bit — about a degree — ABOVE the reticle; I want it right on the reticle."* **TWO wrong theories, both disproven by playtest — documented so nobody re-tries them:** (1) parallax → matched zoom look distance to the reticle's (2000→**4000**); "still above." (2) GUI-inset → a signed camera pitch (`aimZoomVertBiasDeg`); "about the same." The pitch did ~nothing because **the aim reticle is a WORLD-point projected through the LIVE camera — pitching the camera moves the reticle and the content TOGETHER, so their relationship can't change that way.** Also confirmed `aimGui.IgnoreGuiInset = true` (line 210) — SAME as the HUD crosshair — so the reticle projection is already correct (inset theory dead too). **The actual issue:** during RMB zoom the amber reticle was **hidden entirely** (`aimGui.Enabled=false`), so there was NO aim reference in the magnified view — Chad was eyeballing against the faint centre crosshair / his memory → read as "above the reticle." **Outcome (Chad's decision):** the offset is vertical PARALLAX from the chase-cam HEIGHT — the camera sits ABOVE the bird, the reticle is 4000 studs out along the beak, and a nearer enemy projects LOWER than that far point, so the reticle floats above the target (worse the closer it is; that's why matching reticle/zoom distances never helped). A fix that flattened the camera to directly-behind during zoom (`heightRatio *= (1-factor)`) removed the parallax BUT Chad **rejected it** — *"I don't like that the level of the view changes relative to the bird, it's disorienting; I'd rather stay a bit above, keep the reticle."* So that flatten was **REVERTED**. **KEPT:** the visible boresight reticle during zoom (Chad likes it). **ACCEPTED:** the small reticle-above-near-target parallax is a deliberate trade for a stable, un-disorienting over-the-shoulder zoom. Net S23 change = reticle now visible during RMB zoom; camera framing unchanged. **No open follow-up** — Chad settled it.

**S22 — eagle energy retention / glide-coast (Chad ask, needs his Play).** Chad: *"I lose energy 420→250 so fast if I zoom up; in glide mode I need to keep speed a LOT longer if I'm not turning or climbing, just staying aerodynamic."* **Root cause (found, not guessed): the dominant speed-killer above cruise was a hard-coded `1 - dt*0.5` term in the `FlightPhysics` speed-cap block** — an artificial exponential pull of speed ABOVE `maxLevelSpeed` back to cruise (~125 studs/s² at 420, dwarfing real drag ~2 and climb-gravity ~10). Made it a **per-profile `glideBleed`**: Eagle **0.15** (coasts — 420→250 now ~7-8 s vs ~2 s), Crow **0.5** (unchanged, protects the 1-v-4). Also Eagle **`energyRetention` 0.7→0.82** for the zoom-climb. Red-team CLEAR — kernel invariants survive, dive untouched, **no noclip/runaway** (still asymptotes to cruise, just slowly), anti-cheat neutral, phugoid intact.

### ▶ S22 PLAYTEST CHECKLIST (fly the EAGLE)
1. **Coast (the ask):** dive to top speed, level off hands-off (no flap, no turn) → speed should HOLD high and bleed slowly (420→250 over ~7-8 s, was ~2 s). *Want it to hold even longer:* lower Eagle `glideBleed` (0 = never bleeds below terminal). *Coasts too long:* raise toward 0.25-0.3.
2. **Zoom (the ask):** from top speed, pull a hands-off ~30-45° climb → converts much more speed to altitude before washing out. Knob: Eagle `energyRetention` (0.82, cap 0.95).
3. **No runaway (safety):** a long hands-off level glide must EVENTUALLY settle to ~170 (cruise), not hold 400 forever. (Red-team confirmed it does; just eyeball it.)
4. **Dive unchanged:** stoop still tops at `diveSpeedCap` (390) and stamina still regens (CS-9) — should feel identical to before.
5. **1-v-4 (re-check WITH the mob):** the coast extends the eagle's disengage window ~3.5× — can 4 crows still force a merge / corner it, or does it just coast away? *Coasts away too easily:* Eagle `glideBleed`→0.25 or raise `Crow.maxLevelSpeed` — NOT a kernel change. **Open Q for Chad:** is coasting-away an intended eagle escape, or must the mob always be able to force a merge?
- Knobs: Eagle `glideBleed` (level-coast) + `energyRetention` (zoom-climb) — separable. `FlightPhysics` speed-cap uses `p.glideBleed or 0.5`.

*(Prior S20/S21 cold-start detail retained below.)*

---

## ▶ (S20) COLD START — post-Session 20, 2026-07-02

**Where it stands.** Last commit is `f8eabbc`. **The working tree holds an UNCOMMITTED STACK — S16 (crow dive-bomb) + S17 (eagle strike-lethality) + S18→S19 (mob flight retune) + S20 (mouse-aim snappier + eagle dive/flap top speeds) + S21 (free-look exit fast-return) — all build-green + red-teamed, none committed** (`GameConfig.luau`, `GameServer.server.luau`, `BirdController.client.luau`, `HANDOFF.md`). Commit only when Chad OKs the feel, and **SPLIT into logical commits** (per red-team: eagle flight-feel [S20] / free-look camera [S21] / mob flight [S18-19] / dive-bomb system [S16] / eagle combat buffs [S17]).

**S20 — Chad-requested tuning of the SIGNED-OFF eagle flight + player-tuned aim (needs his Play).** Both are GameConfig-only (kernel code untouched; red-team CLEARed both — no LOCKED violation, aim loop verified stable, anti-cheat inside envelope):
- **Mouse aim snappier (CS-8 tuning):** *"at close range it lags; small deflections should SNAP in a fraction of a second — only a large deflection should visibly catch up."* Raised the nose-chases-cursor P-gains (`aimRollGain` 4.5→6.5, `aimPitchGain` 5.0→7.2, `aimYawGain` 1.0→1.4) + damping in step (`aimPitchDamp` .45→.58, `aimRollDamp` .40→.52). Higher P saturates the command at a smaller error → small/medium gaps close at the eagle's max turn rate (snap); big deflections still turn-rate-limited (the intended lag). Red-team verified: it's a rate loop (exponential decay, no ringing), damping raised enough, dead-centre deadzone/expo untouched (fine aim preserved).
- **Eagle dive/flap top speeds (kernel numbers):** *"dive should hit ~390; 420 is the top achievable by flapping out of the dive — the flap boosts/maintains it."* `Eagle.diveSpeedCap` 320→**390**, `Flight.TERMINAL_VELOCITY` 400→**420**. Kernel model (verified): a diving eagle hard-caps at `diveSpeedCap` (390); a NON-diving FLAPPING eagle is capped only by `TERMINAL` (420) — the bleed-to-`maxLevelSpeed`(170) is skipped while flapping — so flapping out of a stoop holds/boosts up to 420; hands-off glide bleeds to 170. Anti-cheat ceiling scaled to 525 (legit 420 safe). Crow (diveSpeedCap 220) can't match it — the eagle's energy dominance IS the 1-v-4 identity.

### ▶ S20 PLAYTEST CHECKLIST (fly the EAGLE)
1. **Aim snap:** small deflection / close range → nose snaps to the cursor in a fraction of a second; only a LARGE deflection shows visible reticle catch-up. *Rings/twitches at dead-centre:* raise `aimPitchDamp`/`aimRollDamp`; *still laggy:* raise `aimPitchGain`/`aimRollGain`.
2. **CS-1 re-confirm (LOCKED):** hold W/S/A/D while moving the mouse → cursor has ZERO pull (the snappier gains must NOT leak into keyboard flight). A held-S loop must stay straight.
3. **Speeds:** pure stoop tops **~390**; flap OUT of the dive → climbs to **~420** and holds; hands-off glide bleeds to ~170. Sustain 420 several seconds → NO rubber-band/kick (anti-cheat). *(Camera shake grows with speed and is unclamped — if 420 shake reads as too much, that's a one-line clamp, not a speed rollback. red-team #6.)*
4. **flight==balance (playtest WITH the mob):** with dive 390 / flap-top 420, can 4 crows still pressure/corner the eagle, or does it just out-run every mob pass? *Out-runs them:* the lever is a faster crow dive-bomb pass (`Crow.maxLevelSpeed`), per the S19 note.

**⚠️ THE MOB (S19) IS STILL UNTESTED — Chad "flew by myself" this round.** After the aim+speed feel is dialed, return to the S19 mob (see the S19 checklist below): the crows were given back turn authority (bank cap 66°) + keep-up speed (128) + constant dive-bomb harassment (attackPeriod 1.4). If they STILL flee, the model itself is suspect (next levers: un-suppress attacker dives, or drop orbit for direct pursuit).

**⚠️ THE MOB IS THE STUCK PROBLEM — 4 playtests, same "they flee, I chase them like mice" feedback.** S16 (dive-bomb), S18 (tighten+slow) both came back "about the same / they flock off." **S19 is a STRATEGY PIVOT after diagnosing the real mechanism, not another orbit tweak.** The reframe (verified from config + red-team): the crow is BUILT to out-turn (`sustainedTurnRate 2.1` vs Eagle `1.0`), so aero was never the limit — but I'd stripped its whole mob toolkit to stop cosmetic crashes: (1) the **60° AI bank cap throttled its turn advantage** → it hit the cap and understeered OUTWARD (the "flee"); (2) my S18 **speed cut to ~100** made it far slower than the eagle (cruise 130 / max 170) so it **literally can't keep up** = "mice and cat." **S19 gives the toolkit back + pivots to aggression:**
- **Keep up + hold:** `aiFlight.combatSpeedMul` 1.05→**1.35** (~128, near the eagle); `aiFlight.maxBankCos` 0.5→**0.40** (60°→66°, use the designed turn advantage); `Squad.mob.orbitRadius` 150→**180** + `orbitLead`→**60** (holdable ring: ~63° req bank < 66° cap, S14 knife-edge margin mostly restored — red-team's safer alternative to my first 72° pass).
- **PIVOT — constant harassment:** `diveBomb.attackPeriod` 3.4→**1.4** so ~1–2 crows are ALWAYS diving at the eagle from spread bearings (was a lone pass every 3.4s while 3 circled = evasion feel). ≤2 concurrent from different angles — NOT the 4-on-one pile-up (scheduler is stateless per-launch; ~1 attacking + ~1 peeling).

### ▶ S19 PLAYTEST CHECKLIST (aiCrowOpponents: fly the EAGLE vs the bot mob)
1. **Do they MOB you now?** Are crows **coming AT you** — near-continuous dives from different angles, forcing you to dodge — instead of fleeing/circling as "mice"? Can they now **keep up** when you run (they shouldn't out-run you, but should stay engaged via turns + dives)?
2. **⚠️ S14 FALL WATCH (red-team #1 — the real risk of the 66° cap):** does a crow ever **roll past vertical and spiral into the ground while turning WITH you** (distinct from an accepted dive-bomb crash)? If yes: DON'T just lower `maxBankCos` (66° < the 63° the ring needs → they spiral out again) — **widen `orbitRadius`** so a lower bank holds.
3. **Too relentless?** ~1–2 diving continuously may be brutal (each landed ram = 33 to you). If the 1-v-4 is crow-favored, **raise `attackPeriod`** (1.4→2.0+); if still too passive, lower it (keep ≥1.0).
4. **Full-stack 1-v-4 (red-team #2):** with S17's deadlier eagle (talon 24 / beak 28 reach, beak one-shots) + S19's pressing crows — can you kill them AND feel genuinely mobbed, without it being trivial either way?
- **Fallbacks:** `diveBomb.enabled=false` → pure orbit; `mob.enabled=false` → no mob. Knobs: `aiFlight.{maxBankCos,combatSpeedMul}`, `mob.{orbitRadius,diveBomb.attackPeriod}`.
- **If STILL "about the same":** the orbit MODEL itself may be wrong for the feel — next levers are un-suppressing the attacker's DIVE (real dive-bomb energy) or dropping the orbit entirely for direct pursuit-and-harass. Say so and we pivot again.

**S18 — close, holdable, "brave" mob (needs Chad's Play).** Chad's S16+S17 playtest: *"this time they crashed a little more and they get scared and fly away from me right away — they are not brave, they are not mobbing me."* Root cause found via the coordinated-turn physics (red-team-confirmed sound): AI crows fly the **no-auto-level kernel**; the autopilot **caps bank at 60°** (`maxBankCos 0.5`). To HOLD a level orbit of radius R at speed v needs `tan θ = v²/(R·g)`, g≈45.6 → holdable iff **v ≤ √(79·R)**. The old 220 ring at 114 studs/s *was* holdable — it just stood off too FAR (crows station 220 out, fly outward to the ring from spawn; the S16 peel flung them ~352 studs). **Fix (GameConfig only):** `orbitRadius 220→150` (in your face), `aiFlight.combatSpeedMul 1.2→1.05` (~100 studs/s — REQUIRED so the tight 150 ring stays inside the 60° bank cap; else they understeer OUTWARD = the flee), `orbitLead 170→100`, `peelRadiusMul 1.6→1.15`, `peelHeightBias 120→50` (stay near after a pass, not flee far). **⚠️ orbitRadius and combatSpeedMul are physically COUPLED — never tighten R without lowering v (keep v ≤ √(79·R)).**

### ▶ S18 PLAYTEST CHECKLIST (aiCrowOpponents: fly the EAGLE vs the bot mob)
1. **Do they MOB now?** Do the crows hold a close (~150-stud) ring right in your face and keep coming, instead of standing off far / flying outward "right away"? *Still fling out:* they're too fast for the ring — lower `combatSpeedMul` (keep v ≤ √(79·R)) or loosen `orbitRadius`.
2. **Orbit MUSH watch (red-team #4).** At the tight ring the crows sustain ~56° bank (~1.8g) near their 24° stall — do they instead go sluggish / sag in altitude / wobble? *If so:* nudge `combatSpeedMul` up a touch (re-check holdability), lower `aiFlight.turnPitchUp`, or loosen `orbitRadius` toward 170.
3. **Crashes better or worse?** Slower+tighter was *meant* to reduce the terrain grinds but may not (see #2). Report if crashes went down. Note: AI crows are non-lethal on terrain, so "crash" = grinding the deck, not dying.
4. **Dive-bomb still bites?** One attacker at a time commits + peels (never all 4). The pass tops ~140 studs/s (kernel `maxLevelSpeed` clamp — NOT the "171" an old comment claimed), still crosses the 150 ring to contact.
5. **1-v-4 BALANCE — the compounding watch (red-team #2).** The cumulative stack makes the eagle deadlier (S17: talon 24 / beak 28 reach, beak one-shots) AND the crows closer/slower (S18). Can you now hit+kill them (S17 fix) AND do they genuinely pressure you (S18), WITHOUT it becoming trivial to farm the mob one pass at a time? If eagle-favored: cut `talon.reachStuds`→18, then talon uptime, then `beakDamage`. If crows too weak: tighten `orbitRadius`/raise dive-bomb cadence.
- **Fallback flags to isolate:** `Squad.mob.diveBomb.enabled=false` → pure orbit; `Squad.mob.enabled=false` → no mob; strike knobs in `GameConfig.Combat.strikes` + Eagle `beakDamage`.

**SCATTER note:** S18 directly targets the flee/scatter via the holdable-ring physics. If they STILL drift away after this, the next suspects are the boids weights (separation up to 2.1 loose vs goalWeight 2.0) and `alignmentWeight 1.0` (peelers leaving together) — report WHEN they scatter.

*(Prior S17 cold-start below retained for the strike-fix detail.)*

---

## ▶ (S17) COLD START — post-Session 17, 2026-07-01

**Where it stands.** Eagle flight/control/camera feel = **SIGNED OFF** (crown jewel; don't reopen calibration — lift curve · gravity · stall · energy retention · camera · mouse-aim — without a fresh Chad ask). S15 baseline is committed/pushed `f8eabbc`. **S16 (dive-bomb) + S17 (strike-lethality fix) are build-green, RED-TEAMED, PLAYTESTED-PARTIAL, and UNCOMMITTED** — all still in the working tree. Frontier = the crow mob + the 1-v-4.

**S16 dive-bomb — PLAYTESTED, net-positive.** Chad flew the eagle vs the bot mob: *"crows still crash but they live a little longer, I only saw one crash… still scatter but it took longer this time."* So increment 2 (staggered dive-bomb + peel-off, `Squad.mob.diveBomb`) HELPS — fewer crashes, delayed scatter — but **two residuals remain: (a) the crows still SCATTER eventually, (b) they still attrit.** Scatter is the top open mob item now (see queue).

**S17 strike-lethality fix — NEW, needs Chad's Play.** Same playtest surfaced a concrete combat bug: *"I'm pretty sure I'm hitting them with beak/talons but they don't die."* Root cause = two numbers bugs in the eagle's OFFENSIVE strike (NOT logic — the pass is wired + `applyDamage` kills correctly): **(1)** `beakDamage 22 < crow health 25` → a clean beak jab left the crow at 3 HP (couldn't kill); **(2)** offensive `reach ≈ 10.2 studs` (point-blank, ~3.5 past touching) while the ARMED reticle lights at `strikeSelectRange 200` → a crow read "on target" from 20× outside actual hit range. **Fix (one coherent "make strikes kill"):** `beakDamage 22→26` (one-shots a 25 HP crow, still < talon 34); added explicit `reachStuds` (talon **24** conservative, beak **28**) that overrides the point-blank formula in `updateEagleStrikes`. **Cones/timers/cooldowns UNCHANGED** so the 1-v-4 saturation balance (one zone at a time, one hit per window) holds. Red-team CLEARed locked-spec/kernel/contract/logic/parry-isolation; its findings are balance-WATCH items (below). Files: `GameConfig` (Eagle `beakDamage`, `Combat.strikes.*.reachStuds`) + `GameServer.updateEagleStrikes` (one line).

### ▶ S17 PLAYTEST CHECKLIST (aiCrowOpponents: fly the EAGLE vs the bot mob)
1. **Beak kills now?** Head-on, crow ~25 studs ahead in the narrow forward cone, LMB → **crow dies in one beak jab** (was: survived at 3 HP). *Still survives:* raise `beakDamage` past 26.
2. **Talon connects at range?** Crow ~20-24 studs below/below-side in the belly cone, LMB → **one talon = kill** without having to nearly collide (was: point-blank only). *Can't reach:* raise `talon.reachStuds` (watch the balance below).
3. **1-v-4 still fair? (red-team #1/#2 — the thing to watch).** Wider reach means an offensive hit spends the strike's shared `caught` flag → it may **disable the parry** for that window (defense→offense shift): do you now KILL more crows but EAT more rams? And can **4 crows still corner/mob you** and land ≥3 rams to win, or does the talon (24 reach × 70° belly cone @ ~67% uptime) let you pick the orbit apart too easily? *Eagle-favored:* cut `talon.reachStuds` toward ~18, then trim talon uptime, then `beakDamage` — in that order.
4. **(Edge) No strike-through-terrain?** At 24-28 studs near the mountain rings, do you ever kill a crow through a thin ridge? (No LOS check yet — red-team #3.) Only worth a raycast gate if it actually shows up.
5. **SCATTER (still open — the top mob residual).** Do the crows still drift far away over a long fight? This is NOT addressed by S17 — it's the next iteration. Candidate causes to localize: boids `separationWeight`(1.5,→2.1 in loose) vs `goalWeight`(2.0); `alignmentWeight`(1.0) letting peelers leave together; the large `orbitLead`(170); or the S16 peel target being far out (`peelRadiusMul 1.6`→352 studs + 120 up). Report WHEN they scatter (during peel? after a kill? when you disengage?) so we can localize.
- **Not committed** — awaiting your Play. If S16+S17 feel good together it's a clean checkpoint commit. Fallbacks: `Squad.mob.diveBomb.enabled=false` → pure S14 orbit; the strike knobs are all in `GameConfig.Combat.strikes` + Eagle `beakDamage`.

**Open design question (carried from S16):** is "attrites to ~1" a bug or the intended sacrifice-trade? (Bot waves respawn only when ALL 4 die; a landed dive-bomb pass is a deliberate sacrifice.) Chad's call.

**Load-bearing orientation fact:** AI crows are NON-LETHAL on terrain (`updateAICrows` resolves with `math.huge` crashSpeed; `GROUND_FAILSAFE_Y=-200`). An AI crow can only die by ramming the eagle (`processCollisions`, relSpeed≥90) or a deep tunnel. So attrition/"crashes" = combat contact, not terrain — the earlier "orbit ring clips terrain" guess is impossible.

*(Older cold-start below kept for eagle-flight/locked-spec context; the frontier is this box → scatter fix, then 1-v-4 balance.)*

---

## ▶ (prior) COLD START — post-Session 14, 2026-07-01

**Where it stands.** The **eagle flight / control / camera feel is SIGNED OFF** — Chad: *"the flight model of the eagle is largely finished. I'm having a great experience."* This is the crown jewel. **Do NOT reopen its calibration** (lift curve · gravity · stall · energy retention · camera · mouse-aim) without a fresh, explicit Chad ask. **S14 added AI-crow combat + a free-look bugfix** — details in the SESSION 14 block just below.

**AI crows are now FLYABLE and mobbing (partial).** S14 went from "crash + scatter instantly" to Chad: *"I can actually play with the crows now… doing better."* Root cause of the old failure was **AI flight control** (the boids mapping dived at the target → too fast → knife-edged/overshot into terrain), NOT goal geometry — fixed with a flight governor + AI-only autopilot; then the mob **orbit** was enabled so they ring the eagle instead of scattering. All research-grounded (`docs/RESEARCH-crow-mobbing.md`; the reframe: mobbing≠flocking).

**The frontier is COMBAT + the 1-v-4 + the CROW** (not eagle flight). Prioritized queue:
1. **Stabilize the mob (residual from S14).** Chad: *"usually only one, others crashed eventually."* The crows fly/mob now but still **attrit down to ~1 over a long engagement.** Chase why (likely: orbit ring clipping terrain during sustained fights, or crows bleeding energy/sinking after many turns). Knobs live in `GameConfig.Squad.aiFlight` + `Squad.mob` (all tunable, playtest-driven). See SESSION 14 block.
2. **Increment 2 — give the mob TEETH: staggered dive-bomb passes.** Orbit is circle-only (no attacks yet). Add take-turns dive-bomb-from-above + peel-off (never all 4 at once), wired into the existing strike/collision combat. Plan: `docs/RESEARCH-crow-mobbing.md` → "build order".
3. **Verify the BEAK strike path + 1-v-4 balance.** The **TALON** path is playtest-confirmed (first kill landed); **BEAK** is untested. Watch talon uptime (4s active / 2s cd ≈ 67%) — if it plays eagle-favoured, cut `duration` / widen `cooldown` / drop offensive damage FIRST (`GameConfig.Combat`).
4. **Tune the Crow profile + collision trades** for the asymmetric fight. *flight==balance: reason about the whole 1-eagle-vs-4-crow fight on every number.* The eagle now keeps more climb-energy (S13) AND refuels stamina in dives (CS-9) — re-check **4 crows can still corner/mob it**.

**Repo / GitHub / sandboxes (set up S13).**
- `origin` = `https://github.com/cjcgervais/EvC2026.git`; `master` @ `75c39f3` is pushed (S14 crow-AI + free-look fix + bird-detail pass; local == remote).
- **Snapshot branch `single-bird-kernel`** (on GitHub) = this exact state, frozen — a standalone flying-bird kernel to branch from.
- Two adjacent **sandboxes**: `D:\EvC2026_s1`, `D:\EvC2026_s2` — independent full clones (origin→GitHub) for spin-off experiments. Work the main line in `D:\EvC2026`; leave the sandboxes alone unless asked.
- Tags: `v1.0-eagle-flight` (pure kernel), `v1.1-eagle-flight-feel`.

**Hard process rules (Chad's LOCKED-SPEC directive — non-negotiable).**
- **Protect the LOCKED CONTROL SPECS registry (CS-1 … CS-9, below).** Grep/read it before ANY control / camera / input / flight-feel edit. Never change a locked behavior *collaterally* while building something else — foresee interactions (this failed before: keyboard-authority silently curved his loops).
- **ASK, don't guess** on control feel. A wrong guess that ships is worse than a question.
- **LOG every playtest note + outcome** here (registry row / session block) so decisions are durable and never re-litigated.
- **Ground truth is Chad's Studio Play.** `build.ps1` resolves wiring but does NOT run or syntax-check Luau. **ONE change at a time**, keep the build green, tee up a crisp playtest checklist, and **checkpoint (commit/tag) before any kernel edit**.
- **Refine incrementally; do NOT regenerate.** **Work under the `/evc-loop` skill** — the governing harness that enforces all of these rules (orient → one-change → verify → red-team → memory → handoff → approved commit). It specializes the **loop-orchestrator** (roblox-game profile) and composes **deep-research** for the research half. See the SESSION 15 block + `reference-evc-loop-skill` memory.
- **Kernel invariants that MUST survive:** `cl0>0` (grip), auto-level OFF (`STABILITY_RATE=0`, both `recoverNoseDownRate=0`), keyboard-first, **stall < spawn < cruise**. `GRAVITY_G` is the master **loft knob** (a tunable, NOT a fixed invariant) — currently **1.3** (swept 2.0→1.5→1.3); the real invariant is that `AIR_DENSITY` scales with it in lockstep (`GRAV_SCALE`) so the stall/cruise/dive ordering holds at any value. *(Older notes below that say "GRAVITY_G=2.0" predate the sweep.)*

*Read order: this box → the SESSION 15 block (the `/evc-loop` harness) → the SESSION 14 block → the LOCKED CONTROL SPECS registry → `CLAUDE.md` → `MEMORY.md`. To start work: run **`/evc-loop`**.*

---

> ## 🧭 SESSION 28 — COORDINATED-FLIGHT INSTRUCTOR REWORK: deep-research → bank-to-turn cascade replaces the 3 PD servos (2026-07-02) — **build-green + luau-lsp clean, red-teamed (REVISE→addressed), UNPLAYTESTED, UNCOMMITTED**
> Executed Chad's S27-close standing directive under `/evc-loop`: research the MODEL first, then one structural change.
> - **RESEARCH (`docs/RESEARCH-coordinated-flight.md`).** `deep-research` workflow (run `wf_46dddd98-a2e`, 103 agents): 5 angles → 21 primary sources → 102 claims → 25 adversarially verified (3-voter panels) → **22 confirmed / 3 over-claims refuted**; the synthesis completed cleanly (no S27-style stall). The literature CONVERGES: (1) BTT autopilots are COUPLED multivariable controllers — coordination is an achieved property of the design, never per-axis tuning (NASA CBTT; Lin & Yueh). (2) The overshoot mechanism is DIAGNOSED, not guessed: an outer law blind to the roll loop's first-order lag is structurally low-damped (Jung & Tsiotras, verified verbatim) — exactly our sail-past. (3) The no-overshoot arrival mechanism is COMMAND shaping, not error damping: ArduPilot's sqrt-controller (linear small = snappy, bounded deceleration large = cannot overshoot) — and it never differentiates the noisy input (kills the jitter class). (4) ArduPilot itself made this exact migration (PID-servo nav → L1 guidance, PR #101). (5) War Thunder's instructor is a DIRECTION mode (mouse sets desired direction; instructor flies coordinated within airframe limits). (6) MouseFlight contributes the raw-world-cursor split + the ~10° small/large mode blend — its inner servo explicitly REFUTED as precedent (0-3). (7) Hawks steer by ONE coupled turn-rate command (mixed PN/PP, 228 motion-captured pursuits) — biology confirms the shape, engineering gives the numbers.
> - **IMPLEMENTATION (client + 6 config knobs; kernel/pitch-channel untouched).** In `computeMouseAim`: the roll/yaw servos become the DIRECT branch of a blend, verbatim; a COORDINATED branch (`wCoord` = error-size × horizontality × smoothed-upright) runs the cascade: signed horizontal heading error → sqrt-controller (`aimTurnP` 2.5, `aimTurnAccel` 2.0; linDist = A/P², continuous at the boundary) → turn rate capped at profile `pitchRate` → `φ_d = atan(V·ψ̇_d/g)` clamped `aimMaxBankDeg` 70° → slew-limited `aimBankSlew` 2.0 rad/s via persistent `aimBankCmd` (tracks the live bank when idle ⇒ zero engage step; reset on resetInput + both suspension paths) → `roll = −(φ_d−bank)·aimBankGain − aimRollDamp·rollRate`, `yaw ∝ turnCmd`. Pitch channel byte-identical (PD + speed scale + stall gate + S27 FF). `aimDirectConeDeg = 999` = one-knob A/B back to the pure S26 law.
> - **RED-TEAM: REVISE → addressed.** Signs re-derived from primitives (S25 lesson): ALL consistent. CS-1/CS-5/CS-8 verified intact; direct branch verified numerically identical at wCoord=0; sqrt-controller verified faithful to ArduPilot (not a facsimile); AI crows confirmed untouched. **R1 (fixed):** `aimBankCmd` went stale across free-look/RMB-zoom → wrong-way roll kick on resume → now reset on both suspension paths. **W1 (hardened):** binary upright gate could step the roll blend crossing 90° bank → smooth fade over UpVector.Y 0..0.15 (identical inside the 70° cap). **W2 (checklist):** flattened heading error exaggerated at steep climb angles — playtest gate 6. **W3 (Chad Q):** `aimBankSlew` shared across profiles mutes the possessed crow's roll-rate edge on turn entry — per-profile or uniform? Checklist gate 9.
> - **VERIFY:** rojo build PASS; **luau-lsp analyze CLEAN (exit 0)** via direct Git-Bash invocation (the `verify.ps1` tier FAIL = the documented pre-existing PS crash, reproduced again; Git Bash is the working path); selene UNAVAILABLE (upstream 404).
> - **STATUS: UNCOMMITTED, awaiting Chad's Play (checklist in COLD START).** Files: `GameConfig.luau`, `BirdController.client.luau`, `docs/RESEARCH-coordinated-flight.md`, `docs/HANDOFF.md`. **Proposed commit split (red-team R2):** ① S27 feel state (bank FF + `aimAnglePerPixel` + `RESEARCH-instructor-turn.md`), ② S28 cascade (+ `RESEARCH-coordinated-flight.md` + docs). Checkpoint of the pre-S28 tree: `.loop/s28-coordinated-flight/pre-S28-checkpoint.patch`.
>
> ### ▶ NEXT AGENT: Chad plays the S28 checklist (COLD START). Rubberband dead + snap identical ⇒ commit the split and move to the frontier queue (combat contact rates). Rubberband alive ⇒ tune `aimTurnAccel`/`aimTurnP` per the checklist knobs BEFORE touching structure; the research doc's open questions list the next levers (measure the roll lag τ empirically if tuning fights back).

---

> ## 🪶 SESSION 27 — INSTRUCTOR HARD-TURN NOSE-DIP FIX: deep-research → bank-proportional pitch FEEDFORWARD (2026-07-02) — **build-green, red-teamed (REVISE→addressed), UNPLAYTESTED, UNCOMMITTED**
> Executed Chad's S26 standing directive: DEEP RESEARCH the instructor porpoise, then the surgical fix.
> - **RESEARCH (`docs/RESEARCH-instructor-turn.md`).** Ran the `deep-research` skill on the full brief (4 questions + the raptor-biology angle). The workflow's search+verify phases completed (69 claims adversarially verified high-confidence, 6 over-claims refuted); the single final synthesis agent hung in a schema-retry loop, so I STOPPED it and synthesized the report directly from the verified journal claims — no loss. **Answer converges hard and matches the pre-registered landing zone:** the fix is a **bank-proportional pitch FEEDFORWARD**. Q1: real autopilots use exactly this — ArduPilot `PTCH2SRV_RLL` ("roll-to-pitch compensation," default 1.0, range 0.7-1.4, reduce if it gains height in turns); War Thunder instructor = AoA/stall envelope protection; A320 α-max = load-factor limit. Q2: feedforward is open-loop → adds NO closed-loop phase lag → won't re-porpoise the way raising P-gain would (it CANCELS the known sag so the PD chases LESS). Q4: level-turn load factor n=1/cos(bank) → extra-lift demand ∝ (sec(bank)-1), zero at wings-level. **Biology (honest):** raptors DO pay the bank's altitude cost with a nose-up AoA increment applied WITH the bank (tail-twist; Science Robotics 2024, Phan & Floreano) — confirms Chad's exact sequence (bank + yaw, THEN elevator to sustain) but gives NO number (bird-inspired drones + soaring obs, not live-eagle telemetry; real eagle/hawk turns are wing+tail coordinated — Gillies/Thomas/Taylor 2011). So: **shape from biology, magnitude from engineering** — did NOT fabricate a biological constant (anti-reward-hacking honored).
> - **IMPLEMENTATION (client + one config knob; kernel untouched).** `GameConfig.Controls.aimBankFeedforward = 0.35`; in `BirdController.computeMouseAim`, `bankFF = (1/cosBank - 1) * gain` added to the pitch command BEFORE the existing `aoaHead` stall gate. Bank read from `-cf.RightVector.Y` (pitch-attitude independent); cos floored (sec caps at 5, no blow-up, NaN-safe); gated to upright (`UpVector.Y>0`, post-red-team). **Zero at wings-level** ⇒ straight flight + the signed-off snap are numerically UNTOUCHED. **Mouse-aim only** (computeMouseAim returns 0,0,0 in free-look; CS-1 gate zeroes it under keyboard) ⇒ CS-1/CS-5/CS-8 hold. **AoA-limited** (rides the aoaHead gate, bypassed when powered) ⇒ respects the stall boundary at low speed where the merge fight lives.
> - **RED-TEAM: REVISE → addressed.** No LOCKED-spec violation; sign correct in shipped config; claims 1-6 verified. Folded in the inverted-flight gate. Left as checklist/Chad-Q items (not blockers): the FF also aids a **possessed crow** (profile-agnostic instructor — two-sided 1-v-4 lever, left as-is = surgical; Chad's call to eagle-scope); latent `invertPitch=true` case (shipped false, consistent with the adjacent aoaHead gate); flagged a **pre-existing duplicate `invertPitch` key** (`GameConfig.luau:804` + `:961`, both false, last-wins) — NOT fixed (one-change discipline).
> - **PLAYTEST OUTCOME (Chad):** *"the porposing seems better"* → the **feedforward is KEPT** (0.35). BUT the aim then showed **rubberbanding**: reticle sails PAST the cursor on large turns, and (after the S27b/c patches) JITTERS on small inputs.
> - **S27b (REVERTED):** `aimAnglePerPixel 0.0035→0.0024` (KEPT — his "cursor too sensitive" ask), `aimPitchDamp 0.64→0.80` + `aimRollDamp 0.58→0.72` (reverted — added arrival lag, didn't fix the horizontal sail-past).
> - **S27c (REVERTED):** derivative-on-error `aimHorizLeadDamp` on the roll command — correct diagnosis (heading is a bank→turn→heading double integrator the roll-rate damp doesn't see) but the error-derivative **amplified mouse jitter** → small-input "jumping around." Red-team CLEARed it (sign correct) yet the FEEL regressed — a reminder that build+red-team green ≠ good feel.
> - **CHAD'S CORRECTION (the load-bearing outcome):** the servo patching proves the instructor's *structure* (3 independent per-axis PD servos) is wrong; he wants a **holistic coordinated-flight instructor**, researched properly. → the **S28 RESEARCH DIRECTIVE** now heads the COLD START box. S27b/c reverted to the S26-loved baseline; only the FF + sensitivity tweak remain.
> - **STATUS: build green. Aim loop = S26 baseline + bank→pitch FF + sensitivity tweak. UNCOMMITTED.** Files: `GameConfig.luau`, `BirdController.client.luau`, `docs/RESEARCH-instructor-turn.md`. Next session = run the S28 coordinated-flight research FIRST.

---

> ## 🦅 SESSION 26 — MOUSE-AIM QoL LIVE-TUNE (rounds a→f, Chad in the loop) + THE INSTRUCTOR RESEARCH DIRECTIVE (2026-07-02) — **build-green, red-teamed (REVISE→addressed), Chad-validated incrementally, COMMITTED at close**
> Post-mob-confirmation, Chad ran a live tweak→fly→tweak session on the eagle aim experience. The arc, for the record (each value is his, tested live):
> - **(a, FAILED+REVERTED)** `aimLeadScreenFrac 0.95→0.625` — the nose-cone can't shrink the visible circle (it follows the lagging nose) and faster catch-up = pulsing. Documented in-config; do not retry.
> - **(b)** **AskUser decision: KEEP the world-anchored CS-8 model** (screen-stick and hybrid explicitly declined). **RESTORED the screen-centred cursor clamp** — `aimCursorAreaFrac` (his June-30 7/8→3/4→1/2 tune) had been silently UNREAD since the nose-chases-cursor rewrite (`git log -S`: born `b54986c`, dropped `b094984`; the third no-op-knob found this session after `clumpSpread` — grep for readers before trusting any config comment). Reimplemented CAMERA-relative in `computeMouseAim` (holds even under heading lag; faithful to the original screen-space radial clamp — red-team verified the math from primitives). Red-team REVISE→addressed: binding-regime comment honest (the bound eats sustained-turn lead — in tension with camera lag), tradeoff disclosed to Chad.
> - **(c)** Chad: "a lot better" → live dials: `mouseAimDistance 135→200→230` ("see more around me in the turn"); **heading-lag preference REVISED for the record** ("I do NOT like the aim heading lag — tighter; the reticle should snap") `aimHeadingLag 1.4→2.6→**4.0**`; gains `6.5/7.2/1.4→7.5/8.2/1.55`, damps `0.58/0.52→0.64/0.58`; cursor circle `0.625→0.5` **+ code hard-cap fitting the circle inside the screen** (an area-fraction circle can be TALLER than the screen — the flat-topped rim made turn direction uncontrollable at the top edge; the cap keeps the rim round on any monitor, margin 48px).
> - **(d)** **CS-1 RE-CONFIRMED LIVE:** "the keyboard overriding the mouse for full deflection works great."
> - **(e/f)** Slow-turn porpoise ("oscillations up and down… maybe lift?"): diagnosed NOT-lift (kernel signed-off; the instructor was SPEED-BLIND and the S26c gain bump ate the low-speed damping margin). Landed: **speed-scaled pitch P-gain** (`× clamp(speed/glideSpeed, aimLowSpeedGainFloor, 1)`, D-damp unscaled → relatively better damped when slow; at/above glide speed numerically IDENTICAL to the tuned snap), floor `0.5→0.35` and `aimStallBandDeg 4→7` per Chad's own escalation (the narrow band gated the pull bang-bang = the limit cycle). Chad: "way better."
> - **RESIDUAL → RESEARCH DIRECTIVE (the COLD START box):** hard MOUSE turns still nose-dip ("goes down to keep the speed… throws you off target when merging"). Root shape: error-feedback-only pitch + the stability concessions vs the banked-turn lift deficit; the AI autopilot's `turnPitchUp` feedforward is the in-repo precedent the player instructor lacks. Chad: **deep research round next, on this instructor problem with this specific cursor-authority setup.**
>
> ### ▶ NEXT AGENT: run `/evc-loop` → compose `deep-research` on the RESEARCH BRIEF in the COLD START box BEFORE touching knobs. Then the queue (combat contact rates first). Commits at close: S26 aim QoL (this block); mob commits `ff76de9`/`19116a8` — ALL UNPUSHED pending Chad.

> ## 🐦‍⬛ SESSION 25 — **THE** MOB ROOT CAUSE: AI HORIZONTAL STEERING WAS SIGN-INVERTED SINCE THE BEGINNING (2026-07-02) — **build-green, RED-TEAMED (REVISE → addressed), UNPLAYTESTED, UNCOMMITTED**
> Chad playtested the S24 fix same-day: *"no, they are still flying away right from spawn — I can only catch them, they don't engage me."* "Right from spawn" falsified the S24 flocking-drift story on the spot (per its own pre-registered checklist) and pointed at something goal-independent: a bird that STABLY flies away from any goal is the signature of an inverted steering sign.
> **The chain (every link independently re-derived by the red-team):** `FlightPhysics` applies `CFrame.Angles(pitch, yaw, roll)` in the LOCAL frame → +roll raises the right wing = bank LEFT; +yaw = nose LEFT; +pitch = nose UP. Confirmed by three in-repo witnesses: `BirdController`'s key map (A → roll **+1** "bank left", D → **-1** "bank right"), the mouse-aim's **negated** horizontal command (`roll = -hCmd·gain`), and the autopilot's leveling ("+roll raises the right wing"). `Boids.steeringToInput` computed `yawError` with **+1 = target RIGHT** and fed it **un-negated** into `input.roll`/`input.yaw` → the AI turned AWAY from its goal every frame. Stability analysis: under the inverted map, deviation off "goal dead astern" self-corrects back to astern — **flying directly away is the attractor.** So every AI crow, forever, calmly fled whatever it was told to seek: the orbit station, the eagle centre during a dive-bomb "pass" (faster, thanks to attackSpeedMul), the rally point. The old too-strong avoidance driving crows "18-20 km away" AND into terrain was the same bug (avoidance steer feeds the same mapping — "away from wall" became "toward wall"). Six playtests of "they scatter / fly away / mice-and-cat" were all this. No goal-side tune (S14/S16/S18/S19/S24) could ever have worked.
> **What landed (2 lines + comments, `Boids.luau` only):** `input.roll = clamp(-yawError)`, `input.yaw = clamp(-yawError·0.35)` — negated to the kernel convention. Pitch was already correct (untouched). Degenerate fallback branch shares the sign meaning, so one negation covers both. Single call site (`updateAICrows`); autopilot leveling is sign-symmetric so it never compensated (it only *attenuated* the wrong-way turn in its blend band) — nothing double-turns now.
> **VERIFY:** `build.ps1` GREEN. **RED-TEAM: REVISE — the fix itself verified correct** (rotation math re-derived from primitives; client/autopilot witnesses checked; stability claim confirmed; **history cross-examined for counter-evidence and none found** — no playtest ever showed crows approaching; attrition-by-contact reconciles as the eagle catching straight-line fleers). Addressed its findings: **F1** HANDOFF now documents the S24+S25 stack + this merged checklist (done, this box); **F2** S24 demoted in-code from "root cause" to secondary (GameConfig comment reconciled; commit split S24/S25 planned; `mob.steering=nil` = A/B lever); **F3** the two now-live balance risks lead the checklist (crow-favored flip → `attackPeriod` first; knife-edge fall-watch → widen `orbitRadius`, never lower the cap); **F4** comment overclaim softened.
> **flight==balance NOTE for the next agent:** all mob numbers were tuned against a controller that fled its goals — treat them as UNTUNED starting points now that steering works. The next session is expected to be a live re-tune against the S25 checklist, not a re-diagnosis.
>
> ### ▶ OUTCOME — **PLAYTEST 7 CONFIRMED THE FIX (2026-07-02, same day).** Chad: *"yep they stayed around me and mob me now… their turns are tight, I can't get in their circle easily… one stuck around me, it would fly in front of me. I killed one but it is hard to get a kill… they are not hitting me and it is hard to hit them."* Mob = WORKING; crow flight = agile (turns TIGHT — the designed turn advantage is finally visible); one crash observed (within Chad's earlier "a couple crashed if they mob" tolerance — keep the knife-edge watch open); combat contact rates BOTH low = the new balance frontier (queue #2). Committed post-confirmation as the planned two commits (S24 blend / S25 sign).

> ## 🐦‍⬛ SESSION 24 — MOB SCATTER ROOT CAUSE (DEMOTED BY S25 — real defects, wrong "root cause" framing): THE FLOCKING BLEND WAS NEVER DROPPED IN MOB MODE (2026-07-02) — **build-green, RED-TEAMED (REVISE → addressed), UNPLAYTESTED, UNCOMMITTED**
> Chad's 5th playtest, same words: *"the crows are not mobbing and they scatter and fly away."* S16/S18/S19 were all tuning passes on the same model and none changed the feel — so per the loop's STUCK rule this session READ THE CONTROL FLOW instead of turning knobs, and found **two code-verified wiring defects** (not tuning misses):
> 1. **`Squad.mob.clumpSpread` was a no-op** — `git grep clumpSpread HEAD` hits only its own definition + one comment; no consumer ever existed. `mobOrbitTarget` stations each crow at its OWN bearing (handed hardcoded 1) and the bot wave spawns 12 studs apart → all 4 ring ONE ~19° sector forever. The documented "surround from multiple angles" never existed in code.
> 2. **`Boids.computeSteering` kept the full flocking blend during mob mode** — alignment(1.0) + cohesion(0.8) stayed active while all 4 crows sat inside `neighborRadius=60`. The research reframe (mobbing≠flocking; independent attackers; cohesion DROPS — `docs/RESEARCH-crow-mobbing.md`) was wired into the goal GEOMETRY only. Net effect: every dive-bomb launch/peel (every 1.4s, peel target OUTSIDE the ring) or eagle disengage put up to ~1.8 of flock-pull on the remaining crows vs goalWeight 2.0 → the whole knot drifts off together = "scatter and fly away." Explains why S16/S18/S19's knobs (none of which touch the flock terms) changed nothing.
> **What landed (one coherent "independent-attacker steering" change, 3 files):** `Boids.computeSteering` honors `formationCfg.alignmentMul` (default 1); new `GameConfig.Squad.mob.steering = {spacing=30, cohesionMul=0, alignmentMul=0, separationMul=1.4}` replaces the dead `clumpSpread` flag; `updateAICrows` passes it as the formationCfg while `mobbing`. AI-only (player squads are never `aggressive`). De-clump expectation: separation spreads the knot; passes/peels re-ring crows at new bearings with nothing re-syncing them — **timescale unproven → pre-registered fallback: per-crow bearing offsets in `mobOrbitTarget` if attacks still come from one sector.**
> **VERIFY:** `build.ps1` GREEN; `luau-lsp analyze` (direct, sourcemap+defs) CLEAN exit 0. ⚠️ `verify.ps1`'s luau-lsp tier FAIL = pre-existing silent luau-lsp crash under PowerShell (red-team reproduced it on clean HEAD) — logged so nobody blames their own diff. **RED-TEAM: REVISE — no code defect.** Independently verified: the no-op flag, the clump mechanism, Lua 0-truthiness in the `or 1` fallbacks, per-squad formationCfg scope, `aggressive` only set on the bot squad, no client/kernel/LOCKED-spec surface touched, same-team collisions skipped (no friendly-fire cost to closer crow-crow passes), `collisionRisk` has zero consumers (contract safe). Its Medium: my root-cause NARRATIVE overclaimed in three spots (clump sits at perception edge, not 12 studs; drift is intermittent — attack phase actually drags the group TOWARD the eagle, the outward drag is the peel phase + the anti-goal tax when chasing a fleeing eagle; pass-through re-ringing on the far side is not guaranteed against a moving eagle) → comment softened to hypothesis-level + the bearing-offset fallback pre-registered in the checklist so the next Play stays diagnostic either way. Lows fixed: `Boids` docstring now lists `alignmentMul`; balance watch items are in the checklist.
>
> ### ▶ NEXT AGENT / Chad: run the **S24 PLAYTEST CHECKLIST** in the COLD START box (stay-on-you? surround? sling watch? 1-v-4 readable? regressions?). **NOT committed** — awaiting the Play. If the mob FINALLY sticks, this + a Chad OK is the checkpoint commit; if they still drift as a group, the flocking-drift hypothesis is falsified — report WHEN they leave and pivot to keep-up/pursuit per checklist #1.

> ## 🦅 SESSION 22 — EAGLE ENERGY RETENTION / GLIDE-COAST ("I lose energy so fast when I zoom / glide") (2026-07-02) — **build-green, RED-TEAMED (CLEAR), UNPLAYTESTED, UNCOMMITTED**
> Chad (signed-off flight, reopened by his explicit ask): *"I lose energy 420→250 so fast if I zoom up. I need MORE energy retention — going to glide mode, keep my speed a LOT longer if I'm not turning or climbing, just staying aerodynamic."* **Diagnosed the real culprit instead of guessing at drag:** the dominant speed-bleed above cruise was a **hard-coded `1 - dt*0.5`** in the `FlightPhysics` speed-cap block — an artificial exponential pull of speed ABOVE `maxLevelSpeed` back to cruise. At 420 that's ~125 studs/s² (real parasitic drag is ~2, the climb gravity-along-path net of retention ~5-10) → 420→250 in ~2 s = exactly his "so fast." NOT drag, NOT energyRetention — this hidden term.
> - **Fix (2 files):** `FlightPhysics` L387 `0.5` → **per-profile `p.glideBleed or 0.5`** (fallback = old behavior; the ONLY kernel-code change). Eagle `glideBleed = 0.15` (excess decays ~3.3× slower → the eagle COASTS: 420→250 in ~7-8 s). Crow `glideBleed = 0.5` (UNCHANGED — protects the crow cruise / 1-v-4). Eagle `energyRetention` 0.7→**0.82** (the zoom-climb half of the ask; still capped <0.95).
> - **RED-TEAM: REVISE — but the delta itself CLEAR** (no Critical/High/code defect). Verified: diagnosis + math correct (125 vs 2 studs/s²); kernel invariants all survive (cl0>0, STABILITY_RATE=0, recoverNoseDownRate=0, GRAVITY↔density lockstep, stall<spawn<cruise, TERMINAL cap unchanged); **dive genuinely untouched** (glideBleed gated `not isDiving`, energyRetention gated `velDir.Y>0`); **NO noclip/runaway** — a hands-off glide still asymptotes to cruise 170, just slowly (coasts, doesn't float forever); anti-cheat neutral (top speed still TERMINAL); phugoid MORE damped during the coast, not less. The 2 Medium items are process/balance: **(6)** the coast extends the eagle's disengage window ~3.5× → re-check the mob can still force a merge (lever = Eagle `glideBleed`→0.25 or `Crow.maxLevelSpeed`, NOT the kernel); **(7)** hunk-stage/split from the S16-S21 stack so the 1-v-4 effect is attributable.
>
> ### ▶ NEXT AGENT / Chad: run the **S22 PLAYTEST CHECKLIST** in the COLD START box (coast holds speed? zoom converts to altitude? no runaway? dive unchanged? 1-v-4 vs the mob?). **NOT committed.** `glideBleed` = level-coast knob, `energyRetention` = zoom-climb knob (separable). On commit, SPLIT (energy-retention is its own logical commit).

> ## 🦅 SESSION 20 — MOUSE-AIM SNAPPIER + EAGLE DIVE/FLAP TOP SPEEDS (Chad-requested; signed-off systems reopened) (2026-07-02) — **build-green, RED-TEAMED (both deltas CLEAR), UNPLAYTESTED, UNCOMMITTED**
> Chad explicitly reopened the signed-off eagle flight + player-tuned aim for two specific asks (authorized — LOCKED-spec gate = "he asked for exactly this," implement precisely, no collateral). Both GameConfig-only; `FlightPhysics.luau` + `BirdController.client.luau` kernel/logic UNTOUCHED (revert = the config numbers / tag `v1.0-eagle-flight`).
> - **Mouse aim snappier (CS-8 tuning):** *"at close range it lags; small deflections should SNAP in a fraction of a second — only a LARGE deflection should have noticeable reticle catch-up."* Raised the nose-chases-cursor P-gains (`aimRollGain 4.5→6.5`, `aimPitchGain 5.0→7.2`, `aimYawGain 1.0→1.4`) + PD damping in step (`aimPitchDamp .45→.58`, `aimRollDamp .40→.52`). Higher P saturates the turn command at a ~24% smaller error → small/medium gaps close at the eagle's MAX turn rate ("snap"); big deflections still turn-rate-limited (the intended lag). Dead-centre deadzone/expo untouched (fine aim preserved).
> - **Eagle dive/flap top speeds (kernel numbers):** *"dive ~390; 420 top via flapping out of the dive — the flap boosts it."* `Eagle.diveSpeedCap 320→390`, `Flight.TERMINAL_VELOCITY 400→420`. Mechanism: diving → hard-cap `diveSpeedCap` (390); non-diving+flapping → capped only by `TERMINAL` (420, the bleed-to-170 is skipped while flapping); glide → bleeds to 170. Anti-cheat ceiling scaled to 525 (legit 420 safe); stale Security comment fixed.
>
> **VERIFY:** `build.ps1` GREEN. **RED-TEAM: REVISE — but both flight deltas themselves CLEAR** (no LOCKED violation; kernel code untouched confirmed via git diff; CS-1 aimGate still zeroes aim during keyboard flight so the higher gains can't curve a loop; CS-9/STABILITY_RATE/grip untouched). Aim loop verified **STABLE** — it commands a body RATE so it's first-order in error (exponential decay, NOT a spring → won't ring), damping raised enough, per-frame loop gain ~0.24@60fps<1. Speed model verified (dive→390/flap→420/glide→170); anti-cheat envelope holds. The REVISE items are process/balance, not defects: **#1** isolate these 2 deltas from the S16-19 mob stack when committing (hunk-stage, don't `commit -a`); **#5** playtest the eagle speed buff TOGETHER with the crow keep-up tuning (a faster/deeper eagle re-opens the "mice/cat" keep-up gap — if it out-runs the mob, raise `Crow.maxLevelSpeed`); **#4** stale Security comment (fixed); **#6** camera shake unclamped at 420 (cosmetic — one-line clamp if it reads as too much).
>
> ### ▶ NEXT AGENT / Chad: run the **S20 PLAYTEST CHECKLIST** in the COLD START box (aim snap + CS-1 re-confirm + dive 390/flap 420 + speeds-vs-mob balance). **NOT committed.** Then return to the still-untested **S19 mob** (Chad flew solo this round). On commit, SPLIT: eagle flight-feel (S20) / mob flight (S18-19) / dive-bomb (S16) / eagle combat buffs (S17).

> ## 🐦‍⬛ SESSION 18/19 — CLOSE, HOLDABLE "BRAVE" MOB (the coordinated-turn fix for "they flee / won't mob") (2026-07-01/02) — **build-green, RED-TEAMED, UNPLAYTESTED, UNCOMMITTED**
> Chad's S16+S17 playtest: *"this time they crashed a little more and they get scared and fly away from me right away — they are not brave, they are not mobbing me."* The recurring #1 complaint. Found the mechanism instead of guessing: **the mob's flee is a coordinated-turn / bank-limit problem.** AI crows fly the no-auto-level kernel; the AI autopilot caps bank at 60° (`maxBankCos 0.5`, the anti-knife-edge guard). To hold a level orbit of radius R at speed v the crow needs bank θ with `tan θ = v²/(R·g)`, and g = REAL_G·GRAVITY_G/METERS_PER_STUD ≈ **45.6** studs/s² → holdable iff **v ≤ √(1.732·R·g) = √(79·R)**. The old 220 ring at 114 studs/s was holdable (v≤132) — it just stood off too FAR (crows station 220 out, fly outward to the ring from spawn; the S16 peel flung them ~352). Red-team independently verified g=45.55 and that the bank cap code (`updateAICrows` autopilot: when `upY<0.5` the leveling roll REPLACES the steering roll) makes required-bank-over-cap ⇒ understeer-outward ⇒ the flee.
>
> **What landed (GameConfig only, one coherent "close, holdable, brave mob"):** `Squad.mob.orbitRadius 220→150` (in the eagle's face); `Squad.aiFlight.combatSpeedMul 1.2→1.05` (~100 studs/s — REQUIRED so the tight 150 ring is holdable within the 60° cap: R=150 → v≤109); `Squad.mob.orbitLead 170→100`; `diveBomb.peelRadiusMul 1.6→1.15` + `peelHeightBias 120→50` (stay near + re-engage after a pass, not flee). **orbitRadius ↔ combatSpeedMul are physically coupled — documented in-config; never tighten R without lowering v.**
>
> **VERIFY:** `build.ps1` GREEN. **RED-TEAM: BLOCK — but the Critical was a FRAMING ARTIFACT** (it diffed worktree vs HEAD and flagged the uncommitted S16+S17+S18 STACK as "one-change violation"; each slice was individually red-teamed, and nothing is committed — the valid core is "split into logical commits when committing"). Physics confirmed **SOUND**; LOCKED-specs/kernel/contract **CLEAR** (all AI-only). Acted on the real catches: **#5** `attackSpeedMul 1.8` is CLAMPED by the kernel's `maxLevelSpeed=140` for a non-diving crow (never 171) → corrected the misleading comment; **#4** a tighter ring = MORE sustained bank (~1.8g) near the crow's 24° stall → could MUSH/sag rather than reduce crashes → softened the "fewer crashes" claim + added the mush watch to the checklist. **#2** the cumulative stack compounds toward an eagle-favored 1-v-4 (deadlier eagle S17 + closer/slower crows S18) → carried as the balance-WATCH in the checklist.
>
> ### ▶ NEXT AGENT / Chad: run the **S18 PLAYTEST CHECKLIST** in the COLD START box (do they MOB close now? orbit mush? crashes better? dive-bomb still bites? 1-v-4 balance / farm-able?). **NOT committed** — on commit, SPLIT: mob geometry (S18) / dive-bomb system (S16) / eagle combat buffs (S17). Fallback flags in the checklist isolate each.

> ## 🦅 SESSION 17 — STRIKE LETHALITY FIX ("I hit them but they don't die") (2026-07-01) — **build-green, RED-TEAMED, UNPLAYTESTED, UNCOMMITTED**
> Chad playtested the S16 dive-bomb and reported it net-positive (*"crows live a little longer, only saw one crash… still scatter but took longer"*) plus a concrete combat bug: *"I'm pretty sure I'm hitting them with beak/talons but they don't die."* Ran the loop on the strike bug (the clearest, most-attributable of his three symptoms; scatter is queued next).
>
> **DIAGNOSIS (numbers bug, not logic).** The eagle's OFFENSIVE strike pass (`updateEagleStrikes`) is correctly wired into `onHeartbeat` before `processCollisions`, and `applyDamage` reduces health + kills at hp≤0. The two bugs were numeric: **(1)** Eagle `beakDamage = 22` vs crow `health = 25` → a clean beak jab leaves the crow at 3 HP (talon 34 one-shots, beak can't). **(2)** offensive `reach = (eagleR 4.5 + MAX_BODY_RADIUS 4.5 + ATTACK_BUFFER 3) × reachFraction 0.85 ≈ 10.2 studs` — barely past the 6.7-stud TOUCHING distance — while the ARMED reticle lights at `strikeSelectRange = 200`. So a crow reads "on target" from 20× outside actual hit range → Chad presses, nothing dies.
>
> **What landed (one coherent "make strikes kill" change, 2 files):**
> - `GameConfig.luau`: Eagle `beakDamage` **22→26** (now one-shots a 25 HP crow; still < talon 34). Added `reachStuds` per strike — **talon 24** (conservative: it already one-shots + 70° cone @ ~67% uptime, so a big reach = death-ray per red-team #2), **beak 28** (narrow 35° cone + short window need the range to connect — the strike Chad struggled with). Cones/timers/cooldowns UNCHANGED.
> - `GameServer.updateEagleStrikes`: `reach = cfg.reachStuds or (…formula…)` — explicit reachStuds overrides the point-blank formula; fallback intact.
>
> **VERIFY:** `build.ps1` GREEN. **RED-TEAM: REVISE** — no BLOCK/High, no locked-spec/kernel/contract/logic issue. Confirmed **parry isolation** (reachStuds only affects the offensive pass; `tryStrikeCatch`/collisions untouched), fallback precedence correct, cone still gates the wider reach, throughput throttle (one hit per window, cooldowns) unchanged. Findings are 1-v-4 balance-WATCH items carried to the playtest checklist: **#1** wider reach spends the shared `caught` flag on offense → may disable the parry that window (defense→offense shift); **#2** talon kill-volume (→ adopted talon reachStuds 24, down from a first pass at 34); **#3** no line-of-sight check at 24-28 studs (edge case near ridges — only gate with a raycast if it shows up); **#4/#5** log the two knobs separately + re-verify "can 4 crows still mob."
>
> ### ▶ NEXT AGENT / Chad: run the **S17 PLAYTEST CHECKLIST** in the COLD START box (beak one-shots? talon connects at range? 1-v-4 still fair / parry-vs-offense trade? scatter — the top open mob residual — WHEN does it happen?). **NOT committed** — unplaytested balance; commit S16+S17 together as a checkpoint once the feel is confirmed. **Scatter is the next mob iteration** (candidate causes listed in the checklist).

> ## 🐦‍⬛ SESSION 16 — CROW MOB INCREMENT 2: STAGGERED DIVE-BOMB + PEEL-OFF (2026-07-01) — **build-green, RED-TEAMED, PLAYTESTED-PARTIAL (net-positive; scatter+attrition residual), UNCOMMITTED**
> Resumed the crow-mobbing frontier under `/evc-loop` after a prior session hit an API error and reset. **START orientation produced a load-bearing correction:** the COLD-START's leading hypothesis for the mob attriting to ~1 ("orbit ring clips terrain") is **impossible** — AI crows are NON-LETHAL on terrain (`updateAICrows` calls `BirdCollision.resolve` with `math.huge` crashSpeed) and `GROUND_FAILSAFE_Y = -200` (the old "-40" note was stale). An AI crow can only die by **ramming the eagle** (`processCollisions`, relSpeed≥90 = its sacrifice ram) or tunneling below -200. So attrition = **combat contact**, and the passive suicide-ram was the crows' ONLY prior offense (S14 orbit has no teeth). That pointed straight at the research-designated next increment.
>
> **What landed (ONE feature, AI-only, config-gated `Squad.mob.diveBomb.enabled` → flip false = fall back to pure S14 orbit):**
> - **`GameConfig.Squad.mob.diveBomb`** — new sub-table: `attackPeriod 3.4`, `attackDuration 1.6`, `peelDuration 1.4`, `attackSpeedMul 1.8`, `peelRadiusMul 1.6`, `peelHeightBias 120`. No existing numbers changed. Documents the ⚠️ timing invariant `attackDuration+peelDuration ≤ attackPeriod` (else attackers overlap → the all-at-once pile-up the model prevents).
> - **`GameServer.updateAICrows`** — (a) `mobPeelTarget` helper (mirrors `mobOrbitTarget`: radial-out beyond the ring + climb); (b) a **squad-level round-robin scheduler** (`squad._mobAttack={nextAt,cursor}`) that launches ONE living-AI attacker every `attackPeriod`, stamping `entry._attackUntil`/`_peelUntil`; (c) per-crow **mode select** when mobbing → DIVE-BOMB (goal=eagle centre) / PEEL-OFF (goal=mobPeelTarget) / ORBIT (default); (d) the attacker gets a **raised speed cap** (`attackSpeedMul`) in the governor so a committed pass actually closes the ~220 standoff and reaches ram range. Also rewrote the stale `updateAICrows` comment that claimed `mob.enabled=false`.
>
> **VERIFY:** `build.ps1` GREEN. **RED-TEAM (red-team-reviewer subagent): REVISE** — no Critical/High, **no locked-spec/kernel risk, cleanly AI-only** (player crow never scheduled/overridden; possession `isAI` flips verified; correctness/contract/round-robin/nil-guards all CLEAR). 3 findings, all handled: **#1** attrition-vs-sacrifice intent is Chad's design call → dropped the overclaimed "attrition fix" framing, surfaced as the open question in the playtest checklist; **#2** passes whiff at the cruise cap (114 studs/s closes ~182 over 1.6s but starts ~224 out) → **FIXED** with `attackSpeedMul=1.8` (~171 studs/s during the pass); **#3** the one-attacker invariant was unenforced (attack+peel `==` period) → bumped `attackPeriod` 3.0→3.4 for margin + added a load-bearing ⚠️ comment.
>
> ### ▶ NEXT AGENT / Chad: run the **S16 PLAYTEST CHECKLIST** in the COLD START box (fly the eagle vs the bot mob; verify take-turns / pass-bites / clean-recover / mob-holds / 1-v-4 fairness, and answer the attrition-vs-sacrifice question). **NOT committed** — this is unplaytested combat/balance; commit as a checkpoint only after Chad OKs the feel. Knobs all in `Squad.mob.diveBomb`. Increment 3 = balance (cadence/damage/collision trades vs the eagle's S13 energy/dive-rest buffs).

> ## 🎛️ SESSION 15 — GOVERNING HARNESS `/evc-loop` + first live loop (2026-07-01) — **HARNESS BUILT & PROVEN; wing-anim/detail PLAYTEST-CONFIRMED; eagle cosmetic pass + harness COMMITTED as the clean baseline**
> Chad's ask (his long-standing one, now greenlit): *"add an agentic layer as a skill… a harness that governs this codebase, evaluates our work through red-teaming, ensures quality, maintains memory each session, commits/pushes when approved, and prepares the codebase so the next cleared-context agent has everything to follow the roadmap."* Built exactly that. **Research-grounded** (3 parallel sub-agents: current Roblox headless tooling; Claude Code v2.x hook/skill/subagent mechanics; internal SOP distillation). Nothing in `src/` changed — the eagle flight kernel and all combat code are untouched.
>
> **What landed:**
> - **`/evc-loop`** — the governing session skill at `.claude/skills/evc-loop/` (`SKILL.md` + 5 `references/` + a session-log template). Runs a SOP-tuned lifecycle: **START** (orient on this box + MEMORY + the CS registry; set a checkable FRAME + budget) → **LOOP one change at a time** (PLAN behind a LOCKED-SPEC gate → ACT → VERIFY → RED-TEAM → SCORE → REFLECT → DECIDE) → **CLOSE** (update memory + MEMORY.md, refresh this HANDOFF, propose an approved commit). It specializes the generic `loop-orchestrator` in `loop_skill/` with THIS project's real rules.
> - **Red-team subagent** `.claude/agents/red-team-reviewer.md` — read-only adversary spawned before proposing any control/kernel/combat/balance change; attacks it against the SOPs (LOCKED specs, no-collateral, one-change, flight==balance, contract integrity, reward-hacking) → BLOCK/REVISE/CLEAR.
> - **Light hooks** (Chad chose "light hooks + rich skill"): a **SessionStart** hook (`.claude/hooks/session-start.ps1`) injects an orientation banner every session so a cleared-context agent lands oriented; **`permissions.ask`** in `.claude/settings.json` gates `git commit`/`git push` to ASK for Chad's approval. No Stop-gate (kept latency/ fragility low).
> - **`verify.ps1`** + `tools/Bootstrap-Verify.ps1` + `selene.toml` — an OPTIONAL headless verify tier that finally catches what `build.ps1` can't: self-bootstraps `luau-lsp analyze` (broken requires / renamed-contract mismatches / nil-field errors) + `selene` (lint), best-effort atop the guaranteed Rojo-build floor. Each tier degrades to UNAVAILABLE if its binary can't be fetched. **PowerShell-5.1 parse-verified; NOT yet run end-to-end on a live machine** — if a download URL drifted, fall back to `build.ps1` and bump the pinned version in `Bootstrap-Verify.ps1`.
> - Orientation updated: `CLAUDE.md` + this box + the read-order line now point at `/evc-loop`; memory `reference-evc-loop-skill` added + indexed in `MEMORY.md`.
>
> **FIRST LIVE LOOP RAN (`.loop/s15-baseline-shakedown/state.md`).** START orientation caught real drift (this box's earlier claim that the "orbit re-enable" was uncommitted was wrong — `GameConfig` mob/goalWeight is committed in `75c39f3`; the ACTUAL uncommitted work is a **remote wing-animation** feature + a **BirdBuilder.Build detail pass**). Ran the loop on it: **build.ps1 GREEN**; an **independent red-team pass** returned REVISE and caught a load-bearing `Motor6D.C1` **rest-pose fix smuggled into the "cosmetic detail pass"** (verified mathematically correct — the old pose was wrong); all LOCKED-spec/contract/dive-correctness axes CLEAR. **Chad playtested → "yes everything is good!"** — wings now flap on every bird on every screen, rest pose right, no flight/feel regression.
>
> ### ▶ CURRENT STATE — BASELINE COMMITTED + PUSHED (2026-07-01):
> - Chad greenlit the commit: *"full pass on the cosmetics you can commit and push and merge everything."* The **eagle appearance cosmetic pass** (from `EvC2026_Art/` concept art) + the playtest-confirmed **wing-anim/detail** pass + the **`/evc-loop` harness** all landed together in ONE clean baseline commit on `master`, pushed to `origin/master`. ("Merge everything" = these working-tree changes merged into the mainline; the old `flight-camera-redesign-v4` branch was deliberately NOT merged.)
> - **Pre-commit gates (both passed):** `build.ps1` GREEN, and an **independent red-team returned CLEAR** — `FlightPhysics`/`GameConfig` byte-identical (kernel untouched), `BirdController` +47 is a purely additive `animateOtherBirds` helper (CS-1/2/3/8 code in `onFlightStep` entirely outside the diff), `GameServer` +6 removes a no-op server-side wing call (Motor6D.Transform doesn't replicate → clients animate other birds), `BirdBuilder.Build` contract fully intact (`PrimaryPart="Body"`, `LeftWing`/`RightWing`, `LeftWingJoint`/`RightWingJoint`, collision sphere). Appearance-only; zero feel-regression risk.
> - **The cosmetic pass was committed WITHOUT a fresh flight-test** (Chad authorized commit directly; red-team confirmed appearance-only so the risk is only visual). ▶ **Chad still to eyeball:** other players' birds + AI crows should now visibly flap/tuck on your screen; re-confirm CS-1 (held-S = straight loop) and CS-2 (free-look pan up/down, horizon level) are unaffected by the render-loop rewrap. Any visual nit = fix-forward.
>
> ### ▶ NEXT AGENT / Chad:
> - Baseline is in. **The frontier is unchanged — crow-mob stabilization (queue #1)**, worked under `/evc-loop`.
> - **Harness notes:** `/evc-loop` + the `red-team-reviewer` subagent auto-register after a session reload (this session used their instructions directly = identical behavior). Optional: run `.\verify.ps1` once to confirm the static-analysis bootstrap works on your machine (first run downloads luau-lsp + selene into `tools/bin/`; non-load-bearing — `build.ps1` unaffected). Tune the `references/` Markdown as the SOPs evolve.

> ## 🐦‍⬛ SESSION 14 — CROW AI MOBBING (research-grounded) + FREE-LOOK BUGFIX (2026-07-01) — **COMMITTED & PUSHED `75c39f3`; crows PLAYABLE, mob partially stable**
> **NET RESULT (Chad): "I can actually play with the crows now… doing better," but "usually only one, others crashed eventually."** So: AI flight control FIXED, mob orbit ON, crows fly + ring the eagle — residual = the mob still attrits to ~1 over a long fight (COLD-START queue #1). Free-look up/down-pan bug also fixed (CS-2). Everything below committed on `master @ 75c39f3` (local == remote). The blow-by-blow of how we got here (it took several playtest passes) is preserved next:
>
> Chad tested a naive `goalWeight=3.0` AI-crow tweak → "made 3 of them crash, they get scared, can't fly very good." So we stopped guessing and ran a **deep-research pass on real corvid mobbing** to ground the 1-v-4. (The research workflow's *synthesis* step died on a session token limit; **all 18 verified + 7 refuted claims are preserved** in **`docs/RESEARCH-crow-mobbing.md`** with a hand-authored parameter plan — nothing lost. Memory: `research-crow-mobbing`.)
>
> **THE REFRAME (drives everything): mobbing ≠ flocking.** Real corvids SWITCH from topological (cohesion-max formation) to **metric** interactions when mobbing (~5 m ≈ 14 body-lengths) → they become **independent attackers that ORBIT + dive-bomb** the raptor; cohesion DROPS. So cranking `goalWeight` was *backwards* — 4 birds on one vector into the eagle's centre = the pile-up/terrain-overshoot Chad saw. Crows are also **BOLD** (97% aggressors vs ravens; higher risk → closer/harder mobbing, never flee — the antidote to "scared" bots). The Crow *profile* is already a fine angles-fighter; **the bug was AI STEERING, not the profile**.
>
> **Increment 1 "orbit shell" — TRIED, DIDN'T HELP, GATED OFF.** Added `GameConfig.Squad.mob` (orbitRadius/lead/heightBias) + `GameServer.mobOrbitTarget` so aggressive crows circle the eagle instead of ramming its centre; set `goalWeight` 2.0. **Playtest: still "scattered and crashed" — same as before.** That was the key signal: reshaping *where* they aim changed nothing → **the crows can't execute controlled flight to hold ANY target.** Reverted to baseline (`mob.enabled=false`, `goalWeight` 1.0); the orbit code + `mobOrbitTarget` stay in place for when flight is fixed.
>
> **DIAGNOSIS (Chad, structured playtest Q's 2026-07-01):** crashes hit **terrain/spires AND the ground**; flight is **"fine, then suddenly crashes"**; and they are **"too fast — blow past, can't turn tight."** Root cause: `Boids.steeringToInput` **DIVES at the target** (dir.Y < -0.4 → dive → accelerates to the 220 dive-cap), so turn radius (v/ω) balloons → they overshoot into terrain and sink into the ground on the pull-out. (AI terrain collision is *non-lethal* — they slide — so "crash" = diving into the deck and grinding, looking broken.)
>
> **INCREMENT 0 "fly controlled first" — landed in two playtested passes (build-green):**
> - **Pass A (speed governor):** `GameConfig.Squad.aiFlight` + governor in `updateAICrows`: **suppress AI dive** (runaway-speed source), **combat-speed cap** (`glideSpeed×1.2≈114`, bleed above it), **soft altitude floor** (Y<250 → climb). *Playtest: helped — "stayed a bit longer" — but they still "crash when chased, losing control" then "scatter fairly quick."*
> - **Pass B (AI autopilot) — CURRENT, UNPLAYTESTED:** the engine has **no auto-level** (eagle's locked feel; crows inherit it), so a hard chase-reversal rolls the bot to knife-edge → loses vertical lift → falls ("lose control when chased"). Added an **AI-only** bank limiter + turn-coordination to `aiFlight` (`autopilot`/`maxBankCos 0.5≈60°`/`levelAssist 3.0`/`turnPitchUp 0.5`): caps bank so it can't knife-edge, and adds up-elevator in the turn so it holds altitude. **Does NOT touch the player's locked no-auto-level** (AI loop only). Orbit still OFF.
>
> **✅ INCREMENT 0 CONFIRMED (Chad playtest 2026-07-01):** *"now they will fly near the wall but not crash… better experience dogfighting with a crow. No mobbing behavior yet."* → **AI flight control is FIXED** (governor + autopilot); the crow dogfights well 1-v-1. Remaining issue: **scatter** — *"two of them flocked off and went far away."* (Boids separation out-weighs a weak eagle-goal with nothing binding them to the fight.)
>
> **What landed (build-green, UNPLAYTESTED) — INCREMENT 1 orbit RE-ENABLED for the scatter/mob:** now that flight is controlled, turned the mob orbit back ON (`Squad.mob.enabled = true`) + raised `boids.goalWeight` 1.0→**2.0** so the orbit RING beats separation (up to 2.1) and binds the crows to a standoff ring around the eagle instead of drifting off. (This is the same orbit that failed pre-flight-fix — it needed controlled flight underneath, which now exists.)
>
> ### ▶ NEXT AGENT — playtest checklist (Increment 1 orbit, on top of the confirmed flight fix):
> - Do the crows now **stay near the eagle and circle it** at a standoff distance instead of "flocking off far away"? Do all ~3 hold the ring (not just peel off)?
> - Knobs: still drifting away → raise `boids.goalWeight` toward 2.5; ring too wide/passive → lower `Squad.mob.orbitRadius` (140–180); circling wild → lower `Squad.mob.orbitLead`; clumping on the ring → lower `goalWeight` to ~1.7.
> - ⚠️ **Still no teeth** — orbit is circle-only. Once they hold a stable mob, **Increment 2** = staggered **dive-bomb passes from above + peel-off** (take turns — never all 4 at once), wired into the existing strike/collision combat. Plan: `docs/RESEARCH-crow-mobbing.md` → "build order".
> - flight==balance: a bound mob is real pressure — re-verify the eagle can still break contact and pick off stragglers.
> - **NOT committed** — awaiting Chad's playtest. (Flight-control fix in aiFlight is worth committing as a checkpoint once he OKs it — it's a solid, confirmed improvement.)
>
> **Also noted this session:** Chad added **`EvC2026_Art/`** (Gemini concept images) for a FUTURE 3D-model pass — not wired in; birds are still procedural in `BirdBuilder`. Memory: `project-art-folder`.

---

> ## 🦅 SESSION 13 — CS-1 + ARCADE ENERGY RETENTION + UPRIGHT CAMERA + DIVE-REST STAMINA (2026-06-30) — **PLAYTESTED; eagle flight SIGNED OFF (record of what landed)**
> Worked the SESSION 12 queue under the LOCKED-SPEC process directive, then a dive-stamina follow-up. **PLAYTESTED — Chad: the eagle flight model is "largely finished… a great experience"; CS-9 explicitly confirmed.** No aero-kernel *calibration* was reopened (lift curve / gravity / stall math of `v1.0-eagle-flight` untouched); the kernel edits are one bounded climb-only energy term + the dive-rest stamina rule. Commits on `master`: `d3c3396` (CS-1), `f61c19a` (energy + camera), `abb1670` (dive-rest stamina). Checkpoint/revert points: `d3c3396`, tag `v1.0-eagle-flight`, GitHub branch `single-bird-kernel`.
>
> **What landed (playtested — Chad signed off the eagle flight/feel; see the ✅ confirmation at the end of this block):**
> 1. **CS-1 — keyboard fully overrides mouse-aim (GLOBAL gate).** `onFlightStep`: while ANY of Q/W/E/A/S/D is held, `aimGate = 0` zeroes the ENTIRE `aimApplied` contribution on ALL three axes → a held S now makes a **straight** loop (was curved by the old per-axis roll/yaw aim-pull). Release every key → mouse-aim resumes. Registry CS-1 → **FIXED, pending playtest**.
> 2. **Energy retention (the TOP ask) — one coherent climb-E model.** New per-profile **`energyRetention`** (Eagle **0.7** / Crow **0.4**) in `GameConfig.Profiles`; consumed in `FlightPhysics:Update` right after the drag term. It adds back `energyRetention × GRAVITY·velDir.Y` **only while CLIMBING** (`velDir.Y > 0`) — cancelling that fraction of the *gravity-along-path* bleed (the dominant climb decel, NOT drag). **Dive/stoop untouched** (gated to climbs), capped `<0.95` (never noclip), and `flapDragRetention` is kept as the small extra under-power drag bonus. Eagle>Crow is the 1-v-4 energy lever.
> 3. **CS-2 revised — UPRIGHT free-look camera (Chad chose "stop at vertical").** Free-look is now an upright spherical orbit: `camUp = Vector3.yAxis` (operator never rolls/inverts), full 360° yaw, `freeLook.pitch` clamped to **`Camera.freeLookPitchLimitDeg = 85`** so it soft-stops just shy of straight up/down instead of flipping over the top; base dir flattened to horizontal for symmetric up/down. Fixes "I end up looking at my eagle sideways/upside down."
> 4. **CS-9 — a DIVE no longer costs stamina; it REGENS (follow-up nitpick, commit `abb1670`).** Chad confirmed the flight/control feel is "ideal" except: diving drained stamina even though a tucked bird isn't flapping. `FlightPhysics` stamina now drains only on `wantFlap and not self.isDiving` — glide AND dive both regen, so a stoop gains speed + stamina even with Shift/Ctrl held. `staminaDiveCost` legacy/unused. **Playtest:** dive with Shift held → stamina bar rises, not falls; confirm non-dive climbing still drains it. flight==balance: dives now refuel endurance — watch the 1-v-4.
>
> ### ▶ NEXT AGENT — get Chad a Studio playtest of all three; log outcomes in the registry. **Playtest checklist:**
> - **CS-1:** In mouse-aim, put the cursor off to one side, then hold **S** — the loop must be **straight** (no drift back toward the cursor); same for a held A/D roll or Q/E yaw. Release all keys → cursor regains authority when you move the mouse. *(Locked — must be exact.)*
> - **Energy:** Dive to build speed, level and pull a **~30° climb without hard-turning** — speed should bleed **slowly** and you should **zoom back near your start altitude**; try an **ascending defensive spiral**. Then confirm the **crow can't do it as well** (feels heavier/bleeds faster). Confirm the **dive/stoop still accelerates the same** (retention is off in dives). Knob: `Profiles.Eagle/Crow.energyRetention` (0..0.95). If it reads floaty/noclip, lower it; if still bleeds too fast, raise toward 0.9.
> - **Camera:** Space into free-look, pan **all the way up and all the way down** (should soft-stop near vertical, never flip), spin **fully around** — the **horizon must stay level and you never end up sideways/upside down**. Knob: `Camera.freeLookPitchLimitDeg` (raise toward 90 for a steeper look, lower if the extreme jitters). Verify mouse-up/down direction still matches your preference (CS-3 sign, one line if inverted).
>
> **flight==balance reminder:** the eagle now keeps more climb-E → re-check that **4 crows can still corner/mob it** (the energy asymmetry is intentional but the mob must still pressure it). Ground truth is Chad's Studio Play. ONE change at a time; sweep the knobs live before re-tuning.
>
> ### ✅ S13 PLAYTEST — EAGLE FLIGHT MODEL "LARGELY FINISHED" (Chad, 2026-06-30)
> Chad played the S13 build and called it: *"The flight model of the eagle is largely finished. I'm having a great experience."* CS-9 (dive = rest) explicitly confirmed (wings tuck, stamina rises). The energy retention, upright camera, and CS-1 keyboard authority are part of that "great experience" batch — treat the **eagle flight/control/camera feel as signed off** (the crown jewel is locked; don't reopen its calibration without a fresh Chad ask). **▶ THE FRONTIER IS NOW COMBAT + THE 1-v-4 + THE CROW**, not eagle flight: (1) make the AI crows actually MOB (they still scatter — re-weight `updateAICrows`/boids); (2) verify the BEAK strike path + 1-v-4 balance (talon path already confirmed); (3) tune the Crow profile + collision trades for the asymmetric fight. See the "frontier is COMBAT" block below and `combat-directional-strike` memory.
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
- **CS-2 — Free-look is an UPRIGHT spherical orbit: full 360° yaw; pitch tilts up/down to a SOFT STOP just shy of straight-up/straight-down; the operator stays WORLD-UPRIGHT (horizon always level, never rolls or inverts).** **REVISED by Chad S13** — the prior "full over-the-top / under-the-belly UNBOUNDED orbit" is RETIRED: its orbit-derived up flipped the view upside down ("I lost my orientation and ended up looking at my eagle sideways… I want to stay upright, not sideways or upside down"). Chad explicitly chose *stop at vertical* over *pass over the top & re-level*. Impl: `camUp = Vector3.yAxis` (hard world-up) + `freeLook.pitch` clamped to `Camera.freeLookPitchLimitDeg` (85°) so `lookAt` never reaches the pole; base dir flattened to horizontal for symmetric up/down (commit `f61c19a`). STATUS: SPECIFIED. **BUGFIX 2026-07-01 (S14):** playtest found **up/down pan didn't work consistently** ("I can't pan up or down… has to be consistent"). Root cause: the pitch axis was a fixed world-X rotated only by yaw (`yawCF*xAxis`), while the camera direction came from the bird's live heading — so elevation degenerated to zero whenever the heading lined up with that axis (heading-dependent = inconsistent). Fixed by deriving the pitch axis from the yaw-rotated camera direction's own horizontal-right (`pitchAxis = (yAxis × dirH).Unit`), so pitch ALWAYS tilts up/down for any heading; sign chosen to preserve CS-3, camUp still hard world-up, 85° clamp intact (`BirdController.updateCamera` free-look block). Pending Chad's re-playtest. **EXIT-SNAP 2026-07-02 (S21):** playtest — *"coming out of free-look the camera goes to a perpendicular view before smoothly moving; costs ~3/4 s reaction time due to disorientation. Snap immediately to the mouse/reticle centred on heading."* Root cause: on exit `targetCF` is instantly the chase pose but the lerp reverts to the slow `followSmoothing` (~0.165/frame) → a ~3/4 s sweep back. Implemented a **fast crisp return** (uses `freeLookSmoothing` for a few frames on exit → re-centres on heading in ~50-80 ms), NOT a hard 1-frame teleport — deliberately, because during free-look the chase-up stops self-levelling, so after a fast loop the stored up can be tilted and a teleport would flash a tilted horizon; the fast ease lets the up re-level in step. Chad gave latitude ("if it's an easy obvious fix that won't ruin the feel, do it; else leave it"). Camera-only, no flight-input touch, orbit/85°-clamp/world-up UNCHANGED (Space engage is now HOLD, S30 — see CS-4; the exit snap runs identically on release). `setFreeLook` sets `cameraState.snapToChase`; `updateCamera` honors it. Pending Chad's re-playtest.
- **CS-3 — Free-look vertical is INVERTED** (mouse-up = look down). STATUS: SPECIFIED (S13 preserved the S12 pitch sign; unplaytested — if it now reads wrong, it's the one-line sign at the `freeLook.pitch = freeLook.pitch - input.Delta.Y*s` input site, independent of CS-2).
- **CS-4 — Free-look is HOLD on SPACE** (hold to look, RELEASE to resume aim), survives crow-swap. **REVISED by Chad 2026-07-13 (S30) — reverted from the session-9 tap-toggle to hold-to-look.** Hold Space engages free-look; release runs the CS-2 exit snap. Impl: InputBegan Space → `setFreeLook(true)`, InputEnded Space → `setFreeLook(false)` (`BirdController`); focus-loss failsafe still force-clears it. STATUS: SPECIFIED (Chad-directed 2026-07-13, pending his confirm). *(Supersedes the prior LOCKED tap-toggle.)*
- **CS-5 — NO auto-leveling.** The nose stays exactly where pointed; AoA changes ONLY on player input (`STABILITY_RATE=0`, both `recoverNoseDownRate=0`). STATUS: LOCKED (session 9, explicit Chad ask).
- **CS-6 — Grip model "flies where you point"** (velocity follows the nose; requires `cl0>0` — never set `cl0=0`). This is what keeps it stall-free without auto-level. STATUS: LOCKED (`v1.0-eagle-flight`).
- **CS-7 — Control mapping:** A=bank left / D=bank right; Q=yaw left / E=yaw right; W=pitch nose-down / S=nose-up; LeftShift=flap throttle up, LeftCtrl=down (sticky); LMB=strike; RMB=awareness zoom; wheel=eagle-distance zoom; F=formation; R=respawn; 1–4=possess crow. STATUS: LOCKED (see CLAUDE.md Controls).
- **CS-8 — Mouse-aim = nose-chases-WORLD-cursor** (cursor is a world-anchored direction; the nose reticle chases and resolves on it). STATUS: **MATH LOCKED; FELT camera-follow REVISED (Stage 1, Chad-approved 2026-07-12).** The world-cursor MODEL (`aimTargetDir` a world direction, both circle clamps, `computeMouseAim`) is unchanged and still locked. What changed: the camera now eases toward the AIM (`aimTargetDir`), not the bird's heading — so the cursor RE-CENTRES as the view catches it (supersedes the 2026-07-02 "cursor hangs out / nose lags" AskUser decision; `mouse-aim-pursuit-model` memory is stale on this point). One-line edit in `updateCamera` (BirdController ~581); revert = ease target back to `followDir`. ⚠️ Watch: rim-pinned-turn pulsing (camera↔circle-clamp loop) — see the S29 playtest gates.
- **CS-9 — A DIVE is a REST: no stamina cost + stamina REGENS while diving.** A diving bird tucks/retracts its wings, so it isn't actually flapping — a dive spends NO stamina and RECOVERS it (gains both speed AND stamina), even with the flap throttle (Shift) or powered tuck (Ctrl) held. Stamina drains ONLY for active flapping in NON-dive flight (the boom-and-zoom fatigue limiter). Impl: `FlightPhysics` stamina block gates cost on `wantFlap and not self.isDiving`; glide+dive both regen (`staminaDiveCost` now legacy/unused). **STATUS: LOCKED — PLAYTEST-CONFIRMED S13** (Chad: "the wings tuck in a dive and it looks right and the stamina goes up! excellent game feature"). *(flight==balance: dives refuel the eagle's endurance — re-check the 1-v-4 doesn't tip too far.)*

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
