-- Parser specs. `lune run tests/run`

local Loader = require("./loader")
local Parser = Loader.get("Parser")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end
local function truthy(v, message)
	if not v then
		error(message or "expected truthy", 2)
	end
end

local function program(src)
	return Parser.parse(src).ast
end
-- the node of the first statement of the first chain
local function stmt(src)
	return program(src).chains[1].steps[1].node
end

return function(t)
	local test = t.test

	test("a bare command with a reference arg", function()
		local c = stmt("kill /Player")
		eq(c.kind, "Command", "command node")
		eq(c.name, "kill", "command name")
		eq(#c.args, 1, "one arg")
		eq(c.args[1].kind, "Reference", "arg is a reference")
		eq(c.args[1].name, "Player", "reference name")
	end)

	test("chain: a && b || c", function()
		local chain = program("a && b || c").chains[1]
		eq(#chain.steps, 3, "three steps")
		eq(chain.steps[1].op, nil, "first has no op")
		eq(chain.steps[2].op, "&&", "second op")
		eq(chain.steps[3].op, "||", "third op")
		eq(chain.steps[2].node.name, "b", "second command")
	end)

	test("pipeline: a | b | c", function()
		local p = stmt("a | b | c")
		eq(p.kind, "Pipeline", "pipeline node")
		eq(#p.stages, 3, "three stages")
		eq(p.stages[3].name, "c", "third stage")
	end)

	test("expression group: (1 + 2 * 3)", function()
		local s = stmt("(1 + 2 * 3)")
		eq(s.kind, "ValueStmt", "value statement")
		eq(s.value.kind, "Binary", "binary")
		eq(s.value.op, "+", "add at the top (mul binds tighter)")
		eq(s.value.right.op, "*", "right side is the multiply")
	end)

	test("references: //, /x#2, /x.prop", function()
		eq(stmt("//").value.last, true, "// is the last-return reference")
		local idx = stmt("/target#2").value
		eq(idx.name, "target", "name")
		eq(idx.index, 2, "index")
		local path = stmt("/thing.health").value
		eq(path.path[1], "health", "dotted path")
	end)

	test("variables: @x, @x.prop, @TYPE[Player]", function()
		local c = stmt("give @x")
		eq(c.args[1].kind, "VarRef", "var ref")
		eq(c.args[1].name, "x", "var name")
		local ty = stmt("give @TYPE[Player]").args[1]
		eq(ty.kind, "TypeValue", "type value")
		eq(ty.typeName, "Player", "type name")
	end)

	test("flags and negative-number args (adjacency)", function()
		local c = stmt("cmd -s -x -5")
		eq(#c.flags, 2, "two flags")
		eq(c.flags[1], "s", "flag s")
		eq(#c.args, 1, "one arg (the -5)")
		eq(c.args[1].value, -5, "negative literal")
	end)

	test("spaced minus is an operator, not a flag: (x - 2)", function()
		local s = stmt("(a - 2)")
		-- `a` alone before ` - ` is an expression: string 'a' minus 2
		eq(s.value.kind, "Binary", "binary subtraction")
		eq(s.value.op, "-", "minus operator")
	end)

	test("--key=value is a modifier; --Bare is a chain directive", function()
		local c = stmt("cmd --count=3")
		eq(c.modifiers.count.value, 3, "valued modifier")
		local chain = program("cmd --Dry-Run").chains[1]
		eq(chain.directives[1], "Dry-Run", "bare long option is a directive")
	end)

	test("assignment inside a group: (x = 2)", function()
		local s = stmt("(x = 2)")
		eq(s.value.kind, "Assignment", "assignment")
		eq(s.value.name, "x", "name")
		eq(s.value.value.value, 2, "value")
	end)

	test("guarded block: (@x == 4) { cmd }", function()
		local s = stmt("(@x == 4) { win }")
		eq(s.kind, "Guarded", "guarded")
		eq(s.guard.kind, "Guard", "guard")
		truthy(s.block, "has a block")
		eq(s.block.chains[1].steps[1].node.name, "win", "block command")
	end)

	test("postfix nil test: @x!", function()
		local s = stmt("(@x!)")
		eq(s.value.kind, "IsNil", "is-nil node")
		eq(s.value.operand.kind, "VarRef", "operand is the var")
	end)

	test("never throws on malformed input", function()
		local result = Parser.parse("kill /  && || ( ")
		truthy(result.ast, "still produced an ast")
		truthy(#result.diagnostics >= 1, "collected diagnostics")
	end)
end
