# FX / Animation APPROACH-VETTING gate (reason away from mediocre solutions)

**Origin (Chad, S41 — the feather churn):** the terrain-crash poof was iterated THREE times — fire
the gate, tune the motion, retune life/drag/gravity — and it was *still* "a brown ball, not a ring of
falling feathers." Build-green passed. A Fable code-audit passed. A headless motion feel-gate passed.
All of them missed the same thing: **a soft round particle puff can NEVER read as discrete falling
feathers** — overlapping soft sprites always blend into a blob. The technique had a structural ceiling
below the goal, and nobody said so *before building*. Chad flew a doomed approach three times.

> Chad: "A puff of color is not feathers… automate a verification before asking me if I would like an
> image and a ring falling. This should not be a question but an SOP so I don't have to test-fly over and
> over… and for other animations as well — it needs to be reasoned away from mediocre solutions."

**The rule:** for any change whose success is a **perceptual read** — particles/FX, animation, procedural
geometry, any "does it *look/feel* like X" — you MUST vet the *technique* against the goal BEFORE building,
reject techniques with a ceiling below the goal, and bring Chad a vetted + headless-gated **working
result — not a menu of approaches, not an untested guess.** This gate runs at PLAN time, before ACT.

## The four steps (all before Chad ever flies)

1. **NAME THE READ — in Chad's words, concretely.** Not "a poof" — "a *ring of falling feathers*." Not
   "juice" — "the wings *flare and the bird recoils*." The concrete noun+verb is the spec you vet against.
   Vague goals are how mediocre techniques slip through.

2. **VET THE TECHNIQUE ADVERSARIALLY — name its failure mode and ceiling.** For each candidate technique
   ask: *"Can this even produce that read? What does it degrade into?"* Kill any technique whose best
   case is below the goal. Enumerate the alternatives and their ceilings; pick the one that CAN reach the
   read; state its cost. Worked example — "discrete falling feathers":
   - Soft round particle sprite → many overlap → **blends to a blob**. Ceiling = a colored puff. ✗ doomed.
   - Squash/rotation on that sprite → still a soft blob, now oval. ✗ same ceiling.
   - Feather-*image* sprite → reads IF the image is good, but an asset id can't be verified headless (bad
     id = invisible). Viable only if Chad supplies/approves the asset. △ gated on an art asset.
   - **Discrete feather PARTS** (thin brown parts that burst in a ring, tumble, flutter down) → discrete
     objects that fall = the read, and "blob" is *structurally impossible*. ✓ reachable + headless-gateable.

   The failure was doing step 2 *after* three flights instead of before the first.

3. **GATE HEADLESSLY — structurally kill the known failure mode, then assert the read you can.** Extract
   the authoring into a pure module + a Lune spec (the [[reference-fx-feel-gate]] / `FeatherFX` pattern).
   Assert everything machine-checkable: discreteness (N distinct parts, not one cloud), shape aspect-ratio
   (a feather is elongated, not round), the fall/spread kinematics (descends + rings outward), persistence
   (lingers). Prefer a technique where the failure mode is *impossible by construction* (discrete parts →
   no blob) over one you can only measure. **Always state the honest residual** that still needs one Studio
   glance (e.g. "does a thin tumbling brown part read as a feather vs a leaf") — but that residual must be
   a *refinement*, never "is the whole approach viable."

4. **PROPOSE, DON'T ASK.** Bring a vetted, gated, working result. Asking Chad "which approach?" is a
   process failure when you could have reasoned to it — *"which of two mediocre options"* is never a valid
   question; reason past both. Only ask when there's a genuine **taste** fork that changes the artifact and
   is not resolvable by reasoning (e.g. "feathers rain silently vs. a soft *fwump* sound") — and even then,
   propose your pick first.

## Anti-pattern (the tombstone)

**Iterating numbers on a technique that can't reach the goal.** If two tuning passes haven't moved the
*read* (not the metric), stop tuning and re-vet the technique — the ceiling is probably the problem, not
the numbers. Three number-passes on a soft-sprite puff was three flights wasted on a doomed approach.

## Where this sits in the loop

PLAN → **(if the change is a perceptual read) APPROACH-VETTING gate: steps 1–2 →** ACT (build the vetted
technique + its pure module) → VERIFY (build + the headless feel/geometry gate, step 3) → only then a
Chad Play that confirms a *refinement*, never the viability of the approach. Pairs with, and runs before,
the RED-TEAM and the [[reference-fx-feel-gate]] headless gate.
