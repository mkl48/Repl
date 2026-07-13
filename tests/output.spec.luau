-- Structured output model specs. `lune run tests/run`

local Loader = require("./loader")
local Output = Loader.get("Output")

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

	test("a segment carries text and style", function()
		local seg = Output.segment("hi", { color = "accent", bold = true, icon = "check" })
		eq(seg.text, "hi")
		eq(seg.color, "accent")
		eq(seg.bold, true)
		eq(seg.icon, "check")
	end)

	test("a line accepts a raw string", function()
		local line = Output.line("plain", "hello")
		eq(line.class, "Line")
		eq(#line.segments, 1, "one segment")
		eq(line.segments[1].text, "hello")
	end)

	test("a line accepts a segment list", function()
		local line = Output.line("plain", { Output.segment("a"), Output.segment("b") })
		eq(#line.segments, 2, "two segments")
	end)

	test("semantic builders set kind and a color token", function()
		local line = Output.success("done")
		eq(line.kind, "success")
		eq(line.segments[1].color, "success", "colored by token, not Color3")
		eq(Output.error("boom").kind, "error")
		eq(Output.warn("careful").kind, "warn")
		eq(Output.info("fyi").kind, "info")
	end)

	test("toText flattens a line", function()
		eq(Output.toText(Output.success("ok")), "ok", "styling stripped")
	end)

	test("toText renders an icon as [name]", function()
		local line = Output.line("plain", { Output.segment("saved", { icon = "check" }) })
		eq(Output.toText(line), "[check] saved")
	end)

	test("a block groups lines and joins with newlines", function()
		local block = Output.block("block", { Output.plain("one"), Output.plain("two") })
		eq(block.class, "Block")
		eq(Output.toText(block), "one\ntwo")
	end)

	test("table aligns columns", function()
		local block = Output.table({
			{ "name", "hp" },
			{ "goblin", "10" },
			{ "dragonlord", "999" },
		})
		eq(block.kind, "table")
		local text = Output.toText(block)
		-- 'name' padded to the width of 'dragonlord' (10) then a 2-space gap
		ok(string.find(text, "name      ", 1, true) ~= nil, "short cell padded to column width")
	end)
end
