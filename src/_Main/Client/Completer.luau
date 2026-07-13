--- The **completion engine** behind the bar. Given the current input, it decides
--- whether the cursor is on the *command name* (fuzzy-matched against the
--- [[Registry]]) or on an *argument* (whose compiled [[Types|type]] supplies the
--- suggestions — including a range's enumerated values), and returns ranked
--- completions with the text span each one replaces. Pure logic: the bar draws
--- the results, this decides them, so it's fully headless-testable.
--- @section Client
--- @client

local Fuzzy = require(script.Parent.Parent.Parent._Utility.Fuzzy)

local Completer = {}

--- One suggestion. `replaceStart`/`replaceEnd` are 1-based byte offsets into the
--- input that the bar overwrites when the completion is accepted.
export type Completion = {
	text: string,
	kind: "command" | "argument",
	detail: string, -- a description / type hint shown beside the entry
	replaceStart: number,
	replaceEnd: number,
}

-- the registry surface the completer needs (kept structural so tests can pass a
-- real Registry or a stub)
export type RegistryLike = {
	all: (self: any) -> { any },
	resolve: (self: any, nameOrAlias: string) -> any?,
}

local function splitWords(input: string): ({ string }, boolean)
	local words = {}
	for word in string.gmatch(input, "%S+") do
		table.insert(words, word)
	end
	local endsWithSpace = input == "" or string.match(input, "%s$") ~= nil
	return words, endsWithSpace
end

--- Produces completions for `input` against `registry` (cursor assumed at end).
function Completer.complete(registry: RegistryLike, input: string): { Completion }
	local words, endsWithSpace = splitWords(input)

	local position: number
	local currentWord: string
	if endsWithSpace then
		position = #words + 1 -- starting a fresh token
		currentWord = ""
	else
		position = #words
		currentWord = words[#words] or ""
	end

	local replaceStart = #input - #currentWord + 1
	local replaceEnd = #input
	local out: { Completion } = {}

	if position <= 1 then
		-- completing the command name: fuzzy over names + aliases
		local names: { string } = {}
		for _, command in registry:all() do
			table.insert(names, command.name)
			for _, alias in command.aliases do
				table.insert(names, alias)
			end
		end
		for _, match in Fuzzy.filter(currentWord, names) do
			local command = registry:resolve(match.value)
			table.insert(out, {
				text = match.value,
				kind = "command",
				detail = command and command.description or "",
				replaceStart = replaceStart,
				replaceEnd = replaceEnd,
			})
		end
	else
		-- completing an argument: ask that argument's type
		local command = registry:resolve(words[1])
		if command then
			local arg = command.args[position - 1]
			if arg then
				for _, suggestion in arg.type.autocomplete(currentWord) do
					table.insert(out, {
						text = suggestion,
						kind = "argument",
						detail = `{arg.name}: {arg.typeExpr}`,
						replaceStart = replaceStart,
						replaceEnd = replaceEnd,
					})
				end
			end
		end
	end

	return out
end

--- The ghost-text completion of `input`: the remaining characters of the single
--- best suggestion, if it *extends* the current word (case-insensitive prefix).
--- Returns "" when there's nothing to ghost.
function Completer.ghost(registry: RegistryLike, input: string): string
	local completions = Completer.complete(registry, input)
	local best = completions[1]
	if not best then
		return ""
	end
	local typed = string.sub(input, best.replaceStart, best.replaceEnd)
	if typed ~= "" and string.sub(string.lower(best.text), 1, #typed) == string.lower(typed) then
		return string.sub(best.text, #typed + 1)
	end
	return ""
end

return Completer
