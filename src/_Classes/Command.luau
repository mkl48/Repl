--- Validates and normalizes a **command definition** — the table a user returns
--- from a command module — into a checked record. Names are validated, the
--- [[Argument|Args DSL]] is parsed, and every problem is collected (never
--- thrown) so the [[Registry]] can report a whole module's mistakes at once.
--- @section Registry
--- @client

local Argument = require(script.Parent.Argument)

local Command = {}

export type Confirm = string | { message: string?, type: ("y/n" | "phrase")?, phrase: string? }

export type Def = {
	Name: string,
	Aliases: { string }?,
	Description: string?,
	Capabilities: { string }?,
	Args: { string }?,
	Confirm: Confirm?,
	Run: (...any) -> ...any,
}

export type Command = {
	name: string,
	aliases: { string },
	description: string,
	capabilities: { string },
	args: { Argument.Spec },
	confirm: Confirm?,
	run: (...any) -> ...any,
}

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

	local args: { Argument.Spec } = {}
	if def.Args ~= nil then
		if isStringArray(def.Args) then
			local parsed, argErrors = Argument.parseList(def.Args :: { string })
			args = parsed
			for _, message in argErrors do
				fail(message)
			end
		else
			fail("Args must be an array of DSL strings")
		end
	end

	if type(def.Run) ~= "function" then
		fail("Run must be a function")
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
			args = args,
			confirm = def.Confirm,
			run = def.Run,
		},
		errors = errors,
	}
end

return Command
