--!nonstrict
--[[
	tools/Extract-Meshes.luau — the mesh-extraction pipeline's Lune extraction step.

	Twin of tools/Extract-Terrain.luau, same reasoning: takes a .rbxlx/.rbxl SAVED BY REAL STUDIO
	after tests/capture/meshes.extract.luau fetched every AssetManifest meshId via
	InsertService:CreateMeshPartAsync (only real Studio can hit that CDN endpoint — @lune/roblox has
	no InsertService, there is no headless generator), pulls out Workspace.MeshTemplates (the Folder
	the injected script built, one child per unique meshId, named by meshId so MeshFactory can look
	templates up by id at runtime), and serializes it to assets/MeshTemplates.rbxm — the artifact
	default.project.json $path-maps into ReplicatedStorage.MeshTemplates at rojo-build time.

	USAGE:  lune run tools/Extract-Meshes.luau <sourcePlacePath> <outputRbxmPath>
	  <sourcePlacePath>  path to the Studio-saved .rbxlx/.rbxl (Extract-Meshes.ps1 passes its scratch copy)
	  <outputRbxmPath>   defaults to assets/MeshTemplates.rbxm if omitted

	Exit codes: 0 = wrote the rbxm.  1 = source place / MeshTemplates missing, or any step errored.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local function fail(msg)
	print("[ExtractMeshes] FAIL: " .. msg)
	process.exit(1)
end

local sourcePath = process.args[1]
local outputPath = process.args[2] or "assets/MeshTemplates.rbxm"

if not sourcePath or sourcePath == "" then
	fail("usage: lune run tools/Extract-Meshes.luau <sourcePlacePath> [outputRbxmPath]")
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

local templates = workspaceInst:FindFirstChild("MeshTemplates")
if not templates then
	fail("Workspace.MeshTemplates not found in " .. sourcePath .. " — did the extractor script run before the save?")
end

local childCount = #templates:GetChildren()
if childCount == 0 then
	fail("Workspace.MeshTemplates has zero children — extraction produced nothing to bake")
end

local okSer, serializedOrErr = pcall(roblox.serializeModel, { templates })
if not okSer then
	fail("serializeModel(MeshTemplates) failed: " .. tostring(serializedOrErr))
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

print(string.format("[ExtractMeshes] PASS: wrote %s (%d bytes, %d template(s))", outputPath, #serializedOrErr, childCount))
process.exit(0)
