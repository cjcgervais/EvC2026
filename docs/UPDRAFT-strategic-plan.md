# UPDRAFT — Strategic Plan (S31, 2026-07-13)

> Research-backed pivot from the rejected "Eagles vs Crows" aerial-melee-kill loop to a
> non-lethal proximity-flight score game, built on the same loved flight kernel.
> Source: a `deep-research` pass on the Roblox market (108 agents, fact-checked) → a Fable 5
> strategic synthesis. This is the north star; the flight kernel stays the fixed crown jewel.

## The pitch
**UPDRAFT** — *become a bird and score by flying dangerously CLOSE to everything: canyon walls,
treetops, waterfalls, and your friends' wingtips.* Store hook: **"UPDRAFT 🪶 — Fly low. Fly fast.
Don't touch."** The structural bet: replace "hit the other bird" (hard, tiring, wrong tone) with
**"almost hit the world"** (easy to attempt, impossible to master, zero violence). Terrain is a
target that never dodges — it removes all three reasons combat failed while using 100% of the
flight skill the kernel already rewards. It's Superflight's proven loop on a better flight model.

## Theme call — birds, non-lethal (decided)
The kernel's identity IS bird flight; re-theming to dragons/planes throws away assets and re-invites
combat expectations. Birds are age-universal, parent-legible (35% of players are under 13). Non-lethal
is ALREADY BUILT: the feather-burst + spiral-tumble reads as "oof, dazed," not "dead" — a crash = puff
of feathers, brief tumble, lose your unbanked combo, recover in the air. Failure costs score, never life.
Fantastical birds (phoenix, thunderbird) become aspirational cosmetic unlocks, not a theme change.

## Core loop (D1) — LINE-RIDING
Fly close to surfaces → a **proximity meter** feeds a **combo multiplier** → closer/faster/longer grows
it → **bank** the combo by tagging a thermal/perch, or **lose it** by clipping terrain (feather-burst +
tumble, keep flying). Altitude is the stake: climb thermals (energy currency, already built) to buy the
next dive line. Boom-and-zoom re-aimed at the mountain. A Tony-Hawk "bank-or-lose-it" tension layer that
Superflight/Flying Wings don't have.

**First 60 seconds (the decisive conversion lever):** spawn already airborne over the valley → "Hold CTRL —
DIVE" → first canyon-wall pass auto-triggers proximity sparks + combo + wind-rush (scored before knowing
the rules) → glowing thermal: "fly through to BANK" (first currency + level-up chime < 90s) → guided
"First Flight" canyon ends at the Nest hub with other players visibly taking off. FTUE < 3 min, all flying.

## Progression spine (D7) — four parallel tracks (so content doesn't exhaust in a week)
1. **Birds as skill CLASSES, not collection** (⚠️ pet-collection-with-flight was refuted): Crow (agile, built),
   Eagle (energy retention, built), Falcon (dive), Albatross (glide), Owl (night). Each changes HOW you fly the same line.
2. **Lines & Medals:** 20–30 authored challenge lines on the existing mountain map (slaloms, dive gates,
   waterfall threads, night runs) with bronze/silver/gold proximity medals; medals gate region access (geography = progression).
3. **Personal-best chasing** + ghosts (Superflight's whole retention engine).
4. **Cosmetics:** feather colors, contrails, callsigns, tumble anims. Identity, zero power.
- Daily: 3 rotating "Flight Orders" scaled to medal tier → **Feathers** currency (earned only by *banked* score — risk is the economy).

## Social + live-ops (D30) — the algorithm now pays for returning + BRINGING FRIENDS
- **Slipstream / Flock Bonus** (the friend-bringing hook): fly within a wingspan of another bird → both get a
  boost + a shared combo multiplier growing with flock size. Proximity-to-terrain and proximity-to-friend are the SAME verb.
- **Ghost races:** race any line vs your PB ghost / a friend's / the daily top ghost (async — reuses possession/AI-bird replay tech).
- **AI wingmates** for solo players (the 4-bird squad tech repurposed) → reduced Flock Bonus; social never locked to the friendless.
- **Weekly Migration:** a limited-time route (wind shift / storm / aurora) + leaderboard + exclusive feather color. Solo-dev-sustainable cadence (one authored line/week; bigger monthly drop).

## Sandbox angle — a LAYER, not the core
Sandbox-first has no first-60-seconds fun and no precedent; keep the core authored proximity-flight.
Ship sandbox in two tiers: **(3) Nests** — customizable perch/home in the hub, display medals + rare feathers,
invite friends to land (roleplay anchor, cheap, daily-return hook); **(4) Course Maker** — players place
rings/gates/boost-thermals, publish, rate, ghost-race → the UGC flywheel that solves long-run content cost.
Build it only AFTER the authored loop proves retention.

## Monetization — ⚠️ inference only (all specific monetization claims were REFUTED in verification)
Given ~73% under-18 / 35% under-13: **cosmetics only, direct-purchase, price shown. No loot boxes / gacha / paid RNG**
(compliance + parent-trust risk). A seasonal **Migration Pass** (~30-day, free + paid cosmetic track, all earnable).
Birds early-unlockable with Feathers; Robux only skips the grind — **no pay-for-power** (power = skill). Do NOT monetize energy/retries/multipliers.

## Risks + mitigations
- **Flight commercially unproven on Roblox (no flight game in top-20):** uncontested-lane bet with a cheap kill-switch —
  the Phase-0 MVP tests the loop in ~2 weeks; gate further spend on real D1/D7 numbers. (It's secretly a skill-score/race game — a proven macro-genre — wearing flight.)
- **Youngest cohort (<9) can't fly 6DOF:** **Fledgling Mode** = auto-flap, stall-proofed pitch envelope, wider proximity detection, mouse-only steer — a kernel *profile* (asymmetry already lives in profiles); offer it in FTUE after 3 crashes.
- **Scoring feels like homework:** Phase-0 gate is Chad's own playtest — "do I hunt lines for fun?" If the meter fights the flying, fall back to Superflight's always-on ambient scoring before adding anything.

## MVP + build order
- **Phase 0 — "Is line-riding fun?" (build FIRST, ~1–2 weeks):** strip combat remotes/UI; **proximity scorer** (reuse
  `BirdCollision`'s spherecast with a second wider probe radius — nearly free); combo counter + bank-on-thermal (thermals
  exist) + crash = feather-burst + tumble (both built) + score HUD; spawn-in-air FTUE stub. Test on the EXISTING mountain map, no new content.
  **Gate: Chad plays 30 min and wants line #2.**
- **Phase 1 — progression skeleton:** Feathers + DataStore persistence, 5 authored medal lines, Crow as 2nd bird (built, needs unlock path), 3 daily Orders. Gate: does a returning session have a goal?
- **Phase 2 — the social sky:** shared-server visibility polish, Slipstream/Flock bonus, PB ghosts + ghost racing, line leaderboards. Ship before public launch (algorithm measures friend-bringing from day one).
- **Phase 3 — launch dressing:** Fledgling Mode, Nest hub, first Migration + Migration Pass, 20+ lines, Falcon + Albatross.
- **Phase 4 — the flywheel:** Course Maker + UGC line browser. Only if D7 numbers earned it.
- **Explicitly NOT building:** any combat system; pet collection/hatching (refuted); open free-building in the core; a new map before the loop is proven; gacha; mobile control rework before Phase 3.

## Research findings this rests on (fact-checked; full report in the S31 deep-research output)
1. 2026 Roblox discovery optimizes for **28-day retention**, down-weights flashy thumbnails, rewards returning + friend-bringing + spend as separate signals. Build to RETAIN.
2. **First-session conversion is THE lever** (casual <2 min vs core 37 min, ~15x); get to fun in <5 min. A flight kernel fun in 60s is the ideal fit.
3. Retention framework: D1 = core loop + FTUE; D7 = progression (don't exhaust content); D30 = live-ops + social.
4. **Flight-as-its-own-reward is proven** (Superflight proximity flying, NO combat; Flying Wings = distance + wing upgrades). ⚠️ pet/creature-collection as a flight companion was **refuted**.
5. Audience ~73% under 18 (35% <13, 38% 13–17), ~2.6 hrs/day per DAU — age-appropriate tone + monetization required.
6. **No flight game in the top-20 by revenue** → risk (unproven core genre) + opportunity (open lane).
7. ⚠️ All specific monetization claims were **refuted** in verification → monetization is reasoned inference, not verified; treat gacha as a compliance risk.

*One-line version: the kernel already made flying feel dangerous and wonderful — UPDRAFT just gives the danger a scoreboard and the wonder a friend.*
