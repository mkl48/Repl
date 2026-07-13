--- A **Result** — the typed outcome a command handler returns. `ok` carries a
--- value, `err` a message, and `abort` a cancellation; each has an exit `code`
--- (0 / 1 / 130) so the shell can branch chains (`a && b`, `a || b`) on real
--- outcomes rather than guessing from a return value. Pairs with [[Option]] and
--- backs `ctx:ok` / `ctx:err` / `ctx:abort`.
--- @section Patterns
--- @client

local Result = {}
Result.__index = Result

export type Result = typeof(setmetatable(
	{} :: { ok: boolean, value: any, error: string?, code: number, aborted: boolean? },
	Result
))

--- A success carrying `value` (exit code 0).
function Result.ok(value: any): Result
	return setmetatable({ ok = true, value = value, code = 0 }, Result)
end

--- A failure carrying `message` (exit code defaults to 1).
function Result.err(message: string, code: number?): Result
	return setmetatable({ ok = false, error = message, code = code or 1 }, Result)
end

--- A cancellation (exit code 130, mirroring SIGINT) — distinct from an error.
function Result.abort(reason: string?): Result
	return setmetatable({ ok = false, error = reason or "aborted", code = 130, aborted = true }, Result)
end

--- True if `value` is a Result.
function Result.is(value: any): boolean
	return type(value) == "table" and getmetatable(value) == Result
end

function Result.isOk(self: Result): boolean
	return self.ok
end

function Result.isErr(self: Result): boolean
	return not self.ok
end

--- The value on ok; raises the error message on err.
function Result.unwrap(self: Result): any
	if self.ok then
		return self.value
	end
	error(self.error or "unwrap on an err Result", 2)
end

--- The value on ok, else `default`.
function Result.unwrapOr(self: Result, default: any): any
	if self.ok then
		return self.value
	end
	return default
end

--- Maps the value on ok, passing err/abort through untouched.
function Result.map(self: Result, fn: (any) -> any): Result
	if self.ok then
		return Result.ok(fn(self.value))
	end
	return self
end

--- Chains a Result-returning fn on ok; short-circuits on err/abort.
function Result.andThen(self: Result, fn: (any) -> Result): Result
	if self.ok then
		return fn(self.value)
	end
	return self
end

--- Branches: `arms.ok(value)` or `arms.err(message, code)`.
function Result.match(self: Result, arms: { ok: (any) -> any, err: (string?, number) -> any }): any
	if self.ok then
		return arms.ok(self.value)
	end
	return arms.err(self.error, self.code)
end

return Result
