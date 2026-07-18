--!nonstrict
--[[
	tests/run.luau — Tier-4 entry point (verify.ps1 runs `lune run tests/run.luau`).

	Discovers every `*.spec.luau` in tests/, requires it (registration is a require
	side effect via _harness), runs the aggregate suite, and exits non-zero on any
	failure so the ladder gates on it. Add a spec file and it is picked up automatically.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("./_harness")

local specs = {}
for _, entry in ipairs(fs.readDir("tests")) do
	if entry:match("%.spec%.luau$") then
		table.insert(specs, entry)
	end
end
table.sort(specs)

print(("Lune Tier-4 suite: %d spec file(s)\n"):format(#specs))
for _, name in ipairs(specs) do
	print("• " .. name)
	require("./" .. name:gsub("%.luau$", ""))
end

print("")
local fails = H.run()
if fails > 0 then
	print(("\nTIER 4: %d test(s) FAILED."):format(fails))
	process.exit(1)
end
print("\nTIER 4: green.")
process.exit(0)
