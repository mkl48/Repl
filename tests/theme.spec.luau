-- Theme specs. `lune run tests/run`

local Loader = require("./loader")
local Theme = Loader.get("Theme")

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

	test("every built-in scheme defines every token", function()
		for _, scheme in Theme.list() do
			Theme:Set(scheme)
			for _, token in Theme.tokens do
				local value = Theme:Get(token)
				ok(string.match(value, "^#%x%x%x%x%x%x$") ~= nil, `{scheme}.{token} is a hex color, got {value}`)
			end
		end
	end)

	test("Set switches the active palette", function()
		Theme:Set("tokyonight")
		local a = Theme:Get("accent")
		Theme:Set("gruvbox")
		local b = Theme:Get("accent")
		ok(a ~= b, "accent differs between schemes")
		eq(Theme.current, "gruvbox", "current updated")
	end)

	test("an unknown scheme errors", function()
		local okCall = pcall(function()
			Theme:Set("nonsense")
		end)
		eq(okCall, false, "rejected")
	end)

	test("Get falls back to text for an unknown token", function()
		Theme:Set("nord")
		eq(Theme:Get("does_not_exist"), Theme:Get("text"), "falls back to text")
	end)

	test("OnChange fires on Set and can unsubscribe", function()
		local log = {}
		local unsub = Theme:OnChange(function(name)
			table.insert(log, name)
		end)
		Theme:Set("catppuccin")
		Theme:Set("nord")
		unsub()
		Theme:Set("tokyonight")
		eq(table.concat(log, ","), "catppuccin,nord", "heard both, then unsubscribed")
	end)

	test("register requires the full token set", function()
		local okCall = pcall(function()
			Theme.register("broken", { bg = "#000000" })
		end)
		eq(okCall, false, "missing tokens rejected")
	end)

	test("register adds a usable scheme", function()
		local palette = Theme:Palette() -- a complete one to clone
		Theme.register("clone", palette)
		ok(Theme.has("clone"), "registered")
		Theme:Set("clone")
		eq(Theme:Get("accent"), palette.accent, "uses the registered palette")
	end)
end
