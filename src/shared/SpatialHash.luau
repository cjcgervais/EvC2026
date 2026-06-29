--!nonstrict
--[[
	SpatialHash — a uniform-grid broad-phase for proximity queries.

	WHY: GameServer's processCollisions (every enemy pair) and findNearestEnemy (scan all
	birds) are O(n²) and O(n). At a handful of birds that's free, but the design target is
	many simultaneous 4-crow swarms (dozens of birds) — see docs/HANDOFF.md queue #6a. This
	grid is built once per Heartbeat and shared by every proximity consumer; each query only
	visits the cells overlapping its radius, turning the pairwise sweep near-linear.

	BEHAVIOUR-PRESERVING: this is a BROAD phase only. forEachInRadius visits a SUPERSET of the
	in-range items (everything in the overlapping cells); the caller still does the exact
	squared-distance test it always did. No in-range item is ever missed as long as the cell
	scan covers the query radius (it does: r = ceil(radius / cell)).

	Buckets are keyed in the XZ plane only (birds spread horizontally; vertical separation is
	caught by the caller's exact 3D distance check). Pure Luau — no instances, so it also runs
	unchanged inside a Parallel Luau Actor later (queue #6b).

	API:
	  SpatialHash.new(cellSize) -> grid
	  grid:clear()
	  grid:insert(position, data)
	  grid:forEachInRadius(position, radius, fn)   -- fn(data, position) per candidate
	  grid:nearest(position, radius, filterFn)     -> data, distance  (filterFn(data) -> bool)
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHash.new(cellSize)
	return setmetatable({
		cell = cellSize or 64,
		buckets = {}, -- ["cx,cz"] = { {position=Vector3, data=any}, ... }
	}, SpatialHash)
end

-- String cell key — avoids the false-candidate risk of a hashed integer key (correctness over
-- a few extra bytes; bucket counts here are tiny).
local function cellKey(cx, cz)
	return cx .. "," .. cz
end

function SpatialHash:clear()
	table.clear(self.buckets)
end

function SpatialHash:insert(position, data)
	local cell = self.cell
	local k = cellKey(math.floor(position.X / cell), math.floor(position.Z / cell))
	local bucket = self.buckets[k]
	if not bucket then
		bucket = {}
		self.buckets[k] = bucket
	end
	bucket[#bucket + 1] = { position = position, data = data }
end

-- Visit every item whose cell overlaps the query radius. The caller does the exact check.
function SpatialHash:forEachInRadius(position, radius, fn)
	local cell = self.cell
	local span = math.ceil(radius / cell)
	local cx = math.floor(position.X / cell)
	local cz = math.floor(position.Z / cell)
	for ix = cx - span, cx + span do
		for iz = cz - span, cz + span do
			local bucket = self.buckets[cellKey(ix, iz)]
			if bucket then
				for _, item in ipairs(bucket) do
					fn(item.data, item.position)
				end
			end
		end
	end
end

-- Nearest item to `position` within `radius` for which filterFn(data) is truthy (or no filter).
-- Returns (data, distance) or nil.
function SpatialHash:nearest(position, radius, filterFn)
	local best, bestDistSq
	local radiusSq = radius * radius
	self:forEachInRadius(position, radius, function(data, itemPos)
		if filterFn and not filterFn(data) then return end
		local d2 = (itemPos - position).Magnitude
		d2 = d2 * d2
		if d2 <= radiusSq and (not bestDistSq or d2 < bestDistSq) then
			best, bestDistSq = data, d2
		end
	end)
	if best then
		return best, math.sqrt(bestDistSq)
	end
	return nil
end

return SpatialHash
