--!nonstrict
--[[
	BirdCollision — swept-sphere obstacle/ground collision for CFrame-driven birds.

	WHY THIS EXISTS: FlightPhysics integrates position in pure Luau and the controllers
	write Body.CFrame directly every frame. A part whose CFrame is set every frame does NOT
	collide with terrain, the baseplate, or the spires/perches — it tunnels straight through
	(see the `birds-have-no-roblox-collision` memory). A point ray also skips thin spires at
	260+ studs/s, so we sweep a SPHERE the size of the bird along its per-step movement vector
	(create.roblox.com/docs/workspace/raycasting → "Shapecasts").

	This module is the ONLY shared place that touches Workspace (via workspace:Spherecast).
	FlightPhysics stays pure; the controllers (BirdController client, GameServer for AI) call
	resolve() AFTER FlightPhysics:Update and BEFORE committing the new CFrame to the part.

	CONTRACT:
	  BirdCollision.makeParams(ignore) -> RaycastParams   (reuse one; Exclude the Birds folder)
	  BirdCollision.resolve(fromPos, toPos, velocity, radius, params, crashSpeed)
	     -> correctedPos (Vector3), correctedVel (Vector3), crashed (bool), hit (RaycastResult|nil)

	resolve() semantics:
	  • No hit                       -> (toPos, velocity, false, nil)              fly on unchanged.
	  • Hit, closing speed >= crash  -> (surfacePos, velocity, true,  hit)         caller kills it.
	  • Hit, closing speed <  crash  -> (surfacePos, slideVel, false, hit)         graze: slide along.
	"Closing speed" is the component of `velocity` INTO the surface (along -hit.Normal); a glancing
	pass (velocity parallel to the surface) has ~0 closing speed and always slides, while a head-on
	ram has high closing speed and crashes — which is the skill/terrain interaction we want.
]]

local BirdCollision = {}

local EPS = 1e-4
local SKIN = 0.15 -- studs of clearance kept off a surface so the next sweep doesn't start embedded

-- Build a reusable RaycastParams that ignores the birds themselves (so a bird never "collides"
-- with another bird here — those are handled by GameServer.processCollisions) and only reports
-- the map/world. Pass the Workspace.Birds folder (or any instance/array) as `ignore`.
function BirdCollision.makeParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	if ignore == nil then
		params.FilterDescendantsInstances = {}
	elseif typeof(ignore) == "table" then
		params.FilterDescendantsInstances = ignore
	else
		params.FilterDescendantsInstances = { ignore }
	end
	return params
end

-- Core resolve. `radius` is the bird's body radius (the swept sphere radius). `crashSpeed`
-- is the closing-speed threshold above which the impact is lethal.
function BirdCollision.resolve(fromPos, toPos, velocity, radius, params, crashSpeed)
	velocity = velocity or Vector3.new()
	local delta = toPos - fromPos
	local dist = delta.Magnitude
	if dist < EPS then
		return toPos, velocity, false, nil
	end

	local hit = workspace:Spherecast(fromPos, radius, delta, params)
	if not hit then
		return toPos, velocity, false, nil
	end

	local normal = hit.Normal
	-- Park the bird just off the surface along the contact normal (no penetration, no tunnel).
	local surfacePos = hit.Position + normal * (radius + SKIN)

	-- Closing speed = how fast we are driving INTO the surface (along -normal).
	local closing = -velocity:Dot(normal)
	if closing >= (crashSpeed or 0) then
		-- Lethal impact. Keep velocity so a server measuring the position delta still sees the
		-- full closing speed (the anti-cheat / authoritative crash check reads deltas, not vel).
		return surfacePos, velocity, true, hit
	end

	-- Survivable graze: remove the into-surface velocity component so we slide along it.
	local slideVel = velocity - normal * velocity:Dot(normal)
	return surfacePos, slideVel, false, hit
end

return BirdCollision
