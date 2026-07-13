-- Dispatcher specs. `lune run tests/run`

local Loader = require("./loader")
local Dispatcher = Loader.get("Dispatcher")
local Registry = Loader.get("Registry")
local Result = Loader.get("Result")

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

local function buildRegistry()
	local reg = Registry.new()
	reg:register({ Name = "ok", Run = function(ctx)
		return ctx:ok("done")
	end })
	reg:register({ Name = "fail", Run = function(ctx)
		return ctx:err("nope")
	end })
	reg:register({ Name = "add", Args = { "a: Integer", "b: Integer" }, Run = function(ctx, a, b)
		return ctx:ok(a + b)
	end })
	reg:register({ Name = "greet", Args = { "who: String? = world" }, Run = function(ctx, who)
		return ctx:ok(who)
	end })
	reg:register({ Name = "make", Run = function(ctx)
		ctx:returns(42, "Number")
		return ctx:ok()
	end })
	reg:register({ Name = "take", Args = { "n: Number" }, Run = function(ctx, n)
		return ctx:ok(n)
	end })
	reg:register({ Name = "boom", Run = function()
		error("kaboom")
	end })
	reg:register({
		Name = "deploy",
		Args = { "target: String", "-f, --force", "--count: Integer = 1" },
		Run = function(ctx, target)
			return ctx:ok(`{target} force={tostring(ctx.flags.force)} count={ctx.flags.count}`)
		end,
	})
	reg:register({ Name = "neg", Args = { "n: Number" }, Run = function(ctx, n)
		return ctx:ok(n)
	end })
	return reg
end

return function(t)
	local test = t.test

	test("a single command runs and returns its Result", function()
		local d = Dispatcher.new(buildRegistry())
		local result = d:run("add 2 3")
		ok(result:isOk(), "ok")
		eq(result:unwrap(), 5, "typed args summed")
	end)

	test("an argument default is filled", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("greet"):unwrap(), "world", "default used")
		eq(d:run("greet Ker"):unwrap(), "Ker", "explicit value")
	end)

	test("a missing required argument errors", function()
		local d = Dispatcher.new(buildRegistry())
		ok(d:run("add 2"):isErr(), "missing b")
	end)

	test("a bad argument value errors", function()
		local d = Dispatcher.new(buildRegistry())
		ok(d:run("add two 3"):isErr(), "'two' is not an Integer")
	end)

	test("an unknown command errors", function()
		local d = Dispatcher.new(buildRegistry())
		ok(d:run("nope"):isErr(), "unknown")
	end)

	test("a throwing handler is caught as an error", function()
		local d = Dispatcher.new(buildRegistry())
		local result = d:run("boom")
		ok(result:isErr(), "caught")
	end)

	test("&& runs the next only on success", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("ok && add 2 3"):unwrap(), 5, "ran the second")
		ok(d:run("fail && add 2 3"):isErr(), "second skipped, fail result kept")
	end)

	test("|| runs the next only on failure", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("fail || greet Ker"):unwrap(), "Ker", "recovered")
		ok(d:run("ok || greet X"):isOk(), "second skipped")
		eq(d:run("ok || greet X"):unwrap(), "done", "kept the ok result")
	end)

	test("; always runs both", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("fail ; add 2 3"):unwrap(), 5, "second ran regardless")
	end)

	test("a // reference reads a prior return", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("make && take //"):unwrap(), 42, "// resolved from the pool")
	end)

	test("output is routed to the sink", function()
		local d = Dispatcher.new(buildRegistry())
		local seen = {}
		d:run("ok", { sink = function(node)
			table.insert(seen, node.kind)
		end })
		ok(table.find(seen, "success") ~= nil, "the success line reached the sink")
	end)

	test("an authorize gate can deny", function()
		local d = Dispatcher.new(buildRegistry(), { authorize = function(command)
			return command.name ~= "add", "denied"
		end })
		ok(d:run("add 2 3"):isErr(), "add denied")
		ok(d:run("ok"):isOk(), "ok allowed")
	end)

	test("flags default, then override", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("deploy prod"):unwrap(), "prod force=false count=1", "defaults")
		eq(d:run("deploy prod --force"):unwrap(), "prod force=true count=1", "long boolean flag")
		eq(d:run("deploy prod -f"):unwrap(), "prod force=true count=1", "short alias")
		eq(d:run("deploy prod --count 5"):unwrap(), "prod force=false count=5", "valued option")
	end)

	test("a flag may precede the positional", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("deploy --force prod"):unwrap(), "prod force=true count=1", "order-independent")
	end)

	test("a bad flag value errors, an unknown flag errors", function()
		local d = Dispatcher.new(buildRegistry())
		ok(d:run("deploy prod --count two"):isErr(), "not an Integer")
		ok(d:run("deploy prod --bogus"):isErr(), "unknown flag")
	end)

	test("a negative number is a value, not a flag", function()
		local d = Dispatcher.new(buildRegistry())
		eq(d:run("neg -5"):unwrap(), -5, "-5 binds as a number")
	end)

	test("router 'remote' delegates to the remote runner with exact source", function()
		local sent
		local d = Dispatcher.new(buildRegistry(), {
			router = function()
				return "remote"
			end,
			remote = function(text)
				sent = text
				return Result.ok("from server")
			end,
		})
		local r = d:run("add 2 3")
		eq(sent, "add 2 3", "the exact segment text was sent")
		ok(r:isOk(), "the remote result is returned")
	end)

	test("each chain segment routes with its own exact text", function()
		local texts = {}
		local d = Dispatcher.new(buildRegistry(), {
			router = function()
				return "remote"
			end,
			remote = function(text)
				table.insert(texts, text)
				return Result.ok()
			end,
		})
		d:run("add 2 3 && greet Ker")
		eq(texts[1], "add 2 3", "first segment")
		eq(texts[2], "greet Ker", "second segment, split at &&")
	end)

	test("router 'both' runs locally and remotely", function()
		local reg = buildRegistry()
		local ranLocal = false
		reg:register({ Name = "sync", Run = function(ctx)
			ranLocal = true
			return ctx:ok()
		end })
		local sent
		local d = Dispatcher.new(reg, {
			router = function(command)
				return if command and command.name == "sync" then "both" else "local"
			end,
			remote = function(text)
				sent = text
				return Result.ok()
			end,
		})
		d:run("sync")
		ok(ranLocal, "the local side ran")
		eq(sent, "sync", "the remote side was invoked too")
	end)

	test("before/after hooks fire", function()
		local reg = buildRegistry()
		local log = {}
		reg:on("before", function()
			table.insert(log, "before")
		end)
		reg:on("after", function()
			table.insert(log, "after")
		end)
		Dispatcher.new(reg):run("ok")
		eq(table.concat(log, ","), "before,after", "both fired around the run")
	end)
end
