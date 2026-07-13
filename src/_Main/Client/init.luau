--- The **client realm**: the visible command [[Bar]] plus the headless pieces
--- that drive it — the [[Completer]] (autocomplete) and [[History]]. The
--- realm-aware `Repl.Start` wires a Bar to the dispatcher and network once those
--- land; until then, mount a Bar directly with `Client.Bar.new{...}`.
---
--- Requiring this pulls Fusion (via Bar), so it's client/Studio-only — the
--- server realm never touches it.
--- @section Client
--- @client

local Client = {}

Client.Bar = require(script.Bar)
Client.Completer = require(script.Completer)
Client.History = require(script.History)

return Client
