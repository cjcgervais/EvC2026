# Kid-Legibility Plan — the Ember Valley fire round (S41)

**Origin:** Chad flew the live fire round — "the fire is square, the squirrels are just light cylinders… it reads a sense of urgency but too abstract for kids… the urgency feels opt-in if you can understand the picture, not intuitive especially for a kid." The round works MECHANICALLY but fails the **kid-FLOOR** (the game's core pillar). Two read-only design passes (rescue-gameplay-architect + a Fable creative-director pass) converged on the staged plan below.

**The bar:** a 5-year-old reads **faces, motion, and known icons** instantly; anything requiring **spatial inference** ("glowing squares are advancing toward light pillars") is *decoding* — and decoding is what makes urgency opt-in. Each stage replaces a decode with an instant read.

**Invariants (every stage):** presentation / world / FX / design ONLY. The flight **KERNEL + camera + aim are SIGNED-OFF and LOCKED — untouched**. Non-lethal always (P3 — peril then rescue/lift-out; a kid never sees an animal die). Reuse the pooled/budgeted render (≤`maxVisualBurning` markers, allocate-once). Each stage ships behind an **identity gate flag** (default = today's behavior; flip to fly it; flip back = byte-identical), gets a **headless Lune gate** where possible, and ends with **one Chad flight**. Follows the S41 approach-vetting SOP (`.claude/skills/evc-loop/references/fx-approach-vetting.md`).

Chad's call (S41): **build the full 1→2→3 sequence**, each gated + revertable + its own flight.

---

## Stage 1 — Squirrels read as CUTE CRITTERS IN PERIL  *(fixes "just light cylinders")*
The critter model is fine (`BirdBuilder.BuildSquirrel:735`, poses `PoseSquirrel:969`); the **neon beacon pillar dominates** so the eye lands on a light column, not the animal. Make the help-signal out of *critter-ness + motion*, not light.
- Demote the tall pillar (`RescueServer.buildBeacon:~330`) → a **flat ground halo/ring** (reuse `FireVisuals.buildRing`) that *frames* the squirrel + a **bobbing chevron/flag** just above the head (rarity by color/shape). Scale the critter up; **default stranded pose → big two-arm wave** (exists) + small **client-side hops** (tell-loop `PivotTo` bob, gate to `State=="stranded"`).
- **Read:** a small animal waving + bouncing under a "look-at-me" frame = pre-verbal "HELP, over here!" Motion catches the eye at flight speed; a static pillar habituates to invisible.
- **Hooks:** `RescueServer.buildBeacon`; `GameConfig.Rescue.beacon*` (~:845) → ring radius + chevron height; client tell-loop (~:2057–2096, reuse the Frantic path); pose default.
- **Gate flag:** `GameConfig.Rescue.beaconStyle = "shaft" | "halo"` (identity `"shaft"`).
- **Headless gate:** extend `tests/models.spec.luau` — halo radius ≥ squirrel footprint, chevron clears head bounds, critter legibility height at scale, wave amplitude ≥ X.
- **Play gate:** "On the dive-in, does your eye land on a waving animal, or on a glowing object?"

## Stage 2 — Fire reads as FIRE  *(fixes "the fire is square")*
Current cell = static Neon box (`FireVisuals.buildCellSet:52`). Fire's identity is **shape (teardrop) + motion (flicker/rise)** — a box has neither.
- **Engine-animated flame particles** on each pooled cell (Roblox built-in fire sprite / legacy `Fire` fallback — free 60fps flicker, no server cost) + **teardrop two-tone geometry** (orange outer Ball + yellow-neon inner core, leaning a few degrees downwind) so the distant front is flame-*shaped*, not cubic + **one MEGA smoke plume** at the burning-set centroid, **leaning downwind** = a free, honest **spread telegraph** ("smoke's blowing at that grove → it's next"), scaling with burning-count.
- **Read:** 🔥 shape + licking motion + a horizon smoke smudge = "FIRE, heading *that* way." No decoding.
- **Hooks:** `FireVisuals.buildCellSet` (inner flame emitter + flicker fields) + `FireVisuals.sync` (per-marker flicker arithmetic off `tickN`; feed `fireState.windX/windZ` into smoke `Acceleration`; centroid plume); `GameConfig.Fire` (~:1084 — `smokeRate`, `flickerAmp`, `flameRate`, `smokeLeanStrength`).
- **Gate flag:** `GameConfig.Fire.flameStyle = "static" | "flicker"` + `smokeLeanStrength = 0` inert.
- **Headless gate:** smoke-lean XZ aligns with `grid.windX/windZ` (telegraph is *correct* vs where cells actually ignite); flame geometry (core-inside-shell, taper, lean sign). Perf: reuse ≤30 pooled markers, +1 small emitter each (allocate-once), flicker arithmetic-only.
- **Play gate:** "From scan altitude, do you see a fire and know which way it's going before you dive?"

## Stage 3 — Urgency becomes VISCERAL and NON-OPTIONAL  *(depends on 1–2 reading first)*
Urgency lands on a kid through two channels needing no decoding: **another creature's fear** and **the world getting worse** — both ambient, can't opt out.
- **Squirrels escalate as the fire nears** (`Danger` 0/1/2 attribute = pure `FireGrid` distance arithmetic, set at fire-tick): calm wave → `waveBig` + hops → full panic + the halo/chevron flips **red and flashes faster** as the deadline nears (reuse the existing `Frantic`/`fireGraceUntil` + cut-off-ring pattern). Auto-teaches triage. Missed squirrels still lift out on the friendly Ranger Balloon (P3 near-miss, never harmed).
- **World dims orange** as `burnedFraction` rises + near the fire (client Lighting projection, **stateless per-frame** per the S37 audio lesson — no tweens/state; tint gently, don't fog out the far-render valley).
- **Fire roar/crackle** loop, `Volume` = stateless per-frame function of distance to nearest burning cell (the proven S37/S38 flap-audio architecture) + an **ignition whoomp/flash** at newly-lit cells (one pooled burst emitter teleported to new-age cells).
- **Read:** a scared little animal + a darkening, roaring world = "GO GO GO," pre-cognitive.
- **Gate flag:** `GameConfig.Fire.urgencyTells = false` inert (balloon unchanged).
- **Headless gate:** the `Danger` escalation is monotone as the front approaches a perch (pure grid arithmetic, `RescueRules`-adjacent — cleanly testable).
- **Play gate (whole plan):** "Did you grin at the 3rd catch AND feel the fire pressure enough to push your luck for one more?"

---

## Larger track (LATER — separate phase, lower leverage-per-hour)
A pretty map won't fix an illegible squirrel or abstract fire, so this *follows* the reads:
- **Map:** a canopy/treeline the fire visibly **eats** (green→charred behind the front — lean on the existing `FireVisuals.buildEmberPatch` charred patches; strongest environmental urgency), a legible waterfall/safe-zone silhouette, per-grove landmark identity.
- **Animation:** richer squirrel panic/relief, the eagle approach, the balloon rescue beat — Fable-bracketed cosmetic batch per the S39 process (build → audit → one Play).

## Files
`src/shared/FireVisuals.luau`, `src/shared/FireGrid.luau`, `src/server/RescueServer.server.luau` (`buildBeacon` ~:330, fire tick ~:1080), `src/client/BirdController.client.luau` (tell-loop ~:2057), `src/shared/BirdBuilder.luau` (`BuildSquirrel:735`, `PoseSquirrel:969`), `src/shared/GameConfig.luau` (`Rescue` ~:743, `Fire` ~:1084), `tests/models.spec.luau` + new specs. Kernel/camera/aim: **never.**
