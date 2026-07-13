--- The **Context** (`ctx`) handed to every command handler: it is how a command
--- talks back to the terminal. Output methods emit structured [[Output]] nodes;
--- `ok`/`err`/`abort` both report *and* return a [[Result]] with the right exit
--- code; `returns` records a value in the [[ReturnPool]] for later `/references`;
--- `store` is a per-session scratch space. Interactive calls (`confirm`, `prompt`,
--- `choose`, `exec`) delegate to an injected bridge — headless in tests, a real
--- client round-trip once Network is in.
--- @section Context
--- @client

local Output = require(script.Parent.Parent._Utility.Render.Output)
local Result = require(script.Parent.Parent._Patterns.Result)
local ReturnPool = require(script.Parent.Parent._Utility.Shell.ReturnPool)
local EventBus = require(script.Parent.Parent._Utility.EventBus)

local Context = {}
Context.__index = Context

export type Bridge = {
	confirm: ((message: string) -> boolean)?,
	prompt: ((message: string, default: string?) -> string?)?,
	choose: ((message: string, options: { string }) -> string?)?,
	exec: ((name: string, ...any) -> any)?,
}

export type Config = {
	executor: any?,
	rawText: string?,
	args: { any }?,
	realm: string?,
	returnPool: any?,
	sink: ((Output.Node) -> ())?,
	bridge: Bridge?,
	bus: any?, -- a shared EventBus (the two sides of a shared command share one)
	net: ((event: string, payload: any) -> any)?, -- cross-realm awaited post
}

--- Creates a context. Everything is optional; a fresh ReturnPool and an empty
--- store are provided if you don't pass them.
function Context.new(config: Config?)
	local cfg = config or {}
	return setmetatable({
		executor = cfg.executor,
		rawText = cfg.rawText or "",
		args = cfg.args or {},
		flags = {}, -- populated by the dispatcher from -x / --name options
		realm = cfg.realm or "server",
		returnPool = cfg.returnPool or ReturnPool.new(),
		output = {} :: { Output.Node }, -- every emitted node, in order
		bus = cfg.bus or EventBus.new(), -- shared-command event bus (queued)
		_sink = cfg.sink,
		_store = {} :: { [string]: any },
		_bridge = cfg.bridge,
		_net = cfg.net,
	}, Context)
end

--- Emits a node: records it and forwards it to the sink (the live terminal).
function Context:emit(node: Output.Node): Output.Node
	table.insert(self.output, node)
	if self._sink then
		self._sink(node)
	end
	return node
end

-- ── output ──────────────────────────────────────────────────────────────────

--- A neutral reply line.
function Context:reply(text: string)
	return self:emit(Output.plain(text))
end
function Context:success(text: string)
	return self:emit(Output.success(text))
end
function Context:error(text: string)
	return self:emit(Output.error(text))
end
function Context:warn(text: string)
	return self:emit(Output.warn(text))
end
function Context:info(text: string)
	return self:emit(Output.info(text))
end
function Context:message(text: string)
	return self:emit(Output.message(text))
end

--- A line in an arbitrary theme color token.
function Context:custom(color: string, text: string)
	return self:emit(Output.line("plain", { Output.segment(text, { color = color }) }))
end

--- A line prefixed with a Lucide icon.
function Context:icon(name: string, text: string)
	return self:emit(Output.line("plain", { Output.segment(text, { icon = name }) }))
end

--- An aligned table block from rows of cells.
function Context:table(rows: { { string } })
	return self:emit(Output.table(rows))
end

--- A multi-line ascii block (split on newlines).
function Context:ascii(text: string)
	local lines: { Output.Line } = {}
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		table.insert(lines, Output.plain(line))
	end
	return self:emit(Output.block("ascii", lines))
end

-- ── outcomes (report + return a Result) ──────────────────────────────────────

--- Reports success (if a message is given) and returns an ok [[Result]].
function Context:ok(message: any?): Result.Result
	if message ~= nil then
		self:success(tostring(message))
	end
	return Result.ok(message)
end

--- Reports an error and returns an err [[Result]] (exit code defaults to 1).
function Context:err(message: string?, code: number?): Result.Result
	if message ~= nil then
		self:error(tostring(message))
	end
	return Result.err(message or "error", code)
end

--- Reports a cancellation and returns an abort [[Result]] (exit code 130).
function Context:abort(reason: string?): Result.Result
	if reason ~= nil then
		self:message(tostring(reason))
	end
	return Result.abort(reason)
end

-- ── return pool ───────────────────────────────────────────────────────────--

--- Records `value` in the return pool so later `/references` can read it back.
function Context:returns(value: any, valueType: string?, label: string?): any
	self.returnPool:push(value, valueType, label)
	return value
end

-- ── session store ─────────────────────────────────────────────────────────--

--- `store(name)` reads; `store(name, value)` writes (and returns the value).
function Context:store(name: string, ...: any): any
	if select("#", ...) > 0 then
		local value = ...
		self._store[name] = value
		return value
	end
	return self._store[name]
end

-- ── interactive (delegated to the bridge) ────────────────────────────────────

local function bridged(self, method: string)
	local bridge = self._bridge
	if not bridge or not bridge[method] then
		error(`ctx:{method} is not available in this context`, 3)
	end
	return bridge[method]
end

--- Asks a yes/no question; blocks the terminal until answered.
function Context:confirm(message: string): boolean
	return bridged(self, "confirm")(message)
end

--- Prompts for a line of text (optionally with a default).
function Context:prompt(message: string, default: string?): string?
	return bridged(self, "prompt")(message, default)
end

--- Presents a choice between `options`.
function Context:choose(message: string, options: { string }): string?
	return bridged(self, "choose")(message, options)
end

--- Runs another command by name from inside this one.
function Context:exec(name: string, ...: any): any
	return bridged(self, "exec")(name, ...)
end

-- ── shared commands (post / subscribe) ───────────────────────────────────────

--- Listens for `event`. Handlers run for same-realm posts *and* posts from the
--- other side (routed in by the network layer); any earlier post is replayed, so
--- subscribing late never misses one. A handler's return value answers a `post`.
function Context:subscribe(event: string, handler: (...any) -> any)
	return self.bus:subscribe(event, handler)
end

--- Posts `event` to both sides. Returns an awaitable: `:Await()` blocks for a
--- guaranteed value — the other realm's response over a RemoteFunction when a
--- shared command spans realms, or the local subscriber's response otherwise —
--- so there's no race between posting and a listener being ready.
function Context:post(event: string, ...: any)
	local localReturns = self.bus:post(event, ...)
	local net = self._net
	local packed = table.pack(...)
	return {
		--- Blocks for the answer (cross-realm if networked, else local).
		Await = function()
			if net then
				return net(event, table.unpack(packed, 1, packed.n))
			end
			return localReturns[1]
		end,
	}
end

return Context
