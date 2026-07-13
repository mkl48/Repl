--- The pattern types Repl passes around: [[Result]] (a command outcome with an
--- exit code) and [[Option]] (a maybe-value). `Stream` (incremental output) lands
--- here alongside them once the Output model is in.
--- @section Patterns
--- @client

local Patterns = {}

Patterns.Result = require(script.Result)
Patterns.Option = require(script.Option)

return Patterns
