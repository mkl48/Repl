--- Token kinds and the `Token` shape for the Repl shell lexer.
---
--- The lexer is deliberately **neutral**: it never decides whether a token means
--- "reference" vs "division" or "flag" vs "minus". It emits the smallest tokens
--- plus `spaceBefore` adjacency, and the [[Parser]] assigns meaning by context
--- and token position.
--- @section Shell
--- @client

local Token = {}

Token.Kind = {
	Newline = "Newline",
	Semicolon = "Semicolon", -- ; (statement separator, same role as a newline)

	-- literals / words
	Number = "Number", -- 5, 3.14
	String = "String", -- "..."
	Boolean = "Boolean", -- true, false
	Ident = "Ident", -- names: commands, args, vars, labels, types

	-- references / sigils
	Slash = "Slash", -- /
	SlashSlash = "SlashSlash", -- //
	Dot = "Dot", -- .
	Hash = "Hash", -- #
	At = "At", -- @

	-- assignment / logic primitives
	Assign = "Assign", -- =
	Bang = "Bang", -- !
	Tilde = "Tilde", -- ~

	-- chain / boolean
	AmpAmp = "AmpAmp", -- &&
	PipePipe = "PipePipe", -- ||
	Amp = "Amp", -- &
	Pipe = "Pipe", -- | (pipeline: feed one command's output into the next)

	-- comparison
	EqEq = "EqEq", -- ==
	BangEq = "BangEq", -- !=
	Gte = "Gte", -- >=
	Lte = "Lte", -- <=
	Gt = "Gt", -- >
	Lt = "Lt", -- <

	-- arithmetic / dashes
	Plus = "Plus", -- +
	Minus = "Minus", -- -
	MinusMinus = "MinusMinus", -- --
	Star = "Star", -- *
	Percent = "Percent", -- %

	-- brackets
	LParen = "LParen", -- (
	RParen = "RParen", -- )
	LBrace = "LBrace", -- {
	RBrace = "RBrace", -- }
	LBracket = "LBracket", -- [
	RBracket = "RBracket", -- ]

	EOF = "EOF",
}

export type Kind = string

--- One lexed token. `value` is the cooked value for literals; `spaceBefore`
--- records whether whitespace separated this token from the previous one (so the
--- parser can tell `-s` the flag from `- s` the operator).
export type Token = {
	kind: Kind,
	text: string, -- raw source text matched
	value: any, -- cooked value: number | string | boolean | nil
	pos: number, -- 1-based byte offset of the first char
	line: number,
	col: number, -- 1-based byte column within the line
	spaceBefore: boolean, -- was this token separated from the previous by whitespace?
}

return Token
