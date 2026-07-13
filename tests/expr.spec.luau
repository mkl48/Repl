-- Type-expression parser specs. `lune run tests/run`

local Loader = require("./loader")
local Expr = Loader.get("Expr")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end

return function(t)
	local test = t.test

	test("a bare name", function()
		local r = Expr.parse("Player")
		eq(#r.errors, 0, "no errors")
		eq(r.ast.kind, "Name")
		eq(r.ast.name, "Player")
		eq(r.optional, false, "not optional")
	end)

	test("trailing ? marks optional", function()
		local r = Expr.parse("Integer?")
		eq(r.optional, true, "optional")
		eq(r.ast.kind, "Name")
		eq(r.ast.name, "Integer")
	end)

	test("a union", function()
		local r = Expr.parse("Player | Character | Model")
		eq(r.ast.kind, "Union")
		eq(#r.ast.options, 3, "three options")
		eq(r.ast.options[1].name, "Player")
		eq(r.ast.options[3].name, "Model")
	end)

	test("an intersection", function()
		local r = Expr.parse("Number & Int32")
		eq(r.ast.kind, "Intersection")
		eq(#r.ast.parts, 2, "two parts")
	end)

	test("union binds looser than intersection", function()
		local r = Expr.parse("A & B | C")
		eq(r.ast.kind, "Union", "top is a union")
		eq(r.ast.options[1].kind, "Intersection", "left side is the intersection")
		eq(r.ast.options[2].name, "C")
	end)

	test("parentheses regroup", function()
		local r = Expr.parse("A & (B | C)")
		eq(r.ast.kind, "Intersection")
		eq(r.ast.parts[2].kind, "Union", "the group is a union")
	end)

	test("a two-sided range", function()
		local r = Expr.parse("2 < Number < 30")
		eq(r.ast.kind, "Range")
		eq(r.ast.inner.name, "Number")
		eq(r.ast.min, 2, "min 2")
		eq(r.ast.minInc, false, "min exclusive")
		eq(r.ast.max, 30, "max 30")
		eq(r.ast.maxInc, false, "max exclusive")
	end)

	test("a one-sided inclusive range", function()
		local r = Expr.parse("Number >= 0")
		eq(r.ast.kind, "Range")
		eq(r.ast.min, 0, "min 0")
		eq(r.ast.minInc, true, "min inclusive")
		eq(r.ast.max, nil, "no max")
	end)

	test("a reversed range normalizes", function()
		local r = Expr.parse("30 > Number > 2")
		eq(r.ast.kind, "Range")
		eq(r.ast.max, 30, "max 30")
		eq(r.ast.min, 2, "min 2")
	end)

	test("garbage records an error, never throws", function()
		local r = Expr.parse("| |")
		eq(#r.errors > 0, true, "has errors")
	end)
end
