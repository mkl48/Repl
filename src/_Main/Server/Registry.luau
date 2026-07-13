--- The **Registry** holds every registered command, indexed by name and by
--- alias, and is the one place a name clash is caught. It parses each definition
--- through the [[Command]] validator, exposes custom-[[Types|type]] registration,
--- and keeps the `before`/`after` run hooks the dispatcher fires. Registration
--- never throws: it returns the collected errors so a bad module fails loudly but
--- in isolation.
--- @section Registry
--- @client

local Command = require(script.Parent.Parent.Parent._Classes.Command)
local Types = require(script.Parent.Parent.Types)

local Registry = {}
Registry.__index = Registry

export type Hook = (...any) -> ...any

--- Creates an empty registry.
function Registry.new()
	return setmetatable({
		commands = {} :: { [string]: Command.Command },
		aliasOf = {} :: { [string]: string }, -- alias/name (lowercased) → canonical name
		order = {} :: { string }, -- registration order, for stable listing
		hooks = { before = {} :: { Hook }, after = {} :: { Hook } },
	}, Registry)
end

local function key(name: string): string
	return string.lower(name)
end

--- Registers a command definition. Returns `(command, errors)`; on any error the
--- command is *not* registered and `command` is nil.
function Registry:register(def: Command.Def): (Command.Command?, { string })
	local result = Command.parse(def)
	if not result.command then
		return nil, result.errors
	end
	local command = result.command
	local errors: { string } = {}

	-- collision check across both names and aliases before mutating anything
	local claimed = { command.name }
	for _, alias in command.aliases do
		table.insert(claimed, alias)
	end
	for _, token in claimed do
		local existing = self.aliasOf[key(token)]
		if existing then
			table.insert(errors, `'{token}' is already registered by '{existing}'`)
		end
	end
	if #errors > 0 then
		return nil, errors
	end

	self.commands[command.name] = command
	self.aliasOf[key(command.name)] = command.name
	for _, alias in command.aliases do
		self.aliasOf[key(alias)] = command.name
	end
	table.insert(self.order, command.name)
	return command, {}
end

--- Resolves a name or alias (case-insensitive) to its command.
function Registry:resolve(nameOrAlias: string): Command.Command?
	local canonical = self.aliasOf[key(nameOrAlias)]
	return canonical and self.commands[canonical] or nil
end

--- Every command, in registration order.
function Registry:all(): { Command.Command }
	local out = {}
	for _, name in self.order do
		table.insert(out, self.commands[name])
	end
	return out
end

--- Registers (or replaces) a custom argument type. Thin passthrough to [[Types]].
function Registry:registerType(def: Types.Def)
	Types.register(def)
end

--- Adds a hook fired `before` or `after` each command runs.
function Registry:on(phase: "before" | "after", fn: Hook)
	local bucket = self.hooks[phase]
	if not bucket then
		error(`unknown hook phase '{phase}'`, 2)
	end
	table.insert(bucket, fn)
end

--- Fires every hook registered for `phase`, passing the extra arguments through.
function Registry:fire(phase: "before" | "after", ...: any)
	for _, fn in self.hooks[phase] do
		fn(...)
	end
end

return Registry
