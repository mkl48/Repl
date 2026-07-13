-- Type-engine specs (compile → transform / validate / autocomplete).
-- `lune run tests/run`

local Loader = require("./loader")
local Types = Loader.get("Types")

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
local function has(list, value)
	for _, item in list do
		if item == value then
			return true
		end
	end
	return false
end

return function(t)
	local test = t.test

	test("Number transforms text and rejects non-numbers", function()
		local ty = Types.compile("Number")
		eq((ty.transform("42")), 42, "'42' -> 42")
		local v, err = ty.transform("nope")
		eq(v, nil, "no value")
		ok(err ~= nil, "reports an error")
		ok(ty.validate(3.5), "3.5 is a number")
		ok(not ty.validate("x"), "a string is not")
	end)

	test("Integer rejects fractional input", function()
		local ty = Types.compile("Integer")
		eq((ty.transform("7")), 7, "'7' -> 7")
		local v = ty.transform("7.5")
		eq(v, nil, "7.5 is not an integer")
	end)

	test("Boolean parses words and autocompletes", function()
		local ty = Types.compile("Boolean")
		eq((ty.transform("yes")), true, "'yes' -> true")
		eq((ty.transform("0")), false, "'0' -> false")
		ok(has(ty.autocomplete(""), "true"), "suggests true")
		ok(has(ty.autocomplete("f"), "false"), "prefix 'f' -> false")
		ok(not has(ty.autocomplete("f"), "true"), "prefix 'f' excludes true")
	end)

	test("a bounded integer range enumerates its values", function()
		local ty = Types.compile("2 < Integer < 6")
		local suggestions = ty.autocomplete("")
		eq(#suggestions, 3, "3, 4, 5")
		ok(has(suggestions, "3") and has(suggestions, "5"), "includes ends")
		ok(not has(suggestions, "2") and not has(suggestions, "6"), "excludes exclusive bounds")
	end)

	test("range validation enforces the bounds", function()
		local ty = Types.compile("2 < Number < 30")
		ok(ty.validate(15), "15 is inside")
		ok(not ty.validate(2), "2 is excluded")
		ok(not ty.validate(30), "30 is excluded")
		ok(not ty.validate(100), "100 is outside")
	end)

	test("inclusive range boundaries", function()
		local ty = Types.compile("Integer >= 0")
		ok(ty.validate(0), "0 is allowed")
		ok(not ty.validate(-1), "-1 is not")
		eq(#ty.autocomplete(""), 0, "an unbounded range does not enumerate")
	end)

	test("a union validates either member and merges completions", function()
		local ty = Types.compile("Boolean | Integer")
		ok(ty.validate(true), "boolean ok")
		ok(ty.validate(5), "integer ok")
		ok(not ty.validate("x"), "string rejected")
		eq((ty.transform("true")), true, "reads a boolean")
		eq((ty.transform("9")), 9, "reads an integer")
	end)

	test("an intersection stacks constraints", function()
		local ty = Types.compile("Number & Integer")
		ok(ty.validate(4), "4 is a whole number")
		ok(not ty.validate(4.5), "4.5 fails the integer part")
	end)

	test("range over a union member still enumerates", function()
		local ty = Types.compile("0 <= Integer <= 3")
		local suggestions = ty.autocomplete("")
		eq(#suggestions, 4, "0,1,2,3")
	end)

	test("an unregistered name is a literal value", function()
		local ty = Types.compile("gruvbox")
		ok(ty.validate("gruvbox"), "matches itself")
		ok(not ty.validate("nord"), "rejects other values")
		eq((ty.transform("gruvbox")), "gruvbox", "transforms to the literal")
		local _, err = ty.transform("x")
		ok(err ~= nil, "a different word errors")
		ok(has(ty.autocomplete(""), "gruvbox"), "autocompletes itself")
	end)

	test("a union of literals is an enum", function()
		local ty = Types.compile("gruvbox | tokyonight | nord")
		ok(ty.validate("tokyonight"), "any member is valid")
		ok(not ty.validate("dracula"), "a non-member is not")
		local all = ty.autocomplete("")
		eq(#all, 3, "all three suggested")
		local narrowed = ty.autocomplete("gr")
		eq(#narrowed, 1, "prefix narrows")
		eq(narrowed[1], "gruvbox")
	end)

	test("registered types still win over literals", function()
		local ty = Types.compile("Integer | tokyonight")
		ok(ty.validate(5), "Integer member")
		ok(ty.validate("tokyonight"), "literal member")
		ok(not ty.validate("gruvbox"), "unlisted literal rejected")
	end)

	test("optional is carried from the expression", function()
		eq(Types.compile("Integer?").optional, true, "optional flagged")
		eq(Types.compile("Integer").optional, false, "not optional")
	end)
end
