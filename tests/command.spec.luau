-- Command-definition validation specs. `lune run tests/run`

local Loader = require("./loader")
local Command = Loader.get("Command")

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

	test("a well-formed command parses", function()
		local result = Command.parse({
			Name = "kill",
			Aliases = { "slay" },
			Description = "Kill a player.",
			Capabilities = { "players.kill" },
			Args = { "amount: Integer? = 1" },
			Run = noop,
		})
		eq(#result.errors, 0, "no errors")
		ok(result.command ~= nil, "a command")
		eq(result.command.name, "kill")
		eq(result.command.aliases[1], "slay")
		eq(#result.command.args, 1, "one arg")
		eq(result.command.args[1].name, "amount")
	end)

	test("a missing Name is rejected", function()
		local result = Command.parse({ Run = noop })
		ok(result.command == nil, "no command")
		ok(#result.errors > 0, "reports the missing name")
	end)

	test("a missing Run is rejected", function()
		local result = Command.parse({ Name = "noop" })
		ok(result.command == nil, "no command")
	end)

	test("an invalid alias is caught", function()
		local result = Command.parse({ Name = "ok", Aliases = { "bad alias!" }, Run = noop })
		ok(result.command == nil, "rejected")
	end)

	test("a bad Args entry surfaces its error", function()
		local result = Command.parse({ Name = "x", Args = { "amount: Integer = notnum" }, Run = noop })
		ok(result.command == nil, "rejected")
		ok(#result.errors > 0, "arg error bubbles up")
	end)

	test("defaults fill in for the optional fields", function()
		local result = Command.parse({ Name = "ping", Run = noop })
		eq(result.command.description, "", "empty description")
		eq(#result.command.aliases, 0, "no aliases")
		eq(#result.command.capabilities, 0, "no capabilities")
	end)
end
