# Profile: OpenSCAD / parametric 3D printing

> Iterate on a parametric CAD model toward a printable, dimensionally-correct part.

## When to use this profile
Designing or refining an OpenSCAD model; tuning parameters for fit, strength,
printability, or material/time efficiency.

## Default architecture
**Iterative refinement** with a **visual + geometric** verify step. Escalate to
**tree-of-thoughts** for genuine design-direction choices (which mechanism/shape),
and **orchestrator-worker** to sweep a parameter grid in parallel.

## Ground truth (SOP-3)
- **Primary check (rules-based):** model compiles headless without errors/warnings
  — `openscad -o out.stl model.scad` (exit 0); optionally export `--export-format`
  and check the STL is manifold/non-empty.
- **Geometric check:** assert key dimensions via parameterized echo/asserts in the
  `.scad` (OpenSCAD `assert()`), or measure the exported mesh's bounding box.
- **Visual:** render a PNG (`openscad --render -o preview.png --camera=...`) and
  diff against intent for shape/feature correctness.
- **Printability (if sliced):** slice headless (e.g. PrusaSlicer/Cura CLI) and read
  back print time, filament use, support volume, min feature/wall thickness.
- **Typical metrics:** dimensional error (mm) ↓, wall thickness ≥ nozzle-derived
  min, print time ↓, filament grams ↓, overhang/support volume ↓.

## Default budget (SOP-2)
- max_iterations: 6
- no_improvement_streak: 2
- cost/time ceiling: n/a (local; cheap) — cap iterations instead

## Reflection mode (SOP-6)
**last_attempt** — geometry feedback is usually direct; full Reflexion rarely needed.

## Domain guardrails
- Keep all real dimensions as named parameters at the top; never hard-code magic
  numbers mid-model (so the loop tunes parameters, not scattered literals).
- Respect printer constraints (nozzle diameter, bed size, min wall, max overhang
  angle) — encode them as parameters and as `assert()`s so violations fail verify.
- Don't relax a dimensional `assert()` to pass (SOP-7) — that defeats the part.

## Success-criteria starters
- "Compiles to a manifold STL with no warnings."
- "Critical dimension <X> = <value> mm ± <tol>; verified by assert/measurement."
- "Min wall thickness ≥ <2× nozzle>; no unsupported overhang > <angle>."
- "Slices in < <T> min using < <G> g filament."

## Notes / tools
- CLI: `openscad` (headless render/export, `--camera`, `-D var=val` to override
  params), slicer CLI for print stats. On Windows use the full path to
  `openscad.exe` if not on PATH.
- Drive parameter sweeps by passing `-D` overrides per worker (orchestrator-worker).
