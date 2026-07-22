--!nonstrict
-- ==== SCRATCH TELEMETRY RELAY (Wind Tunnel capture) ====
-- ⚠️ S44 AUDIT: this header used to claim "DELETE after; non-committed". It IS committed and IS
-- Rojo-mapped into ServerScriptService, so that claim was false and self-concealing. What it actually
-- is: a dev backdoor that exposes a client-fireable RemoteEvent and POSTs client-supplied bodies to
-- localhost:8080. Harmless while HttpEnabled is off, but it should be a deliberate keep, not a
-- forgotten one. CHAD'S CALL: delete this file + its default.project.json mapping + the F8/F9/F10
-- capture block in BirdController, or keep it and drop this warning.
-- HttpService is server-only, so the client scratch block in BirdController fires the CSV here and
-- this relays it to the local capture server (flight_sim/harness/capture_server.luau on :8080).
-- Revert with:  git checkout src/server/_ScratchTele.server.luau  (and remove the default.project.json mapping)
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "_ScratchTele"
remote.Parent = RS

remote.OnServerEvent:Connect(function(_player, name, body)
	-- Stage 7 strike telemetry uses print() (no HTTP). The F9/F10 CSV export needs HttpEnabled + a
	-- local Lune capture server; if HTTP is off, bail QUIETLY so it can't spam the Output that the
	-- strike-telemetry capture is reading. (Turn HttpEnabled on only if you actually want the CSV.)
	if not HttpService.HttpEnabled then
		print("[EvC scratch server] HTTP disabled — F9/F10 CSV export skipped (Stage 7 telemetry is print-only).")
		return
	end
	name = tostring(name):gsub("[^%w%-_.]", "_")
	local ok, err = pcall(function()
		HttpService:PostAsync("http://localhost:8080/" .. name, tostring(body), Enum.HttpContentType.TextPlain)
	end)
	print("[EvC scratch server] POST " .. name .. (ok and " OK" or (" FAIL: " .. tostring(err))))
end)

print("[EvC scratch server] ready — _ScratchTele relay live")
