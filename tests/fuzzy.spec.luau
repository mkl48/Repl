-- Fuzzy matcher specs. `lune run tests/run`

local Loader = require("./loader")
local Fuzzy = Loader.get("Fuzzy")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end
local function ok(cond, message)
	if not cond then
		error(message or "expected truthy", 2)
	end
end

return function(t)
	local test = t.test

	test("a subsequence matches and reports positions", function()
		local score, positions = Fuzzy.match("kil", "kill")
		ok(score ~= nil, "matched")
		eq(table.concat(positions, ","), "1,2,3", "positions in order")
	end)

	test("a non-subsequence does not match", function()
		local score = Fuzzy.match("xyz", "kill")
		eq(score, nil, "no match")
	end)

	test("wrong order does not match", function()
		-- 'k' then 'p': after the k in 'kill' there is no p
		eq((Fuzzy.match("kp", "players.kill")), nil, "kp fails")
		ok(Fuzzy.match("pk", "players.kill") ~= nil, "pk matches across the dot")
	end)

	test("an empty query matches everything at score 0", function()
		local score, positions = Fuzzy.match("", "anything")
		eq(score, 0, "zero score")
		eq(#positions, 0, "no positions")
	end)

	test("case-insensitive", function()
		ok(Fuzzy.match("KIL", "kill") ~= nil, "upper query")
		ok(Fuzzy.match("kil", "KILL") ~= nil, "upper candidate")
	end)

	test("a start match outscores a mid-word match", function()
		local startScore = Fuzzy.match("kil", "kill")
		local midScore = Fuzzy.match("kil", "skill")
		ok(startScore > midScore, "start beats middle")
	end)

	test("a boundary match outscores a buried one", function()
		-- 'k' at a word boundary (after '.') vs buried inside a word
		local boundary = Fuzzy.match("k", "a.kill")
		local buried = Fuzzy.match("k", "asked")
		ok(boundary > buried, "boundary beats buried")
	end)

	test("filter ranks best first and drops non-matches", function()
		local results = Fuzzy.filter("kil", { "kill", "skill", "killer", "milk", "teleport" })
		eq(results[1].value, "kill", "exact-ish start wins")
		for _, r in results do
			ok(r.value ~= "milk", "milk (no subsequence) dropped")
			ok(r.value ~= "teleport", "teleport dropped")
		end
	end)

	test("consecutive runs score higher than scattered", function()
		local run = Fuzzy.match("abc", "abcxyz")
		local scattered = Fuzzy.match("abc", "axbxc")
		ok(run > scattered, "consecutive beats scattered")
	end)
end
