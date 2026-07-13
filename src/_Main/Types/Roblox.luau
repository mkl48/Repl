--- Built-in Roblox argument types, registered onto the [[Types]] engine at
--- startup so `Args = { "victim: Player" }` works out of the box — with autofill.
---
--- A type has three jobs and *autocomplete is what fills in suggestions*: it takes
--- the partial text and returns the matching options. `Player` lists online player
--- names, `Players` adds `all`/`*`, `Team` lists team names. `transform` turns the
--- chosen text into the real instance, and `validate` confirms a value is the right
--- kind (both must actually return — a `validate` that returns nothing reads as
--- "invalid").
--- @section Types
--- @client

local Roblox = {}

--- Registers Player / Players / Team on a Types engine.
function Roblox.register(Types: any)
	local Players = game:GetService("Players")
	local Teams = game:GetService("Teams")

	-- online names whose start matches the partial input (this is the autofill)
	local function matchNames(prefix: string): { string }
		local low = string.lower(prefix)
		local names = {}
		for _, player in Players:GetPlayers() do
			if string.sub(string.lower(player.Name), 1, #low) == low then
				table.insert(names, player.Name)
			end
		end
		return names
	end

	-- resolve a name (or DisplayName), exact then case-insensitive
	local function findPlayer(raw: string): Player?
		local exact = Players:FindFirstChild(raw)
		if exact and exact:IsA("Player") then
			return exact
		end
		local low = string.lower(raw)
		for _, player in Players:GetPlayers() do
			if string.lower(player.Name) == low or string.lower(player.DisplayName) == low then
				return player
			end
		end
		return nil
	end

	Types.register({
		name = "Player",
		transform = function(raw)
			local player = findPlayer(raw)
			if player then
				return player -- the Player instance, not the service
			end
			return nil, `no player '{raw}'`
		end,
		validate = function(value)
			if typeof(value) == "Instance" and value:IsA("Player") then
				return true -- validate must return a boolean
			end
			return false, "expected a player"
		end,
		autocomplete = matchNames, -- ← the autofill
	})

	Types.register({
		name = "Players",
		transform = function(raw)
			if raw == "*" or string.lower(raw) == "all" then
				return Players:GetPlayers()
			end
			local player = findPlayer(raw)
			if player then
				return { player }
			end
			return nil, `no player '{raw}'`
		end,
		validate = function(value)
			return type(value) == "table", if type(value) == "table" then nil else "expected players"
		end,
		autocomplete = function(prefix)
			local out = matchNames(prefix)
			for _, keyword in { "all", "*" } do
				if string.sub(keyword, 1, #prefix) == prefix then
					table.insert(out, keyword)
				end
			end
			return out
		end,
	})

	Types.register({
		name = "Team",
		transform = function(raw)
			local team = Teams:FindFirstChild(raw)
			if team and team:IsA("Team") then
				return team
			end
			return nil, `no team '{raw}'`
		end,
		validate = function(value)
			if typeof(value) == "Instance" and value:IsA("Team") then
				return true
			end
			return false, "expected a team"
		end,
		autocomplete = function(prefix)
			local low = string.lower(prefix)
			local out = {}
			for _, team in Teams:GetTeams() do
				if string.sub(string.lower(team.Name), 1, #low) == low then
					table.insert(out, team.Name)
				end
			end
			return out
		end,
	})
end

return Roblox
