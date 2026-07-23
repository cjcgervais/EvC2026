--!nonstrict
--[[
	tests/boot.spec.luau — S51 boot-barrier gate.

	Chad-observed live bug: round 1 started ~63s before the client ever saw a rendered world (GameServer's
	WorldGen.build was still sculpting terrain while RescueServer's round loop free-ran on wall clock), AND
	RescueServer's 60s "Birds folder never appeared" carrier-loss-reset guard was timing out every boot
	because GameServer only created the Birds folder lazily on first spawn.

	Lune can't run GameServer/RescueServer (they touch Workspace/Players at require-time), so — same
	source-gate pattern as worldgen.spec.luau's §14 — this pins the SHAPE of the fix:
	  1. GameServer creates the `Birds` folder EAGERLY at boot (not just lazily in spawnFor).
	  2. GameServer sets Workspace:SetAttribute("WorldReady", true) after its world build, unconditionally
	     of which of the 3 boot branches ran (worldV2 success / worldV2-pcall-failed fallback / legacy).
	  3. RescueServer's round loop waits on WorldReady before doing anything else, with a bounded timeout
	     that WARNS rather than hangs silently forever.
	  4. RescueServer's round 1 (and only round 1) also waits for a player's bird to exist before going
	     ACTIVE, with the same warn-on-timeout pattern.
]]

local H = require("./_harness")
local fs = require("@lune/fs")

local gameServerSrc = fs.readFile("src/server/GameServer.server.luau")
local rescueServerSrc = fs.readFile("src/server/RescueServer.server.luau")
local worldGenSrc = fs.readFile("src/shared/WorldGen.luau")

--------------------------------------------------------------------------------
-- 1. Eager Birds folder at GameServer boot.
--------------------------------------------------------------------------------
H.test("source-gate: GameServer creates the Birds folder eagerly at boot (not just lazily on first spawn)", function()
	local bootStart = gameServerSrc:find("INITIALIZATION")
	H.ok(bootStart ~= nil, "expected the INITIALIZATION boot section banner")
	local bootTail = gameServerSrc:sub(bootStart)
	H.ok(bootTail:find("ensureBirdContainer%(%)") ~= nil,
		"GameServer's boot tail must call ensureBirdContainer() eagerly, before any player spawns")
end)

H.test("source-gate: ensureBirdContainer is find-or-create (never clobbers an existing Birds folder)", function()
	local startI = gameServerSrc:find("local function ensureBirdContainer")
	H.ok(startI ~= nil, "expected ensureBirdContainer's definition")
	local endI = gameServerSrc:find("\r?\nend", startI)
	local block = gameServerSrc:sub(startI, endI)
	H.ok(block:find('FindFirstChild%("Birds"%)') ~= nil,
		"ensureBirdContainer must look for an existing Birds folder before minting a new one")
end)

--------------------------------------------------------------------------------
-- 2. WorldReady barrier — set in GameServer after the world build, on every boot path.
--------------------------------------------------------------------------------
H.test("source-gate: GameServer sets Workspace WorldReady after the world build completes", function()
	local worldV2I = gameServerSrc:find("GameConfig%.Map and GameConfig%.Map%.worldV2")
	local readyI = gameServerSrc:find('SetAttribute%("WorldReady"', worldV2I)
	H.ok(worldV2I ~= nil, "expected the worldV2 branch that runs WorldGen.build / legacy fallback")
	H.ok(readyI ~= nil, "GameServer must SetAttribute(\"WorldReady\", true) on Workspace after the world build")
	H.ok(readyI > worldV2I, "WorldReady must be set AFTER the world-build branch, not before it")
end)

H.test("source-gate: the WorldReady set sits after the if/else so it covers all 3 boot branches", function()
	-- The if/else block covers: worldV2 success, worldV2 pcall-failed fallback (still inside the `if`
	-- body), and worldV2=false legacy (the `else` body). The SetAttribute call must be OUTSIDE/after that
	-- whole if/else — not duplicated inside just one branch — so every path reaches it exactly once.
	local worldV2I = gameServerSrc:find("if GameConfig%.Map and GameConfig%.Map%.worldV2 then")
	local elseI = gameServerSrc:find("\nelse\r?\n", worldV2I)
	local endBlockI = gameServerSrc:find("\nend\r?\n", elseI)
	local readyI = gameServerSrc:find('SetAttribute%("WorldReady"', worldV2I)
	H.ok(worldV2I and elseI and endBlockI and readyI, "expected to locate the full if/else/end world-build block and the WorldReady set")
	H.ok(readyI > endBlockI, "WorldReady must be set after the if/else/end block closes, so all branches reach it")
end)

--------------------------------------------------------------------------------
-- 3. RescueServer waits on WorldReady before its first round, with a bounded warn-on-timeout.
--------------------------------------------------------------------------------
H.test("source-gate: RescueServer waits for WorldReady before the round loop does anything else", function()
	H.ok(rescueServerSrc:find("waitForWorldReady") ~= nil, "expected a waitForWorldReady helper")
	local loopI = rescueServerSrc:find("local function RescueRoundLoop%(%)")
	H.ok(loopI ~= nil, "expected RescueRoundLoop's definition")
	local callI = rescueServerSrc:find("waitForWorldReady%(%)", loopI)
	local buildWorldCallI = rescueServerSrc:find("\tbuildWorld%(%)", loopI)
	H.ok(callI ~= nil, "RescueRoundLoop must call waitForWorldReady()")
	H.ok(buildWorldCallI ~= nil, "expected the buildWorld() call inside RescueRoundLoop")
	H.ok(callI < buildWorldCallI, "waitForWorldReady() must run BEFORE buildWorld()")
end)

H.test("source-gate: waitForWorldReady has a bounded timeout and warns rather than hanging silently", function()
	local startI = rescueServerSrc:find("local function waitForWorldReady")
	H.ok(startI ~= nil, "expected waitForWorldReady's definition")
	local endI = rescueServerSrc:find("\r?\nend\r?\n", startI)
	local block = rescueServerSrc:sub(startI, endI)
	H.ok(block:find("120") ~= nil, "waitForWorldReady must use a bounded timeout (120s)")
	H.ok(block:find("warn%(") ~= nil, "waitForWorldReady must warn loudly if the timeout is exceeded, never hang silently")
end)

--------------------------------------------------------------------------------
-- 4. Round 1 (only) waits for a player's bird before going ACTIVE, same warn-on-timeout pattern.
--------------------------------------------------------------------------------
H.test("source-gate: round 1's ACTIVE phase waits for a player bird before starting", function()
	H.ok(rescueServerSrc:find("waitForFirstPlayerBird") ~= nil, "expected a waitForFirstPlayerBird helper")
	local gateI = rescueServerSrc:find("roundIndex == 1")
	H.ok(gateI ~= nil, "expected a roundIndex == 1 gate")
	local startRoundI = rescueServerSrc:find("startRound%(%)", gateI)
	local waitCallI = rescueServerSrc:find("waitForFirstPlayerBird%(%)", gateI)
	H.ok(waitCallI ~= nil and startRoundI ~= nil, "expected waitForFirstPlayerBird() called ahead of startRound() under the roundIndex==1 gate")
	H.ok(waitCallI < startRoundI, "waitForFirstPlayerBird() must run BEFORE startRound() for round 1")
end)

H.test("source-gate: waitForFirstPlayerBird has a bounded timeout and warns rather than hanging silently", function()
	local startI = rescueServerSrc:find("local function waitForFirstPlayerBird")
	H.ok(startI ~= nil, "expected waitForFirstPlayerBird's definition")
	local endI = rescueServerSrc:find("\r?\nend\r?\n", startI)
	local block = rescueServerSrc:sub(startI, endI)
	H.ok(block:find("120") ~= nil, "waitForFirstPlayerBird must use a bounded timeout (120s)")
	H.ok(block:find("warn%(") ~= nil, "waitForFirstPlayerBird must warn loudly if the timeout is exceeded, never hang silently")
end)

--------------------------------------------------------------------------------
-- 5. Boot-clock instrument — a probe, always-on, one print per boot stage (SOP: probe before optimizing).
--------------------------------------------------------------------------------
H.test("source-gate: GameServer prints a [BootClock] line for remotes+world-build timing", function()
	H.ok(gameServerSrc:find("%[BootClock%]") ~= nil, "GameServer must print a [BootClock] line")
	H.ok(gameServerSrc:find("os%.clock%(%)") ~= nil, "GameServer's boot timing must use os.clock()")
end)

H.test("source-gate: WorldGen.build prints a [BootClock] line with per-phase timings", function()
	local buildI = worldGenSrc:find("function WorldGen%.build")
	H.ok(buildI ~= nil, "expected WorldGen.build's definition")
	local block = worldGenSrc:sub(buildI)
	H.ok(block:find("%[BootClock%]") ~= nil, "WorldGen.build must print a [BootClock] line")
	for _, phase in ipairs({ "sculpt", "scatter", "lighting", "total" }) do
		H.ok(block:find(phase) ~= nil, ("WorldGen.build's [BootClock] line must report a %s= timing"):format(phase))
	end
end)

H.test("source-gate: BirdController prints a [BootClock] first-playable line, once, client-side", function()
	H.ok(gameServerSrc, "sanity") -- keep the table shape consistent with other blocks
	local src = fs.readFile("src/client/BirdController.client.luau")
	H.ok(src:find("first%-playable") ~= nil, "BirdController must print a 'first-playable' [BootClock] line")
	H.ok(src:find("EvCFirstPlayablePrinted") ~= nil, "the first-playable print must be guarded so it only fires once")
end)
