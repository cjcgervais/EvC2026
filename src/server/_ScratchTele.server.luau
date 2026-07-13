--!nonstrict
-- ==== SCRATCH TELEMETRY RELAY (Wind Tunnel capture — DELETE after; non-committed) ====
-- HttpService is server-only, so the client scratch block in BirdController fires the CSV here and
-- this relays it to the local capture server (flight_sim/harness/capture_server.luau on :8080).
-- Revert with:  git checkout src/server/_ScratchTele.server.luau  (and remove the default.project.json mapping)
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "_ScratchTele"
remote.Parent = RS

remote.OnServerEvent:Connect(function(_player, name, body)
	name = tostring(name):gsub("[^%w%-_.]", "_")
	local ok, err = pcall(function()
		HttpService:PostAsync("http://localhost:8080/" .. name, tostring(body), Enum.HttpContentType.TextPlain)
	end)
	print("[EvC scratch server] POST " .. name .. (ok and " OK" or (" FAIL: " .. tostring(err))))
end)

print("[EvC scratch server] ready — _ScratchTele relay live")
