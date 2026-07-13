-- Context specs. `lune run tests/run`

local Loader = require("./loader")
local Context = Loader.get("Context")
local Output = Loader.get("Output")
local EventBus = Loader.get("EventBus")

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

	test("new fills sensible defaults", function()
		local ctx = Context.new()
		eq(ctx.rawText, "", "empty rawText")
		eq(ctx.realm, "server", "default realm")
		eq(#ctx.output, 0, "no output yet")
		ok(ctx.returnPool ~= nil, "has a return pool")
	end)

	test("config fields are carried", function()
		local ctx = Context.new({ executor = "Ker", rawText = "kill Ker", args = { 1 }, realm = "client" })
		eq(ctx.executor, "Ker")
		eq(ctx.rawText, "kill Ker")
		eq(ctx.args[1], 1)
		eq(ctx.realm, "client")
	end)

	test("output methods emit and collect nodes", function()
		local ctx = Context.new()
		ctx:reply("hi")
		ctx:success("done")
		ctx:error("boom")
		eq(#ctx.output, 3, "three nodes")
		eq(ctx.output[2].kind, "success")
		eq(Output.toText(ctx.output[1]), "hi")
	end)

	test("the sink receives each emitted node live", function()
		local seen = {}
		local ctx = Context.new({ sink = function(node)
			table.insert(seen, node.kind)
		end })
		ctx:warn("w")
		ctx:info("i")
		eq(table.concat(seen, ","), "warn,info", "sink saw both, in order")
	end)

	test("ok reports success and returns an ok Result", function()
		local ctx = Context.new()
		local result = ctx:ok("killed 3")
		ok(result:isOk(), "ok result")
		eq(result:unwrap(), "killed 3", "carries the value")
		eq(ctx.output[1].kind, "success", "emitted a success line")
	end)

	test("err returns an err Result and emits an error line", function()
		local ctx = Context.new()
		local result = ctx:err("nope")
		ok(result:isErr(), "err result")
		eq(result.code, 1, "code 1")
		eq(ctx.output[1].kind, "error", "emitted an error line")
	end)

	test("abort returns an abort Result (code 130)", function()
		local ctx = Context.new()
		local result = ctx:abort("cancelled")
		ok(result.aborted, "aborted")
		eq(result.code, 130)
	end)

	test("returns pushes to the return pool", function()
		local ctx = Context.new()
		ctx:returns(42, "Number", "answer")
		local value = ctx.returnPool:resolve({ last = true, path = {} })
		eq(value, 42, "resolvable from the pool")
	end)

	test("store reads and writes", function()
		local ctx = Context.new()
		eq(ctx:store("x"), nil, "absent -> nil")
		eq(ctx:store("x", 7), 7, "write returns the value")
		eq(ctx:store("x"), 7, "read sees it")
	end)

	test("table and ascii emit blocks", function()
		local ctx = Context.new()
		ctx:table({ { "a", "b" }, { "1", "2" } })
		ctx:ascii("line1\nline2")
		eq(ctx.output[1].class, "Block", "table is a block")
		eq(ctx.output[2].kind, "ascii", "ascii block")
		eq(#ctx.output[2].lines, 2, "two ascii lines")
	end)

	test("confirm delegates to the bridge", function()
		local ctx = Context.new({ bridge = { confirm = function(message)
			return message == "sure?"
		end } })
		eq(ctx:confirm("sure?"), true, "bridge answered")
	end)

	test("an interactive call without a bridge errors clearly", function()
		local ctx = Context.new()
		local okCall, err = pcall(function()
			ctx:confirm("sure?")
		end)
		eq(okCall, false, "raised")
		ok(string.find(tostring(err), "confirm", 1, true) ~= nil, "mentions the method")
	end)

	-- shared commands: two contexts on one bus stand in for the two sides --------

	test("post reaches a subscriber on the shared bus", function()
		local bus = EventBus.new()
		local server = Context.new({ realm = "server", bus = bus })
		local client = Context.new({ realm = "client", bus = bus })
		local got
		server:subscribe("hello", function(name)
			got = name
		end)
		client:post("hello", "Ker")
		eq(got, "Ker", "the other side received it")
	end)

	test("post:Await returns the subscriber's response (request/response)", function()
		local bus = EventBus.new()
		local server = Context.new({ realm = "server", bus = bus })
		local client = Context.new({ realm = "client", bus = bus })
		server:subscribe("sum", function(a, b)
			return a + b
		end)
		eq(client:post("sum", 2, 3):Await(), 5, "awaited the response")
	end)

	test("a late subscriber still receives an earlier post (queued)", function()
		local bus = EventBus.new()
		local a = Context.new({ bus = bus })
		local b = Context.new({ bus = bus })
		a:post("boot", "ready")
		local seen
		b:subscribe("boot", function(v)
			seen = v
		end)
		eq(seen, "ready", "replayed to the late side")
	end)

	test("Await uses the network bridge when one is present", function()
		local ctx = Context.new({ net = function(event, payload)
			return `{event}:{payload}` -- stand-in for the awaited RemoteFunction
		end })
		eq(ctx:post("ping", "x"):Await(), "ping:x", "cross-realm response")
	end)
end
