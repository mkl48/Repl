--- Validates and normalizes a **command definition** — the table a user returns
--- from a command module — into a checked record. Names are validated, the
--- [[Argument|Args DSL]] is parsed, and every problem is collected (never
--- thrown) so the [[Registry]] can report a whole module's mistakes at once.
--- @section Registry
--- @client

local Argument = require(script.Parent.Argument)

local Command = {}

export type Confirm = string | { message: string?, type: ("y/n" | "phrase")?, phrase: string? }

export type Realm = "Server" | "Client" | "Shared"

export type Def = {
	Name: string,
	Aliases: { string }?,
	Description: string?,
	Capabilities: { string }?,
	Realm: Realm?, -- where it runs / is validated (default "Server")
	Args: { string }?,
	Confirm: Confirm?,
	Run: (...any) -> ...any,
}

export type Command = {
	name: string,
	aliases: { string },
	description: string,
	capabilities: { string },
	realm: Realm,
	args: { Argument.Spec }, -- positional arguments, in order
	flags: { Argument.Spec }, -- -x / --name options
	flagByName: { [string]: Argument.Spec }, -- every flag alias → its spec
	confirm: Confirm?,
	run: (...any) -> ...any,
}

local REALMS: { [string]: boolean } = { Server = true, Client = true, Shared = true }

export type Result = {
	command: Command?,
	errors: { string },
}

local NAME_PATTERN = "^[%a_][%w_%-]*$" -- letters/underscore, then word chars or dashes

local function isStringArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, item in value do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end

--- Parses and validates a command definition table.
function Command.parse(def: Def): Result
	local errors: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end

	if type(def) ~= "table" then
		return { command = nil, errors = { "command definition must be a table" } }
	end

	local name = def.Name
	if type(name) ~= "string" or not string.match(name, NAME_PATTERN) then
		fail(`Name must be a valid identifier, got {tostring(name)}`)
		name = tostring(name)
	end

	local aliases: { string } = {}
	if def.Aliases ~= nil then
		if isStringArray(def.Aliases) then
			for _, alias in def.Aliases :: { string } do
				if not string.match(alias, NAME_PATTERN) then
					fail(`alias '{alias}' is not a valid identifier`)
				else
					table.insert(aliases, alias)
				end
			end
		else
			fail("Aliases must be an array of strings")
		end
	end

	if def.Capabilities ~= nil and not isStringArray(def.Capabilities) then
		fail("Capabilities must be an array of strings")
	end

	local args: { Argument.Spec } = {} -- positional
	local flags: { Argument.Spec } = {}
	local flagByName: { [string]: Argument.Spec } = {}
	if def.Args ~= nil then
		if isStringArray(def.Args) then
			local seenOptional = false
			for index, raw in def.Args :: { string } do
				local spec = Argument.parse(raw)
				if spec.error then
					fail(`arg #{index} ({spec.name}): {spec.error}`)
				end
				if spec.isFlag then
					table.insert(flags, spec)
					for _, alias in spec.names do
						if flagByName[alias] then
							fail(`flag '--{alias}' is declared twice`)
						end
						flagByName[alias] = spec
					end
				else
					-- positional ordering: required may not follow optional
					if spec.optional then
						seenOptional = true
					elseif seenOptional then
						fail(`arg #{index} ({spec.name}): a required argument cannot follow an optional one`)
					end
					table.insert(args, spec)
				end
			end
		else
			fail("Args must be an array of DSL strings")
		end
	end

	if type(def.Run) ~= "function" then
		fail("Run must be a function")
	end

	local realm = def.Realm or "Server"
	if not REALMS[realm] then
		fail(`Realm must be "Server", "Client", or "Shared", got {tostring(def.Realm)}`)
		realm = "Server"
	end

	if #errors > 0 then
		return { command = nil, errors = errors }
	end

	return {
		command = {
			name = name,
			aliases = aliases,
			description = def.Description or "",
			capabilities = (def.Capabilities :: { string }?) or {},
			realm = realm,
			args = args,
			flags = flags,
			flagByName = flagByName,
			confirm = def.Confirm,
			run = def.Run,
		},
		errors = errors,
	}
end

--- A usage signature: `name <required> [optional]`.
function Command.signature(command: Command): string
	local parts = { command.name }
	for _, arg in command.args do
		table.insert(parts, Argument.usage(arg))
	end
	return table.concat(parts, " ")
end

return Command
