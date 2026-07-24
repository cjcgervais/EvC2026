--!nonstrict
--[[
	tests/meshtemplates.spec.luau — Tier-4 gate on the committed mesh-template artifact + its wiring.

	Twin of tests/bakedterrain.spec.luau, same reasoning applied to VISUAL-QUALITY-BAR.md sec 1.5's
	committed-mesh path: the actual extraction (tools/Extract-Meshes.ps1 -> tools/Extract-Meshes.luau)
	can't run headlessly (InsertService:CreateMeshPartAsync only works in real Studio with network
	access), but everything downstream of the produced .rbxm CAN be gated here:
	  1. assets/MeshTemplates.rbxm (committed -- either a real extraction or the unbaked placeholder
	     Folder that ships so a fresh clone's `rojo build` never fails on a missing $path) deserializes
	     with Lune's own @lune/roblox and contains exactly one root Folder instance.
	  2. default.project.json wires assets/MeshTemplates.rbxm into ReplicatedStorage.MeshTemplates via
	     $path (rojo 7.6.1 has no $optional -- confirmed empirically by the BakedTerrain precedent --
	     so the placeholder-file strategy is load-bearing here too).
	  3. .gitignore carries the targeted negation past the blanket *.rbxm rule.
	  4. Source gates on MeshFactory's template-first resolution: getTemplate must check
	     ReplicatedStorage.MeshTemplates before falling back to InsertService:CreateMeshPartAsync, and
	     prewarm must short-circuit committed ids to instant successes rather than spawning a task.
]]

local H = require("./_harness")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local RBXM_PATH = "assets/MeshTemplates.rbxm"

H.test("assets/MeshTemplates.rbxm exists and is non-empty", function()
	H.ok(fs.isFile(RBXM_PATH), RBXM_PATH .. " is missing — a fresh clone's rojo build would fail on the $path")
	local bytes = fs.readFile(RBXM_PATH)
	H.ok(#bytes > 0, RBXM_PATH .. " is empty")
end)

H.test("assets/MeshTemplates.rbxm deserializes (Lune @lune/roblox) and contains a Folder instance", function()
	local bytes = fs.readFile(RBXM_PATH)
	local ok, models = pcall(roblox.deserializeModel, bytes)
	H.ok(ok, "roblox.deserializeModel failed on " .. RBXM_PATH .. ": " .. tostring(models))
	H.eq(#models, 1, "expected exactly one root instance in " .. RBXM_PATH)
	H.eq(models[1].ClassName, "Folder", "root instance is not a Folder")
end)

H.test("source-gate: default.project.json $path-maps assets/MeshTemplates.rbxm into ReplicatedStorage.MeshTemplates", function()
	local proj = fs.readFile("default.project.json")
	local rsStart = proj:find('"ReplicatedStorage"%s*:%s*{')
	H.ok(rsStart ~= nil, "expected a ReplicatedStorage block in default.project.json")
	local window = proj:sub(rsStart)
	local mtStart = window:find('"MeshTemplates"')
	H.ok(mtStart ~= nil, "ReplicatedStorage block has no MeshTemplates key")
	local mtWindow = window:sub(mtStart, mtStart + 200)
	H.ok(mtWindow:find('"%$path"%s*:%s*"assets/MeshTemplates%.rbxm"') ~= nil,
		"ReplicatedStorage.MeshTemplates must $path-map assets/MeshTemplates.rbxm")
end)

H.test("source-gate: .gitignore does not blanket-exclude the committed mesh-template artifact", function()
	local ig = fs.readFile(".gitignore")
	H.ok(ig:find("!assets/MeshTemplates.rbxm", 1, true) ~= nil,
		".gitignore's *.rbxm rule must carry a negation for assets/MeshTemplates.rbxm, or a fresh clone " ..
		"never gets the committed artifact")
end)

H.test("source-gate: MeshFactory's getTemplate checks ReplicatedStorage.MeshTemplates before InsertService", function()
	local src = fs.readFile("src/shared/MeshFactory.luau")
	local fnStart = src:find("local function getTemplate%(meshId%)")
	H.ok(fnStart ~= nil, "MeshFactory must define a local getTemplate(meshId) function")
	local body = src:sub(fnStart)
	local committedPos = body:find('FindFirstChild%(meshId%)')
	H.ok(committedPos ~= nil, "getTemplate must look up the committed template by meshId")
	local insertPos = body:find("CreateMeshPartAsync")
	H.ok(insertPos ~= nil, "getTemplate must still call InsertService:CreateMeshPartAsync as a fallback")
	H.ok(committedPos < insertPos,
		"the committed-template lookup must be checked BEFORE the InsertService fallback, not after")
end)

H.test("source-gate: prewarm short-circuits committed ids to instant successes instead of task.spawn", function()
	local src = fs.readFile("src/shared/MeshFactory.luau")
	local prewarmStart = src:find("function MeshFactory%.prewarm")
	H.ok(prewarmStart ~= nil, "MeshFactory.prewarm must exist")
	local prewarmBody = src:sub(prewarmStart)
	H.ok(prewarmBody:find('folder:FindFirstChild%(meshId%)') ~= nil,
		"prewarm must check the committed folder per meshId before deciding to spawn a task")
end)
