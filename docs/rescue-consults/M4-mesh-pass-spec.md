# M4 — MESH PASS SPEC (S50, Fable-designed)

**Chad's directive (S50):** free Roblox creator-store assets, swappable, no dependencies, no manual
steps — one build, one map level, "make the map just work." Fable leads; **Sonnet builds from this
spec**; **Opus verifies**. Commits are automatic (S49). Chad is pinged only when done.

**Architecture proven this session (S50 spikes — do not re-litigate):**
- Anonymous toolbox APIs curate assets (details expose triangles/meshParts/hasScripts/isFree/votes).
- `game:GetObjects("rbxassetid://<id>")` at plugin security (run-in-roblox EDIT mode) loads
  un-acquired free models — this is the extraction path. `InsertService:LoadAsset` is NOT (18/20
  failed auth).
- Runtime mesh instantiation: `InsertService:CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box,
  Enum.RenderFidelity.Automatic)` **works** (probed in-engine), as does
  `AssetService:CreateMeshPartAsync(Content.fromUri(id), {opts})`. Fallback: `Part` + `SpecialMesh`
  (FileMesh, `Scale = targetSize/meshSize`) — settable at runtime, renders part color when untextured.
- All curated mesh IDs are pre-2021 uploads (permanently public — no asset-privacy risk).
- Local `.rbxm` download is a DEAD END (auth). Nothing is committed as binary; meshes stream by ID.

**Raw extraction data (source of truth for the manifest):**
`C:\Users\Chad\AppData\Local\Temp\claude\D--EvC2026\03cdb468-74e6-44e3-ac6d-68aa747dfdbd\scratchpad\extract-final-out.txt`
— lines `[X] OK <assetId> <role> <json>` where json = `{ models = [{rootName, parts=[{class, name,
size[3], color[3 0-255], material, offset[3], rot[3 deg], meshId?, textureId?, meshSize[3]?,
transparency, shape?, specialMesh?}]}], skies = [{bk,dn,ft,lf,rt,up,sun,sunSize}] }`.
Curated set: 3287226226 + 12549617200 (tree_leafy) · 5616880673 + 12605122162 (tree_pine) ·
2128776869 (rock_pack, 10 rocks) · 9682467046 (nature_pack, 26 meshParts across named roots) ·
5186800496 (sky) · 627302570 (sky_backup). Creators, for provenance comments: akbarbinta,
Remadex Development, smartycar23, MichaelAngelist, FracturedSkies, Proudism, DotDDotexe, TracyCyanne.

---

## Packet M4-A (Sonnet): manifest + extractor tooling

1. **`tools/asset-extract/extract-S50.jsonl`** — copy the raw `[X]` lines from the scratchpad file
   verbatim (committed provenance; the manifest is regenerable from it).
2. **`tools/asset-extract/extract-assets.luau`** — the final extractor script (copy from scratchpad
   `extract-final.luau`), with the candidate ID list clearly at the top = the SWAP POINT.
3. **`tools/Extract-Assets.ps1`** — wraps run-in-roblox exactly like `tools/Smoke-Boot.ps1` (same
   bootstrap + time-box + stdout capture patterns), writes `tools/asset-extract/extract-latest.jsonl`.
   Workflow documented in a header comment: edit ID list → run → regenerate manifest.
4. **`src/shared/AssetManifest.luau`** — `--!nonstrict` pure data module, hand-generated FROM the
   jsonl (this packet does the transform once; keep it faithful — colors as {r,g,b} 0-255 ints,
   numbers rounded to ≤3 decimals). Shape:

```lua
return {
	meta = { extracted = "2026-07-22", session = "S50",
		source = "Roblox creator store, free assets; see tools/asset-extract/" },
	skybox = { bk="rbxassetid://...", dn=..., ft=..., lf=..., rt=..., up=...,
		sun=..., sunSize=21, sourceAssetId=5186800496, creator="DotDDotexe" },
	skyboxBackup = { ... , sourceAssetId=627302570, creator="TracyCyanne" },
	props = {
		treeLeafy = { <variant>, <variant> },   -- one variant per source model
		treePine  = { <variant>, <variant> },
		rock      = { ... },   -- every rock from the rock_pack as its own variant
		-- nature_pack roots: classify each root by rootName keywords into
		-- treeLeafy/treePine/rock/bush/stump/flower/grass/log (add prop roles as found;
		-- unclassifiable roots go under `misc` and are simply unused).
	},
}
-- variant = { sourceAssetId=, creator=, rootName=, height=<bounding Y extent of all parts>,
--             parts = { {meshId=, textureId=, meshSize={x,y,z}, size={x,y,z}, color={r,g,b},
--                        material="Plastic", offset={x,y,z}, rot={x,y,z}} } }
```

5. **`tests/assetmanifest.spec.luau`** (Tier-4): every prop variant has ≥1 part; every part meshId
   matches `^rbxassetid://%d+$`; meshSize components > 0; size components > 0; colors are 0-255 ints;
   offsets/rots finite; height in [2, 200]; skybox has 6 nonempty textures; ≥2 treeLeafy, ≥2
   treePine, ≥6 rock variants exist. Run `.\verify.ps1` green before finishing.

## Packet M4-B (Sonnet): runtime mesh layer

Config: new `GameConfig.Map` flags, each default **true**, each a one-word kill switch:
`meshTrees`, `meshScatter`, `meshSky`.

1. **`src/shared/MeshFactory.luau`** (shared, `--!nonstrict`):
   - `MeshFactory.plan(variant, targetHeight)` — PURE (lune-testable): returns per-part build specs
     {scale, scaledSize, scaledOffset, rot, color, material, meshId, textureId} where
     `scale = targetHeight / variant.height` (uniform). No Instances.
   - `MeshFactory.build(variant, cf, targetHeight, parent)` — applier. Template cache per unique
     meshId: pcall `InsertService:CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box,
     Enum.RenderFidelity.Automatic)`; on failure → `Part` + `SpecialMesh` (MeshType FileMesh,
     MeshId, `Scale = scaledSize / meshSize`). Clone template per part, apply Size (MeshPart
     resize is legal post-CMPA), Color, Material, CFrame = cf * offset * rot.
     **Every part: Anchored=true, CanCollide=false, CanQuery=false, CanTouch=false,
     CastShadow=false** (ghost forest is LOCKED — Chad's `treeCollision="off"` decision; CastShadow
     off is the perf budget). Wrap parts in a Model named after the role.
   - The CMPA-vs-fallback decision is cached PER MESH ID so a dead id costs one pcall per boot.
2. **Tree visual swap** (`RescueServer.server.luau`, behind `Map.meshTrees`):
   - In the tree builder (~:160-190 `plantTree`): keep EVERY existing part (trunk + Canopy blobs)
     with identical names/sizes/positions/queryable registration — set their `Transparency = 1`
     (and trunk too). THE CONTRACT PARTS STAY: `CanopyCount`, canopyQ, `RescueRules.canopyRadius`,
     B4.2 scoring, perch placement all read the invisible geometry unchanged.
   - Then `MeshFactory.build` one tree visual at the trunk base: variant = deterministic pick from
     treeLeafy++treePine (use the round rng already in scope; groves lean leafy, backdrop mixes in
     pines), targetHeight = the OLD tree's total visual height (crown top − base) so squirrel
     perches sit in the mesh crown, ±nothing — same height, same spot.
   - Flag off → Transparency stays 0 and no mesh spawns (legacy look intact — honesty rule).
3. **Decorative scatter** (behind `Map.meshScatter`): rocks along the rim base ring + near the
   river/lake shores, bushes+flowers+stumps sprinkled over the meadow annulus. Positions computed
   in a PURE function (new `WorldGen.scatterPlan(cfg, seed)` following WorldGen's plan/build split —
   lune-testable): deterministic seed, y from `heightAt`, exclusion zones = delivery pad approach,
   spawn core, river/lake/sea water, groves handled by trees already. Budget: ≤ 140 total scatter
   models, each 1-3 parts. Applier goes in `WorldGen.build` next to existing steps (respect the
   `task.wait()` every-24-ops yield rule — S49 landmine).
4. **Skybox** (behind `Map.meshSky`): in WorldGen's lighting apply step, build a `Sky` in Lighting
   from `AssetManifest.skybox` (six textures + sun), replacing any existing Sky. Keep the existing
   Atmosphere/CC/Bloom rig — the skybox joins the golden-hour rig, doesn't replace it.
5. **Tests** (Tier-4): MeshFactory.plan scale math + structure (variant with meshSize≠size scales
   correctly; height 0 guarded); scatterPlan bounds (all points inside valleyRadius, none in
   exclusion zones, y == heightAt sample, count ≤ budget, deterministic for fixed seed); source-gate
   (grep-style, like the catch-floor gate in `tests/worldgen.spec.luau`): plantTree still creates
   parts named "Canopy" and `meshTrees` path sets Transparency=1 rather than deleting.
   Run `.\verify.ps1` green.

## Packet M4-V (Opus): red-team + verify

- Red-team M4-A + M4-B against the SOPs: LOCKED specs untouched (no kernel/camera/aim/controls
  files), Canopy contract intact (CanopyCount equal flag on/off — assert via the existing worldgen/
  models specs plus a new count test if missing), P3 intact (no new lethal geometry; scatter parts
  CanCollide=false so BirdCollision never sees them), one-word kill switches real (flag off = no
  mesh instances — source-verify), perf budget (count total new anchored parts; CastShadow=false
  everywhere; no per-frame work added), PowerShell-corruption check (`git diff` for mojibake — S46
  SOP).
- Full ladder `.\verify.ps1` + `tools\Smoke-Boot.ps1` (extend `tests/smoke/boot.smoke.luau` to
  assert: AssetManifest loads; MeshFactory.plan returns sane specs; a real
  `CreateMeshPartAsync` succeeds in-engine for the first manifest meshId — pcall, report which path).
- Honesty report: LOGIC verified (tests) / APPEARANCE verified (smoke built meshes in-engine; no
  screenshot — M2 capture is unreliable) / FEEL unverified (Chad's flight).

## Sequencing

M4-A → M4-B → M4-V → fix anything Opus finds (Sonnet) → build place → smoke → auto-commit each
packet → Fable ping to Chad. No Chad checkpoints anywhere in the middle.
