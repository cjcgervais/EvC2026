# archive/ — Eagles vs Crows, the single-bird-kernel spec

This folder holds the **reconstruction-grade master specification** of the game as of the
`single-bird-kernel` snapshot (commit `52a929c`, 2026-06-30). It is the durable, human-readable
record of *what the codebase is, why every number is what it is, how it's coded, and what was
learned building it.*

- **[`SINGLE-BIRD-KERNEL-MASTER-SPEC.md`](SINGLE-BIRD-KERNEL-MASTER-SPEC.md)** — THE document.
  If all source were lost, an engineer could rebuild the flight kernel, the controls, the camera,
  the server authority model, and the full tunable set from this one file. It reverse-engineers the
  live code (`src/`), the research (`docs/RESEARCH.md`), the design memory, and the playtest history.

## Provenance
- **Frozen source snapshot:** GitHub branch `single-bird-kernel` at commit `52a929c`
  (`https://github.com/cjcgervais/EvC2026`). Also tagged `v1.0-eagle-flight` (pure kernel) and
  `v1.1-eagle-flight-feel`.
- **State at capture:** the eagle flight / control / camera feel is **signed off** by the designer
  ("largely finished… a great experience"). The frontier is combat + the 1-v-4 + the crow.

## How to use this to reconstruct
1. Read Part I–II (vision + research) to internalise the design thesis: *flight physics and
   asymmetric balance are one system.*
2. Rebuild in dependency order: `GameConfig` (Part V) → `FlightPhysics` (Part IV) → `BirdBuilder`
   / `Boids` / `BirdCollision` / `SpatialHash` (Part VII) → `GameServer` (Part VII) →
   `BirdController` / `GameUI` (Part VI).
3. Validate against the acceptance criteria (Part X). Ground truth is Studio Play — the build
   resolves wiring but does not run Luau.
4. Never violate the LOCKED CONTROL SPECS (Part VIII) or the kernel invariants (Part X).
