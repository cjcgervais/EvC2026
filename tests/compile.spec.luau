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
-- Also normalises CRLF -> LF. The working tree is CRLF (core.autocrlf=true), so any gate whose
-- pattern anchors on "\n" silently matches nothing against a `)\r\n` line ending — it does not fail
-- loudly, it goes VACUOUS, which is the one failure mode these gates exist to prevent. Stripping \r
-- here fixes the whole class once instead of per-pattern. (S46: cost one red test to find.)
local function codeOnly(s)
	local out = {}
	for line in (s:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
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

--------------------------------------------------------------------------------
-- M1 (Phase V) WORLDGEN WIRING — source gates in the S45c tradition. The pure world data is gated
-- in worldgen.spec, but that suite cannot see the GameServer BRANCH or the build() APPLIER: a
-- WorldGen that plans a perfect valley but is never wired, or whose applier silently drops the
-- birth contract (Gravity / StreamingEnabled), leaves every pure gate green while the game boots
-- broken. codeOnly() strips `--` lines first (the comments below name every symbol these match).
--------------------------------------------------------------------------------

H.test("M1 wiring: GameServer branches on worldV2 and calls WorldGen.build", function()
	local src = codeOnly(fs.readFile("src/server/GameServer.server.luau"))
	H.ok(src:find("GameConfig%.Map.-worldV2") ~= nil or src:find("worldV2") ~= nil,
		"GameServer no longer branches on GameConfig.Map.worldV2 — the kill switch is inert and the " ..
		"new world can never boot (or the legacy path can never be restored).")
	H.ok(src:find("WorldGen%.build") ~= nil,
		"GameServer no longer calls WorldGen.build — the worldV2 branch would build no world at all.")
	-- The legacy branch must survive intact until Gate V (the flag-off path).
	H.ok(src:find("SetupLighting%(%)") ~= nil and src:find("BuildMap%(%)") ~= nil,
		"the legacy SetupLighting()/BuildMap() branch is gone — flag-off would restore nothing.")
end)

H.test("M1 wiring: WorldGen.build reproduces the birth contract and sculpts terrain", function()
	local src = codeOnly(fs.readFile("src/shared/WorldGen.luau"))
	H.ok(src:find("%.Gravity%s*=") ~= nil,
		"WorldGen.build no longer sets Gravity — the flight model's gravity contract (BuildMap:260) is dropped.")
	H.ok(src:find("StreamingEnabled") ~= nil,
		"WorldGen no longer touches StreamingEnabled — the replication contract (BuildMap:267) is dropped.")
	H.ok(src:find("Terrain") ~= nil and src:find(":Clear%(%)") ~= nil,
		"WorldGen.build no longer clears the Terrain — a re-build would stack voxels on the old world.")
	H.ok(src:find(":FillBlock%(") ~= nil,
		"WorldGen.build no longer calls Terrain:FillBlock — the valley/rim/water are never sculpted.")
	-- M1.5: sculpt() is now a dumb interpreter over plan.sculptOps whose materials are STRING keys
	-- mapped through Enum.Material[...]; water is filled by emitting `mat = "Water"` ops (the lake
	-- de-box, the plunge pool, the river). Assert BOTH the interpreter and a Water op survive.
	H.ok(src:find("Enum%.Material%[") ~= nil,
		"WorldGen.sculpt no longer maps Enum.Material[...] — the sculptOps interpreter is gone and nothing is filled.")
	H.ok(src:find('"Water"') ~= nil,
		"WorldGen no longer emits a Water fill op — invariant ② (water bodies) is not built.")
	H.ok(src:find(":FillCylinder%(") ~= nil,
		"WorldGen.sculpt no longer calls Terrain:FillCylinder — the de-boxed lake / plunge pool are never carved.")
	-- P3 void-death guard: the catch slab is the only thing standing between a graze off a solid
	-- edge and the -200 failsafe, and the applier isn't lune-testable — so this source-gate is the
	-- ONLY machine check that the slab exists, spans ±REACHABLE_RADIUS, and sits at CATCH_FLOOR_Y.
	H.ok(src:find("CATCH_FLOOR_Y") ~= nil,
		"WorldGen.sculpt no longer fills a catch slab at CATCH_FLOOR_Y — a graze into a void gap falls " ..
		"past the -200 failsafe and dies unearned (P3 violation).")
	H.ok(src:find("REACHABLE_RADIUS") ~= nil,
		"WorldGen.sculpt's catch slab no longer spans REACHABLE_RADIUS — void gaps outside the grass " ..
		"square/rim are uncovered again.")
end)

--------------------------------------------------------------------------------
-- B4.2 — TREE STYLE SCORING. The pure math is gated in rescuerules.spec, but the pure module cannot
-- see the CLIENT GLUE: deleting the whole feature from BirdController leaves that suite fully green.
-- These are source gates on the glue. They read CODE only (codeOnly strips `--` lines) per the S45c
-- lesson — the first CastShadow gate passed against a mutant because it matched its own comment.
--------------------------------------------------------------------------------

H.test("B4.2 glue: the style meter scores canopies through the PURE helpers, not by hand", function()
	local src = codeOnly(fs.readFile("src/client/BirdController.client.luau"))

	H.ok(src:find("treeStyleScoring") ~= nil,
		"BirdController no longer reads Rescue.treeStyleScoring — the kill switch gates nothing and " ..
		"the whole B4.2 decoupling has been deleted or bypassed.")

	-- The radius MUST come from the pure helper. Inlining Size.X/2 scores a sphere 25% wider than the
	-- drawn canopy (a Ball's radius is half its SMALLEST axis) — an invisible skirt around every tree.
	H.ok(src:find("RescueRules%.canopyRadius") ~= nil,
		"the canopy radius is no longer read via RescueRules.canopyRadius. Any hand-rolled Size.X/2 " ..
		"is wrong for a Ball and is unreachable by the headless gates in rescuerules.spec.")

	-- The SHELL form is the packet. An inline max(0, dist - radius) re-creates the inversion the
	-- red-team blocked: closeness 1.0 through the whole crown interior, so ghost trees pay you for
	-- plowing through them instead of threading them.
	H.ok(src:find("RescueRules%.shellCloseness") ~= nil,
		"the style meter no longer scores via RescueRules.shellCloseness. If this was inlined, the " ..
		"inversion gate in rescuerules.spec is now vacuous — the interior may score maximum again.")

	-- Trees must NOT come back as a collision surface through the scoring door.
	H.ok(src:find("CanQuery%s*=%s*true") == nil,
		"BirdController is setting CanQuery=true. Chad's ghost forest (S45c) is a design decision; " ..
		"style scoring must reach trees by POSITION, never by making them queryable.")
end)

--------------------------------------------------------------------------------
-- S46 CYLINDER AXIS. The pure test in rescuerules.spec proves cylinderSize permutes correctly, which
-- is nearly worthless on its own: the BUG lived entirely in ARGUMENT ORDER at four call sites. These
-- gates read the call sites. codeOnly() strips `--` lines first (S45c: a gate that matches its own
-- explanatory comment is not a gate — and the comments here name every one of these symbols).
--------------------------------------------------------------------------------

H.test("S46: every upright cylinder goes through the ONE helper that knows the axis", function()
	local src = codeOnly(fs.readFile("src/server/RescueServer.server.luau"))

	-- The whole point of uprightCylinder is that Size, Shape and the stand-up rotation are owned
	-- together. If a new cylinder is hand-rolled, the axis can be got wrong again with no gate firing.
	local shapes = select(2, src:gsub("Enum%.PartType%.Cylinder", ""))
	H.eq(shapes, 1, ("RescueServer sets Enum.PartType.Cylinder %d times; it must be exactly 1 (inside " ..
		"uprightCylinder). A hand-rolled cylinder can reintroduce the S46 axis bug undetected — route " ..
		"it through the helper instead."):format(shapes))

	local helper = src:match("local function uprightCylinder.-\nend")
	H.ok(helper ~= nil, "uprightCylinder is gone from RescueServer — this gate has gone vacuous, fix the pattern")
	H.ok(helper:find("math%.rad%(90%)") ~= nil,
		"uprightCylinder no longer applies the stand-up rotation. Sized correctly but left lying on " ..
		"its side is the SAME class of bug, and the helper exists so a caller cannot forget it.")
	H.ok(helper:find("RescueRules%.cylinderSize") ~= nil,
		"uprightCylinder no longer derives its Size from RescueRules.cylinderSize, so the headless " ..
		"axis test in rescuerules.spec no longer describes what the world actually builds.")

	local calls = select(2, src:gsub("uprightCylinder%(", ""))
	H.ok(calls >= 7, ("expected the uprightCylinder definition + at least 6 call sites (%d found). " ..
		"Trunk, Mesa, SafePad, RimPool, UpdraftColumn and FoxFlare all stand up."):format(calls))
end)

H.test("S46: the four fixed sites pass AXIAL FIRST — this is the bug, pinned by literal", function()
	-- Mutation (a) from the red-team: swap the args back at ONE site, e.g. uprightCylinder("Trunk", 7, h,
	-- ...). That reintroduces the exact bug and every pure test stays green. Only a literal check
	-- on argument order catches it.
	local src = codeOnly(fs.readFile("src/server/RescueServer.server.luau"))
	local sites = {
		{ 'uprightCylinder%("Trunk", h, 7,',    "Trunk: h is the HEIGHT (axial), 7 the diameter — swapped, trunks are 7-stud pancakes" },
		{ 'uprightCylinder%("Mesa", R%.deliverPadY / 6 %+ 2, rad,', "Mesa: padY/6+2 is the disc THICKNESS, rad the diameter — swapped, each disc is a ~260-tall blade" },
		{ 'uprightCylinder%("SafePad", 6, 200,', "SafePad: 6 is the THICKNESS, 200 the diameter — swapped, the pad is a 200-tall wall" },
		{ 'uprightCylinder%("RimPool", 4, 120,', "RimPool: 4 is the THICKNESS, 120 the diameter — swapped, the pool is a 120-tall wall" },
	}
	for _, s in ipairs(sites) do
		H.ok(src:find(s[1]) ~= nil, "S46 ARGUMENT ORDER REGRESSED — " .. s[2])
	end

	-- The two sites that were ALWAYS correct must NOT take the legacy path, or the kill switch would
	-- break what was never broken.
	local col = src:match('uprightCylinder%("UpdraftColumn".-%)\n')
	local fox = src:match('uprightCylinder%("FoxFlare".-%)\n')
	H.ok(col and not col:find("legacyAxis"), "UpdraftColumn was always correct — it must not pass legacyAxis()")
	H.ok(fox and not fox:find("legacyAxis"), "FoxFlare was always correct — it must not pass legacyAxis()")
end)

--------------------------------------------------------------------------------
-- M2 (Phase V) CAPTURE HARNESS WIRING — source gates in the S45c tradition. The screenshot
-- harness itself needs Studio + a display, so it is NOT machine-gated here; what IS gated is that
-- the two pieces are actually WIRED — the injected edit-mode script builds the real WorldGen world
-- and signals capture, and the PowerShell orchestrator reads that signal and screenshots. A future
-- edit that guts either half (so the sheet is empty or of the wrong world) fails a red test instead
-- of a session. compile.spec already reads source via @lune/fs, which reaches tools/ + tests/capture/.
--------------------------------------------------------------------------------

H.test("M2 wiring: the edit-mode capture script builds the WorldGen world and signals each shot", function()
	local src = fs.readFile("tests/capture/world.capture.luau")
	H.ok(src:find("WorldGen%.build") ~= nil,
		"world.capture.luau no longer calls WorldGen.build — the sheet would capture no world (or the " ..
		"wrong one). M2 look-devs the WorldGen valley specifically; build() must run in edit mode.")
	H.ok(src:find("M2READY") ~= nil,
		"world.capture.luau no longer prints the M2READY sentinel — Capture-World.ps1 tails stdout for it, " ..
		"so with no sentinel the orchestrator captures nothing (the stdout channel is the ONLY sync path).")
	H.ok(src:find("VANTAGES") ~= nil,
		"world.capture.luau no longer has a VANTAGES table — the 8 committed vantage poses (hardening ③, " ..
		"a reviewable diff) are gone, so no session can be held to a fixed frame set.")
end)

H.test("M2 wiring: Capture-World.ps1 tails the sentinel, launches run-in-roblox, and screenshots", function()
	local ok, ps = pcall(fs.readFile, "tools/Capture-World.ps1")
	H.ok(ok and ps ~= nil, "tools/Capture-World.ps1 is missing — the M2 orchestrator does not exist.")
	H.ok(ps:find("M2READY") ~= nil,
		"Capture-World.ps1 no longer tails the M2READY sentinel — it would never know when to capture.")
	H.ok(ps:find("run%-in%-roblox") ~= nil or ps:find("Bootstrap%-RunInRoblox") ~= nil,
		"Capture-World.ps1 no longer bootstraps/launches run-in-roblox — it can't drive Studio headlessly.")
	H.ok(ps:find("CopyFromScreen") ~= nil,
		"Capture-World.ps1 no longer calls CopyFromScreen — nothing actually grabs the Studio window pixels.")
end)

H.test("B4.2 glue: the index waits for the server's published canopy count", function()
	local src = codeOnly(fs.readFile("src/client/BirdController.client.luau"))
	H.ok(src:find("CanopyCount") ~= nil,
		"the client no longer waits on RescueWorld's CanopyCount attribute. Replication is not " ..
		"atomic, so a build-once index that scans early bakes in a SHORT forest permanently and " ..
		"silently, per client — the invisible failure class S44/S45 burned two sessions on.")
	local server = codeOnly(fs.readFile("src/server/RescueServer.server.luau"))
	H.ok(server:find('SetAttribute%("CanopyCount"') ~= nil,
		"RescueServer no longer publishes CanopyCount, so the client's wait can never be satisfied " ..
		"and tree style scoring is dead on every client.")
end)
