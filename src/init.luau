--- Repl — the umbrella module. `require(ReplicatedStorage.Repl)` returns the
--- whole public API; it's realm-aware (server → registry/authority, client →
--- the bar). A standalone module: nothing to wire together.
---
--- **Status: early.** The shell front end (lexer → parser → AST) is in and
--- tested; the registry, type engine, authority, context, network, and the
--- Fusion bar are being built up the pipeline. See DESIGN.md.
--- @section Overview
--- @client

local Repl = {}

-- Internal subsystems live under the _-prefixed folders:
--   _Classes  · _Main (Client/Server/Types/Network) · _Patterns
--   _Utility (Shell/Fuzzy/Render) · _Commands (_Client/_Server/_Shared/_Types)
--   _Packages (vendored deps)

-- Available today: the shell front end, the type engine, and the pattern types.
Repl.Shell = require(script._Utility.Shell)
Repl.Types = require(script._Main.Types)

local Patterns = require(script._Patterns)
Repl.Result = Patterns.Result
Repl.Option = Patterns.Option

return Repl
