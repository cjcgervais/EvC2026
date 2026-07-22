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

--------------------------------------------------------------------------------
-- S45 REGISTER HEADROOM — an EARLY warning, not a post-mortem.
--
-- The tests above fail when a file is ALREADY bricked. That is too late: S44 discovered the 200-local
-- cap by shipping a client that would not run, and an S45 audit then measured BirdController's
-- top-level chunk at 199/200 — ONE free register. The cap applies to the module CHUNK, and every
-- column-0 `local` counts, INCLUDING every `local function`; none ever goes out of scope.
--
-- This gate binary-searches the real headroom by appending dummy locals and compiling at Studio's
-- exact settings, then fails while there is still room to think. Hitting it is not a bug — it is the
-- signal to pay for the space first (group locals into a table, or extract a module, as S45 did).
--------------------------------------------------------------------------------

local HEADROOM_FLOOR = 8   -- fail here, ~8 locals BEFORE the client would refuse to run.

local function headroomOf(path)
	local src = fs.readFile(path)
	local function fits(n)
		local pad = table.create(n)
		for i = 1, n do pad[i] = ("local __pad%d = %d"):format(i, i) end
		return (pcall(function()
			luau.compile(src .. "\n" .. table.concat(pad, "\n"), { optimizationLevel = 1, debugLevel = 2 })
		end))
	end
	if fits(256) then return 256 end
	local lo, hi = 0, 256
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if fits(mid) then lo = mid else hi = mid - 1 end
	end
	return lo
end

H.test("register headroom: BirdController can still take a new module-local", function()
	local path = "src/client/BirdController.client.luau"
	local room = headroomOf(path)
	print(("      [registers] %s: %d module-locals of headroom left"):format(path, room))
	H.ok(room >= HEADROOM_FLOOR, ((
		"BirdController has only %d module-locals of headroom (floor %d). This file is the one that " ..
		"BRICKED the client in S44. Do NOT squeeze past this — pay for the space first: group related " ..
		"locals into one table (S45 did this for RIDER/FEATHER/RETICLE/music/scan, +18), or extract a " ..
		"module (the costed ladder is in docs/HANDOFF.md: RescueAudio ≈ +25, RescuePresentation ≈ +55). " ..
		"⚠️ Extracting the audio band MUST carry the ping-law source gate with it or that gate goes vacuous."
	):format(room, HEADROOM_FLOOR)))
end)

--------------------------------------------------------------------------------
-- S45 ROJO MAPPING GATE — a module that compiles but was never MAPPED is a silent brick.
--
-- default.project.json maps every shared module INDIVIDUALLY (not the folder). So adding
-- `src/shared/Foo.luau` and requiring it does NOT put Foo in ReplicatedStorage: the require's
-- `WaitForChild("Foo")` blocks FOREVER, and the whole script dies quietly at startup with no error —
-- the exact "dead-but-quiet" class that left the rescue layer frozen with zero console evidence in
-- S44. Nothing caught it: the module compiles, luau-lsp only emits its usual "Unknown require" noise,
-- and `rojo build` succeeds because the file simply isn't referenced. This gate closes that hole.
--------------------------------------------------------------------------------

H.test("rojo mapping: every ReplicatedStorage module required by src/ is mapped in the project file", function()
	local project = fs.readFile("default.project.json")
	local missing, checked = {}, 0
	for _, path in ipairs(listLuau()) do
		local src = fs.readFile(path)
		for name in src:gmatch('require%b()') do
			local mod = name:match('ReplicatedStorage:WaitForChild%("([%w_]+)"%)')
			if mod then
				checked += 1
				-- The mapping is what puts it in ReplicatedStorage at runtime; match the PATH so a
				-- renamed key with a stale path can't pass.
				if not project:find('src/shared/' .. mod .. '%.luau') then
					missing[#missing + 1] = ("%s requires %s, which default.project.json does not map")
						:format(path, mod)
				end
			end
		end
	end
	H.ok(checked > 0, "the scanner found no ReplicatedStorage requires at all — it has gone vacuous")
	H.eq(#missing, 0, "UNMAPPED MODULE(S) — WaitForChild would hang forever and silently brick the " ..
		"script:\n  " .. table.concat(missing, "\n  "))
end)
