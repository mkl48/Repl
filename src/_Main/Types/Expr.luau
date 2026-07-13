--- Parses a **type expression** — the text after the colon in an `Args` entry —
--- into a small AST the [[Types]] engine compiles. This is what makes
--- `Player | Character`, `Number & Int32`, and `2 < Number < 30` real.
---
--- Grammar (low → high precedence):
--- `Union(|) → Intersection(&) → Range(bounded atom) → Atom(Name | "(" expr ")")`.
--- A trailing `?` on the whole expression marks the argument optional.
--- @section Types
--- @client

local Expr = {}

export type Node = any -- { kind: "Union"|"Intersection"|"Range"|"Name", ... }

export type ParseResult = {
	ast: Node?,
	optional: boolean,
	errors: { string },
}

type Tok = { t: string, v: any }

local COMPARE: { [string]: boolean } = { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }

local function tokenize(source: string): { Tok }
	local toks: { Tok } = {}
	local i, n = 1, #source
	while i <= n do
		local c = string.sub(source, i, i)
		if string.match(c, "%s") then
			i += 1
		elseif c == "|" or c == "&" or c == "(" or c == ")" or c == "?" then
			table.insert(toks, { t = c })
			i += 1
		elseif c == "<" or c == ">" then
			if string.sub(source, i + 1, i + 1) == "=" then
				table.insert(toks, { t = c .. "=" })
				i += 2
			else
				table.insert(toks, { t = c })
				i += 1
			end
		elseif string.match(c, "%d") or (c == "-" and string.match(string.sub(source, i + 1, i + 1), "%d")) then
			local j = if c == "-" then i + 1 else i
			while j <= n and string.match(string.sub(source, j, j), "[%d%.]") do
				j += 1
			end
			table.insert(toks, { t = "num", v = tonumber(string.sub(source, i, j - 1)) })
			i = j
		elseif string.match(c, "[%a_]") then
			local j = i
			while j <= n and string.match(string.sub(source, j, j), "[%w_]") do
				j += 1
			end
			table.insert(toks, { t = "name", v = string.sub(source, i, j - 1) })
			i = j
		else
			i += 1 -- lenient: skip anything unrecognized
		end
	end
	table.insert(toks, { t = "eof" })
	return toks
end

--- Parses a type-expression string. Never throws; returns the AST (or nil),
--- whether the argument is optional (trailing `?`), and any errors.
function Expr.parse(source: string): ParseResult
	local toks = tokenize(source)
	local pos = 1
	local errors: { string } = {}

	local function cur(): Tok
		return toks[pos]
	end
	local function at(t: string): boolean
		return toks[pos].t == t
	end
	local function advance(): Tok
		local tok = toks[pos]
		if tok.t ~= "eof" then
			pos += 1
		end
		return tok
	end
	local function err(message: string)
		table.insert(errors, message)
	end

	local parseUnion, parseIntersection, parseConstrained, parseAtom

	function parseAtom(): Node?
		if at("(") then
			advance()
			local inner = parseUnion()
			if at(")") then
				advance()
			else
				err("expected ')'")
			end
			return inner
		elseif at("name") then
			local nameTok = advance()
			return { kind = "Name", name = nameTok.v }
		end
		err(`unexpected '{cur().t}' in a type`)
		if not at("eof") then
			advance()
		end
		return nil
	end

	-- a bounded atom: [num op] atom [op num]  (a range/conditional), else the atom
	function parseConstrained(): Node?
		local leadNum, leadOp
		if at("num") then
			leadNum = advance().v
			if COMPARE[cur().t] then
				leadOp = advance().t
			else
				err("expected a comparison after the bound")
			end
		end
		local atom = parseAtom()
		local trailOp, trailNum
		if COMPARE[cur().t] then
			trailOp = advance().t
			if at("num") then
				trailNum = advance().v
			else
				err("expected a number after the comparison")
			end
		end
		if leadNum == nil and trailNum == nil then
			return atom
		end
		local node: any = { kind = "Range", inner = atom }
		-- lead:  leadNum <op> atom
		if leadNum ~= nil and leadOp then
			if leadOp == "<" then
				node.min, node.minInc = leadNum, false
			elseif leadOp == "<=" then
				node.min, node.minInc = leadNum, true
			elseif leadOp == ">" then
				node.max, node.maxInc = leadNum, false
			elseif leadOp == ">=" then
				node.max, node.maxInc = leadNum, true
			end
		end
		-- trail:  atom <op> trailNum
		if trailNum ~= nil and trailOp then
			if trailOp == "<" then
				node.max, node.maxInc = trailNum, false
			elseif trailOp == "<=" then
				node.max, node.maxInc = trailNum, true
			elseif trailOp == ">" then
				node.min, node.minInc = trailNum, false
			elseif trailOp == ">=" then
				node.min, node.minInc = trailNum, true
			end
		end
		return node
	end

	function parseIntersection(): Node?
		local left = parseConstrained()
		if not at("&") then
			return left
		end
		local parts = { left }
		while at("&") do
			advance()
			table.insert(parts, parseConstrained())
		end
		return { kind = "Intersection", parts = parts }
	end

	function parseUnion(): Node?
		local left = parseIntersection()
		if not at("|") then
			return left
		end
		local options = { left }
		while at("|") do
			advance()
			table.insert(options, parseIntersection())
		end
		return { kind = "Union", options = options }
	end

	local ast = parseUnion()
	local optional = false
	if at("?") then
		advance()
		optional = true
	end
	if not at("eof") then
		err(`trailing '{cur().t}' in a type`)
	end
	return { ast = ast, optional = optional, errors = errors }
end

return Expr
