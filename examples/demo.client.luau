--!strict
-- Repl bar demo. Drop this in as a LocalScript (e.g. StarterPlayerScripts) with
-- the Repl package at ReplicatedStorage.Repl, then press ` (backquote) in-game.
--
-- This is all the setup it takes now: theme, register a few commands, Start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Repl = require(ReplicatedStorage:WaitForChild("Repl"))

Repl.Theme:Set("tokyonight")

Repl:RegisterCommand({
	Name = "hello",
	Description = "Greet someone.",
	Args = { "who: String? = world" },
	Run = function(ctx, who)
		return ctx:ok(`hello, {who}!`)
	end,
})

Repl:RegisterCommand({
	Name = "theme",
	Aliases = { "colorscheme" },
	Description = "Switch the colorscheme.",
	Args = { "name: String" },
	Run = function(ctx, name)
		if not Repl.Theme.has(name) then
			return ctx:err(`no theme '{name}' (have: {table.concat(Repl.Theme.list(), ", ")})`)
		end
		Repl.Theme:Set(name)
		return ctx:ok(`theme → {name}`)
	end,
})

Repl:RegisterCommand({
	Name = "add",
	Description = "Add two numbers (try: add 2 3).",
	Args = { "a: Number", "b: Number" },
	Run = function(ctx, a, b)
		return ctx:ok(`{a} + {b} = {a + b}`)
	end,
})

Repl:RegisterCommand({
	Name = "commands",
	Aliases = { "help" },
	Description = "List commands.",
	Run = function(ctx)
		local rows = { { "command", "description" } }
		for _, command in Repl.Registry:all() do
			table.insert(rows, { command.name, command.description })
		end
		ctx:table(rows)
		return ctx:ok()
	end,
})

-- gate a game keybind while the terminal is focused
Repl.FocusChanged:Connect(function(isFocused)
	print(`[game] terminal focused: {isFocused} — disable your own binds here`)
end)

Repl:Start()
