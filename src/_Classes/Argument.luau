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

--- Parses a single `"name: TypeExpr = default # description"` entry.
function Argument.parse(spec: string): Spec
	-- pull off a trailing `# description` first (types never contain '#')
	local description = ""
	local hashIndex = string.find(spec, "#", 1, true)
	if hashIndex then
		description = trim(string.sub(spec, hashIndex + 1))
		spec = string.sub(spec, 1, hashIndex - 1)
	end

	local name, rest = string.match(spec, "^%s*([%a_][%w_]*)%s*:%s*(.+)$")
	if not name then
		local bare = string.match(spec, "^%s*([%a_][%w_]*)") or trim(spec)
		return {
			name = bare,
			typeExpr = "",
			type = Types.compile(""),
			optional = false,
			hasDefault = false,
			default = nil,
			description = description,
			error = `expected 'name: Type' but got '{trim(spec)}'`,
		}
	end

	local typeExpr, default = rest, nil
	local eq = findDefaultEq(rest)
	if eq then
		typeExpr = string.sub(rest, 1, eq - 1)
		default = trim(string.sub(rest, eq + 1))
	end
	typeExpr = trim(typeExpr)

	local ty = Types.compile(typeExpr)
	local errParts = (ty :: any).parseErrors
	local err
	if errParts and #errParts > 0 then
		err = `bad type '{typeExpr}': {table.concat(errParts, "; ")}`
	elseif default ~= nil then
		-- a default must itself pass the type
		local value, transformErr = ty.transform(default)
		if transformErr ~= nil then
			err = `default '{default}' is invalid: {transformErr}`
		else
			local ok, why = ty.validate(value)
			if not ok then
				err = `default '{default}' is invalid: {why}`
			end
		end
	end

	return {
		name = name,
		typeExpr = typeExpr,
		type = ty,
		optional = ty.optional == true or default ~= nil,
		hasDefault = default ~= nil,
		default = default,
		description = description,
		error = err,
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
