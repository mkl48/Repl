--- Capability-based **Authority**. Commands declare `Capabilities` (dotted
--- strings like `players.kill.others`), never a rank. **Roles** are named bundles
--- of capabilities — with wildcards (`players.*`, `*`) and inheritance — and a
--- player's capabilities are the union of their roles (plus the default role
--- everyone has). `Can` / `CanAll` answer whether an executor may run something.
---
--- A role can be assigned statically (`Assign`) or resolved dynamically (a
--- `SetResolver` hook — group rank, gamepass, attribute, DataStore). The matching
--- and role math are headless-testable; the resolver is where Roblox specifics live.
--- @section Server
--- @client

local Authority = {}
Authority.__index = Authority

export type RoleDef = {
	Capabilities: { string }?,
	Inherits: { string }?,
}

--- Creates an authority with no roles.
function Authority.new()
	return setmetatable({
		roles = {} :: { [string]: { capabilities: { string }, inherits: { string } } },
		defaultRole = nil :: string?,
		assignments = {} :: { [any]: { string } }, -- executor → role names
		resolver = nil :: ((executor: any) -> { string })?,
	}, Authority)
end

-- segment-wise wildcard match: `players.*` covers players / players.kill / …,
-- `*` covers everything, an exact grant covers only that capability
local function matches(grant: string, capability: string): boolean
	local g = string.split(grant, ".")
	local c = string.split(capability, ".")
	for i, segment in g do
		if segment == "*" then
			return true -- `*` swallows the rest
		end
		if c[i] ~= segment then
			return false
		end
	end
	return #c == #g -- exact grant: no extra capability segments
end
Authority.matches = matches

--- Defines (or replaces) a role.
function Authority:DefineRole(name: string, def: RoleDef)
	self.roles[name] = {
		capabilities = (def.Capabilities or {}),
		inherits = (def.Inherits or {}),
	}
end

--- Sets the role every executor implicitly has (the "base level").
function Authority:SetDefaultRole(name: string)
	self.defaultRole = name
end

--- Statically gives `executor` a role.
function Authority:Assign(executor: any, role: string)
	local list = self.assignments[executor]
	if not list then
		list = {}
		self.assignments[executor] = list
	end
	if not table.find(list, role) then
		table.insert(list, role)
	end
end

--- Removes a static assignment.
function Authority:Unassign(executor: any, role: string)
	local list = self.assignments[executor]
	if list then
		local index = table.find(list, role)
		if index then
			table.remove(list, index)
		end
	end
end

--- Sets the dynamic role resolver (returns extra role names for an executor).
function Authority:SetResolver(resolver: (executor: any) -> { string })
	self.resolver = resolver
end

--- The role names an executor holds: default + assigned + resolved.
function Authority:RolesOf(executor: any): { string }
	local names, seen = {}, {}
	local function add(name)
		if name and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	add(self.defaultRole)
	for _, role in self.assignments[executor] or {} do
		add(role)
	end
	if self.resolver then
		for _, role in self.resolver(executor) or {} do
			add(role)
		end
	end
	return names
end

-- flatten a role's capabilities, following Inherits (cycle-safe)
function Authority:_collect(role: string, into: { [string]: boolean }, visiting: { [string]: boolean })
	if visiting[role] then
		return
	end
	visiting[role] = true
	local def = self.roles[role]
	if def then
		for _, capability in def.capabilities do
			into[capability] = true
		end
		for _, parent in def.inherits do
			self:_collect(parent, into, visiting)
		end
	end
end

--- The flattened capability set an executor holds.
function Authority:CapabilitiesOf(executor: any): { string }
	local set, visiting = {}, {}
	for _, role in self:RolesOf(executor) do
		self:_collect(role, set, visiting)
	end
	local out = {}
	for capability in set do
		table.insert(out, capability)
	end
	return out
end

--- Whether `executor` holds `capability` (through any grant/wildcard).
function Authority:Can(executor: any, capability: string): boolean
	for _, grant in self:CapabilitiesOf(executor) do
		if matches(grant, capability) then
			return true
		end
	end
	return false
end

--- Whether `executor` holds every capability in `required`. Returns
--- `(ok, missing)` — `missing` lists the first uncovered capabilities.
function Authority:CanAll(executor: any, required: { string }): (boolean, { string })
	local granted = self:CapabilitiesOf(executor)
	local missing = {}
	for _, capability in required do
		local covered = false
		for _, grant in granted do
			if matches(grant, capability) then
				covered = true
				break
			end
		end
		if not covered then
			table.insert(missing, capability)
		end
	end
	return #missing == 0, missing
end

return Authority
