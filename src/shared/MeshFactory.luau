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
local templateCache = {} -- meshId -> { kind = "mesh"|"part", template = Instance }

local function getTemplate(meshId)
	local cached = templateCache[meshId]
	if cached ~= nil then
		return cached
	end

	local rec
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
	templateCache[meshId] = rec
	return rec
end

-- build(variant, cf, targetHeight, parent) -> the Model it built, or nil if the variant/height is unusable.
-- `cf` is the world CFrame of the variant's own local origin (its offset-{0,0,0} part sits there).
function MeshFactory.build(variant, cf, targetHeight, parent)
	local specs = MeshFactory.plan(variant, targetHeight)
	if #specs == 0 then
		return nil
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
		inst.CFrame = cf * offsetCF
		inst.Parent = model
	end

	model.Parent = parent
	return model
end

return MeshFactory
