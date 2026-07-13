--- An **Option** — `some(value)` or `none()` — for the many places Repl has
--- "maybe a value": a resolved return, an optional argument, a looked-up command.
--- Keeps `nil`-juggling out of the call sites. Pairs with [[Result]].
--- @section Patterns
--- @client

local Option = {}
Option.__index = Option

export type Option = typeof(setmetatable({} :: { present: boolean, value: any }, Option))

--- An option holding `value`.
function Option.some(value: any): Option
	return setmetatable({ present = true, value = value }, Option)
end

--- The empty option.
function Option.none(): Option
	return setmetatable({ present = false }, Option)
end

--- `some(value)` if `value ~= nil`, else `none()`.
function Option.of(value: any): Option
	if value == nil then
		return Option.none()
	end
	return Option.some(value)
end

--- True if `value` is an Option.
function Option.is(value: any): boolean
	return type(value) == "table" and getmetatable(value) == Option
end

function Option.isSome(self: Option): boolean
	return self.present
end

function Option.isNone(self: Option): boolean
	return not self.present
end

--- The value if present; raises otherwise.
function Option.unwrap(self: Option): any
	if self.present then
		return self.value
	end
	error("unwrap on a none Option", 2)
end

--- The value if present, else `default`.
function Option.unwrapOr(self: Option, default: any): any
	if self.present then
		return self.value
	end
	return default
end

--- Maps the value if present; a none passes through.
function Option.map(self: Option, fn: (any) -> any): Option
	if self.present then
		return Option.of(fn(self.value))
	end
	return self
end

--- Chains an Option-returning fn if present; a none short-circuits.
function Option.andThen(self: Option, fn: (any) -> Option): Option
	if self.present then
		return fn(self.value)
	end
	return self
end

--- Branches: `arms.some(value)` or `arms.none()`.
function Option.match(self: Option, arms: { some: (any) -> any, none: () -> any }): any
	if self.present then
		return arms.some(self.value)
	end
	return arms.none()
end

return Option
