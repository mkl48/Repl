--- The **fuzzy matcher** behind autocomplete. A query matches a candidate when
--- its characters appear in order (a subsequence); the score rewards matches at
--- the start, on word boundaries (after `.` `_` `-` `/` space, or a camelCase
--- hump), and in consecutive runs — so `pk` ranks `players.kill` above a stray
--- mid-word hit. Returns the matched positions too, for highlighting.
--- @section Utility
--- @client

local Fuzzy = {}

export type Match = {
	value: string,
	score: number,
	positions: { number }, -- 1-based indices in `value` that matched, in query order
}

local SEPARATORS = "[%._%-/ ]"

local function isBoundary(candidate: string, pos: number): boolean
	if pos == 1 then
		return true
	end
	local prev = string.sub(candidate, pos - 1, pos - 1)
	if string.match(prev, SEPARATORS) then
		return true
	end
	-- camelCase hump: a lowercase char followed by an uppercase one
	local cur = string.sub(candidate, pos, pos)
	return string.match(prev, "%l") ~= nil and string.match(cur, "%u") ~= nil
end

--- Matches `query` against `candidate`. Returns `(score, positions)` or nil if
--- the query is not a subsequence. An empty query matches everything at score 0.
function Fuzzy.match(query: string, candidate: string): (number?, { number }?)
	if query == "" then
		return 0, {}
	end

	local q = string.lower(query)
	local c = string.lower(candidate)
	local positions: { number } = {}
	local qi = 1
	for ci = 1, #c do
		if qi > #q then
			break
		end
		if string.sub(c, ci, ci) == string.sub(q, qi, qi) then
			positions[qi] = ci
			qi += 1
		end
	end
	if qi <= #q then
		return nil, nil -- not every query char was consumed
	end

	local score = 0
	local prev: number? = nil
	for k, pos in positions do
		score += 1
		if prev ~= nil and pos == prev + 1 then
			score += 5 -- consecutive run
		end
		if isBoundary(candidate, pos) then
			score += 10
		end
		if pos == 1 then
			score += 15 -- matches the very start
		end
		if k == 1 then
			score -= (pos - 1) -- penalize how far in the first match sits
		end
		prev = pos
	end
	return score, positions
end

--- Filters and ranks `candidates` against `query`, best first (ties broken
--- alphabetically). Non-matches are dropped.
function Fuzzy.filter(query: string, candidates: { string }): { Match }
	local results: { Match } = {}
	for _, candidate in candidates do
		local score, positions = Fuzzy.match(query, candidate)
		if score ~= nil then
			table.insert(results, { value = candidate, score = score, positions = positions :: { number } })
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.value < b.value
	end)
	return results
end

return Fuzzy
