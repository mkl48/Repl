--!strict
-- Repl bar demo. Drop this in as a LocalScript (e.g. StarterPlayerScripts) with
-- the Repl package at ReplicatedStorage.Repl, then press ` (backquote) in-game.
--
-- The built-ins (help, theme, themes, clear, ping) install automatically on Start.
-- See server.server.luau for roles + server commands (kick, announce, give).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Repl = require(ReplicatedStorage:WaitForChild("Repl"))

Repl.Theme:Set("tokyonight")

-- one of your own client commands
Repl:RegisterCommand({
	Name = "hello",
	Realm = "Client",
	Description = "Greet someone.",
	Args = { "who: String? = world # who to greet" },
	Run = function(ctx, who)
		return ctx:ok(`hello, {who}!`)
	end,
})

-- gate a game keybind while the terminal is focused
Repl.FocusChanged:Connect(function(isFocused)
	print(`[game] terminal focused: {isFocused} — disable your own binds here`)
end)

Repl:Start()
-- everything is customizable:
-- Repl:Start({
--     Terminal = {
--         Compact = true,             -- single Cmdr-like bar
--         Align = "Center",           -- "Top" | "Bottom" | "Center"
--         Square = false,             -- no rounded corners
--         Scale = 1,                  -- UIScale over the whole terminal
--         Transparency = 0.1,         -- command-line background
--         Directory = "MyGame",       -- prompt root -> "MyGame/kr3ative/repl >"
--         Intellisense = true,        -- the live signature hint
--         Width = 720,
--     },
-- })
