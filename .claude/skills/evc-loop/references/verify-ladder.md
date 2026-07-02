# Verify ladder — ground truth, cheapest-first

**The hard truth (do not forget it):** Roblox isn't headless and there's no
compiler/linter/test runner wired in, so `build.ps1` **resolves project wiring and
class mapping but does NOT run or syntax-check Luau.** The only validation of
behavior and *feel* is **Chad pressing Play in Studio.** Never mark work "done" on
your own assertion — that violates the loop's independence rule (verifier ≠
optimizer). Escalate the ladder cheapest-first and stop at the tier that can
actually judge the change.

## Tier 0 — wiring floor (every iteration, seconds, guaranteed)
```
.\build.ps1
```
Green = the Rojo project resolves and every script maps to the right class
(Script / LocalScript / ModuleScript). Red = you broke the project structure —
fix before anything else. This is the floor, never the definition of done.

## Tier 1 — headless static analysis (OPTIONAL, high value, best-effort)
```
.\verify.ps1
```
`verify.ps1` self-bootstraps (mirrors `Bootstrap-Rojo.ps1`) and runs, best-effort:
1. **`luau-lsp analyze`** over `src/` with a Rojo sourcemap + Roblox API defs —
   catches the things the build can't: broken `require` paths, renamed-contract
   mismatches (`GameConfig.Profiles.*`, the `FlightPhysics` API, Remote names),
   nil-index and unknown-field errors. This is the single biggest automated win —
   it enforces the "grep before renaming" cross-file contracts in `CLAUDE.md`.
2. **`selene`** lint over `src/` — undefined globals, shadowing, unused,
   suspicious comparisons, multiple-return misuse.
3. **`rojo build`** (Tier 0) as the guaranteed floor.

Each tool is **best-effort**: if a binary can't be bootstrapped on this machine,
`verify.ps1` reports that tier `UNAVAILABLE` and still runs the rest, so the build
floor always executes. Run `verify.ps1` on any meaningful logic change; it's cheap
insurance against a broken-require regression that would otherwise only surface
mid-playtest. *(This tier is newer than the rest of the harness and was authored
without a live run — if it misbehaves, fall back to `build.ps1` and note it.)*

## Tier 2 — pure-kernel numeric tests (OPTIONAL, offline, future)
`FlightPhysics` is a pure module (no instances touched), so its math is testable
offline with **Lune** (`lune run tests/kernel.luau`): assert lift/stall AoA,
energy-retention climb bleed, no NaN, and the **stall < spawn < cruise** invariant
as regression tests. Not yet set up — a good task when kernel churn resumes. It
converts the research-grounded numbers into guardrails so a future edit can't
silently break the ordering. (See the tooling notes in the S14 research report /
memory for `luau-lsp`, `selene`, `lune`, Open Cloud Luau Execution and their
exact limits — notably: Open Cloud runs Luau in-engine but **does NOT run physics
or auto-run scripts**, so it can't validate the integrated flight loop.)

## Tier 3 — the human gate (Studio Play — irreducible)
Flight feel, camera, input, `SetNetworkOwner` replication, collisions over stepped
physics, frame budget, and the 1-eagle-vs-4-crow matchup **can only be judged by
Chad in Studio.** No 2026 tool removes this. Your job is to make his Play sessions
count by handing him a **crisp playtest checklist.**

### Writing a good playtest checklist (this is your ground-truth *request*)
For each thing that needs a human eye, give:
- **Setup** — how to get into the situation (e.g. "possess a crow with 1–4",
  "dive to build speed, then pull a ~30° climb without hard-turning").
- **Exact input → expected observation** — what he should do and what he should
  see if it's right ("hold S off-center cursor → the loop is *straight*").
- **The knob if it's off** — the `GameConfig` field + which way to move it
  (Chad tunes live, so name the lever and its direction).
- **Re-confirm touched LOCKED specs** — for any control/kernel change, list which
  CS rows the checklist re-verifies (they must still hold).
- **flight==balance re-check** — one line on the 1-v-4 implication to eyeball.

Then **wait for his result and LOG it** (into the HANDOFF session block / CS
registry). His confirmation is the CONVERGED signal; his "no, it does X" is a
Reflexion input for the next iteration — both are gold, neither is a failure of
process.

## Anti-reward-hacking (non-negotiable)
Never weaken a criterion, silence a check, or hard-code an output to make a gate
pass. If the only way to "pass" is to change the test or reinterpret what Chad
asked, **stop and surface it to him.** Green-on-a-technicality is worse than red.
