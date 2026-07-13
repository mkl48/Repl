-- Signal specs. `lune run tests/run`

local Loader = require("./loader")
local Signal = Loader.get("Signal")

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

	test("connect and fire", function()
		local s = Signal.new()
		local got
		s:Connect(function(x)
			got = x
		end)
		s:Fire(42)
		eq(got, 42, "handler ran with the arg")
	end)

	test("multiple handlers all fire", function()
		local s = Signal.new()
		local sum = 0
		s:Connect(function(n)
			sum += n
		end)
		s:Connect(function(n)
			sum += n * 10
		end)
		s:Fire(1)
		eq(sum, 11, "both fired")
	end)

	test("disconnect stops a handler", function()
		local s = Signal.new()
		local count = 0
		local c = s:Connect(function()
			count += 1
		end)
		s:Fire()
		c:Disconnect()
		s:Fire()
		eq(count, 1, "only the first fire counted")
		eq(c.Connected, false, "marked disconnected")
	end)

	test("Once fires exactly once", function()
		local s = Signal.new()
		local count = 0
		s:Once(function()
			count += 1
		end)
		s:Fire()
		s:Fire()
		eq(count, 1, "one fire only")
	end)

	test("disconnecting during a fire is safe", function()
		local s = Signal.new()
		local order = {}
		local a
		a = s:Connect(function()
			table.insert(order, "a")
			a:Disconnect()
		end)
		s:Connect(function()
			table.insert(order, "b")
		end)
		s:Fire()
		eq(table.concat(order, ","), "a,b", "both ran this dispatch despite the disconnect")
		s:Fire()
		eq(table.concat(order, ","), "a,b,b", "a gone next time")
	end)

	test("DisconnectAll clears handlers", function()
		local s = Signal.new()
		local count = 0
		s:Connect(function()
			count += 1
		end)
		s:DisconnectAll()
		s:Fire()
		eq(count, 0, "nothing fired")
	end)
end
