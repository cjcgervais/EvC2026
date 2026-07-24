--!nonstrict
--[[
	MeshFactory — turns an AssetManifest `variant` (a curated free-mesh prop: a tree, rock, bush, log...)
	into either build SPECS (pure) or real Instances (engine). Follows the WorldGen plan/build split so
	the geometry math stays lune-testable while the Instance/Roblox-service work is isolated:

	  • MeshFactory.plan(variant, targetHeight) — PURE. No Instances, no services, no `game`. Computes
	    a uniform scale (targetHeight / variant.height) and returns one build spec per part: scaled
	    size/offset, rotation, color, material, meshId/textureId. This is what tests/meshfactory.spec
	    exercises. `targetHeight <= 0`, a missing variant, or `variant.height <= 0` all return {}.

	  • MeshFactory.build(variant, cf, targetHeight, parent) — the applier. Re-derives the same specs via
	    plan(), then for each unique meshId either mints a real MeshPart (InsertService:CreateMeshPartAsync,
	    pcall'd, cached PER MESH ID so a dead id only costs one failed pcall for the whole boot) or falls
	    back to a Part + SpecialMesh (FileMesh, Scale = scaledSize / meshSize). Every part it creates is
	    Anchored=true, CanCollide=false, CanQuery=false, CanTouch=false, CastShadow=false (ghost-forest +
	    perf-budget contract, M4-B spec) and parented under a Model named after the variant's rootName.

	    TEMPLATE RESOLUTION (VISUAL-QUALITY-BAR.md sec 1.5 -- committed mesh path, S51): the runtime
	    InsertService:CreateMeshPartAsync path is permission-fragile and network-dependent, so it is now
	    the FALLBACK, not the primary path. getTemplate(meshId) first checks
	    ReplicatedStorage.MeshTemplates (committed via tools/Extract-Meshes.ps1 -> assets/MeshTemplates.rbxm,
	    mapped in by default.project.json) for a child named exactly `meshId` and, if found, clones it
	    instantly -- offline, deterministic, zero CDN round-trip. Only when the committed folder is
	    missing an id (pre-extraction, or a newly-added manifest entry the extractor hasn't caught up to
	    yet) does it fall back to InsertService:CreateMeshPartAsync, pcall'd, with the same Part+
	    SpecialMesh (FileMesh) last resort on outright failure. Both paths are cached PER MESH ID in
	    templateCache so a given id only ever pays its resolution cost once per boot.

	    Never called by a Tier-4 spec — @lune/roblox has no InsertService.
]]

local MeshFactory = {}

--------------------------------------------------------------------------------
-- plan(variant, targetHeight) -> array of pure per-part build specs. No Instances, no services.
--------------------------------------------------------------------------------
function MeshFactory.plan(variant, targetHeight)
	if not variant or type(variant.height) ~= "number" or variant.height <= 0 then
		return {}
	end
	if type(targetHeight) ~= "number" or targetHeight <= 0 then
		return {}
	end
	if type(variant.parts) ~= "table" or #variant.parts == 0 then
		return {}
	end

	local scale = targetHeight / variant.height
	local specs = {}
	for i, part in ipairs(variant.parts) do
		specs[i] = {
			meshId = part.meshId,
			textureId = part.textureId,
			scale = scale,
			meshSize = part.meshSize,
			scaledSize = { part.size[1] * scale, part.size[2] * scale, part.size[3] * scale },
			scaledOffset = { part.offset[1] * scale, part.offset[2] * scale, part.offset[3] * scale },
			rot = part.rot,
			color = part.color,
			material = part.material,
		}
	end
	return specs
end

--------------------------------------------------------------------------------
-- build() — ENGINE ONLY. Template cache keyed per mesh id so a dead id costs one pcall for the whole
-- session (module-scope upvalue: persists across every MeshFactory.build call, i.e. the whole boot).
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- uniqueMeshIds(manifestProps) -> array of unique meshId strings. PURE — no Instances, no services,
-- just walks an AssetManifest.props-shaped table ({ role = { variant, ... }, ... }) collecting every
-- part.meshId exactly once. Sorted so the return is deterministic (lune-testable).
--------------------------------------------------------------------------------
function MeshFactory.uniqueMeshIds(manifestProps)
	local seen = {}
	local ids = {}
	if type(manifestProps) ~= "table" then
		return ids
	end
	for _, variants in pairs(manifestProps) do
		if type(variants) == "table" then
			for _, variant in ipairs(variants) do
				if type(variant) == "table" and type(variant.parts) == "table" then
					for _, part in ipairs(variant.parts) do
						local id = part.meshId
						if type(id) == "string" and id ~= "" and not seen[id] then
							seen[id] = true
							ids[#ids + 1] = id
						end
					end
				end
			end
		end
	end
	table.sort(ids)
	return ids
end

local templateCache = {} -- meshId -> { kind = "mesh"|"part", template = Instance }

-- findTemplatesFolder() -- looks up ReplicatedStorage.MeshTemplates, the committed-mesh folder
-- default.project.json $path-maps from assets/MeshTemplates.rbxm (bar sec 1.5). pcall'd: this module
-- must never hard-error just because the folder is momentarily absent (e.g. a placeholder-only clone
-- pre-extraction, or a caller running before ReplicatedStorage has finished streaming in edge cases).
local function findTemplatesFolder()
	local ok, folder = pcall(function()
		return game:GetService("ReplicatedStorage"):FindFirstChild("MeshTemplates")
	end)
	if ok then
		return folder
	end
	return nil
end

local function getTemplate(meshId)
	local cached = templateCache[meshId]
	if cached ~= nil then
		return cached
	end

	local rec

	-- 1. Committed template path (bar sec 1.5): instant, offline, deterministic -- zero CDN round-trip.
	local folder = findTemplatesFolder()
	local committed = folder and folder:FindFirstChild(meshId)
	if committed then
		local kind = (committed.ClassName == "MeshPart") and "mesh" or "part"
		rec = { kind = kind, template = committed }
	else
		-- 2. Fallback: runtime CDN fetch (pre-extraction, or an id the committed folder doesn't have).
		local InsertService = game:GetService("InsertService")
		local ok, meshPart = pcall(function()
			return InsertService:CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
		end)
		if ok and meshPart then
			rec = { kind = "mesh", template = meshPart }
		else
			local part = Instance.new("Part")
			part.Shape = Enum.PartType.Block
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = meshId
			mesh.Parent = part
			rec = { kind = "part", template = part }
		end
	end
	templateCache[meshId] = rec
	return rec
end

--------------------------------------------------------------------------------
-- prewarm(meshIds) — ENGINE ONLY. Fires one task.spawn per unique meshId, each calling the same
-- getTemplate() path above (pcall'd, cached per mesh id in the shared templateCache) so the ~N CDN
-- round-trips overlap in parallel instead of serializing one-by-one behind every MeshFactory.build call
-- (S50 audit FIX 2: boot speed). Waits until every spawn reports done or a 15s deadline, whichever
-- first. Returns (successCount, total) so a caller can log how many templates actually resolved. The
-- per-call getTemplate() path (inside build()) stays as the cache-hit/fallback for anything prewarm
-- missed (a late-added meshId, a timeout, or a caller that never prewarmed).
--
-- S51 (bar sec 1.5): any meshId already served by the committed ReplicatedStorage.MeshTemplates
-- folder resolves synchronously inside getTemplate() with zero network round-trip, so it is counted
-- as an INSTANT success here rather than spawned as an async task -- prewarm becomes a no-op (in the
-- "nothing to wait on" sense) once every referenced mesh has been extracted.
--------------------------------------------------------------------------------
local PREWARM_DEADLINE_S = 15

function MeshFactory.prewarm(meshIds)
	if type(meshIds) ~= "table" or #meshIds == 0 then
		return 0, 0
	end

	local total = #meshIds
	local completed = 0
	local successCount = 0
	local folder = findTemplatesFolder()

	for _, meshId in ipairs(meshIds) do
		if folder and folder:FindFirstChild(meshId) then
			-- Committed template: resolve inline, no task.spawn needed -- instant success.
			local ok, rec = pcall(getTemplate, meshId)
			if ok and rec then
				successCount += 1
			end
			completed += 1
		else
			task.spawn(function()
				local ok, rec = pcall(getTemplate, meshId)
				if ok and rec and rec.kind == "mesh" then
					successCount += 1
				end
				completed += 1
			end)
		end
	end

	local start = os.clock()
	while completed < total and (os.clock() - start) < PREWARM_DEADLINE_S do
		task.wait()
	end

	return successCount, total
end

-- build(variant, cf, targetHeight, parent, anchorBase) -> the Model it built, or nil if unusable.
-- `cf` is the world CFrame of the variant's own local origin (its offset-{0,0,0} part sits there).
-- The extractor pins that origin at the FIRST part's CENTRE (rootCf:ToObjectSpace), which for a tree
-- is the trunk centre — roughly mid-model, NOT the base. So by default `cf` places the model centred
-- on cf. Pass anchorBase=true to instead land the model's LOWEST extent at cf's Y (base-at-ground) —
-- what the tree swap needs so the mesh crown reaches the same height as the invisible canopy/perches
-- instead of the trunk half-sinking into the terrain. Scatter leaves it false (origin-at-surface).
function MeshFactory.build(variant, cf, targetHeight, parent, anchorBase)
	local specs = MeshFactory.plan(variant, targetHeight)
	if #specs == 0 then
		return nil
	end

	-- Base-anchor lift: raise every part in WORLD-Y so the lowest part bottom sits at cf's Y. cf carries
	-- at most a yaw (trees: none; scatter: Y-axis only), so its local Y == world Y and a world-vertical
	-- pre-translation is exact. scaledSize/2 approximates each part's vertical half-extent (the trunk,
	-- rot=0 and lowest, dominates the min — canopy tilt is a few studs, immaterial to grounding).
	local baseLift = 0
	if anchorBase then
		local minY = math.huge
		for _, spec in ipairs(specs) do
			local bottom = spec.scaledOffset[2] - spec.scaledSize[2] * 0.5
			if bottom < minY then minY = bottom end
		end
		if minY ~= math.huge then baseLift = -minY end
	end

	local model = Instance.new("Model")
	model.Name = variant.rootName or "MeshProp"

	for i, spec in ipairs(specs) do
		local rec = getTemplate(spec.meshId)
		local inst = rec.template:Clone()
		inst.Name = "MeshPart_" .. i
		inst.Size = Vector3.new(spec.scaledSize[1], spec.scaledSize[2], spec.scaledSize[3])

		if rec.kind == "part" then
			local sm = inst:FindFirstChildOfClass("SpecialMesh")
			if sm then
				local ms = spec.meshSize
				sm.Scale = Vector3.new(
					spec.scaledSize[1] / math.max(ms[1], 1e-4),
					spec.scaledSize[2] / math.max(ms[2], 1e-4),
					spec.scaledSize[3] / math.max(ms[3], 1e-4)
				)
			end
		end

		inst.Anchored = true
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
		inst.CastShadow = false
		inst.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
		local mat = spec.material and Enum.Material[spec.material]
		if mat then
			inst.Material = mat
		end

		local offsetCF = CFrame.new(spec.scaledOffset[1], spec.scaledOffset[2], spec.scaledOffset[3])
			* CFrame.Angles(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
		inst.CFrame = CFrame.new(0, baseLift, 0) * cf * offsetCF
		inst.Parent = model
	end

	model.Parent = parent
	return model
end

return MeshFactory
