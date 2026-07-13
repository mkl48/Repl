--- The **built-in commands**, grouped by [[Command|realm]]. `install(Repl)`
--- registers them, skipping any name a game already took (so your own commands
--- win). Client commands need no server round-trip; Server commands are validated
--- against [[Authority]] capabilities; Shared runs on both sides.
--- @section Overview
--- @client

local Commands = {}

--- Registers every built-in on `Repl.Registry`, skipping name clashes.
function Commands.install(Repl: any)
	local function add(def)
		if not Repl.Registry:resolve(def.Name) then
			Repl.Registry:register(def)
		end
	end

	-- ── Client (no capabilities → base level, run locally) ───────────────────

	add({
		Name = "help",
		Aliases = { "commands" },
		Realm = "Client",
		Description = "List every command.",
		Run = function(ctx)
			local rows = { { "command", "description" } }
			for _, command in Repl.Registry:all() do
				table.insert(rows, { command.name, command.description })
			end
			ctx:table(rows)
			return ctx:ok()
		end,
	})

	add({
		Name = "theme",
		Realm = "Client",
		Description = "Switch the colorscheme.",
		Args = { `name: {table.concat(Repl.Theme.list(), " | ")} # the scheme to use` },
		Run = function(ctx, name)
			Repl.Theme:Set(name)
			return ctx:ok(`theme → {name}`)
		end,
	})

	add({
		Name = "themes",
		Realm = "Client",
		Description = "List the colorschemes.",
		Run = function(ctx)
			return ctx:ok(table.concat(Repl.Theme.list(), ", "))
		end,
	})

	add({
		Name = "clear",
		Aliases = { "cls" },
		Realm = "Client",
		Description = "Clear the terminal.",
		Run = function(ctx)
			-- routed to the bar if it exposed a clear bridge; harmless otherwise
			if ctx._bridge and ctx._bridge.clear then
				ctx._bridge.clear()
			end
			return ctx:ok()
		end,
	})

	-- ── Server (validated against Authority capabilities) ────────────────────

	add({
		Name = "kick",
		Realm = "Server",
		Capabilities = { "players.kick" },
		Description = "Kick a player.",
		Args = { "victim: Player", "reason: String? = Kicked by a moderator" },
		Run = function(ctx, victim, reason)
			victim:Kick(reason)
			return ctx:ok(`kicked {victim.Name}`)
		end,
	})

	add({
		Name = "announce",
		Realm = "Server",
		Capabilities = { "server.announce" },
		Description = "Broadcast a message to everyone.",
		Args = { "message: String" },
		Run = function(ctx, message)
			-- a game would post this to all clients over its own channel
			return ctx:ok(`announced: {message}`)
		end,
	})

	-- ── Shared (runs on both sides once Network routes it) ───────────────────

	add({
		Name = "ping",
		Realm = "Shared",
		Description = "A round-trip liveness check.",
		Run = function(ctx)
			return ctx:ok(`pong ({ctx.realm})`)
		end,
	})
end

return Commands
