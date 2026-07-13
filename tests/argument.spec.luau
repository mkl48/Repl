-- Args-DSL parser specs. `lune run tests/run`

local Loader = require("./loader")
local Argument = Loader.get("Argument")

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

	test("a plain 'name: Type' entry", function()
		local spec = Argument.parse("amount: Integer")
		eq(spec.name, "amount")
		eq(spec.typeExpr, "Integer")
		eq(spec.optional, false, "required")
		eq(spec.hasDefault, false, "no default")
		eq(spec.error, nil, "no error")
	end)

	test("trailing ? makes it optional", function()
		local spec = Argument.parse("amount: Integer?")
		eq(spec.optional, true, "optional via ?")
		eq(spec.hasDefault, false, "still no default")
	end)

	test("a default value implies optional and is validated", function()
		local spec = Argument.parse("amount: Integer? = 1")
		eq(spec.name, "amount")
		eq(spec.typeExpr, "Integer?", "type strips the default")
		eq(spec.default, "1", "raw default text")
		eq(spec.hasDefault, true)
		eq(spec.optional, true)
		eq(spec.error, nil, "1 is a valid Integer")
	end)

	test("an invalid default is reported", function()
		local spec = Argument.parse("amount: Integer = notanumber")
		ok(spec.error ~= nil, "default fails the type")
	end)

	test("the default '=' is not confused with >= inside a range", function()
		local spec = Argument.parse("n: Integer >= 0")
		eq(spec.typeExpr, "Integer >= 0", "the whole range is the type")
		eq(spec.hasDefault, false, "no default here")
		eq(spec.error, nil)
	end)

	test("a range type with a real default", function()
		local spec = Argument.parse("n: 2 < Integer < 30 = 5")
		eq(spec.typeExpr, "2 < Integer < 30", "type keeps both bounds")
		eq(spec.default, "5", "default separated correctly")
		eq(spec.error, nil, "5 is inside the range")
	end)

	test("a default outside the range is rejected", function()
		local spec = Argument.parse("n: 2 < Integer < 30 = 99")
		ok(spec.error ~= nil, "99 is out of range")
	end)

	test("a malformed entry reports an error", function()
		local spec = Argument.parse("justaname")
		ok(spec.error ~= nil, "no colon/type")
		eq(spec.name, "justaname", "still recovers the name")
	end)

	test("parseList collects errors", function()
		local specs, errors = Argument.parseList({ "a: Integer", "b: Boolean" })
		eq(#specs, 2, "two specs")
		eq(#errors, 0, "all valid")
	end)

	test("a required arg cannot follow an optional one", function()
		local _, errors = Argument.parseList({ "a: Integer?", "b: Integer" })
		ok(#errors > 0, "flags the ordering")
	end)

	test("a description is parsed off the '# …' suffix", function()
		local spec = Argument.parse("name: String # the display name")
		eq(spec.typeExpr, "String", "type doesn't include the note")
		eq(spec.description, "the display name")
	end)

	test("a bare --flag is an optional boolean defaulting false", function()
		local spec = Argument.parse("--force")
		eq(spec.isFlag, true, "a flag")
		eq(spec.isBoolean, true, "boolean")
		eq(spec.name, "force", "canonical name")
		eq(spec.optional, true, "flags are optional")
		eq(spec.default, "false", "defaults to false")
	end)

	test("a flag with short + long aliases", function()
		local spec = Argument.parse("-f, --force")
		eq(#spec.names, 2, "two aliases")
		eq(spec.names[1], "f")
		eq(spec.names[2], "force")
		eq(spec.name, "force", "the long name is canonical")
	end)

	test("a valued option (--count: Integer = 1)", function()
		local spec = Argument.parse("--count: Integer = 1 # how many")
		eq(spec.isFlag, true)
		eq(spec.isBoolean, false, "takes a value")
		eq(spec.name, "count")
		eq(spec.default, "1")
		eq(spec.description, "how many")
	end)

	test("a positional carries no flag markers", function()
		local spec = Argument.parse("a: Integer")
		eq(spec.isFlag, false)
		eq(#spec.names, 0)
	end)
end
