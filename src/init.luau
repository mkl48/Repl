--- Repl — the umbrella. `require(ReplicatedStorage.Repl)` returns the whole
--- public API. It's realm-aware: the shared engine (Registry, Dispatcher, Types,
--- Theme) loads everywhere, and the Fusion [[Bar]] is pulled in only on the
--- client, only when you call `Repl:Start()` — so the server never touches Fusion.
---
--- ```lua
--- local Repl = require(game.ReplicatedStorage.Repl)
--- Repl.Theme:Set("tokyonight")
--- Repl:RegisterCommand({ Name = "hello", Args = { "who: String? = world" },
---     Run = function(ctx, who) return ctx:ok(`hello, {who}!`) end })
--- Repl:Start()                       -- mounts the bar (client); no-op on server
--- ```
---
--- Dev-facing state + events (`Repl.IsFocused()`, `Repl.FocusChanged`, …) let a
--- game gate its own keybinds while the terminal is in use.
--- @section Overview
--- @client

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Registry = require(script._Main.Server.Registry)
local Dispatcher = require(script._Main.Server.Dispatcher)
local Signal = require(script._Utility.Signal)
local Patterns = require(script._Patterns)

local Repl = {}

-- ── shared engine (both realms) ──────────────────────────────────────────────
Repl.Shell = require(script._Utility.Shell)
Repl.Types = require(script._Main.Types)
Repl.Theme = require(script._Utility.Theme)
Repl.Result = Patterns.Result
Repl.Option = Patterns.Option

--- The icon map — upload `assets/icons/png/*` and set ids: `Repl.Icons.set(...)`.
Repl.Icons = require(script._Utility.Render.Icons)

--- The command registry (`Repl.Registry:RegisterCommand(def)`, `:RegisterHook`, …).
Repl.Registry = Registry.new()
local dispatcher = Dispatcher.new(Repl.Registry)

-- ── dev-facing state + events ────────────────────────────────────────────────
Repl.Focused = false
Repl.Visible = false
--- Fires when the bar opens.
Repl.Opened = Signal.new()
--- Fires when the bar closes.
Repl.Closed = Signal.new()
--- Fires `(isFocused: boolean)` when input focus changes — gate your keybinds here.
Repl.FocusChanged = Signal.new()
--- Fires `(line: string)` when a line is submitted.
Repl.Submitted = Signal.new()

--- True while the input is focused.
function Repl.IsFocused(): boolean
	return Repl.Focused
end

--- True while the bar is open.
function Repl.IsOpen(): boolean
	return Repl.Visible
end

-- ── command / type / hook registration (shortcuts onto the Registry) ─────────

--- Registers one command definition.
function Repl:RegisterCommand(def: any)
	return Repl.Registry:register(def)
end

--- Registers a custom argument type.
function Repl:RegisterType(name: string, typeDef: any)
	return Repl.Registry:RegisterType(name, typeDef)
end

--- Adds a `"BeforeRun"` / `"AfterRun"` hook.
function Repl:RegisterHook(phase: string, fn: (...any) -> ())
	return Repl.Registry:RegisterHook(phase, fn)
end

--- Runs a line programmatically (same path the bar submits through).
function Repl:Execute(line: string, exec: any?)
	return dispatcher:run(line, exec or { realm = if RunService:IsServer() then "server" else "client" })
end

-- ── the bar (client only) ────────────────────────────────────────────────────
local bar: any = nil
local pendingActivationKeys: { Enum.KeyCode }? = nil

--- Sets the activation key(s). Call before `Start`, or any time after.
function Repl:SetActivationKeys(keys: { Enum.KeyCode })
	pendingActivationKeys = keys
	if bar and bar.setActivationKeys then
		bar:setActivationKeys(keys)
	end
end

--- Mounts the bar on the client (no-op on the server) and wires it to the
--- dispatcher. Returns `Repl` for chaining. `config`: `prompt`, `cursorStyle`,
--- `activationKeys`, `parent`.
function Repl:Start(config: any?)
	if RunService:IsServer() or bar then
		return Repl
	end
	config = config or {}
	local Bar = require(script._Main.Client.Bar)
	bar = Bar.new({
		registry = Repl.Registry,
		prompt = config.prompt or `{workspace.Name}/kr3ative/repl`,
		activationKeys = config.activationKeys or pendingActivationKeys,
		cursorStyle = config.cursorStyle,
		compact = config.compact,
		width = config.width,
		parent = config.parent,
		submit = function(text)
			dispatcher:run(text, {
				executor = Players.LocalPlayer,
				realm = "client",
				sink = function(node)
					bar:print(node)
				end,
			})
		end,
	})

	-- surface the bar's state/events at the Repl level
	bar.FocusChanged:Connect(function(isFocused)
		Repl.Focused = isFocused
		Repl.FocusChanged:Fire(isFocused)
	end)
	bar.Opened:Connect(function()
		Repl.Visible = true
		Repl.Opened:Fire()
	end)
	bar.Closed:Connect(function()
		Repl.Visible = false
		Repl.Closed:Fire()
	end)
	bar.Submitted:Connect(function(line)
		Repl.Submitted:Fire(line)
	end)

	Repl._bar = bar
	return Repl
end

--- Opens the bar.
function Repl:Show()
	if bar then
		bar:show()
	end
end

--- Closes the bar.
function Repl:Hide()
	if bar then
		bar:hide()
	end
end

--- Toggles the bar.
function Repl:Toggle()
	if bar then
		bar:toggle()
	end
end

return Repl
