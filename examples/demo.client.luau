--!strict
-- Repl bar demo. Drop this in as a LocalScript (e.g. StarterPlayerScripts) with
-- the Repl package at ReplicatedStorage.Repl, then press ` (backquote) in-game.
--
-- It wires the Bar to a tiny inline dispatcher so a few commands actually run —
-- the real Dispatcher (chains, /references, typed-arg coercion) replaces this
-- `dispatch` function later, but the Bar's `submit` seam is identical.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Repl = ReplicatedStorage:WaitForChild("Repl")
local Registry = require(Repl._Main.Server.Registry)
local Bar = require(Repl._Main.Client.Bar)
local Context = require(Repl._Classes.Context)
local Output = require(Repl._Utility.Render.Output)
local Theme = require(Repl._Utility.Theme)

Theme:Set("tokyonight")

-- ── a handful of commands ────────────────────────────────────────────────────
local registry = Registry.new()

registry:register({
	Name = "hello",
	Description = "Greet someone.",
	Args = { "who: String? = world" },
	Run = function(ctx, who)
		return ctx:ok(`hello, {who or "world"}!`)
	end,
})

registry:register({
	Name = "theme",
	Aliases = { "colorscheme" },
	Description = "Switch the colorscheme.",
	Args = { "name: String" },
	Run = function(ctx, name)
		if not Theme.has(name) then
			return ctx:err(`no theme '{name}' (have: {table.concat(Theme.list(), ", ")})`)
		end
		Theme:Set(name)
		return ctx:ok(`theme → {name}`)
	end,
})

registry:register({
	Name = "commands",
	Aliases = { "help" },
	Description = "List commands.",
	Run = function(ctx)
		local rows = { { "command", "description" } }
		for _, command in registry:all() do
			table.insert(rows, { command.name, command.description })
		end
		ctx:table(rows)
		return ctx:ok()
	end,
})

-- ── mount the bar + a minimal dispatcher ─────────────────────────────────────
local bar
bar = Bar.new({
	registry = registry,
	prompt = `{workspace.Name}/kr3ative/repl`,
	submit = function(text)
		local words = string.split(text, " ")
		local name = table.remove(words, 1)
		local command = registry:resolve(name or "")
		if not command then
			bar:print(Output.error(`unknown command: {name}`))
			return
		end
		local ctx = Context.new({
			executor = Players.LocalPlayer,
			rawText = text,
			realm = "client",
			sink = function(node)
				bar:print(node)
			end,
		})
		local ok, err = pcall(command.run, ctx, table.unpack(words))
		if not ok then
			bar:print(Output.error(tostring(err)))
		end
	end,
})

bar:printText("info", "Repl demo — press ` to toggle. Try: commands · hello you · theme gruvbox")
