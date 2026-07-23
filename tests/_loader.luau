--!nonstrict
--[[
	tests/_loader.luau — bridge Roblox-style ModuleScripts onto Lune's string loader.

	This is the keystone of verify.ps1 Tier 4 (headless logic tests). It runs the
	UNMODIFIED `src/shared` pure modules OUTSIDE Roblox so pure logic — flight kernel
	invariants, and (once packet A2 lands) RescueRules gate/scoring/phase math — can be
	exit-code gated on every change, catching the ~70% "same fact in two authorities"
	bug class that used to cost Studio playtests.

	HOW each ModuleScript is faked:
	  - Represented by a lightweight "script object" table carrying Name / Parent.
	  - luau.load()'d from its source STRING with a flat `environment` that supplies:
	      * the Roblox datatypes the modules use (Vector3/CFrame/Color3/Enum via
	        @lune/roblox) + a couple of Roblox-isms (tick/warn),
	      * a `script` bound to that module (so `script.Parent.X` resolves), and
	      * a `require` shim that memoizes sibling loads.
	  Standard Luau libs (math/table/string/pairs/...) are auto-injected by luau.load,
	  so only Roblox-isms need supplying here.

	PRELOAD note: fs.readFile yields; we read ALL sources up front so the require shim
	(invoked from inside an already-loaded chunk) never yields across the luau boundary.

	CWD note: paths are repo-root-relative; verify.ps1 (and `lune run tests/...` from
	the repo root) run with cwd = repo root.
]]

local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

-- Shared-module registry: logical name -> source path (mirrors the Rojo
-- ReplicatedStorage.* mapping in default.project.json). Add rows as pure modules
-- are extracted (RescueRules in A2, FireGrid in B1, ...).
local MODULES = {
	GameConfig    = "src/shared/GameConfig.luau",
	FlightPhysics = "src/shared/FlightPhysics.luau",
	BirdBuilder   = "src/shared/BirdBuilder.luau",
	RescueRules   = "src/shared/RescueRules.luau",
	FireGrid      = "src/shared/FireGrid.luau",
	FireVisuals   = "src/shared/FireVisuals.luau",
	BounceRules   = "src/shared/BounceRules.luau",
	FeatherFX     = "src/shared/FeatherFX.luau",
	FeatherBurst  = "src/shared/FeatherBurst.luau",
	TouchAimAdapter = "src/shared/TouchAimAdapter.luau",
	CrowdLayout   = "src/shared/CrowdLayout.luau",
	GroundDetail  = "src/shared/GroundDetail.luau",
	WorldGen      = "src/shared/WorldGen.luau",
	AssetManifest = "src/shared/AssetManifest.luau",
}

-- Preload every source string (before any luau.load; fs yields).
local sources = {}
for name, path in pairs(MODULES) do
	sources[name] = fs.readFile(path)
end

-- The shared "folder": name -> script object. Each module's `script.Parent` is this,
-- so `require(script.Parent.GameConfig)` finds a sibling.
local sharedFolder = {}
local cache = {} -- script object -> memoized module return value

-- Roblox-ism globals not covered by luau.load's standard-library injection.
local function baseGlobals()
	return {
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		-- @lune/roblox implements the instance tree (Part/WedgePart/Weld/Motor6D/Model/...) so the
		-- PROCEDURAL model builders (BirdBuilder) run headlessly — the model-build quality gate.
		-- (Runtime-only Model methods PivotTo/ScaleTo/GetBoundingBox are NOT implemented; the gate
		-- reads part .CFrame/.Size directly and does its own forward kinematics.)
		Instance = roblox.Instance,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		tick = os.clock,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
end

local requireShim -- forward decl

local function loadScript(scriptObj)
	if cache[scriptObj] ~= nil then
		return cache[scriptObj]
	end
	local env = baseGlobals()
	env.script = scriptObj
	env.require = requireShim
	local fn = luau.load(sources[scriptObj.Name], {
		environment = env,
		debugName = scriptObj.Name,
	})
	local result = fn()
	cache[scriptObj] = result
	return result
end

requireShim = function(target)
	-- Every require in src/shared is `require(script.Parent.<Name>)`; target is that
	-- sibling's script object.
	if type(target) == "table" and target.__isScript then
		return loadScript(target)
	end
	error("loader: only `require(script.Parent.<Module>)` is bridged; got " .. tostring(target))
end

for name in pairs(MODULES) do
	sharedFolder[name] = { __isScript = true, Name = name, Parent = sharedFolder }
end

local Loader = {}

-- Load a shared module by logical name, e.g. `Loader.load("FlightPhysics")`.
function Loader.load(name)
	local scriptObj = sharedFolder[name]
	if not scriptObj then
		error("loader: unknown module '" .. tostring(name) .. "'")
	end
	return loadScript(scriptObj)
end

-- Re-export the Roblox datatypes so SPEC files (which run in Lune's plain global
-- environment, where Vector3/CFrame/... are NOT globals) can construct kernel inputs.
Loader.Vector3 = roblox.Vector3
Loader.Vector2 = roblox.Vector2
Loader.CFrame = roblox.CFrame
Loader.Color3 = roblox.Color3
Loader.Enum = roblox.Enum
-- Re-export Instance so SPEC files can build/inspect real Instances headlessly (the FireVisuals
-- geometry gate constructs a container Folder and reads Enum.Material/Enum.PartType directly).
Loader.Instance = roblox.Instance

return Loader
