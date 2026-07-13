--- The shell front end: source → tokens → AST. Re-exports the stages
--- ([[Lexer]], [[Parser]], [[Ast]], [[Token]]) and the two entry points.
--- @section Shell
--- @client

local Shell = {}

Shell.Token = require(script.Token)
Shell.Lexer = require(script.Lexer)
Shell.Ast = require(script.Ast)
Shell.Parser = require(script.Parser)
Shell.ReturnPool = require(script.ReturnPool)

--- Tokenize source into a flat token list + diagnostics.
Shell.tokenize = Shell.Lexer.tokenize
--- Tokenize and parse source into an AST + diagnostics.
Shell.parse = Shell.Parser.parse

return Shell
