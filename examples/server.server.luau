--!strict
-- Repl server setup + role config. Drop this in as a Script (e.g. ServerScriptService)
-- with the Repl package at ReplicatedStorage.Repl.
--
-- Authority is capability-based: commands declare capabilities (dotted strings),
-- roles are bundles of them (with wildcards + inheritance), and a resolver maps a
-- player to their roles. Server/Shared commands are validated here on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Repl = require(ReplicatedStorage:WaitForChild("Repl"))

-- ── roles ────────────────────────────────────────────────────────────────────
-- everyone is a Player (the base level): no capabilities means base commands like
-- help/theme just work, with no auth.
Repl.Authority:DefineRole("Player", { Capabilities = {} })
Repl.Authority:SetDefaultRole("Player")

Repl.Authority:DefineRole("Mod", {
	Capabilities = { "players.kick" },
	Inherits = { "Player" },
})

Repl.Authority:DefineRole("Admin", {
	Capabilities = { "players.*", "server.*" }, -- wildcards
	Inherits = { "Mod" },
})

Repl.Authority:DefineRole("Owner", {
	Capabilities = { "*" }, -- everything
})

-- ── who gets which role ──────────────────────────────────────────────────────
-- the resolver runs per-command; return the role names a player holds. Mix in
-- group rank, gamepasses, attributes, a DataStore — whatever you like.
Repl.Authority:SetResolver(function(player: Player): { string }
	if player.UserId == game.CreatorId then
		return { "Owner" }
	end
	-- example: a group rank check
	-- if player:GetRankInGroup(1234567) >= 250 then return { "Admin" } end
	-- if player:GetRankInGroup(1234567) >= 100 then return { "Mod" } end
	return {}
end)

-- you can also assign statically at runtime:
-- game.Players.PlayerAdded:Connect(function(p) Repl.Authority:Assign(p, "Mod") end)

-- ── commands ─────────────────────────────────────────────────────────────────
-- the built-ins (kick, announce, …) live on the server realm; register your own
-- server commands the same way.
Repl:InstallBuiltins()

Repl:RegisterCommand({
	Name = "give",
	Realm = "Server",
	Capabilities = { "players.give" }, -- only Admins (players.*) or Owners pass
	Description = "Give a tool to a player.",
	Args = { "target: Player", "tool: String", "--count: Integer = 1" },
	Run = function(ctx, target, tool, _)
		return ctx:ok(`gave {ctx.flags.count}× {tool} to {target.Name}`)
	end,
})
