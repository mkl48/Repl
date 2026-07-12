-- Lexer specs. `lune run tests/run`

local Loader = require("./loader")
local Lexer = Loader.get("Lexer")

local function tokens(source: string)
	return Lexer.tokenize(source).tokens
end

-- token kinds excluding the trailing EOF
local function kinds(source: string): { string }
	local out = {}
	for _, tok in tokens(source) do
		if tok.kind ~= "EOF" then
			table.insert(out, tok.kind)
		end
	end
	return out
end

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end

local function kindsEq(source: string, want: { string })
	local got = kinds(source)
	eq(#got, #want, `token count for "{source}"`)
	for i, k in want do
		eq(got[i], k, `token {i} of "{source}"`)
	end
end

return function(t)
	local test = t.test

	test("numbers, decimals, booleans, idents", function()
		kindsEq("5 3.14 true false hello", { "Number", "Number", "Boolean", "Boolean", "Ident" })
		local toks = tokens("42")
		eq(toks[1].value, 42, "number value")
		eq(tokens("3.5")[1].value, 3.5, "decimal value")
	end)

	test("digit-led barewords stay idents (30s, 1d)", function()
		kindsEq("30s 1d 5m", { "Ident", "Ident", "Ident" })
		eq(tokens("30s")[1].kind, "Ident", "30s is an ident")
	end)

	test("comma lists and bracketed coords are one token", function()
		kindsEq("a,b,c", { "Ident" })
		kindsEq("1,200,1", { "Ident" })
		local coord = tokens("[1,2,3]")
		eq(coord[1].kind, "Ident", "coord list is an ident")
		eq(coord[1].value, "1,2,3", "brackets stripped, spaces removed")
	end)

	test("longest-match operators: // && || == != >= <= --", function()
		kindsEq("// && || == != >= <= --", {
			"SlashSlash", "AmpAmp", "PipePipe", "EqEq", "BangEq", "Gte", "Lte", "MinusMinus",
		})
		kindsEq("/ & | = ! > < -", {
			"Slash", "Amp", "Pipe", "Assign", "Bang", "Gt", "Lt", "Minus",
		})
	end)

	test("spaceBefore adjacency distinguishes -s from - s", function()
		local adjacent = tokens("kill -s")
		-- kill, Minus, s(Ident)
		eq(adjacent[2].kind, "Minus", "minus token")
		eq(adjacent[2].spaceBefore, true, "minus had a space before it")
		eq(adjacent[3].spaceBefore, false, "s is adjacent to the minus")

		local spaced = tokens("x - s")
		eq(spaced[2].spaceBefore, true, "minus spaced")
		eq(spaced[3].spaceBefore, true, "s spaced from minus")
	end)

	test("internal dash keeps an ident together; x-2 splits", function()
		kindsEq("Ignore-Errors", { "Ident" })
		kindsEq("x-2", { "Ident", "Minus", "Number" })
	end)

	test("strings with escapes are cooked", function()
		local s = tokens([["hi\tthere\n"]])
		eq(s[1].kind, "String", "string kind")
		eq(s[1].value, "hi\tthere\n", "escapes cooked")
	end)

	test("unterminated string yields a diagnostic but still a token", function()
		local result = Lexer.tokenize('"open')
		eq(result.tokens[1].kind, "String", "still a string token")
		eq(#result.diagnostics >= 1, true, "has a diagnostic")
	end)

	test("unexpected character yields a diagnostic", function()
		local result = Lexer.tokenize("`")
		eq(#result.diagnostics >= 1, true, "backtick is unexpected")
	end)

	test("sigils and brackets", function()
		kindsEq("@ . # ( ) { }", { "At", "Dot", "Hash", "LParen", "RParen", "LBrace", "RBrace" })
	end)

	test("always ends with EOF", function()
		local toks = tokens("hi")
		eq(toks[#toks].kind, "EOF", "last token is EOF")
	end)
end
