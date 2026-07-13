--- Command **history** for the bar — readline semantics. `add` records a
--- submitted line (consecutive duplicates and blanks dropped, capped to a limit);
--- `up`/`down` walk older→newer, and the in-progress line is saved as a *draft*
--- so pressing Down past the newest entry restores what you were typing. Pure
--- state, headless-testable.
--- @section Client
--- @client

local History = {}
History.__index = History

--- Creates a history buffer (default cap 100 entries).
function History.new(limit: number?)
	return setmetatable({
		entries = {} :: { string },
		limit = limit or 100,
		cursor = nil :: number?, -- nil = at the live line; else an index into entries
		draft = "", -- the live line stashed when navigation began
	}, History)
end

--- Records a submitted line and resets navigation. Blank lines and immediate
--- repeats are ignored.
function History:add(text: string)
	local trimmed = (string.gsub(text, "^%s*(.-)%s*$", "%1"))
	if trimmed == "" then
		self:reset()
		return
	end
	if self.entries[#self.entries] ~= trimmed then
		table.insert(self.entries, trimmed)
		while #self.entries > self.limit do
			table.remove(self.entries, 1)
		end
	end
	self:reset()
end

--- Moves to an older entry, stashing `current` as the draft on the first step.
--- Returns the entry to show, or nil when there's no history.
function History:up(current: string): string?
	if #self.entries == 0 then
		return nil
	end
	if self.cursor == nil then
		self.draft = current
		self.cursor = #self.entries
	else
		self.cursor = math.max(1, self.cursor - 1)
	end
	return self.entries[self.cursor]
end

--- Moves to a newer entry; stepping past the newest restores the draft (and
--- returns to the live line). Returns nil when not currently navigating.
function History:down(): string?
	if self.cursor == nil then
		return nil
	end
	self.cursor += 1
	if self.cursor > #self.entries then
		self.cursor = nil
		return self.draft
	end
	return self.entries[self.cursor]
end

--- Returns to the live line without changing the stored entries.
function History:reset()
	self.cursor = nil
	self.draft = ""
end

--- Every entry, oldest first (a copy).
function History:all(): { string }
	return table.clone(self.entries)
end

return History
