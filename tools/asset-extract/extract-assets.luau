--!nonstrict
--[[
	tools/asset-extract/extract-assets.luau — M4-A asset-extraction script.

	Runs at PLUGIN security inside `run-in-roblox` EDIT mode (see tools/Extract-Assets.ps1).
	`game:GetObjects("rbxassetid://<id>")` loads un-acquired FREE toolbox models at plugin
	security — the proven extraction path (S50 spike). `InsertService:LoadAsset` is NOT
	usable here (18/20 failed auth in the S50 spike); do not swap back to it.

	For each candidate asset: walk every descendant BasePart, record its geometry relative
	to the root's first-encountered BasePart CFrame (so parts are extractor-orientation-
	independent), and print one `[X] OK <assetId> <role> <json>` line per asset (or
	`[X] ERR <assetId> <reason>` on failure), ending with a `[X] DONE` sentinel. This output
	format is verbatim what's captured in extract-S50.jsonl / extract-latest.jsonl and is the
	source of truth AssetManifest.luau is hand-transformed from.

	============================================================================
	SWAP POINT — edit this list to curate a different/expanded asset set, then run
	tools/Extract-Assets.ps1 to regenerate tools/asset-extract/extract-latest.jsonl.
	============================================================================
]]
local HttpService = game:GetService("HttpService")

local candidates = {
	{ id = 3287226226, role = "tree_leafy" },
	{ id = 12549617200, role = "tree_leafy" },
	{ id = 5616880673, role = "tree_pine" },
	{ id = 12605122162, role = "tree_pine" },
	{ id = 2128776869, role = "rock_pack" },
	{ id = 9682467046, role = "nature_pack" },
	{ id = 5003870763, role = "bush" },
	{ id = 5186800496, role = "sky" },
	{ id = 627302570, role = "sky_backup" },
}
-- ============================================================================

for _, c in candidates do
	local ok, err = pcall(function()
		local objs = game:GetObjects("rbxassetid://" .. c.id)
		local models = {}
		local skies = {}
		for _, root in objs do
			if root:IsA("Sky") then
				table.insert(skies, {
					bk = root.SkyboxBk, dn = root.SkyboxDn, ft = root.SkyboxFt,
					lf = root.SkyboxLf, rt = root.SkyboxRt, up = root.SkyboxUp,
					sun = root.SunTextureId, sunSize = root.SunAngularSize,
				})
			else
				local parts = {}
				local rootCf = nil
				for _, d in root:GetDescendants() do
					if d:IsA("Sky") then
						table.insert(skies, { bk = d.SkyboxBk, dn = d.SkyboxDn, ft = d.SkyboxFt, lf = d.SkyboxLf, rt = d.SkyboxRt, up = d.SkyboxUp, sun = d.SunTextureId, sunSize = d.SunAngularSize })
					elseif d:IsA("BasePart") then
						if not rootCf then rootCf = d.CFrame end
						local rel = rootCf:ToObjectSpace(d.CFrame)
						local rx, ry, rz = rel:ToOrientation()
						local rec = {
							class = d.ClassName,
							name = d.Name,
							size = { d.Size.X, d.Size.Y, d.Size.Z },
							color = { math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5) },
							material = d.Material.Name,
							offset = { rel.X, rel.Y, rel.Z },
							rot = { math.deg(rx), math.deg(ry), math.deg(rz) },
							shape = (d.ClassName == "Part") and tostring(d.Shape.Name) or nil,
							transparency = d.Transparency,
						}
						if d:IsA("MeshPart") then
							rec.meshId = d.MeshId
							rec.textureId = d.TextureID
							local okMs, ms = pcall(function() return d.MeshSize end)
							if okMs and ms then rec.meshSize = { ms.X, ms.Y, ms.Z } end
						end
						local sm = d:FindFirstChildOfClass("SpecialMesh")
						if sm then
							rec.specialMesh = { meshId = sm.MeshId, textureId = sm.TextureId, scale = { sm.Scale.X, sm.Scale.Y, sm.Scale.Z }, meshType = sm.MeshType.Name }
						end
						table.insert(parts, rec)
					end
				end
				if #parts > 0 then
					table.insert(models, { rootName = root.Name, parts = parts })
				end
			end
			root:Destroy()
		end
		print("[X] OK " .. c.id .. " " .. c.role .. " " .. HttpService:JSONEncode({ models = models, skies = skies }))
	end)
	if not ok then
		print("[X] ERR " .. c.id .. " " .. tostring(err))
	end
end
print("[X] DONE")
