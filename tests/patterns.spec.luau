-- Result / Option specs. `lune run tests/run`

local Loader = require("./loader")
local Result = Loader.get("Result")
local Option = Loader.get("Option")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end
local function ok(cond, message)
	if not cond then
		error(message or "expected truthy", 2)
	end
end

return function(t)
	local test = t.test

	-- Result ----------------------------------------------------------------

	test("ok carries a value and exit code 0", function()
		local r = Result.ok(42)
		ok(r:isOk(), "is ok")
		eq(r.code, 0, "code 0")
		eq(r:unwrap(), 42, "unwrap")
	end)

	test("err carries a message and code 1", function()
		local r = Result.err("nope")
		ok(r:isErr(), "is err")
		eq(r.code, 1, "code 1")
		eq(r:unwrapOr("fallback"), "fallback", "unwrapOr on err")
	end)

	test("abort is a distinct outcome with code 130", function()
		local r = Result.abort("cancelled")
		ok(r:isErr(), "abort is not ok")
		eq(r.code, 130, "SIGINT-style code")
		eq(r.aborted, true, "flagged aborted")
	end)

	test("map transforms ok and passes err through", function()
		eq(Result.ok(2):map(function(n)
			return n * 10
		end):unwrap(), 20, "mapped ok")
		local e = Result.err("bad"):map(function(n)
			return n * 10
		end)
		ok(e:isErr(), "err unchanged")
	end)

	test("andThen chains and short-circuits", function()
		local chained = Result.ok(3):andThen(function(n)
			return Result.ok(n + 1)
		end)
		eq(chained:unwrap(), 4, "chained ok")
		local stopped = Result.err("x"):andThen(function()
			return Result.ok("never")
		end)
		ok(stopped:isErr(), "short-circuited")
	end)

	test("match branches", function()
		local out = Result.err("boom", 7):match({
			ok = function()
				return "ok"
			end,
			err = function(message, code)
				return `{message}:{code}`
			end,
		})
		eq(out, "boom:7", "err arm with code")
	end)

	test("Result.is recognizes results", function()
		ok(Result.is(Result.ok(1)), "a result")
		ok(not Result.is({ ok = true }), "a plain table is not")
	end)

	-- Option ----------------------------------------------------------------

	test("some / none basics", function()
		ok(Option.some(1):isSome(), "some")
		ok(Option.none():isNone(), "none")
		eq(Option.some("v"):unwrap(), "v", "unwrap some")
		eq(Option.none():unwrapOr("d"), "d", "unwrapOr none")
	end)

	test("Option.of folds nil to none", function()
		ok(Option.of(nil):isNone(), "nil -> none")
		ok(Option.of(5):isSome(), "value -> some")
	end)

	test("map and andThen respect presence", function()
		eq(Option.some(2):map(function(n)
			return n + 1
		end):unwrap(), 3, "mapped")
		ok(Option.none():map(function()
			return 1
		end):isNone(), "none stays none")
		eq(Option.some(2):andThen(function(n)
			return Option.some(n * 5)
		end):unwrap(), 10, "chained")
	end)

	test("mapping to nil collapses to none", function()
		ok(Option.some(1):map(function()
			return nil
		end):isNone(), "nil result -> none")
	end)
end
