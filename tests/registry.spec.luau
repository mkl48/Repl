-- Registry specs. `lune run tests/run`

local Loader = require("./loader")
local Registry = Loader.get("Registry")

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
local function noop() end

return function(t)
	local test = t.test

	test("register then resolve by name and alias", function()
		local reg = Registry.new()
		local command, errors = reg:register({ Name = "kill", Aliases = { "slay" }, Run = noop })
		eq(#errors, 0, "no errors")
		ok(command ~= nil, "returned the command")
		ok(reg:resolve("kill") ~= nil, "by name")
		ok(reg:resolve("slay") ~= nil, "by alias")
		ok(reg:resolve("KILL") ~= nil, "case-insensitive")
		ok(reg:resolve("missing") == nil, "unknown is nil")
	end)

	test("a name collision is rejected", function()
		local reg = Registry.new()
		reg:register({ Name = "kill", Run = noop })
		local command, errors = reg:register({ Name = "kill", Run = noop })
		ok(command == nil, "second not registered")
		ok(#errors > 0, "reports the clash")
	end)

	test("an alias that clashes with an existing name is rejected", function()
		local reg = Registry.new()
		reg:register({ Name = "kill", Run = noop })
		local command, errors = reg:register({ Name = "murder", Aliases = { "kill" }, Run = noop })
		ok(command == nil, "rejected")
		ok(#errors > 0, "alias clash reported")
	end)

	test("a rejected command leaves the registry unchanged", function()
		local reg = Registry.new()
		reg:register({ Name = "kill", Run = noop })
		reg:register({ Name = "kill", Aliases = { "x" }, Run = noop }) -- clashes
		ok(reg:resolve("x") == nil, "the failed alias was not indexed")
		eq(#reg:all(), 1, "still just one command")
	end)

	test("all() lists in registration order", function()
		local reg = Registry.new()
		reg:register({ Name = "first", Run = noop })
		reg:register({ Name = "second", Run = noop })
		local list = reg:all()
		eq(list[1].name, "first")
		eq(list[2].name, "second")
	end)

	test("hooks fire in order with their args", function()
		local reg = Registry.new()
		local log = {}
		reg:on("before", function(x)
			table.insert(log, "b:" .. x)
		end)
		reg:on("before", function(x)
			table.insert(log, "b2:" .. x)
		end)
		reg:on("after", function(x)
			table.insert(log, "a:" .. x)
		end)
		reg:fire("before", "go")
		reg:fire("after", "done")
		eq(table.concat(log, ","), "b:go,b2:go,a:done", "order + payload preserved")
	end)
end
