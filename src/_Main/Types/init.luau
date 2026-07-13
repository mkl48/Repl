--- The **type engine**. A type is a small record with three jobs: `transform`
--- turns raw text into a value, `validate` checks a value, and `autocomplete`
--- offers completions for a partial input. The engine ships primitive types and
--- compiles a [[Expr|type expression]] (`Player | Character`, `Number & Int32`,
--- `2 < Integer < 30`) into a single composed type — unions merge completions,
--- intersections stack constraints, and a bounded range *enumerates* its valid
--- values so the command bar can suggest them.
--- @section Types
--- @client

local Expr = require(script.Expr)

local Types = {}

--- A resolved, ready-to-use type.
export type Type = {
	name: string,
	optional: boolean?,
	--- Raw text → `(value, nil)` or `(nil, error)`.
	transform: (raw: string) -> (any, string?),
	--- A value → `(ok, reason?)`.
	validate: (value: any) -> (boolean, string?),
	--- A partial input → completion strings.
	autocomplete: (prefix: string) -> { string },
}

--- A type definition you register. Only `name` and `transform` are required;
--- the rest have sensible defaults.
export type Def = {
	name: string,
	transform: ((raw: string) -> (any, string?))?,
	validate: ((value: any) -> (boolean, string?))?,
	autocomplete: ((prefix: string) -> { string })?,
	--- Marks a whole-number type so ranges over it enumerate integers.
	integer: boolean?,
}

local ENUM_CAP = 60 -- never suggest more than this many range values

local registry: { [string]: Def } = {}

local function identity(raw: string): (any, string?)
	return raw, nil
end
local function alwaysValid(): (boolean, string?)
	return true
end
local function noCompletions(): { string }
	return {}
end

--- Registers (or replaces) a type definition.
function Types.register(def: Def)
	registry[def.name] = def
end

--- Returns the raw definition registered under `name`, if any.
function Types.get(name: string): Def?
	return registry[name]
end

-- ── built-in primitives ─────────────────────────────────────────────────────

Types.register({
	name = "String",
	transform = identity,
	validate = function(v)
		return type(v) == "string", if type(v) == "string" then nil else "expected a string"
	end,
})

Types.register({
	name = "Number",
	transform = function(raw)
		local n = tonumber(raw)
		if n == nil then
			return nil, `'{raw}' is not a number`
		end
		return n
	end,
	validate = function(v)
		return type(v) == "number", if type(v) == "number" then nil else "expected a number"
	end,
})

Types.register({
	name = "Integer",
	integer = true,
	transform = function(raw)
		local n = tonumber(raw)
		if n == nil then
			return nil, `'{raw}' is not a number`
		end
		if n % 1 ~= 0 then
			return nil, `'{raw}' is not a whole number`
		end
		return n
	end,
	validate = function(v)
		if type(v) ~= "number" then
			return false, "expected a number"
		end
		return v % 1 == 0, if v % 1 == 0 then nil else "expected a whole number"
	end,
})

Types.register({
	name = "Boolean",
	transform = function(raw)
		local low = string.lower(raw)
		if low == "true" or low == "yes" or low == "y" or low == "1" then
			return true
		elseif low == "false" or low == "no" or low == "n" or low == "0" then
			return false
		end
		return nil, `'{raw}' is not true/false`
	end,
	validate = function(v)
		return type(v) == "boolean", if type(v) == "boolean" then nil else "expected a boolean"
	end,
	autocomplete = function(prefix)
		local out = {}
		for _, word in { "true", "false" } do
			if string.sub(word, 1, #prefix) == prefix then
				table.insert(out, word)
			end
		end
		return out
	end,
})

-- ── compilation ─────────────────────────────────────────────────────────────

local compileNode: (node: any) -> Type

local function unknownType(name: string): Type
	return {
		name = name,
		transform = function()
			return nil, `unknown type '{name}'`
		end,
		validate = function()
			return false, `unknown type '{name}'`
		end,
		autocomplete = noCompletions,
	}
end

local function compileName(node: any): Type
	local def = registry[node.name]
	if not def then
		return unknownType(node.name)
	end
	return {
		name = def.name,
		transform = def.transform or identity,
		validate = def.validate or alwaysValid,
		autocomplete = def.autocomplete or noCompletions,
	}
end

-- is the innermost atom a whole-number type? (so a range enumerates integers)
local function innerIsInteger(node: any): boolean
	if node.kind == "Name" then
		local def = registry[node.name]
		return def ~= nil and def.integer == true
	elseif node.kind == "Range" then
		return innerIsInteger(node.inner)
	elseif node.kind == "Intersection" then
		for _, part in node.parts do
			if innerIsInteger(part) then
				return true
			end
		end
	end
	return false
end

local function compileRange(node: any): Type
	local inner = compileNode(node.inner)
	local min, minInc, max, maxInc = node.min, node.minInc, node.max, node.maxInc
	local isInt = innerIsInteger(node.inner)

	local function boundsText(): string
		local lo = if min ~= nil then `{min}{if minInc then " ≤" else " <"}` else ""
		local hi = if max ~= nil then `{if maxInc then "≤ " else "< "}{max}` else ""
		return `{lo} {inner.name} {hi}`
	end

	local function inRange(v: number): (boolean, string?)
		if min ~= nil then
			if minInc and v < min then
				return false, `must be ≥ {min}`
			elseif not minInc and v <= min then
				return false, `must be > {min}`
			end
		end
		if max ~= nil then
			if maxInc and v > max then
				return false, `must be ≤ {max}`
			elseif not maxInc and v >= max then
				return false, `must be < {max}`
			end
		end
		return true
	end

	return {
		name = boundsText(),
		transform = inner.transform,
		validate = function(v)
			local ok, why = inner.validate(v)
			if not ok then
				return false, why
			end
			if type(v) ~= "number" then
				return false, "expected a number"
			end
			return inRange(v)
		end,
		autocomplete = function(prefix)
			-- enumerate only a fully-bounded integer range; otherwise nothing useful
			if not isInt or min == nil or max == nil then
				return {}
			end
			local lo = if minInc then math.ceil(min) else math.floor(min) + 1
			local hi = if maxInc then math.floor(max) else math.ceil(max) - 1
			local out = {}
			for value = lo, hi do
				if #out >= ENUM_CAP then
					break
				end
				local text = tostring(value)
				if string.sub(text, 1, #prefix) == prefix then
					table.insert(out, text)
				end
			end
			return out
		end,
	}
end

local function dedupe(list: { string }): { string }
	local seen, out = {}, {}
	for _, item in list do
		if not seen[item] then
			seen[item] = true
			table.insert(out, item)
		end
	end
	return out
end

local function compileUnion(node: any): Type
	local options = {}
	local names = {}
	for _, opt in node.options do
		local t = compileNode(opt)
		table.insert(options, t)
		table.insert(names, t.name)
	end
	return {
		name = table.concat(names, " | "),
		transform = function(raw)
			local firstErr
			for _, opt in options do
				local value, err = opt.transform(raw)
				if err == nil then
					local ok = opt.validate(value)
					if ok then
						return value
					end
				end
				firstErr = firstErr or err
			end
			return nil, firstErr or `'{raw}' matched no option`
		end,
		validate = function(v)
			for _, opt in options do
				if opt.validate(v) then
					return true
				end
			end
			return false, `matched none of {table.concat(names, " | ")}`
		end,
		autocomplete = function(prefix)
			local out = {}
			for _, opt in options do
				for _, s in opt.autocomplete(prefix) do
					table.insert(out, s)
				end
			end
			return dedupe(out)
		end,
	}
end

local function compileIntersection(node: any): Type
	local parts = {}
	local names = {}
	for _, p in node.parts do
		local t = compileNode(p)
		table.insert(parts, t)
		table.insert(names, t.name)
	end
	return {
		name = table.concat(names, " & "),
		transform = parts[1].transform, -- the first part reads the value; the rest constrain it
		validate = function(v)
			for _, part in parts do
				local ok, why = part.validate(v)
				if not ok then
					return false, why
				end
			end
			return true
		end,
		autocomplete = function(prefix)
			-- the first part's completions, kept only if they satisfy the rest
			local out = {}
			for _, s in parts[1].autocomplete(prefix) do
				local value, err = parts[1].transform(s)
				local keep = err == nil
				if keep then
					for i = 2, #parts do
						if not parts[i].validate(value) then
							keep = false
							break
						end
					end
				end
				if keep then
					table.insert(out, s)
				end
			end
			return out
		end,
	}
end

function compileNode(node: any): Type
	if node == nil then
		return unknownType("?")
	elseif node.kind == "Name" then
		return compileName(node)
	elseif node.kind == "Range" then
		return compileRange(node)
	elseif node.kind == "Union" then
		return compileUnion(node)
	elseif node.kind == "Intersection" then
		return compileIntersection(node)
	end
	return unknownType(node.kind or "?")
end

--- Compiles a type-expression string into a resolved [[Type]]. On a parse error
--- the returned type rejects everything, and the messages are in `.parseErrors`.
function Types.compile(source: string): Type & { parseErrors: { string } }
	local parsed = Expr.parse(source)
	if parsed.ast == nil or #parsed.errors > 0 then
		local bad: any = {
			name = source,
			optional = parsed.optional,
			parseErrors = parsed.errors,
			transform = function()
				return nil, `invalid type '{source}'`
			end,
			validate = function()
				return false, `invalid type '{source}'`
			end,
			autocomplete = noCompletions,
		}
		return bad
	end
	local resolved: any = compileNode(parsed.ast)
	resolved.optional = parsed.optional
	resolved.parseErrors = parsed.errors
	return resolved
end

return Types
