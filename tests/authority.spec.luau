-- Authority specs. `lune run tests/run`

local Loader = require("./loader")
local Authority = Loader.get("Authority")

local function eq(a, b, message)
	if a ~= b then
		error(`{message or "expected equal"}: got {tostring(a)}, want {tostring(b)}`, 2)
	end
end
local function ok(cond, message)
	if not cond then
		error(message or "expected truthy", 2)
	end
end

return function(t)
	local test = t.test

	test("wildcard matching by segment", function()
		ok(Authority.matches("players.*", "players.kill"), "players.* covers players.kill")
		ok(Authority.matches("players.*", "players.kill.others"), "…and deeper")
		ok(Authority.matches("players.*", "players"), "…and the bare prefix")
		ok(Authority.matches("*", "anything.at.all"), "* covers everything")
		ok(Authority.matches("players.kill", "players.kill"), "exact match")
		ok(not Authority.matches("players.kill", "players.kill.others"), "exact is not a prefix")
		ok(not Authority.matches("players.*", "server.shutdown"), "different root")
	end)

	test("a role grants its capabilities", function()
		local auth = Authority.new()
		auth:DefineRole("Mod", { Capabilities = { "players.kick" } })
		auth:Assign("ker", "Mod")
		ok(auth:Can("ker", "players.kick"), "granted")
		ok(not auth:Can("ker", "players.ban"), "not granted")
	end)

	test("role inheritance flattens capabilities", function()
		local auth = Authority.new()
		auth:DefineRole("Mod", { Capabilities = { "players.kick" } })
		auth:DefineRole("Admin", { Capabilities = { "players.ban" }, Inherits = { "Mod" } })
		auth:Assign("ker", "Admin")
		ok(auth:Can("ker", "players.ban"), "own capability")
		ok(auth:Can("ker", "players.kick"), "inherited capability")
	end)

	test("wildcards inside a role", function()
		local auth = Authority.new()
		auth:DefineRole("Owner", { Capabilities = { "*" } })
		auth:Assign("ker", "Owner")
		ok(auth:Can("ker", "anything.here"), "owner can do anything")
	end)

	test("the default role is held by everyone", function()
		local auth = Authority.new()
		auth:DefineRole("Player", { Capabilities = { "theme", "chat" } })
		auth:SetDefaultRole("Player")
		ok(auth:Can("nobody", "theme"), "base capability without assignment")
		ok(not auth:Can("nobody", "players.kick"), "nothing above base")
	end)

	test("a dynamic resolver adds roles", function()
		local auth = Authority.new()
		auth:DefineRole("Admin", { Capabilities = { "players.*" } })
		auth:SetResolver(function(executor)
			if executor == "boss" then
				return { "Admin" }
			end
			return {}
		end)
		ok(auth:Can("boss", "players.kill"), "resolved into Admin")
		ok(not auth:Can("peon", "players.kill"), "others unaffected")
	end)

	test("CanAll reports missing capabilities", function()
		local auth = Authority.new()
		auth:DefineRole("Mod", { Capabilities = { "players.kick" } })
		auth:Assign("ker", "Mod")
		local okAll, missing = auth:CanAll("ker", { "players.kick", "server.shutdown" })
		eq(okAll, false, "not all granted")
		eq(missing[1], "server.shutdown", "the uncovered one")
		ok(auth:CanAll("ker", { "players.kick" }), "the granted subset passes")
	end)

	test("Unassign revokes a role", function()
		local auth = Authority.new()
		auth:DefineRole("Mod", { Capabilities = { "players.kick" } })
		auth:Assign("ker", "Mod")
		auth:Unassign("ker", "Mod")
		ok(not auth:Can("ker", "players.kick"), "revoked")
	end)

	test("inheritance cycles are safe", function()
		local auth = Authority.new()
		auth:DefineRole("A", { Capabilities = { "a" }, Inherits = { "B" } })
		auth:DefineRole("B", { Capabilities = { "b" }, Inherits = { "A" } })
		auth:Assign("ker", "A")
		ok(auth:Can("ker", "a") and auth:Can("ker", "b"), "both, no infinite loop")
	end)
end
