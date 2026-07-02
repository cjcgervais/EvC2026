# Memory maintenance + the context-clear handoff

Two disciplines that make this project survive context clears. Both run in CLOSE
(and memory writes can happen mid-session the moment a fact is settled). The goal
Chad stated: *when he clears context, the next agent invoked here has everything it
needs to follow the roadmap and succeed.*

---

## Project memory — the auto-loaded knowledge base

Location: `C:\Users\Chad\.claude\projects\D--EvC2026\memory\`. `MEMORY.md` is the
**index** (its first lines are auto-loaded into every session); each fact lives in
its own `<slug>.md` file, read on demand.

### File format
```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary — used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-slug]].>
```

Types: **user** (who Chad is / preferences), **feedback** (how he wants you to
work — corrections *and* confirmed approaches; always include the why),
**project** (ongoing work/goals/constraints not derivable from code or git),
**reference** (pointers to docs, specs, external resources). Convert relative
dates to absolute.

### The discipline (do this, every session)
1. **After anything is settled** — a design question resolved, a new constraint, a
   confirmed preference, a playtest outcome — capture it. Don't let it evaporate
   when context clears.
2. **Update, don't duplicate.** Check for an existing file that already covers it
   and edit that. Delete memories that turn out to be wrong.
3. **Add/refresh the one-line pointer in `MEMORY.md`** (`- [Title](file.md) —
   hook`). Never put memory *content* in the index; never leave a new file
   unindexed.
4. **Link liberally** with `[[slug]]` — a link to a not-yet-written memory is a
   fine to-do marker.
5. **Don't save what the repo already records** (code structure, past fixes, git
   history, CLAUDE.md). If asked to remember something derivable, save instead the
   *non-obvious* insight about it.
6. **Recalled memories are point-in-time.** If one names a file/field/flag, verify
   it still exists in the live code before acting on it.

### High-value memories to keep current for THIS project
`feedback-locked-control-specs` (the LOCKED discipline), `user-profile` (working
style), `feedback-flight-balance-inseparable` (the central thesis),
`flight-energy-retention-arcade` (signed-off eagle flight state),
`combat-directional-strike` (combat state), `research-crow-mobbing` (the frontier
model), and this skill's own memory (`reference-evc-loop-skill`).

---

## The HANDOFF — the roadmap a cold-started agent reads first

`docs/HANDOFF.md` is the top-of-funnel document. Its **COLD START box** must be
true *right now* at the end of every session. On CLOSE:

1. **Append a new SESSION block** (newest at top of the session list): what
   landed, *why*, build/playtest status (build-green? UNPLAYTESTED? confirmed?),
   commit hashes, and the exact next-agent playtest checklist.
2. **Rewrite the COLD START box** so it reflects reality: where it stands, what's
   signed off vs. the live frontier, the residual bug, and the **prioritized
   frontier queue** (numbered). Move completed items out; promote the next ones.
3. **Update the LOCKED CONTROL SPECS registry** with any new/confirmed CS rows and
   status changes (SPECIFIED → LOCKED when Chad confirms; MUST-FIX when code
   violates a spec). Log playtest results verbatim where his words matter.
4. **Keep the read-order pointer honest** (cold-start box → newest session block →
   CS registry → `CLAUDE.md` → `MEMORY.md`).

---

## The context-clear guarantee (the acceptance test for a clean close)

Before declaring a session closed, run this check:

> *If I cleared context right now and a fresh agent ran `/evc-loop`, would it — from
> HANDOFF + MEMORY + the CS registry alone — know exactly where we are, what is
> LOCKED and must not change, what the next move is, how to verify it, and how to
> reach ground truth (Chad's playtest)?*

If any answer is "not really," fix the docs until they're all "yes." Only then is
the session closed. This is the whole point of the harness: **continuity across
context clears is a deliverable, not an afterthought.**
