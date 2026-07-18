--!nonstrict
--[[
	tests/_harness.luau — tiny exit-code-gated test harness for the Lune Tier-4 suite.

	Specs register cases with H.test(name, fn); tests/run.luau requires every *.spec
	(registration is a side effect of require) then calls H.run(), which pcalls each
	case and returns the failure count for process.exit. An assertion helper that fails
	`error()`s with level 2 so the message points at the spec line.

	Kept deliberately minimal — no describe/BDD sugar; the goal is a machine gate,
	not a framework.
]]

local tests = {}
local H = {}

function H.test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

function H.run()
	local pass, fail = 0, 0
	for _, t in ipairs(tests) do
		local ok, err = pcall(t.fn)
		if ok then
			pass += 1
			print(("  PASS  %s"):format(t.name))
		else
			fail += 1
			print(("  FAIL  %s\n        %s"):format(t.name, tostring(err)))
		end
	end
	print(("\n%d passed, %d failed"):format(pass, fail))
	return fail
end

-- ---- assertion helpers (all error at level 2 so the spec line is blamed) ----

function H.ok(cond, msg)
	if not cond then
		error(msg or "expected truthy", 2)
	end
end

function H.eq(a, b, msg)
	if a ~= b then
		error(("%s: expected %s, got %s"):format(msg or "eq", tostring(b), tostring(a)), 2)
	end
end

function H.approx(a, b, tol, msg)
	tol = tol or 1e-4
	if type(a) ~= "number" or type(b) ~= "number" or math.abs(a - b) > tol then
		error(("%s: |%s - %s| > %s"):format(msg or "approx", tostring(a), tostring(b), tostring(tol)), 2)
	end
end

-- A single number is finite (not NaN, not +/-inf).
function H.finite(x, msg)
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		error(("%s: not finite (%s)"):format(msg or "finite", tostring(x)), 2)
	end
end

-- Every component of a Vector3 is finite.
function H.finiteVec(v, msg)
	msg = msg or "finiteVec"
	H.finite(v.X, msg .. ".X")
	H.finite(v.Y, msg .. ".Y")
	H.finite(v.Z, msg .. ".Z")
end

-- a is within [lo, hi] inclusive.
function H.between(a, lo, hi, msg)
	if type(a) ~= "number" or a < lo or a > hi then
		error(("%s: %s not in [%s, %s]"):format(msg or "between", tostring(a), tostring(lo), tostring(hi)), 2)
	end
end

return H
