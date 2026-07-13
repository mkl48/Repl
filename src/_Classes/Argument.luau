--- Parses the terse **Args DSL** — one `"name: TypeExpr = default"` string per
--- argument — into structured specs. The text after the colon is a real
--- [[Types|type expression]] (so `amount: Integer? = 1` and `n: 2 < Integer < 30`
--- both work); the type is compiled here so the handler receives typed, validated
--- values. Never throws; problems land in each spec's `.error`.
--- @section Registry
--- @client

local Types = require(script.Parent.Parent._Main.Types)

local Argument = {}

export type Spec = {
	name: string,
	typeExpr: string,
	type: Types.Type,
	optional: boolean,
	hasDefault: boolean,
	default: string?, -- the raw default text, transformed by `type` at dispatch
	description: string, -- the "# …" trailing note, for intellisense
	isFlag: boolean, -- a `-x` / `--name` option rather than a positional
	isBoolean: boolean, -- a presence flag (no value needed)
	names: { string }, -- flag aliases without dashes (empty for positionals)
	error: string?,
}

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Find the `=` that separates a default from the type, skipping the `=` inside
-- the comparison operators `<=` / `>=` that a range expression may contain.
local function findDefaultEq(rest: string): number?
	for p = 1, #rest do
		if string.sub(rest, p, p) == "=" then
			local prev = string.sub(rest, p - 1, p - 1)
			if prev ~= "<" and prev ~= ">" and prev ~= "=" then
				return p
			end
		end
	end
	return nil
end

-- splits "TypeExpr = default" into its two halves (the default may be nil)
local function splitTypeDefault(rest: string): (string, string?)
	local eq = findDefaultEq(rest)
	if eq then
		return trim(string.sub(rest, 1, eq - 1)), trim(string.sub(rest, eq + 1))
	end
	return trim(rest), nil
end

-- validates a default against its type; returns an error message or nil
local function defaultError(ty: any, typeExpr: string, default: string?): string?
	local errParts = (ty :: any).parseErrors
	if errParts and #errParts > 0 then
		return `bad type '{typeExpr}': {table.concat(errParts, "; ")}`
	end
	if default ~= nil then
		local value, transformErr = ty.transform(default)
		if transformErr ~= nil then
			return `default '{default}' is invalid: {transformErr}`
		end
		local ok, why = ty.validate(value)
		if not ok then
			return `default '{default}' is invalid: {why}`
		end
	end
	return nil
end

-- parses a `-x, --name: Type = default` flag/option entry
local function parseFlag(spec: string, description: string): Spec
	local colon = string.find(spec, ":", 1, true)
	local namesPart = if colon then string.sub(spec, 1, colon - 1) else spec
	local typePart = if colon then string.sub(spec, colon + 1) else ""

	local names = {}
	for token in string.gmatch(namesPart, "[^,]+") do
		local n = string.match(trim(token), "^%-%-?([%a_][%w_%-]*)$")
		if n then
			table.insert(names, n)
		end
	end

	local typeExpr, default = splitTypeDefault(typePart)
	if typeExpr == "" then
		typeExpr = "Boolean" -- a bare `--flag` is a presence switch
	end
	local isBoolean = typeExpr == "Boolean"
	if default == nil and isBoolean then
		default = "false" -- absent boolean flag → false
	end

	local ty = Types.compile(typeExpr)
	local err = defaultError(ty, typeExpr, default)
	if #names == 0 then
		err = err or `flag '{trim(spec)}' has no valid -x/--name`

	end
	return {
		name = names[#names] or "flag", -- the long (last) name is canonical
		typeExpr = typeExpr,
		type = ty,
		optional = true, -- flags are always optional
		hasDefault = default ~= nil,
		default = default,
		description = description,
		isFlag = true,
		isBoolean = isBoolean,
		names = names,
		error = err,
	}
end

--- Parses a single entry: a positional `"name: TypeExpr = default # desc"` or a
--- flag `"-x, --name: TypeExpr = default # desc"` (a bare `--name` is a boolean).
function Argument.parse(spec: string): Spec
	-- pull off a trailing `# description` first (types never contain '#')
	local description = ""
	local hashIndex = string.find(spec, "#", 1, true)
	if hashIndex then
		description = trim(string.sub(spec, hashIndex + 1))
		spec = string.sub(spec, 1, hashIndex - 1)
	end
	spec = trim(spec)

	if string.sub(spec, 1, 1) == "-" then
		return parseFlag(spec, description)
	end

	local name, rest = string.match(spec, "^([%a_][%w_]*)%s*:%s*(.+)$")
	if not name then
		local bare = string.match(spec, "^([%a_][%w_]*)") or spec
		return {
			name = bare,
			typeExpr = "",
			type = Types.compile(""),
			optional = false,
			hasDefault = false,
			default = nil,
			description = description,
			isFlag = false,
			isBoolean = false,
			names = {},
			error = `expected 'name: Type' but got '{spec}'`,
		}
	end

	local typeExpr, default = splitTypeDefault(rest)
	local ty = Types.compile(typeExpr)

	return {
		name = name,
		typeExpr = typeExpr,
		type = ty,
		optional = ty.optional == true or default ~= nil,
		hasDefault = default ~= nil,
		default = default,
		description = description,
		isFlag = false,
		isBoolean = false,
		names = {},
		error = defaultError(ty, typeExpr, default),
	}
end

--- A usage token for one spec: `<name>` (required) or `[name]` (optional).
function Argument.usage(spec: Spec): string
	if spec.optional then
		return `[{spec.name}]`
	end
	return `<{spec.name}>`
end

--- Parses a whole `Args` list, collecting per-entry errors plus one structural
--- rule: a required argument may not follow an optional one.
function Argument.parseList(specs: { string }): ({ Spec }, { string })
	local out: { Spec } = {}
	local errors: { string } = {}
	local seenOptional = false
	for index, raw in specs do
		local spec = Argument.parse(raw)
		if spec.error then
			table.insert(errors, `arg #{index} ({spec.name}): {spec.error}`)
		end
		if spec.optional then
			seenOptional = true
		elseif seenOptional then
			table.insert(errors, `arg #{index} ({spec.name}): a required argument cannot follow an optional one`)
		end
		table.insert(out, spec)
	end
	return out, errors
end

return Argument
