-- EventBus specs. `lune run tests/run`

local Loader = require("./loader")
local EventBus = Loader.get("EventBus")

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

	test("subscribe then post delivers", function()
		local bus = EventBus.new()
		local got
		bus:subscribe("ping", function(x)
			got = x
		end)
		bus:post("ping", 42)
		eq(got, 42, "handler received the post")
	end)

	test("a late subscriber still receives earlier posts (replay)", function()
		local bus = EventBus.new()
		bus:post("data", "a")
		bus:post("data", "b")
		local seen = {}
		bus:subscribe("data", function(v)
			table.insert(seen, v)
		end)
		eq(table.concat(seen, ","), "a,b", "queued posts replayed in order")
	end)

	test("each subscriber sees each post exactly once", function()
		local bus = EventBus.new()
		local count = 0
		bus:subscribe("e", function()
			count += 1
		end)
		bus:post("e") -- delivered live
		local lateCount = 0
		bus:subscribe("e", function()
			lateCount += 1
		end)
		bus:post("e") -- delivered to both
		eq(count, 2, "first sub: two live posts")
		eq(lateCount, 2, "late sub: first via replay + second live, each once (no dup)")
	end)

	test("multiple posts interleave in call order (both sides post)", function()
		local bus = EventBus.new()
		local log = {}
		bus:subscribe("chan", function(v)
			table.insert(log, v)
		end)
		bus:post("chan", "server:1")
		bus:post("chan", "client:1")
		bus:post("chan", "server:2")
		eq(table.concat(log, ","), "server:1,client:1,server:2", "order preserved")
	end)

	test("disconnect stops delivery", function()
		local bus = EventBus.new()
		local count = 0
		local c = bus:subscribe("e", function()
			count += 1
		end)
		bus:post("e")
		c:Disconnect()
		bus:post("e")
		eq(count, 1, "no delivery after disconnect")
		eq(c.Connected, false, "marked disconnected")
	end)

	test("once fires a single time", function()
		local bus = EventBus.new()
		local count = 0
		bus:once("e", function()
			count += 1
		end)
		bus:post("e")
		bus:post("e")
		eq(count, 1, "one delivery")
	end)

	test("clear drops retained posts", function()
		local bus = EventBus.new()
		bus:post("e", "x")
		bus:clear("e")
		local seen = false
		bus:subscribe("e", function()
			seen = true
		end)
		ok(not seen, "nothing replayed after clear")
	end)

	test("carries multiple + nil arguments", function()
		local bus = EventBus.new()
		local a, b, c
		bus:subscribe("multi", function(x, y, z)
			a, b, c = x, y, z
		end)
		bus:post("multi", 1, nil, 3)
		eq(a, 1)
		eq(b, nil, "nil preserved in the middle")
		eq(c, 3)
	end)
end
