-- ReturnPool specs. `lune run tests/run`

local Loader = require("./loader")
local ReturnPool = Loader.get("ReturnPool")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end
local function ref(fields)
	return {
		last = fields.last or false,
		name = fields.name,
		index = fields.index,
		path = fields.path or {},
	}
end

return function(t)
	local test = t.test

	test("push and // reads the most recent", function()
		local pool = ReturnPool.new()
		pool:push(1, "Number")
		pool:push(2, "Number")
		eq((pool:resolve(ref({ last = true }))), 2, "// is the newest")
		eq((pool:resolve(ref({ last = true, index = 2 }))), 1, "//#2 is one back")
	end)

	test("/Type resolves by type, newest first", function()
		local pool = ReturnPool.new()
		pool:push("a", "String")
		pool:push(7, "Number")
		pool:push("b", "String")
		eq((pool:resolve(ref({ name = "String" }))), "b", "newest String")
		eq((pool:resolve(ref({ name = "String", index = 2 }))), "a", "second String")
		eq((pool:resolve(ref({ name = "Number" }))), 7, "the Number")
	end)

	test("/label beats /type on a name clash", function()
		local pool = ReturnPool.new()
		pool:push("byType", "target")             -- a value whose *type* is 'target'
		pool:push("byLabel", "Player", "target")  -- a value *labelled* 'target'
		eq((pool:resolve(ref({ name = "target" }))), "byLabel", "label wins")
	end)

	test(".path drills into the value", function()
		local pool = ReturnPool.new()
		pool:push({ health = { current = 42 } }, "Status")
		eq((pool:resolve(ref({ last = true, path = { "health", "current" } }))), 42, "nested path")
	end)

	test("missing return yields an error message", function()
		local pool = ReturnPool.new()
		local value, err = pool:resolve(ref({ name = "Player" }))
		eq(value, nil, "no value")
		eq(err ~= nil, true, "has an error")
	end)

	test("bad property access errors instead of throwing", function()
		local pool = ReturnPool.new()
		pool:push(5, "Number")
		local value, err = pool:resolve(ref({ last = true, path = { "nope" } }))
		-- indexing a number with a missing key is nil, not an error; go one deeper
		local value2, err2 = pool:resolve(ref({ last = true, path = { "nope", "deeper" } }))
		eq(value2, nil, "no value")
		eq(err2 ~= nil, true, "reading a key of nil is a clean error")
	end)

	test("clear empties the pool", function()
		local pool = ReturnPool.new()
		pool:push(1, "Number")
		pool:clear()
		eq(pool:last(), nil, "empty after clear")
	end)
end
