-- Headless test runner. Usage: lune run tests/run

local process = require("@lune/process")
local Harness = require("./harness")

local specs = {
	{ name = "Lexer", spec = require("./lexer.spec") },
	{ name = "Parser", spec = require("./parser.spec") },
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
