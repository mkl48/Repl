-- History specs. `lune run tests/run`

local Loader = require("./loader")
local History = Loader.get("History")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end

return function(t)
	local test = t.test

	local function seeded()
		local h = History.new()
		h:add("a")
		h:add("b")
		h:add("c")
		return h
	end

	test("up walks from newest to oldest and clamps", function()
		local h = seeded()
		eq(h:up(""), "c", "first up = newest")
		eq(h:up(""), "b")
		eq(h:up(""), "a")
		eq(h:up(""), "a", "clamps at the oldest")
	end)

	test("down walks back toward the live line", function()
		local h = seeded()
		h:up("")
		h:up("") -- at 'b'
		eq(h:down(), "c", "newer")
		eq(h:down(), "", "past the newest -> the (empty) draft")
	end)

	test("down without navigating returns nil", function()
		local h = seeded()
		eq(h:down(), nil, "not navigating")
	end)

	test("the in-progress line is preserved as a draft", function()
		local h = seeded()
		eq(h:up("half-typed"), "c", "up shows history")
		eq(h:down(), "half-typed", "down restores the draft")
	end)

	test("consecutive duplicates are collapsed", function()
		local h = History.new()
		h:add("same")
		h:add("same")
		eq(#h:all(), 1, "only one entry")
	end)

	test("a non-consecutive repeat is kept", function()
		local h = History.new()
		h:add("a")
		h:add("b")
		h:add("a")
		eq(#h:all(), 3, "a, b, a")
	end)

	test("blank lines are ignored", function()
		local h = History.new()
		h:add("   ")
		h:add("")
		eq(#h:all(), 0, "nothing recorded")
	end)

	test("the limit evicts the oldest", function()
		local h = History.new(2)
		h:add("a")
		h:add("b")
		h:add("c")
		local all = h:all()
		eq(#all, 2, "capped")
		eq(all[1], "b", "oldest dropped")
		eq(all[2], "c")
	end)

	test("add resets an in-progress navigation", function()
		local h = seeded()
		h:up("")
		h:add("d")
		eq(h:down(), nil, "navigation reset after add")
		eq(h:up(""), "d", "newest is the just-added entry")
	end)
end
