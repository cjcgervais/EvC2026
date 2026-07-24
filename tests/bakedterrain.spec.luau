--!nonstrict
--[[
	tests/bakedterrain.spec.luau — Tier-4 gate on the terrain-bake artifact + its consumers.

	The bake pipeline (tools/Bake-World.ps1 -> tools/Extract-Terrain.luau) can't run headlessly (only
	real Studio can produce SmoothGrid), but everything downstream of the produced .rbxm CAN be gated
	here, same spirit as worldgen.spec's pure-plan gates:
	  1. assets/BakedTerrain.rbxm (committed — either a real bake or the unbaked placeholder that ships
	     so a fresh clone's `rojo build` never fails on a missing $path) deserializes with Lune's own
	     @lune/roblox and contains exactly one Terrain instance — the spike's proven round-trip,
	     re-verified on every CI/verify run instead of trusted once and forgotten.
	  2. default.project.json wires assets/BakedTerrain.rbxm into Workspace.Terrain via $path (rojo
	     7.6.1 has no $optional — confirmed empirically: an unknown $optional field fails project
	     parsing outright — so the placeholder-file strategy is load-bearing, not decorative).
	  3. Source gates on the runtime skip: WorldGen.build accepts an opts table and gates
	     terrain:Clear()+sculpt() behind opts.skipSculpt, and GameServer checks the Terrain's
	     BakedByWorldGen attribute before deciding skipSculpt — so a baked Terrain is never re-sculpted
	     at boot, and an unbaked (placeholder) Terrain still gets the normal live sculpt.
]]

local H = require("./_harness")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local RBXM_PATH = "assets/BakedTerrain.rbxm"

H.test("assets/BakedTerrain.rbxm exists and is non-empty", function()
	H.ok(fs.isFile(RBXM_PATH), RBXM_PATH .. " is missing — a fresh clone's rojo build would fail on the $path")
	local bytes = fs.readFile(RBXM_PATH)
	H.ok(#bytes > 0, RBXM_PATH .. " is empty")
end)

H.test("assets/BakedTerrain.rbxm deserializes (Lune @lune/roblox) and contains a Terrain instance", function()
	local bytes = fs.readFile(RBXM_PATH)
	local ok, models = pcall(roblox.deserializeModel, bytes)
	H.ok(ok, "roblox.deserializeModel failed on " .. RBXM_PATH .. ": " .. tostring(models))
	H.eq(#models, 1, "expected exactly one root instance in " .. RBXM_PATH)
	H.eq(models[1].ClassName, "Terrain", "root instance is not a Terrain")
end)

H.test("source-gate: default.project.json $path-maps assets/BakedTerrain.rbxm into Workspace.Terrain", function()
	local proj = fs.readFile("default.project.json")
	local wsStart = proj:find('"Workspace"%s*:%s*{')
	H.ok(wsStart ~= nil, "expected a Workspace block in default.project.json")
	-- Scope the search to a generous window after "Workspace" so we don't accidentally match some
	-- unrelated Terrain-named key elsewhere in the tree.
	local window = proj:sub(wsStart, wsStart + 800)
	H.ok(window:find('"Terrain"') ~= nil, "Workspace block has no Terrain key")
	H.ok(window:find('"%$path"%s*:%s*"assets/BakedTerrain%.rbxm"') ~= nil,
		"Workspace.Terrain must $path-map assets/BakedTerrain.rbxm")
end)

H.test("source-gate: .gitignore does not blanket-exclude the committed bake artifact", function()
	local ig = fs.readFile(".gitignore")
	H.ok(ig:find("!assets/BakedTerrain.rbxm", 1, true) ~= nil,
		".gitignore's *.rbxm rule must carry a negation for assets/BakedTerrain.rbxm, or a fresh clone " ..
		"never gets the committed artifact")
end)

H.test("source-gate: WorldGen.build takes an opts table and gates sculpt behind opts.skipSculpt", function()
	local src = fs.readFile("src/shared/WorldGen.luau")
	H.ok(src:find("function WorldGen%.build%(target,%s*cfg,%s*opts%)") ~= nil,
		"WorldGen.build must accept a third opts parameter for the bake pipeline's skipSculpt")
	H.ok(src:find("opts%.skipSculpt") ~= nil,
		"WorldGen.build no longer reads opts.skipSculpt — a baked Terrain would be re-sculpted every boot")
end)

H.test("source-gate: GameServer checks the Terrain's BakedByWorldGen attribute before skipping sculpt", function()
	local src = fs.readFile("src/server/GameServer.server.luau")
	H.ok(src:find('GetAttribute%("BakedByWorldGen"%)') ~= nil,
		"GameServer must read Terrain:GetAttribute(\"BakedByWorldGen\") to decide skipSculpt")
	H.ok(src:find("skipSculpt%s*=%s*baked") ~= nil,
		"GameServer no longer passes { skipSculpt = baked } into WorldGen.build")
end)

H.test("source-gate: tools/Extract-Terrain.luau stamps the BakedByWorldGen marker before serializing", function()
	local src = fs.readFile("tools/Extract-Terrain.luau")
	H.ok(src:find('SetAttribute%("BakedByWorldGen"') ~= nil,
		"Extract-Terrain.luau no longer stamps BakedByWorldGen — GameServer could never detect a real bake")
	H.ok(src:find("roblox%.serializeModel") ~= nil,
		"Extract-Terrain.luau no longer serializes the Terrain out to the .rbxm")
end)
