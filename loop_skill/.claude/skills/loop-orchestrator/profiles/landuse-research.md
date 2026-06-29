# Profile: Land-use research

> Iterate on a research question about land use toward a defensible, cited answer.

## When to use this profile
Multi-source research and analysis on land use (zoning, parcels, ecology, policy,
GIS/spatial data) where the deliverable is a verified, cited conclusion or dataset.

## Default architecture
**Orchestrator-worker (fan-out/fan-in)** — decompose the question into angles,
research each in a parallel subagent, synthesize. Pair with an
**evaluator-optimizer** verify step (a critic checks each claim is cited and
sound). This mirrors the `deep-research` skill; reuse it for the search half.

## Ground truth (SOP-3)
- **Primary check (rules-based):** every claim in the output maps to a cited,
  retrievable source; no uncited assertions. For data work: the analysis script
  runs and reproduces the stated numbers; geometries/units validate.
- **Adversarial verification:** a separate critic agent tries to **refute** each
  key claim; a claim survives only if it isn't refuted (mirrors `deep-research`).
- **Typical metrics:** % claims with primary-source citations ↑, # unrefuted key
  claims, # contradictions found ↓, source-quality mix (primary vs. secondary).

## Default budget (SOP-2)
- max_iterations: 5 (rounds of find→verify→synthesize)
- no_improvement_streak: 2 (stop when a round surfaces nothing new — "dry")
- cost/time ceiling: set for unattended runs (web fetch + many subagents add up)

## Reflection mode (SOP-6)
**reflexion** — record which sources/angles were dead ends so later rounds don't repeat them.

## Domain guardrails
- **Cite or cut:** no claim ships without a source the reader can open (SOP-7
  applied to research — don't fabricate citations to "pass" the cite check).
- Prefer **primary sources** (statutes, official parcel/zoning/GIS data, peer-
  reviewed work) over blogs; record source quality.
- Separate **established fact** from **inference**; flag uncertainty explicitly.
- Note data vintage and jurisdiction — land-use rules are local and change.

## Success-criteria starters
- "Question answered with ≥ <N> independent primary sources; 0 uncited key claims."
- "All key claims survive adversarial refutation."
- "Reproducible: analysis re-runs and yields the reported figures."

## Notes / tools
- Reuse the `deep-research` skill for the search/verify fan-out; this profile adds
  the bounded *loop* around it (rounds, dry-stop, reflection) and the cited-output gate.
- For spatial data, keep source files and analysis scripts under `artifacts/` so
  results are reproducible (SOP-9).
