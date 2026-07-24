--!nonstrict
--[[
	tests/capture/meshes.extract.luau — the mesh-extraction pipeline's Studio-side driver
	(tools/Extract-Meshes.ps1). Twin of tests/capture/world.bake.luau, same shape.

	WHAT IT DOES: run-in-roblox injects this at PLUGIN security in EDIT mode (same proven vector as
	world.capture.luau / world.bake.luau / boot.smoke.luau). For every unique meshId referenced by
	AssetManifest.props (computed via the shared MeshFactory.uniqueMeshIds — the SAME enumeration
	MeshFactory itself uses, so nothing here can drift from what the runtime actually needs), it makes
	the SAME call MeshFactory.getTemplate makes at runtime: InsertService:CreateMeshPartAsync, with the
	identical Part+SpecialMesh fallback on failure (mirrors MeshFactory.luau's getTemplate — see that
	module's doc comment for why: a dead id must cost exactly one failed pcall, never break the boot).
	Each resulting template is named by its meshId (a plain string Name — Roblox Instance names accept
	arbitrary strings, "rbxassetid://..." included) and parented under a Folder "MeshTemplates" in
	Workspace, so MeshFactory can look templates up by meshId at runtime via a simple
	:FindFirstChild(meshId) on ReplicatedStorage.MeshTemplates. It then prints the EXTRACTREADY
	sentinel and DWELLS — giving tools/Extract-Meshes.ps1 time to Ctrl+S the place (saving the fetched
	MeshParts to the temp .rbxlx run-in-roblox opened) before run-in-roblox kills Studio on return.

	This is a ONE-WAY channel (Studio -> PowerShell via stdout print, same constraint as the bake/
	capture harnesses): Luau at plugin security cannot read a file or receive stdin, so the wrapper
	cannot ACK a completed save back to this script. The DWELL is therefore a generous fixed budget,
	not a real handshake — tools/Extract-Meshes.ps1 documents the same asymmetry.
]]

local RS = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local function need(cond, msg)
	if not cond then
		print("[MESHEXTRACT] FAIL: " .. msg)
		error("[MESHEXTRACT] FAIL: " .. msg, 0)
	end
end

-- 1. Load the shared contracts in the REAL engine.
local okM, AssetManifest = pcall(require, RS:WaitForChild("AssetManifest", 10))
need(okM, "AssetManifest failed to load: " .. tostring(AssetManifest))
local okF, MeshFactory = pcall(require, RS:WaitForChild("MeshFactory", 10))
need(okF, "MeshFactory failed to load: " .. tostring(MeshFactory))

-- 2. Enumerate every unique meshId across ALL manifest prop roles (treeLeafy, treePine, rock, bush,
--    log, and any future role) via the SAME pure helper MeshFactory itself uses for prewarm, so this
--    extractor can never enumerate a different set than the runtime consumer expects.
local meshIds = MeshFactory.uniqueMeshIds(AssetManifest.props)
need(#meshIds > 0, "AssetManifest.props yielded zero unique meshIds -- nothing to extract")
print(("[MESHEXTRACT] %d unique meshId(s) to fetch"):format(#meshIds))

local folder = Instance.new("Folder")
folder.Name = "MeshTemplates"
folder.Parent = workspace

local meshCount, fallbackCount = 0, 0
for i, meshId in ipairs(meshIds) do
	-- Same call + fallback MeshFactory.luau's getTemplate makes at runtime (kept in lockstep by hand;
	-- see that module's doc comment).
	local ok, meshPart = pcall(function()
		return InsertService:CreateMeshPartAsync(meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)

	local inst
	if ok and meshPart then
		inst = meshPart
		meshCount += 1
	else
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = meshId
		mesh.Parent = part
		inst = part
		fallbackCount += 1
		warn("[MESHEXTRACT] CreateMeshPartAsync failed for " .. meshId .. " -- using SpecialMesh fallback")
	end

	inst.Anchored = true
	inst.Name = meshId
	inst.Parent = folder
	print(("[MESHEXTRACT] %d/%d %s -> %s"):format(i, #meshIds, meshId, inst.ClassName))
end

print(("[MESHEXTRACT] done: %d mesh, %d fallback, %d total"):format(meshCount, fallbackCount, #meshIds))

-- 3. READY — tools/Extract-Meshes.ps1 tails stdout for this exact sentinel, then Ctrl+S's the Studio
--    window (the place was opened by run-in-roblox from a temp .rbxlx path, so Ctrl+S saves in place
--    with no dialog) and copies the saved file out before this script returns.
print("EXTRACTREADY")

-- 4. DWELL — hold the process open long enough for the wrapper to detect+copy the save.
task.wait(40)

print("EXTRACTDONE")
