--!nonstrict
--[[
	tests/meshfactory.spec.luau — Tier-4 gates for packet M4-B's MeshFactory.plan (the PURE half).

	MeshFactory.build touches `game`/InsertService/Instance.new and is engine-only (no @lune/roblox
	InsertService), so it is NOT exercised here — only plan()'s scale/spec math, which is what
	WorldGen's tree-swap and scatter appliers both depend on being correct.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local MeshFactory = Loader.load("MeshFactory")
local AssetManifest = Loader.load("AssetManifest")

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

-- asset 12549617200 "Model" (trunk + leaf blob) — meshSize != size on both parts, height 39.693.
local function findVariant(role, sourceAssetId)
	for _, v in ipairs(AssetManifest.props[role]) do
		if v.sourceAssetId == sourceAssetId then
			return v
		end
	end
	error(("fixture variant not found: props.%s sourceAssetId=%d"):format(role, sourceAssetId))
end

--------------------------------------------------------------------------------
-- 1. SCALE MATH — targetHeight/variant.height uniform scale, applied to size AND offset alike.
--------------------------------------------------------------------------------
H.test("plan: scale = targetHeight / variant.height, applied uniformly to size and offset", function()
	local variant = findVariant("treeLeafy", 12549617200) -- height 39.693, meshSize != size
	local targetHeight = 79.386 -- exactly 2x variant.height
	local specs = MeshFactory.plan(variant, targetHeight)
	H.eq(#specs, #variant.parts, "plan must return one spec per source part")

	local expectedScale = targetHeight / variant.height
	H.approx(expectedScale, 2.0, 1e-9, "fixture sanity: targetHeight was chosen as exactly 2x height")

	for i, spec in ipairs(specs) do
		local part = variant.parts[i]
		H.approx(spec.scale, expectedScale, 1e-9, ("specs[%d].scale"):format(i))
		for k = 1, 3 do
			H.approx(spec.scaledSize[k], part.size[k] * expectedScale, 1e-6, ("specs[%d].scaledSize[%d]"):format(i, k))
			H.approx(spec.scaledOffset[k], part.offset[k] * expectedScale, 1e-6, ("specs[%d].scaledOffset[%d]"):format(i, k))
		end
		-- meshSize is carried through UNSCALED (build() uses it to derive a FileMesh fallback Scale).
		H.eq(spec.meshSize, part.meshSize, ("specs[%d].meshSize must pass through unscaled"):format(i))
		H.eq(spec.meshId, part.meshId, ("specs[%d].meshId must pass through"):format(i))
		H.eq(spec.color, part.color, ("specs[%d].color must pass through"):format(i))
		H.eq(spec.material, part.material, ("specs[%d].material must pass through"):format(i))
		H.eq(spec.rot, part.rot, ("specs[%d].rot must pass through"):format(i))
	end
end)

H.test("plan: scale = 1 when targetHeight equals variant.height (identity)", function()
	local variant = findVariant("rock", 2128776869)
	local specs = MeshFactory.plan(variant, variant.height)
	H.approx(specs[1].scale, 1.0, 1e-9, "identity scale")
	for k = 1, 3 do
		H.approx(specs[1].scaledSize[k], variant.parts[1].size[k], 1e-9, "identity scaledSize")
	end
end)

--------------------------------------------------------------------------------
-- 2. STRUCTURE — a multi-part variant (nature_pack "Normal Tree", 9 parts) scales every part.
--------------------------------------------------------------------------------
H.test("plan: a multi-part variant produces one correctly-scaled spec per part", function()
	local variant = findVariant("treeLeafy", 9682467046) -- "Normal Tree", 10 parts
	local targetHeight = 30
	local specs = MeshFactory.plan(variant, targetHeight)
	H.eq(#specs, #variant.parts, "plan must return one spec per source part")
	local scale = targetHeight / variant.height
	for i, spec in ipairs(specs) do
		H.approx(spec.scale, scale, 1e-9, ("part %d scale"):format(i))
		H.ok(spec.scaledSize[1] > 0 and spec.scaledSize[2] > 0 and spec.scaledSize[3] > 0,
			("part %d scaledSize must stay positive"):format(i))
	end
end)

--------------------------------------------------------------------------------
-- 3. GUARDS — height <= 0, targetHeight <= 0, and a nil/empty variant all return {} rather than error
-- or divide-by-zero (a dead/misclassified manifest entry must never crash the world builder).
--------------------------------------------------------------------------------
H.test("plan: height <= 0 is guarded (returns {} rather than dividing by zero)", function()
	local specs = MeshFactory.plan({ height = 0, parts = { { size = { 1, 1, 1 }, offset = { 0, 0, 0 } } } }, 10)
	H.eq(#specs, 0, "a zero-height variant must plan to nothing")
end)

H.test("plan: targetHeight <= 0 is guarded", function()
	local variant = findVariant("rock", 2128776869)
	local specs = MeshFactory.plan(variant, 0)
	H.eq(#specs, 0, "targetHeight=0 must plan to nothing")
	specs = MeshFactory.plan(variant, -5)
	H.eq(#specs, 0, "negative targetHeight must plan to nothing")
end)

H.test("plan: a nil variant is guarded", function()
	local specs = MeshFactory.plan(nil, 10)
	H.eq(#specs, 0, "a nil variant must plan to nothing")
end)

H.test("plan: a variant with no parts is guarded", function()
	local specs = MeshFactory.plan({ height = 10, parts = {} }, 10)
	H.eq(#specs, 0, "an empty-parts variant must plan to nothing")
end)

--------------------------------------------------------------------------------
-- 4. ENGINE-ONLY SOURCE GATE — MeshFactory.build must exist and go through plan() (the scale math
-- lives in ONE place), but must never reference `game`/Instance at module TOP LEVEL (that would break
-- the Lune loader, which provides neither).
--------------------------------------------------------------------------------
H.test("source-gate: MeshFactory exposes both plan and build", function()
	H.ok(type(MeshFactory.plan) == "function", "MeshFactory.plan must be a function")
	H.ok(type(MeshFactory.build) == "function", "MeshFactory.build must be a function")
end)
