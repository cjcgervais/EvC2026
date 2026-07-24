--!nonstrict
--[[
	AssetManifest — pure data module: free Roblox creator-store mesh/skybox assets curated
	for the M4 mesh pass (S50). Hand-generated ONCE from tools/asset-extract/extract-S50.jsonl
	(the `[X] OK <assetId> <role> <json>` lines are the source of truth; regenerate that jsonl
	via tools/Extract-Assets.ps1 and redo this transform if the candidate set changes).

	No Instances are touched here — MeshFactory (M4-B) is the applier that turns a `variant`
	into real geometry. This module only describes WHAT exists and WHERE its parts sit,
	relative to each source model's own root.

	Shape:
	  meta      = { extracted, session, source }
	  skybox / skyboxBackup = { bk, dn, ft, lf, rt, up, sun, sunSize, sourceAssetId, creator }
	  props     = { treeLeafy = {variant, ...}, treePine = {...}, rock = {...}, bush = {...},
	                log = {...} }  -- roles present in the curated set; grass/stump/flower
	                found none worth keeping this session (see classification note below)

	variant = {
	    sourceAssetId = number, creator = string, rootName = string,
	    height = number,  -- bounding Y extent of ALL parts (max top − min bottom), studs
	    parts = { { meshId, textureId, meshSize = {x,y,z}, size = {x,y,z}, color = {r,g,b},
	                material, offset = {x,y,z}, rot = {x,y,z} }, ... },
	}

	CLASSIFICATION (nature_pack asset 9682467046 has 12 named roots; classified by rootName
	keyword — case-insensitive substring — into a prop role; a root with NO real MeshPart
	descendant (only rig-placeholder Parts) is force-classified `misc` regardless of keyword
	match, and `misc` roots are simply excluded from `props` below (nothing consumes them):
	    "pine"/"redwood" -> treePine   "palm"/"tree" -> treeLeafy   "rock"       -> rock
	    "bush"/"shrub"   -> bush        "stump"       -> stump       "flower"/"mushroom" -> flower
	    "grass"          -> grass       "log"         -> log         else         -> misc
	Excluded (misc) this session: "Trees", "Shrubs & Nature", "Rocks" (placeholder-only rig
	anchors — a single "Head" Part, no meshId, no matter what the name says) and the
	nature_pack root literally named "Model" (a two-part mushroom-cap-looking prop with no
	keyword match at all — distinct from "(Editable) Low Poly Mushrooms", which DOES match
	the "mushroom" keyword).

	DEVIATION from the M4-A spec's literal table (documented, not silent): the spec's own
	assetmanifest.spec.luau bound requires every variant's `height` in [2, 200]. Two real,
	otherwise-valid extracted variants read under that floor — nature_pack "Small Low-Poly
	Rock" (height 0.963, a pebble-scale rock) and "(Editable) Low Poly Mushrooms" (height
	1.653) — so both are DROPPED here rather than weakening the sanity bound. `rock` still
	has 10 variants (>= the required 6); `flower` has none this session (not spec-required).

	Numbers rounded to <=3 decimals per the M4-A spec; colors are {r,g,b} 0-255 ints.
]]

return {
	meta = {
		extracted = "2026-07-22",
		session = "S50",
		source = "Roblox creator store, free assets; see tools/asset-extract/",
	},

	-- §2 bar packet: swapped to the sunset set (627302570, TracyCyanne) as primary — the far-read
	-- horizon/sky criterion needs a sky that actually reads as a sunset from altitude, not just "not
	-- broken". CONFIRMED RENDERING (S52 captures/S52-mountains, machine-eyes review): the sunset sky is
	-- live and reads correctly from altitude, no longer provisional. Fallbacks still kept if a future
	-- capture ever regresses: the old primary below (now skyboxBackup), then Map.meshSky=false (the
	-- procedural default-sky floor).
	skybox = {
		bk = "rbxassetid://541743453",
		dn = "rbxassetid://541743443",
		ft = "rbxassetid://541743446",
		lf = "rbxassetid://541743436",
		rt = "rbxassetid://541743435",
		up = "rbxassetid://541743441",
		sun = "rbxasset://sky/sun.jpg",
		sunSize = 21,
		sourceAssetId = 627302570,
		creator = "TracyCyanne",
	},
	-- Former primary (DotDDotexe, 5186800496) — demoted to backup, not deleted, so a rejected-sunset
	-- capture can fall back to it without re-authoring the manifest.
	skyboxBackup = {
		bk = "rbxassetid://600830446",
		dn = "rbxassetid://600831635",
		ft = "rbxassetid://600832720",
		lf = "rbxassetid://600886090",
		rt = "rbxassetid://600833862",
		up = "rbxassetid://600835177",
		sun = "rbxasset://sky/sun.jpg",
		sunSize = 21,
		sourceAssetId = 5186800496,
		creator = "DotDDotexe",
	},

	props = {
		treeLeafy = {
			-- asset 3287226226 "Model" (stump + leaf blob)
			{
				sourceAssetId = 3287226226, creator = "akbarbinta", rootName = "Model", height = 20.513,
				parts = {
					{ meshId = "rbxassetid://2638167049", textureId = "", meshSize = { 50, 81.914, 52.885 }, size = { 7.27, 13.364, 7.515 }, color = { 105, 64, 40 }, material = "Plastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://2992901017", textureId = "", meshSize = { 2.412, 1.414, 1.155 }, size = { 14.462, 11.824, 19.785 }, color = { 31, 128, 29 }, material = "Plastic", offset = { 0.507, 7.919, -0.189 }, rot = { 0, 0, 0 } },
				},
			},
			-- asset 12549617200 "Model" (trunk + leaf blob)
			{
				sourceAssetId = 12549617200, creator = "Remadex Development", rootName = "Model", height = 39.693,
				parts = {
					{ meshId = "rbxassetid://12545267056", textureId = "", meshSize = { 11.086, 50, 10.121 }, size = { 6.99, 31.524, 6.381 }, color = { 160, 95, 53 }, material = "Plastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://12545269850", textureId = "", meshSize = { 23.422, 50, 24.452 }, size = { 14.768, 31.524, 15.417 }, color = { 40, 127, 71 }, material = "Plastic", offset = { -0.288, 8.168, 0.558 }, rot = { 0, 0, 0 } },
				},
			},
			-- nature_pack "Normal Tree"
			{
				sourceAssetId = 9682467046, creator = "Proudism", rootName = "Normal Tree", height = 17.945,
				parts = {
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 8.012, 4.992, 5.628 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 9.192, 5.809, 8.124 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -2.178, 2.542, 4.062 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 6.559, 4.13, 7.715 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -4.72, 1.067, -0.59 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037289960", textureId = "", meshSize = { 43.206, 50, 45.044 }, size = { 12.569, 14.546, 13.104 }, color = { 105, 64, 40 }, material = "SmoothPlastic", offset = { -1.23, -5.226, 3.93 }, rot = { 0, 90, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 6.332, 4.13, 7.08 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -7.466, 0.431, 2.133 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 5.016, 3.086, 5.355 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -5.219, 2.632, 2.178 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 9.192, 3.903, 7.08 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -2.178, 1.588, 7.897 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 5.016, 3.086, 5.355 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -5.219, 3.041, 6.399 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 5.198, 3.313, 7.352 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { -7.035, 1.883, 6.989 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://3037308484", textureId = "", meshSize = { 47.553, 50, 50 }, size = { 6.423, 3.313, 7.171 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { 3.29, 1.702, 5.129 }, rot = { 0, 0, 0 } },
				},
			},
			-- nature_pack "Low Poly Tree"
			{
				sourceAssetId = 9682467046, creator = "Proudism", rootName = "Low Poly Tree", height = 15.202,
				parts = {
					{ meshId = "rbxassetid://5214312176", textureId = "", meshSize = { 695.171, 595.928, 590.824 }, size = { 6.403, 6.159, 5.442 }, color = { 75, 151, 75 }, material = "SmoothPlastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://5214283841", textureId = "", meshSize = { 38.971, 50, 20.896 }, size = { 4.823, 10.768, 2.586 }, color = { 108, 88, 75 }, material = "SmoothPlastic", offset = { -1.703, -4.343, -0.207 }, rot = { 0, 0, 20 } },
					{ meshId = "rbxassetid://5214312176", textureId = "", meshSize = { 695.171, 595.928, 590.824 }, size = { 9.445, 8.097, 8.028 }, color = { 75, 151, 75 }, material = "SmoothPlastic", offset = { -5.39, 1.426, 0.417 }, rot = { 15.189, -48.236, -6.832 } },
				},
			},
			-- nature_pack "Palm_1" (AnchorPoint placeholder Part dropped -- no meshId)
			{
				sourceAssetId = 9682467046, creator = "Proudism", rootName = "Palm_1", height = 20.813,
				parts = {
					{ meshId = "rbxassetid://864893767", textureId = "", meshSize = { 1.308, 7.982, 1.377 }, size = { 2.934, 17.9, 3.089 }, color = { 126, 104, 63 }, material = "SmoothPlastic", offset = { 0.897, 7.476, 0.523 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://864894551", textureId = "", meshSize = { 6.178, 4.213, 6.295 }, size = { 13.853, 9.447, 14.115 }, color = { 91, 154, 76 }, material = "SmoothPlastic", offset = { 2.095, 14.616, 1.127 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://864891559", textureId = "", meshSize = { 0.915, 0.888, 0.792 }, size = { 2.051, 1.992, 1.777 }, color = { 86, 66, 54 }, material = "SmoothPlastic", offset = { 2.005, 15.984, 1.599 }, rot = { 0, 0, 0 } },
				},
			},
		},

		treePine = {
			-- asset 5616880673 "Tree"
			{
				sourceAssetId = 5616880673, creator = "smartycar23", rootName = "Tree", height = 45.092,
				parts = {
					{ meshId = "rbxassetid://2919523288", textureId = "", meshSize = { 50, 44.183, 50 }, size = { 25.129, 39.609, 25.129 }, color = { 31, 128, 29 }, material = "SmoothPlastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://2919522588", textureId = "", meshSize = { 40.911, 50, 40.911 }, size = { 9.869, 12.062, 9.869 }, color = { 106, 57, 9 }, material = "SmoothPlastic", offset = { 0, -19.256, 0 }, rot = { 0, 0, 0 } },
				},
			},
			-- asset 12605122162 "RedwoodTree-Var01"
			{
				sourceAssetId = 12605122162, creator = "MichaelAngelist", rootName = "RedwoodTree-Var01", height = 104.773,
				parts = {
					{ meshId = "rbxassetid://5804646885", textureId = "", meshSize = { 84.519, 159.256, 82.294 }, size = { 44.098, 83.093, 42.937 }, color = { 163, 162, 165 }, material = "Plastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://5804648905", textureId = "", meshSize = { 84.374, 186.161, 76.14 }, size = { 44.023, 97.13, 39.726 }, color = { 163, 162, 165 }, material = "Plastic", offset = { -0.038, -14.662, 1.607 }, rot = { 0, 0, 0 } },
				},
			},
		},

		rock = {
			-- rock_pack 2128776869, 10 rocks -- one part each.
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock7", height = 6.386, parts = { { meshId = "rbxassetid://2128761993", textureId = "", meshSize = { 191.273, 201.763, 184.567 }, size = { 6.054, 6.386, 5.842 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock1", height = 7.058, parts = { { meshId = "rbxassetid://2128766734", textureId = "", meshSize = { 184.915, 222.988, 158.861 }, size = { 5.853, 7.058, 5.028 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { -5.58, 0.09, 5.341 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock5", height = 4.92, parts = { { meshId = "rbxassetid://2128759273", textureId = "", meshSize = { 140.002, 155.427, 145.358 }, size = { 4.431, 4.92, 4.601 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 19.214, 0.42, 5.885 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock8", height = 3.914, parts = { { meshId = "rbxassetid://2128764023", textureId = "", meshSize = { 178.239, 123.664, 193.074 }, size = { 5.642, 3.914, 6.111 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 6.598, 0.324, 0.093 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock4", height = 4.953, parts = { { meshId = "rbxassetid://2128758599", textureId = "", meshSize = { 156.519, 156.467, 136.799 }, size = { 4.954, 4.953, 4.33 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 13.831, 0.351, 5.755 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock3", height = 7.143, parts = { { meshId = "rbxassetid://2128758133", textureId = "", meshSize = { 217.167, 225.67, 120.978 }, size = { 6.874, 7.143, 3.829 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 7.102, 0.589, 6.094 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock9", height = 6.314, parts = { { meshId = "rbxassetid://2128764428", textureId = "", meshSize = { 179.997, 199.489, 208.225 }, size = { 5.697, 6.314, 6.591 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 13.249, 0.076, -0.923 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock10", height = 4.398, parts = { { meshId = "rbxassetid://2128764803", textureId = "", meshSize = { 170.629, 138.953, 168.477 }, size = { 5.401, 4.398, 5.333 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 19.257, -0.061, -0.242 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock6", height = 6.016, parts = { { meshId = "rbxassetid://2128760908", textureId = "", meshSize = { 184.908, 190.046, 188.78 }, size = { 5.853, 6.016, 5.975 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { -6.753, -0.365, -0.679 }, rot = { 0, 0, 0 } } } },
			{ sourceAssetId = 2128776869, creator = "FracturedSkies", rootName = "Rock2", height = 5.848, parts = { { meshId = "rbxassetid://2128754279", textureId = "", meshSize = { 157.823, 184.747, 151.796 }, size = { 4.996, 5.848, 4.805 }, color = { 149, 153, 172 }, material = "SmoothPlastic", offset = { 0.634, 0.383, 6.317 }, rot = { 0, 0, 0 } } } },
			-- nature_pack "Small Low-Poly Rock" DROPPED: height 0.963 < the [2,200] sanity floor (see header note).
		},

		bush = {
			-- nature_pack "Low Poly bush"
			{ sourceAssetId = 9682467046, creator = "Proudism", rootName = "Low Poly bush", height = 2.205, parts = { { meshId = "rbxassetid://9299837325", textureId = "", meshSize = { 207.17, 173.058, 246.568 }, size = { 3.17, 2.205, 3.733 }, color = { 91, 154, 76 }, material = "Plastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } } } },
			-- nature_pack "Bush"
			{
				sourceAssetId = 9682467046, creator = "Proudism", rootName = "Bush", height = 7.057,
				parts = {
					{ meshId = "rbxassetid://5214312176", textureId = "", meshSize = { 695.171, 595.928, 590.824 }, size = { 3.449, 3.318, 2.932 }, color = { 75, 151, 75 }, material = "SmoothPlastic", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } },
					{ meshId = "rbxassetid://5214312176", textureId = "", meshSize = { 695.171, 595.928, 590.824 }, size = { 5.088, 4.362, 4.325 }, color = { 75, 151, 75 }, material = "SmoothPlastic", offset = { -1.046, 1.827, 1.687 }, rot = { 51.757, 7.364, 105.113 } },
					{ meshId = "rbxassetid://5214312176", textureId = "", meshSize = { 695.171, 595.928, 590.824 }, size = { 3.449, 3.318, 2.932 }, color = { 75, 151, 75 }, material = "SmoothPlastic", offset = { -0.823, 3.739, 1.607 }, rot = { -36.742, 26.064, 28.553 } },
				},
			},
		},

		-- flower: "(Editable) Low Poly Mushrooms" DROPPED: height 1.653 < the [2,200] sanity floor
		-- (see header note). No flower variants this session; not spec-required.

		log = {
			-- nature_pack "Log"
			{ sourceAssetId = 9682467046, creator = "Proudism", rootName = "Log", height = 3.012, parts = { { meshId = "rbxassetid://6349136797", textureId = "", meshSize = { 50, 17.243, 18.369 }, size = { 8.733, 3.012, 3.208 }, color = { 160, 95, 53 }, material = "Concrete", offset = { 0, 0, 0 }, rot = { 0, 0, 0 } } } },
		},
	},
}
