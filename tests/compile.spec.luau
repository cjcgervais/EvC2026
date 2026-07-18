--!nonstrict
--[[
	tests/compile.spec.luau — the Tier-4 COMPILE gate.

	luau.load COMPILES a source to bytecode (register allocation included) WITHOUT running it, so it
	catches codegen + syntax errors headlessly — crucially "Out of local registers when trying to allocate
	… exceeded limit 200" (>200 locals live in one function). luau-lsp analyze and `rojo build` do NOT catch
	that; it BRICKS the script at load time. S41: packet B3 pushed BirdController's onFlightStep over the cap
	→ the client script failed to compile → the eagle was inert in Play and every RescueState remote dropped.
	No headless tier saw it (Tier-4 never loads the .client/.server scripts; the edit-mode smoke never RUNS
	them). This gate compiles EVERY src script — including the big .client/.server ones — so that class of bug
	is caught before Chad ever presses Play. Compilation needs no runtime env (game/workspace/require are
	runtime lookups), so a plain luau.load is enough.
]]

local H = require("./_harness")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local DIRS = { "src/shared", "src/server", "src/client" }

local function listLuau()
	local files = {}
	for _, dir in ipairs(DIRS) do
		for _, entry in ipairs(fs.readDir(dir)) do
			if entry:match("%.luau$") then
				files[#files + 1] = dir .. "/" .. entry
			end
		end
	end
	table.sort(files)
	return files
end

for _, path in ipairs(listLuau()) do
	H.test("compiles (no syntax / register overflow): " .. path, function()
		local src = fs.readFile(path)
		-- Roblox Studio's PLAY mode compiles at optimizationLevel 1 with FULL debug info (debugLevel 2 = every
		-- local kept in its own register for the debugger), so it hits the 200-local cap that lune's default
		-- (optimized, debug 1) packs away. opt1/debug2 reproduces Studio EXACTLY (verified S41: it reproduces
		-- BirdController's real "3209: … acquiring: exceeded limit 200" on the broken B3 build, and passes the
		-- fix) → a >200-local function fails HERE, headlessly, not in Chad's face at Play. (opt0/debug2 is
		-- STRICTER than Studio and would false-alarm; debug2 is the load-bearing bit.)
		local ok, err = pcall(function()
			luau.compile(src, { optimizationLevel = 1, debugLevel = 2 })
		end)
		H.ok(ok, path .. " failed to COMPILE (Studio-debug settings): " .. tostring(err))
	end)
end
