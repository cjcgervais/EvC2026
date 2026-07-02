# Red-team — adversarial review before you propose a change

The loop's quality gate. The optimizer (you, making the change) must not grade its
own work; a **separate** adversarial reviewer attacks the change against the
project's SOPs before it's proposed to Chad. This catches the collateral
regressions and balance blunders that are this project's biggest risk — *before*
they cost a playtest session.

## When to red-team
- **Always**, before proposing a change that touches: control / camera / input /
  flight-feel, the aero **kernel** (`FlightPhysics`, `GameConfig.Flight`/profiles),
  **combat** (strike, collision, damage), or the **1-v-4 balance**.
- **Optional** for isolated AI-tuning or map/BirdBuilder tweaks — use judgment;
  when in doubt, run it.
- **Skip** for pure docs / memory / comment edits.

## How to run it
Spawn the **`red-team-reviewer`** subagent (defined in
`.claude/agents/red-team-reviewer.md`) with: the diff (or a precise description of
the change), the FRAME (what "done" is), and which CS rows / invariants you believe
are in scope. It reviews against the checklist below and returns findings by
severity. It has read-only tools — it reports, it does not edit.

Prefer a real subagent (isolated context, independent judgment) over reviewing
your own change in-line. For a heavier pass on a big or risky change, spawn 2–3
reviewers with different lenses (LOCKED-spec correctness · flight==balance · build/
contract integrity) and take the union of their findings.

## The red-team checklist (what the reviewer attacks)
1. **LOCKED-spec violation or collateral.** Does the change alter or interact with
   any CS-1…CS-9 behavior or a kernel invariant (`cl0>0`, auto-level off, keyboard-
   first, stall<spawn<cruise, `AIR_DENSITY`/`GRAVITY_G` lockstep)? Any *second-order*
   effect on a locked behavior (shared input/camera/stamina/energy state)?
2. **One-change discipline.** Is this actually one attributable change, or several
   smuggled together? If bundled, it should be split.
3. **flight == balance.** What does this do to the 1-eagle-vs-4-crow fight? Does it
   quietly tip the matchup (e.g. eagle keeps more energy → can the mob still corner
   it)? Every flight number is a balance number.
4. **Refine-not-regenerate.** Is this a surgical module change, or a rewrite that
   throws away tuned, loved behavior?
5. **Build / contract integrity.** Does it keep `build.ps1` green and honor the
   cross-file contracts (`FlightPhysics` API, `GameConfig` table names, Remote
   names)? Any renamed symbol grepped across client/server?
6. **Reward-hacking.** Does it "pass" by weakening a check, hard-coding, or
   reinterpreting Chad's ask rather than solving it?
7. **Verifiability.** Is there a concrete way for Chad to confirm it in Studio, and
   is the playtest checklist crisp (input → expected → knob)?
8. **Ask-vs-guess.** If the change encodes a guess about control feel, it should be
   a question to Chad instead.

## What to do with findings
- **Critical / High** (LOCKED violation, balance blunder, broken contract,
  reward-hack): do not propose the change. Fix it, or if it's a genuine design
  fork, surface it to Chad as a question.
- **Medium / Low**: fix if cheap; otherwise note it in the session log and in the
  playtest checklist so Chad can weigh it.
- Record the red-team verdict in the session log (SCORE step) so the decision is
  auditable.
