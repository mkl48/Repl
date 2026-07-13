-- Headless test runner. Usage: lune run tests/run

local process = require("@lune/process")
local Harness = require("./harness")

local specs = {
	{ name = "Lexer", spec = require("./lexer.spec") },
	{ name = "Parser", spec = require("./parser.spec") },
	{ name = "ReturnPool", spec = require("./returnpool.spec") },
	{ name = "Expr", spec = require("./expr.spec") },
	{ name = "Types", spec = require("./types.spec") },
	{ name = "Argument", spec = require("./argument.spec") },
	{ name = "Command", spec = require("./command.spec") },
	{ name = "Registry", spec = require("./registry.spec") },
	{ name = "Patterns", spec = require("./patterns.spec") },
	{ name = "Fuzzy", spec = require("./fuzzy.spec") },
	{ name = "Output", spec = require("./output.spec") },
	{ name = "Context", spec = require("./context.spec") },
	{ name = "Theme", spec = require("./theme.spec") },
	{ name = "Completer", spec = require("./completer.spec") },
	{ name = "History", spec = require("./history.spec") },
	{ name = "Signal", spec = require("./signal.spec") },
	{ name = "Dispatcher", spec = require("./dispatcher.spec") },
	{ name = "EventBus", spec = require("./eventbus.spec") },
}

local t = Harness.new()
for _, entry in specs do
	entry.spec(t)
end

print(`\n{t.passed} passed, {t.failed} failed`)
if t.failed > 0 then
	print("")
	for _, f in t.failures do
		print(`FAIL  {f.name}`)
		print(`      {tostring(f.err)}`)
	end
	process.exit(1)
end
process.exit(0)
