--!nonstrict
--[[
	tools/Extract-Terrain.luau — the bake pipeline's Lune extraction step.

	Takes a .rbxlx/.rbxl SAVED BY REAL STUDIO after WorldGen.build sculpted it (Bake-World.ps1's
	Ctrl+S-to-temp-file step), pulls out Workspace.Terrain (the ONLY thing a bake exists to capture —
	SmoothGrid voxel data can only be produced by real Studio's Fill* calls, never headlessly), stamps
	it BakedByWorldGen=true so GameServer can recognize a baked Terrain at boot and skip re-sculpting,
	and serializes just that one instance to assets/BakedTerrain.rbxm — the artifact
	default.project.json $path-maps into Workspace.Terrain at rojo-build time.

	Proven headlessly (spike + this build):
	  - roblox.deserializePlace(bytes) reads a .rbxlx (XML place) file fine, not just binary .rbxl.
	  - Instance:SetAttribute / :GetAttribute round-trip through roblox.serializeModel/deserializeModel
	    (attributes are just a serialized BinaryString property — AttributesSerialize).
	  - SmoothGrid bytes round-trip as opaque binary state on the Terrain instance across
	    serialize/deserialize — Lune never has to understand voxel data, just carry it.

	USAGE:  lune run tools/Extract-Terrain.luau <sourcePlacePath> <outputRbxmPath>
	  <sourcePlacePath>  path to the Studio-saved .rbxlx/.rbxl (Bake-World.ps1 passes its scratch copy)
	  <outputRbxmPath>   defaults to assets/BakedTerrain.rbxm if omitted

	Exit codes: 0 = wrote the rbxm.  1 = source place / Terrain missing, or any step errored.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local function fail(msg)
	print("[ExtractTerrain] FAIL: " .. msg)
	process.exit(1)
end

local sourcePath = process.args[1]
local outputPath = process.args[2] or "assets/BakedTerrain.rbxm"

if not sourcePath or sourcePath == "" then
	fail("usage: lune run tools/Extract-Terrain.luau <sourcePlacePath> [outputRbxmPath]")
end
if not fs.isFile(sourcePath) then
	fail("source place not found: " .. tostring(sourcePath))
end

local okRead, placeBytes = pcall(fs.readFile, sourcePath)
if not okRead then
	fail("could not read source place " .. sourcePath .. ": " .. tostring(placeBytes))
end

local okDeser, dataModelOrErr = pcall(roblox.deserializePlace, placeBytes)
if not okDeser then
	fail("deserializePlace failed on " .. sourcePath .. ": " .. tostring(dataModelOrErr))
end
local dataModel = dataModelOrErr

local okWs, workspaceOrErr = pcall(function()
	return dataModel.Workspace or dataModel:FindFirstChildOfClass("Workspace")
end)
if not okWs or not workspaceOrErr then
	fail("deserialized place has no Workspace")
end
local workspaceInst = workspaceOrErr

local terrain = workspaceInst:FindFirstChildOfClass("Terrain")
if not terrain then
	fail("Workspace.Terrain not found in " .. sourcePath .. " — did WorldGen.build run before the save?")
end

-- Stamp the bake marker. Attributes are the primary mechanism (proven to round-trip); if a future
-- Lune/Roblox combo ever can't set one, fall back to a child StringValue with the same name so the
-- marker still survives serialize -> GameServer's GetAttribute check would just need a matching
-- fallback (not needed today — SetAttribute is proven working, see the doc comment above).
local okAttr = pcall(function()
	terrain:SetAttribute("BakedByWorldGen", true)
end)
if not okAttr then
	local marker = roblox.Instance.new("StringValue")
	marker.Name = "BakedByWorldGen"
	marker.Value = "true"
	marker.Parent = terrain
	print("[ExtractTerrain] WARN: SetAttribute unavailable, used a StringValue marker child instead")
end

local okSer, serializedOrErr = pcall(roblox.serializeModel, { terrain })
if not okSer then
	fail("serializeModel(Terrain) failed: " .. tostring(serializedOrErr))
end

-- Ensure the output directory exists (assets/ ships committed, but be defensive for a fresh path).
local outDir = outputPath:match("^(.*)[/\\][^/\\]+$")
if outDir and not fs.isDir(outDir) then
	local okDir = pcall(fs.writeDir, outDir)
	if not okDir then
		-- writeDir errors if it already exists as a file or on some races; only fatal if still missing.
		if not fs.isDir(outDir) then fail("could not create output dir " .. outDir) end
	end
end

local okWrite, writeErr = pcall(fs.writeFile, outputPath, serializedOrErr)
if not okWrite then
	fail("could not write " .. outputPath .. ": " .. tostring(writeErr))
end

print(string.format("[ExtractTerrain] PASS: wrote %s (%d bytes)", outputPath, #serializedOrErr))
process.exit(0)
