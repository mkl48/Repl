--- The **network layer** — how a client hands a Server/Shared command to the
--- server. It's a single [[Substance]] `Solve` channel (a RemoteFunction), so a
--- `run` is an *awaited round-trip*: the client blocks until the server has
--- validated, executed, and returned the rendered output + exit code. The server
--- is authoritative — it re-parses and re-checks capabilities against the real
--- executor, never trusting the client.
---
--- Studio-only (pulls Substance). The realm-neutral queuing lives in [[EventBus]];
--- this is just the transport.
--- @section Server
--- @client

-- Network is _Main/Network/init, so root is two parents up (Network → _Main → Repl)
local Substance = require(script.Parent.Parent._Packages.Substance)

local Network = {}

local CHANNEL = "Repl.Run"
local ready = false

-- define + compose the Solve (RemoteFunction) channel once, on either realm
local function ensure()
	if ready then
		return
	end
	ready = true
	local atom = Substance.Define("ReplRunAtom", { line = "string" })
	atom:Compose(CHANNEL, "Solve")
end

--- Server: handle incoming runs. `handler(line, player)` returns the response
--- table (`{ output, code, error }`) sent back over the RemoteFunction.
function Network.serve(handler: (line: string, player: Player) -> any)
	ensure()
	Substance.Subscribe(CHANNEL, function(payload: any, player: Player?)
		return handler(payload.line, player :: Player)
	end)
end

--- Client: run `line` on the server and block for the response.
function Network.run(line: string): any
	ensure()
	return Substance.Post(CHANNEL, { line = line }):Await()
end

-- ── command registration replication ─────────────────────────────────────────
-- a Strict (RemoteEvent) channel broadcasts a command's metadata to the other
-- realm; a Solve channel lets a client pull the server's full command list.

local REG = "Repl.Register"
local LIST = "Repl.List"
local regReady, listReady = false, false

local function ensureReg()
	if regReady then
		return
	end
	regReady = true
	Substance.Define("ReplRegisterAtom", {}):Compose(REG, "Strict")
end

local function ensureList()
	if listReady then
		return
	end
	listReady = true
	Substance.Define("ReplListAtom", {}):Compose(LIST, "Solve")
end

--- Broadcasts one command's metadata to the other realm (server → all clients,
--- or client → server).
function Network.publishRegistration(metadata: any)
	ensureReg()
	pcall(function()
		Substance.Post(REG, metadata)
	end)
end

--- Receives metadata broadcasts from the other realm.
function Network.onRegistration(handler: (metadata: any) -> ())
	ensureReg()
	Substance.Subscribe(REG, function(metadata: any)
		handler(metadata)
	end)
end

--- Server: answer a client's request for the full command list.
function Network.serveList(getList: () -> { any })
	ensureList()
	Substance.Subscribe(LIST, function()
		return getList()
	end)
end

--- Client: pull the server's command list (empty on failure).
function Network.requestList(): { any }
	ensureList()
	local okCall, list = pcall(function()
		return Substance.Post(LIST, {}):Await()
	end)
	if okCall and type(list) == "table" then
		return list
	end
	return {}
end

return Network
