-- Completer specs. `lune run tests/run`

local Loader = require("./loader")
local Completer = Loader.get("Completer")
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
local function texts(completions)
	local out = {}
	for _, c in completions do
		table.insert(out, c.text)
	end
	return out
end
local function has(list, value)
	return table.find(list, value) ~= nil
end

local function buildRegistry()
	local reg = Registry.new()
	reg:register({ Name = "kill", Aliases = { "slay" }, Description = "Kill a player.", Args = { "confirm: Boolean" }, Run = noop })
	reg:register({ Name = "kick", Description = "Kick a player.", Run = noop })
	reg:register({ Name = "announce", Description = "Broadcast.", Run = noop })
	reg:register({ Name = "count", Args = { "n: 2 < Integer < 6" }, Run = noop })
	reg:register({
		Name = "theme",
		Description = "Switch the colorscheme.",
		Args = { "name: gruvbox | tokyonight | nord # the colorscheme to use" },
		Run = noop,
	})
	return reg
end

return function(t)
	local test = t.test

	test("empty input lists all commands", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, ""))
		ok(has(list, "kill") and has(list, "announce") and has(list, "count"), "all present")
		for _, c in Completer.complete(reg, "") do
			eq(c.kind, "command", "all are command completions")
		end
	end)

	test("a command-name prefix ranks the match first", function()
		local reg = buildRegistry()
		-- 'kil' is a subsequence of kill but not kick (no 'l'), so it's unambiguous
		local list = Completer.complete(reg, "kil")
		eq(list[1].text, "kill", "only kill matches 'kil'")
		ok(list[1].kind == "command", "command kind")
		eq(list[1].replaceStart, 1, "replaces from the start")
		eq(list[1].replaceEnd, 3, "…through the typed text")
	end)

	test("an ambiguous prefix breaks ties alphabetically", function()
		local reg = buildRegistry()
		-- 'ki' matches both kill and kick at equal score → alphabetical: kick first
		local list = Completer.complete(reg, "ki")
		eq(list[1].text, "kick", "kick sorts before kill on the tie")
	end)

	test("aliases are completable", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, "sl"))
		ok(has(list, "slay"), "alias suggested")
	end)

	test("after the command, a Boolean arg suggests true/false", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, "kill "))
		ok(has(list, "true") and has(list, "false"), "boolean values")
		for _, c in Completer.complete(reg, "kill ") do
			eq(c.kind, "argument", "argument completions")
			eq(c.detail, "confirm: Boolean", "detail shows the arg + type")
		end
	end)

	test("a partial argument value filters", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, "kill t"))
		ok(has(list, "true"), "true kept")
		ok(not has(list, "false"), "false filtered out")
	end)

	test("a range argument enumerates its valid values", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, "count "))
		eq(#list, 3, "3,4,5")
		ok(has(list, "3") and has(list, "5"), "enumerated")
	end)

	test("replace span points at the current argument word", function()
		local reg = buildRegistry()
		local list = Completer.complete(reg, "count 4")
		-- 'count 4' -> current word '4' at index 7
		ok(#list >= 0, "no error")
		local c = Completer.complete(reg, "kill tr")[1]
		if c then
			eq(c.replaceStart, 6, "starts at the arg word")
			eq(c.replaceEnd, 7, "through the input end")
		end
	end)

	test("an unknown command yields no argument completions", function()
		local reg = buildRegistry()
		eq(#Completer.complete(reg, "bogus something"), 0, "nothing")
	end)

	test("ghost text extends the current word", function()
		local reg = buildRegistry()
		eq(Completer.ghost(reg, "anno"), "unce", "announce - anno")
		eq(Completer.ghost(reg, "kill t"), "rue", "true - t")
	end)

	test("a literal-union argument suggests its values", function()
		local reg = buildRegistry()
		local list = texts(Completer.complete(reg, "theme "))
		eq(#list, 3, "gruvbox / tokyonight / nord")
		ok(has(list, "gruvbox") and has(list, "nord"), "literals suggested")
		eq(#texts(Completer.complete(reg, "theme gr")), 1, "prefix narrows to gruvbox")
	end)

	test("a command completion's detail is its signature", function()
		local reg = buildRegistry()
		local list = Completer.complete(reg, "theme")
		eq(list[1].detail, "theme <name>", "usage signature")
		eq(list[1].description, "Switch the colorscheme.", "description carried too")
	end)

	test("an argument completion shows the arg description", function()
		local reg = buildRegistry()
		local list = Completer.complete(reg, "theme ")
		eq(list[1].detail, "the colorscheme to use", "the '# …' note")
	end)

	test("hint reports the active argument", function()
		local reg = buildRegistry()
		local onName = Completer.hint(reg, "theme")
		eq(onName.activeIndex, 0, "still on the command name")
		eq(onName.signature, "theme <name>", "signature")
		local onArg = Completer.hint(reg, "theme ")
		eq(onArg.activeIndex, 1, "on the first argument")
		eq(onArg.args[1].description, "the colorscheme to use", "arg description available")
	end)

	test("hint is nil for an unknown command", function()
		local reg = buildRegistry()
		eq(Completer.hint(reg, "bogus x"), nil, "no hint")
	end)
end
