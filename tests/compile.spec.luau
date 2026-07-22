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

--------------------------------------------------------------------------------
-- S45c SCENERY COST GATE — a source-text gate, in the S44 ping-law tradition.
--
-- "Everything renders in so slow" was MEASURED to be quality-scaled render distance: the boot probe
-- showed every part on the client at t=1s with counts that never climb, and setting Graphics →
-- Manual → max made it vanish. Roblox throttles draw distance to protect the frame budget, so the
-- fix is to stop spending it. The two convicted items are one line each — and one line is exactly
-- what a future edit deletes without noticing, because nothing about the game LOOKS different when
-- 78 shadow casters come back. This gate makes that regression cost a red test instead of a session.
--------------------------------------------------------------------------------

-- Strip `--` comment lines. Without this the gates below match their own explanatory prose instead of
-- the code: the first version of the CastShadow gate PASSED against a mutant that had deleted the
-- assignment, because the comment above it says "CastShadow" four times. A gate that reads comments
-- is not a gate.
local function codeOnly(s)
	local out = {}
	for line in (s .. "\n"):gmatch("(.-)\n") do
		if not line:match("^%s*%-%-") then out[#out + 1] = line end
	end
	return table.concat(out, "\n")
end

H.test("scenery cost: Map's addPart must clear CastShadow", function()
	local src = fs.readFile("src/server/GameServer.server.luau")
	local addPart = src:match("local function addPart%(props%).-\n\tend")
	H.ok(addPart ~= nil, "could not find addPart in GameServer — this gate has gone vacuous, fix the pattern")
	H.ok(codeOnly(addPart):find("CastShadow%s*=%s*false") ~= nil,
		"addPart no longer touches CastShadow. Every Map part then casts a shadow again — including a " ..
		"16,000-stud baseplate and 45 mountains up to 3,400 tall — which is the measured cause of " ..
		"Automatic graphics throttling the render distance. RescueServer's builder always sets " ..
		"CastShadow=false; Map must match.")
end)

H.test("scenery cost: the Sea is not unconditionally Glass-with-Reflectance", function()
	local src = fs.readFile("src/server/GameServer.server.luau")
	local sea = codeOnly(src:match('Name = "Sea".-%}%)') or "")
	H.ok(sea ~= "", "could not find the Sea part in GameServer — this gate has gone vacuous")
	-- It may still MENTION Glass (the cheapScenery=false revert path keeps it); what it must not do is
	-- hand the GPU 108 million square studs of transparent reflective surface with no way out.
	if sea:find("Glass") then
		H.ok(sea:find("cheapScenery") ~= nil,
			"the Sea is Glass with no cheapScenery gate. It is 6,000 x 18,000 studs of transparent, " ..
			"reflective surface across the whole horizon — one of the most expensive things the GPU " ..
			"draws here, and it reads identically as SmoothPlastic from 11,000 studs away.")
	end
end)
