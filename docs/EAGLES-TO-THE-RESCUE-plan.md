# EAGLES TO THE RESCUE — Creative Design Bible (S31, 2026-07-13)

> The current game direction (supersedes UPDRAFT + the combat loop). Chad-authored vision,
> sharpened into a design bible by a Fable 5 creative consult. Built on the loved flight kernel
> (the fixed crown jewel). Reuse claims below are verified against `src/`.
> Target: a HIT on Roblox for ages 5–20. Non-lethal, cute, heartfelt, flight-FIRST.

## Pitch & pillars
**EAGLES TO THE RESCUE** — *you are the fastest thing in a burning forest, and every squirrel down there knows your name.* A forest is on fire; you dive a hero eagle under the canopy and terrified critters leap for your talons in slow-motion — always caught — then ride your back to the waterfall safe zone as the fire closes in. Listing subtitle: **"Fly. Dive. Save them all. 🦅🔥🐿️"**

**Pillars:**
- **P1 — THE CATCH IS SACRED.** Every system serves one moment: a small brave creature leaping, and you being there. The catch is *guaranteed on trigger* — the skill is getting there, never the grab. A feature that dulls/delays/complicates the catch gets cut.
- **P2 — FLIGHT IS THE SKILL, SPEED IS THE STYLE.** The loved kernel IS the game. Ceiling-skimming, trail-threading, waterfall-riding. A 5-yo can rescue; a 15-yo rescues *beautifully*, and the game scores the beauty.
- **P3 — DANGER WITHOUT CRUELTY.** The fire spreads and pressures, but nothing on screen ever suffers. Un-rescued squirrels are carried off safe by the "Ranger Balloon" at round end (they wave sadly = missed points, never harm). No death anywhere, ever.
- **P4 — EVERYONE YOU SAVE, SAVES WITH YOU.** Rescued squirrels become decorated pets → ride your back → earn RC planes → fly formation to rescue *their* friends. Heroism grows a family that helps.

## THE SIGNATURE CATCH (make-or-break — ~2.1s beat, ~1.2s of slow-mo)
Design goal: a moment so charming a spectating parent says "do that again." Juice before geometry.
1. **The want:** stranded squirrels wave both arms (readable 300+ studs), emit a soft golden **sparkle beacon** (rare types tint it), and **squeak spatially** ("Hey! Over here!!") so you hear hidden ones under the canopy. Near the fire the wave goes frantic + beacon flickers orange = urgency at a glance.
2. **The trigger (the flyby):** a ~28-stud sphere around the squirrel, gated on **closing speed > ~40% cruise** and **you have carry capacity** (hovering doesn't trigger — the *flyby* is the verb; too-slow → squirrel signals "go around, come back fast!"). **No aiming** — any fast pass through the sphere triggers; the skill was the approach LINE (under canopy, through trunks, along a trail cut). Reuses `computeProximity` (retarget rays: nearest terrain → nearest rescuable).
3. **Pre-trigger tell (~0.4s out, predicted from closing velocity):** the squirrel SEES you, stops waving, plants its feet, eyes go wide-and-determined — the "determined little survivor" beat + a "hup—!" inhale. **This anticipation frame is the heart of the game. Never cut it.**
4. **The leap + slow-mo:** on trigger the squirrel FLINGS itself in a **ballistic arc solved to intercept the eagle's PREDICTED path** ~0.5–0.8s ahead (path known from velocity → the catch is guaranteed while looking fully physical; the arc silently re-fits each frame if the player yanks the stick — unbreakable, forgiving). World timescale eases to **0.25×** (client-side presentation only), wind drops, a warm "catch chord" (rising major third) swells, everything desaturates *except* the squirrel + eagle. The squirrel tumbles once (reuse spiral/tumble anim) into a starfish "I'M FLYING" spread at apex (the screenshot frame), golden-mote trail (rare = tinted arc across your screen).
5. **The catch:** talon-basket swings under; the eagle does a small authored "scoop" flourish (5–10° bank-dip-and-rise **decorating the real flown path — kernel trajectory never overridden**). Squirrel lands butt-first, bounces, grabs the rim. **POOF** = feather burst (reuse) + gold sparkle ring + a big soft **"POMF"** + 3-frame hit-stop.
6. **The GOTCHA:** time snaps back over 0.2s with a *whip* of wind; **"GOTCHA!"** (or "RAINBOW GOTCHA!!") stamp + points; the squirrel scrambles to an open seat on your **back**, turns, and **waves back at the forest**; back-riders high-five the newcomer. A delayed 0.5s "…woohoo!" lands after your attention returns to flying.
- **Camera:** slow-mo eases ~15% closer, cants ~4°, FOV tightens ~5° — cinematic but **input keeps full authority the whole time** (the free-cursor render/control split makes this safe). Catch = one soft 2–3px shake pulse, ease home 0.4s. Rare catches auto-capture the apex frame → polaroid on the round-end screen (screenshot bait).
- **Multiplayer:** slow-mo is **client-side presentation** (catching player's client dilates anim/FX/camera/audio locally; sim + server run real-time; arc authored to read at both speeds; catch is server-validated off the same trigger — matches the existing client-spectacle / server-authority model).
- **Anti-staleness:** vary voice pitch, 3–4 leap styles (cannonball/swan-dive/flail/cool-guy), catch quips, back-seat antics, and the STYLE score (§ loop) so the *approach* varies. Core timing never changes — a ritual, like Mario's flagpole.

## Core loop (2-min round)
Macro-rhythm: **SCAN (high) → DIVE → THREAD (low, under canopy) → CATCH ×N → CLIMB the waterfall → DELIVER → re-SCAN.** One lap ≈ 25–40s; 4–6 laps/round; the fire re-scores the map between laps.
- **SCAN:** altitude = information (beacons, smoke, spatial squeaks) AND stored dive energy — the kernel's energy model teaches itself (height = rescue speed).
- **DIVE + THREAD:** easy squirrels on treetop crowns (skim + swoop); juicy ones in clearings/grottos reachable only via **trail cuts** (tunnel gaps under the canopy). The S31 line-riding proximity scorer becomes the **STYLE meter** (skim/thread/tunnel = a style combo multiplying the next catch). Speed + closeness = style currency = the kernel's feel as score.
- **CATCH → CARRY:** base **3 squirrels on your back** (start value). **Zero handling penalty for carrying** — the loved flight feel is sacred; cargo pressure comes from the round CLOCK, not degraded flight.
- **DELIVER (the waterfall):** the safe zone sits atop a central waterfall; a **Thermals-tech updraft** runs up its face (direct reuse, re-skinned as mist) — you spiral-climb it, squirrels whooping, and cross the rim pool where they leap off onto the meadow and join the growing crowd of everyone you've saved. **The safe-zone crowd IS the visible scoreboard.**
- **FIRE:** advances meanwhile; cut-off beacons flash orange; last 20s = heartbeat drum + "the balloon's coming — save who you can!"
- **Round end:** fireworks; the Ranger Balloon collects the missed (safe, waving); tally (rescues, rares, style, best combo, Forest Saved %) → meta screen (who joined your den, plane progress, next unlock).

**FTUE (first 60s, no tutorial screens):** spawn already airborne over a *green* corner; one beacon ahead + "Fly to the squirrel!"; the trigger sphere is 1.5× for the first 3 catches so **the game's best moment fires unearned in the first 20 seconds**; a back-rider points you to the waterfall; deliver; then a distant *whoomph*, smoke, 3 beacons light, clock appears 2:00, "Eagle! They need you! GO!" — the real round begins. **Crashing is NEVER death** — cartoon bounce + feather poof + 1.5s dazed recovery (reuse the graze-slide; delete the lethal branch for this game).

## The world + the fire — "Emberpine Valley"
A bowl valley readable in one glance from altitude (reuse the terrain map, re-dressed). Vertical layering IS the design (high = scan/safety/energy; canopy = style; understory = skill/treasure):
- **CANOPY** — a rolling treetop sea (map's "second floor"), skimmable, with crown perches.
- **UNDERSTORY** — trunk colonnades, boulders, log arches, and **TRAIL CUTS**: 6–10 named authored tunnel-corridors of clear air under the leaves (the skill race-lines to hidden clearings — "Foxglove Run", "Old Log Tunnel").
- **CLEARINGS/GROTTOS** — named landmarks holding better squirrels (lily pond, stump circle, ruined ranger tower, berry hollow).
- **RIVER → WATERFALL** (the vertical centerpiece, visible everywhere = wayfinding) → **SAFE ZONE** rim-pool meadow on top (always green, the saved-crowd, the Ranger's cabin/shop space).
- **THE FIRE (living antagonist — a slow, readable, inevitable tide; pressures the MAP not your reflexes):** a coarse **fire-cell grid** (~40–60 stud cells, ~20×20–30×30, server-side, ~2 Hz). States GREEN→SMOLDER(15–25s warning)→BURNING→EMBER; spread rolls to neighbors weighted by a **per-round wind vector** (one number → a different fire shape each round = replayability). Squirrels don't die — they get **cut off** (surrounded beacon → countdown ring → Ranger Balloon pre-collects it, safe but off your board). Triage = the strategy layer. **Perf plan:** never per-tree sim — per-cell flipbook flame billboards + one smoke `ParticleEmitter` + one `PointLight` per *burning* cell, hard-capped (~30 active), EMBER = free material/tint swap; trees never deform; reuse `SpatialHash` for near-queries. Target ≤ ~1.5ms server + normal particle budget on a low-end phone.

## Progression + meta
- **ACORN POINTS** (soft currency) from rescues + rare bonuses + style combos + full-batch delivery + Forest Saved %.
- **Level track:** new *valleys* unlock on cumulative-rescue milestones (Emberpine → Frostfall → Cinder Canyon → night rounds); each = new trails, same sacred loop.
- **Rare squirrels:** spawn-table rarities (brown / Silver / Gold / Rainbow / Shadow(dusk) / seasonal). Rares score big AND join **The Den** (collection book = the completionist engine). **Rares are never purchasable — rarity is only rescuable.**
- **PET → BACK → RC PLANE → FORMATION arc (meta crown jewel, maps directly onto shipped squad tech):** rescued → lives in your **Den** (named, greets you on login) → **decorate** (hats/goggles/scarves/paint — the collection's expression + monetization heart) → **ride-along** back crew (up to 3, cosmetic + charm, soft beacon-pointing assist) → **the plane grind** (each squirrel visibly *yearns* to fly; its RC plane unlocks via its own meter = rounds-on-your-back + rare **plane PARTS** hidden in hard-to-reach grottos [flight-skill content]; a den workbench visibly assembles it part by part; finish = a little hangar cutscene) → **FORMATION SQUADRON** (up to 3 plane-squirrels fly formation — **direct reuse of the 4-bird `Boids`/`Squad.formations` tight/loose + AI-update path**, re-skinned prop planes; **F** still toggles tight/loose). Squadron verbs (staged): **ladder-drop** (planes ferry near-squirrels to safety = throughput; your slow-mo catch stays the sacred, superior hero moment), **spotter** (pings hidden/cut-off squirrels), **scooper** (late-game, mists a smolder cell green briefly — the only, small, expensive anti-fire verb). Possession-swap (1–4) is NOT exposed at launch (flying the eagle IS the game) — held for a future "Plane Day" event; the tech idles, not deleted.
- **Roster expansion (new RESCUERS):** POSSUM (glider, huge carry, plays-dead crash gag), RACCOON (barrel-copter, grabs from water/ground), owl (night specialist), hummingbird (trail demon) — **each a PROFILE on the same kernel** (the Eagle/Crow profile system already proves the kernel is class-agnostic). Each brings favored critter types (hedgehogs, turtles, bunnies, owlets…) = catch variety (new leap anims, same catch grammar).
- **Session hooks:** daily Ranger Requests, weekly rare rotations, event valleys — all feed den/decoration/planes, **never flight power**.

## Social
- **Solo is fully first-class** (FTUE is solo-shaped; the squadron makes solo feel companioned).
- **DUOS:** two eagles, one valley, shared round score + individual style; co-op around **complementary lanes** (the fire splits the map); kid-safe **ping wheel** ("I got the stumps!", "Help!", "GOTCHA!"). **Double Rescue:** both trigger catches within 2s → both slow-mo together on both screens + bonus (the clip kids capture).
- **Friend-bringing (2026 algorithm reward):** Rescue Assist bonus; a "first rescue together" polaroid with both names; daily den greetings (your squirrels miss you); plane-assembly that resolves *next session*; weekly rare rotation; a visitable/decoratable den friends can tour.
- **Servers:** small (8–12), valley-shared but round-instanced per party (public feels alive — other eagles' fireworks, den emote plaza — without strangers affecting your round). **Zero griefing surface** (no one can touch your squirrels/fire/score) = safe for 5-yos + parent trust.

## Monetization (wholesome, compliance-safe)
**No pay-to-win** (nothing purchasable affects flight/catch/capacity/fire/score); **no paid randomness for under-13** (no gacha/crates; every purchase is see-exactly-what-you-get); cosmetic/expression only.
- Eagle **swag** (feather patterns, style trails, basket skins, victory fireworks) + squirrel **decoration** + den furniture. The style system means eagle cosmetics are seen at their best in every flyby (they sell themselves).
- **Rescue Pass** (seasonal, one price, visible generous free lane) + a one-time "Golden Feather" supporter pass (cosmetic only).
- **Earnable-first:** every cosmetic category has strong acorn-earnable entries; paid = variants, not gates. Roblox text filter on names; no trading at launch (scam vector).

## Risks + mitigations (top ones)
1. **Forest+fire art cost (the big one)** → stylized-chunky art (reads lush via color+density, not fidelity); ONE hero valley at launch; canopy imposters/instancing; the per-cell fire budget above; extend `BirdBuilder` procedural pipeline for critters/planes.
2. **Youngest control floor** → generous trigger spheres (+1.5× FTUE), zero-death crashes, waterfall updraft does the climb, treetop squirrels catchable with sloppy flying (depth lives UNDER the canopy, floor ABOVE it), optional "Junior Wings" presentation-assist (kernel untouched), touch/gamepad first-class from MVP (huge % of 5–12 are on touch).
3. **Slow-mo multiplayer sync** → client-side presentation dilation (prototype week one — the plan's only novel tech risk).
4. **Catch staleness** → variation axes + style-as-variable + protect the ritual timing.
5. **Fire trivial-or-unfair** → never harms (only cuts off), countdown rings, 2 Hz tunable cells, live-tune the pace (Chad's one-knob-per-flight rule).
6. **Tone drift to peril** → P3 content gate ("would a 5-yo's parent smile?"); Ranger Balloon guarantees safety; no burned animals ever, incl. marketing.
7. **Kernel regression** → rescue is built AROUND the kernel (triggers/presentation/world), never IN it; catch flourish only decorates the flown path; carrying adds zero handling; any kernel touch goes through the LOCKED-spec gate.

## MVP + build order
**The one question the MVP answers: "Is flyby-catch-and-deliver FUN for 2 minutes?" Everything else waits for a yes.**
- **PHASE 0 — THE FUN TEST (build FIRST, smallest slice, gray-box):** (1) **the catch end-to-end at full juice** — retarget `computeProximity` to squirrel proximity → guaranteed arc-intercept leap → client slow-mo → auto-catch + POMF (reuse feather burst + tumble) → GOTCHA stamp → capsule squirrel on the back. *The squirrel can be a bean with eyes — the TIMING + SOUND must be real. Juice before geometry.* (2) 10 hand-placed squirrels on primitive trees, 2–3 with a crude under-canopy approach. (3) delivery: a cliff + re-skinned Thermal column + safe pad + batch counter. (4) 2:00 clock + score; no fire yet (a scripted beacon-expiry at 1:00 fakes triage). **Gate (verbatim): "Did you grin at the third catch, and push your luck for one more before the waterfall?"** If no → live-tune the catch timing/sound before building anything else.
- **PHASE 1 — THE ROUND:** fire-cell system (coarse/ugly/functional) + cut-off + wind variety; style combo scoring on the line-riding detector; round flow + tally; real squirrel model + 3 leap anims; FTUE; crash→bounce (delete lethality); touch + gamepad passes.
- **PHASE 2 — THE VALLEY (make it beautiful, once):** Emberpine proper (canopy + imposters, 6 named trails, clearings/grottos, real waterfall + safe-zone crowd), fire visual tiers + audio, rare spawn table + The Den collection. **Soft-launch here** (a complete charming product: catch + fire + collection).
- **PHASE 3 — THE SQUADRON:** squirrel decoration + den; plane-part pickups + workbench arc; RC planes flying formation (Boids/Squad reuse) + ladder-drop; duos + ping wheel + Double Rescue; Rescue Pass + shop.
- **PHASE 4+ (deferred — written down, not built):** possum/raccoon/owl rescuers (new profiles), new valleys + night rounds, new critters, spotter/scooper verbs, Plane Day possession event, seasonal events, den visiting, trading (maybe never).
- **NOT in MVP:** planes, decoration, duos, rares, fire visuals, real trees, a 2nd rescuer, monetization. The whole vision is staged here — but the brave eagle, the leaping squirrel, and the nick-of-time catch come FIRST.

## Reuse map (verified against src/)
| Bible element | Reuses |
|---|---|
| The hero eagle + flight | The loved kernel (`FlightPhysics`), untouched — the fixed crown jewel |
| Catch trigger | `computeProximity` (S31 line-riding rays), retargeted terrain→squirrel |
| Style/combo scoring | The S31 line-riding proximity scorer (`GameConfig.Updraft` + BirdController) |
| Slow-mo camera safety | The free-cursor render/control split (camera decoupled from input) |
| Catch poof / crash bounce | The feather-burst FX + spiral/tumble anim (S31 juice) + `BirdCollision` graze-slide |
| Waterfall updraft delivery | `Thermals` volumes + `FlightPhysics:SetThermalForce` |
| Squirrel-plane squadron | `Boids` + `Squad.formations` (tight/loose) + the AI-crow update path + possession tech |
| New rescuers (possum/raccoon…) | The class-agnostic Profile system (asymmetry in numbers) |
| Procedural critters/planes | `BirdBuilder` construction pipeline |
| Near-queries (fire/squirrels) | `SpatialHash` |

*Heart of the doc (Chad's): a forest on fire, a determined little survivor leaping into the sky, and you — already there.*
