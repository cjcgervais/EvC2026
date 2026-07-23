--!nonstrict
--[[
	tests/assetmanifest.spec.luau — Tier-4 gates for packet M4-A (AssetManifest data pass).

	AssetManifest is pure data (no Instances), so every gate here runs directly against the
	table Loader.load("AssetManifest") returns:
	  1. structure  — every prop variant has >=1 part, and each part's fields are well-formed
	                  (meshId pattern, meshSize/size > 0, 0-255 int colors, finite offset/rot,
	                  height in the [2,200] sanity band).
	  2. skybox     — both skybox and skyboxBackup carry all 6 nonempty face textures.
	  3. coverage   — the curated set actually has enough variants to look non-repetitive:
	                  >=2 treeLeafy, >=2 treePine, >=6 rock.
]]

local H = require("./_harness")
local Loader = require("./_loader")

local AssetManifest = Loader.load("AssetManifest")

local MESH_ID_PATTERN = "^rbxassetid://%d+$"

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function isColorByte(x)
	return type(x) == "number" and x == math.floor(x) and x >= 0 and x <= 255
end

local function checkVec3(t, msg)
	H.ok(type(t) == "table" and #t == 3, msg .. ": expected a {x,y,z} triple")
	for i = 1, 3 do
		H.finite(t[i], msg .. "[" .. i .. "]")
	end
end

local function checkPart(part, ctx)
	H.ok(type(part.meshId) == "string" and part.meshId:match(MESH_ID_PATTERN) ~= nil,
		("%s: meshId %q does not match %s"):format(ctx, tostring(part.meshId), MESH_ID_PATTERN))
	H.ok(type(part.textureId) == "string", ctx .. ": textureId must be a string (possibly empty)")

	checkVec3(part.meshSize, ctx .. ".meshSize")
	for i = 1, 3 do
		H.ok(part.meshSize[i] > 0, ("%s.meshSize[%d]=%s must be > 0"):format(ctx, i, tostring(part.meshSize[i])))
	end

	checkVec3(part.size, ctx .. ".size")
	for i = 1, 3 do
		H.ok(part.size[i] > 0, ("%s.size[%d]=%s must be > 0"):format(ctx, i, tostring(part.size[i])))
	end

	H.ok(type(part.color) == "table" and #part.color == 3, ctx .. ".color: expected a {r,g,b} triple")
	for i, label in ipairs({ "r", "g", "b" }) do
		H.ok(isColorByte(part.color[i]), ("%s.color.%s=%s must be a 0-255 int"):format(ctx, label, tostring(part.color[i])))
	end

	H.ok(type(part.material) == "string" and #part.material > 0, ctx .. ".material must be a nonempty string")

	checkVec3(part.offset, ctx .. ".offset")
	checkVec3(part.rot, ctx .. ".rot")
end

local function checkVariant(variant, ctx)
	H.ok(type(variant.sourceAssetId) == "number", ctx .. ".sourceAssetId must be a number")
	H.ok(type(variant.creator) == "string" and #variant.creator > 0, ctx .. ".creator must be a nonempty string")
	H.ok(type(variant.rootName) == "string" and #variant.rootName > 0, ctx .. ".rootName must be a nonempty string")
	H.between(variant.height, 2, 200, ctx .. ".height")

	H.ok(type(variant.parts) == "table" and #variant.parts >= 1, ctx .. ": every prop variant needs >=1 part")
	for i, part in ipairs(variant.parts) do
		checkPart(part, ("%s.parts[%d]"):format(ctx, i))
	end
end

local function checkSkybox(sky, name)
	for _, face in ipairs({ "bk", "dn", "ft", "lf", "rt", "up" }) do
		H.ok(type(sky[face]) == "string" and #sky[face] > 0, ("%s.%s must be a nonempty texture id"):format(name, face))
	end
	H.ok(type(sky.sun) == "string" and #sky.sun > 0, name .. ".sun must be a nonempty texture id")
	H.ok(type(sky.sunSize) == "number" and sky.sunSize > 0, name .. ".sunSize must be a positive number")
end

--------------------------------------------------------------------------------
-- 1. STRUCTURE — every prop variant across every role is well-formed.
--------------------------------------------------------------------------------
H.test("structure: props table exists and every variant is well-formed", function()
	H.ok(type(AssetManifest.props) == "table", "AssetManifest.props must be a table")
	local sawAny = false
	for role, variants in pairs(AssetManifest.props) do
		H.ok(type(variants) == "table", "props." .. role .. " must be a table of variants")
		for i, variant in ipairs(variants) do
			sawAny = true
			checkVariant(variant, ("props.%s[%d] (%s)"):format(role, i, tostring(variant.rootName)))
		end
	end
	H.ok(sawAny, "AssetManifest.props has no variants at all — the manifest would be vacuous")
end)

--------------------------------------------------------------------------------
-- 2. SKYBOX — both the primary and backup skybox carry all 6 faces + sun.
--------------------------------------------------------------------------------
H.test("skybox: primary skybox has 6 nonempty textures", function()
	H.ok(type(AssetManifest.skybox) == "table", "AssetManifest.skybox must be a table")
	checkSkybox(AssetManifest.skybox, "skybox")
end)

H.test("skybox: backup skybox has 6 nonempty textures", function()
	H.ok(type(AssetManifest.skyboxBackup) == "table", "AssetManifest.skyboxBackup must be a table")
	checkSkybox(AssetManifest.skyboxBackup, "skyboxBackup")
end)

--------------------------------------------------------------------------------
-- 3. COVERAGE — enough variants per role to not look copy-pasted in the world.
--------------------------------------------------------------------------------
H.test("coverage: at least 2 treeLeafy, 2 treePine, and 6 rock variants exist", function()
	local props = AssetManifest.props
	H.ok(type(props.treeLeafy) == "table" and #props.treeLeafy >= 2,
		("props.treeLeafy has %d variant(s), need >= 2"):format(props.treeLeafy and #props.treeLeafy or 0))
	H.ok(type(props.treePine) == "table" and #props.treePine >= 2,
		("props.treePine has %d variant(s), need >= 2"):format(props.treePine and #props.treePine or 0))
	H.ok(type(props.rock) == "table" and #props.rock >= 6,
		("props.rock has %d variant(s), need >= 6"):format(props.rock and #props.rock or 0))
end)
