--- The **Dispatcher** runs a submitted line. It tokenizes with the [[Lexer]],
--- splits on chain operators, and for each command: resolves it in the
--- [[Registry]], binds the argument tokens (coercing each through the arg's
--- compiled [[Types|type]], filling defaults, erroring on a missing required
--- one), runs the handler with a [[Context]], and captures a [[Result]]. Chains
--- branch on the exit code — `&&` runs the next only on success, `||` only on
--- failure, `;`/`&` always. A shared return pool lets `//` / `/refs` read earlier
--- results back. Fully headless-testable.
---
--- Pipelines (`|`) and rich reference paths (`/x.y#2`) are not wired yet — bare
--- `//` and `/Name` references resolve; anything fancier is left for later.
--- @section Server
--- @client

local Shell = require(script.Parent.Parent.Parent._Utility.Shell)
local Context = require(script.Parent.Parent.Parent._Classes.Context)
local Result = require(script.Parent.Parent.Parent._Patterns.Result)

local Kind = Shell.Token.Kind

local Dispatcher = {}
Dispatcher.__index = Dispatcher

export type ExecConfig = {
	executor: any?,
	realm: string?,
	sink: ((any) -> ())?,
	bridge: any?,
}

export type Config = {
	--- Optional gate run before a command; return `(false, reason)` to deny.
	authorize: ((command: any, exec: ExecConfig) -> (boolean, string?))?,
}

-- operator tokens that separate one command from the next
local CHAIN_OPS: { [string]: string } = {
	[Kind.AmpAmp] = "&&",
	[Kind.PipePipe] = "||",
	[Kind.Amp] = ";",
	[Kind.Semicolon] = ";",
	[Kind.Newline] = ";",
}

--- Creates a dispatcher over `registry`.
function Dispatcher.new(registry: any, config: Config?)
	return setmetatable({ registry = registry, config = config or {} }, Dispatcher)
end

-- split the token stream into { op, tokens } segments on chain operators
local function segment(tokens)
	local segments = {}
	local current = { op = nil :: string?, tokens = {} }
	for _, token in tokens do
		if token.kind == Kind.EOF then
			break
		elseif CHAIN_OPS[token.kind] then
			table.insert(segments, current)
			current = { op = CHAIN_OPS[token.kind], tokens = {} }
		else
			table.insert(current.tokens, token)
		end
	end
	table.insert(segments, current)
	return segments
end

-- the raw string form of an argument token, for the type to transform
local function rawText(token): string
	if token.value ~= nil then
		return tostring(token.value)
	end
	return token.text
end

-- runs one command segment; returns a Result
function Dispatcher._runSegment(self, tokens, exec, returnPool): any
	if #tokens == 0 then
		return Result.ok(nil)
	end
	local head = tokens[1]
	local ctx = Context.new({
		executor = exec.executor,
		realm = exec.realm or "server",
		rawText = table.concat((function()
			local parts = {}
			for _, t in tokens do
				table.insert(parts, t.text)
			end
			return parts
		end)(), " "),
		sink = exec.sink,
		bridge = exec.bridge,
		returnPool = returnPool,
	})

	if head.kind ~= Kind.Ident then
		return ctx:err(`expected a command, got '{head.text}'`)
	end
	local command = self.registry:resolve(head.text)
	if not command then
		return ctx:err(`unknown command: {head.text}`)
	end

	if self.config.authorize then
		local allowed, reason = self.config.authorize(command, exec)
		if not allowed then
			return ctx:err(reason or `not allowed to run '{command.name}'`)
		end
	end

	-- gather raw argument values (tokens after the command name)
	local rawArgs = {}
	for index = 2, #tokens do
		local token = tokens[index]
		if token.kind == Kind.SlashSlash then
			rawArgs[#rawArgs + 1] = { ref = { last = true, path = {} } }
		elseif token.kind == Kind.Slash then
			local nameToken = tokens[index + 1]
			if nameToken and nameToken.kind == Kind.Ident then
				rawArgs[#rawArgs + 1] = { ref = { last = false, name = nameToken.text, path = {} } }
				tokens[index + 1] = { kind = "__consumed", text = "", value = nil } -- skip the name next loop
			end
		elseif token.kind ~= "__consumed" then
			rawArgs[#rawArgs + 1] = { text = rawText(token) }
		end
	end

	-- bind to the declared arguments
	local bound = {}
	local count = 0
	if #command.args == 0 then
		-- untyped passthrough for arg-less commands
		for _, raw in rawArgs do
			count += 1
			bound[count] = if raw.ref then (returnPool:resolve(raw.ref)) else raw.text
		end
	else
		for i, spec in command.args do
			local raw = rawArgs[i]
			count = i
			if raw == nil then
				if spec.hasDefault then
					bound[i] = (spec.type.transform(spec.default))
				elseif spec.optional then
					bound[i] = nil
				else
					return ctx:err(`missing required argument '{spec.name}'`)
				end
			elseif raw.ref then
				local value, refErr = returnPool:resolve(raw.ref)
				if refErr then
					return ctx:err(refErr)
				end
				local okValid, why = spec.type.validate(value)
				if not okValid then
					return ctx:err(`argument '{spec.name}': {why}`)
				end
				bound[i] = value
			else
				local value, transformErr = spec.type.transform(raw.text)
				if transformErr then
					return ctx:err(`argument '{spec.name}': {transformErr}`)
				end
				local okValid, why = spec.type.validate(value)
				if not okValid then
					return ctx:err(`argument '{spec.name}': {why}`)
				end
				bound[i] = value
			end
		end
	end

	self.registry:fire("before", ctx, command)
	local okRun, returned = pcall(command.run, ctx, table.unpack(bound, 1, count))
	local result
	if not okRun then
		result = ctx:err(`{command.name} errored: {tostring(returned)}`)
	elseif Result.is(returned) then
		result = returned
	else
		result = Result.ok(returned)
	end
	self.registry:fire("after", ctx, command, result)
	return result
end

--- Runs a whole line (with chains). Returns the last executed [[Result]].
function Dispatcher:run(line: string, exec: ExecConfig?): any
	local execConfig = exec or {}
	local lex = Shell.tokenize(line)
	local segments = segment(lex.tokens)
	local returnPool = Shell.ReturnPool.new()

	local last = Result.ok(nil)
	local ran = false
	for _, seg in segments do
		if #seg.tokens == 0 then
			continue
		end
		local shouldRun
		if not ran then
			shouldRun = true -- the first real command always runs
		elseif seg.op == "&&" then
			shouldRun = last.code == 0
		elseif seg.op == "||" then
			shouldRun = last.code ~= 0
		else -- ";" / "&" / nil
			shouldRun = true
		end

		if shouldRun then
			last = Dispatcher._runSegment(self, seg.tokens, execConfig, returnPool)
			ran = true
		end
	end
	return last
end

return Dispatcher
