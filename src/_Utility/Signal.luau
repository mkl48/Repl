--- A tiny **signal** (event) — `Connect`, `Fire`, `Once`, `DisconnectAll`. Used
--- for the dev-facing terminal events (`Opened`, `Closed`, `FocusChanged`…) so a
--- game can react to the bar without pulling a UI dependency. Firing is snapshot-
--- safe: connecting or disconnecting inside a handler won't skip or double-fire
--- the current dispatch.
--- @section Utility
--- @client

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }

--- Creates an empty signal.
function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

--- Connects `fn`; returns a connection with `:Disconnect()`.
function Signal:Connect(fn: (...any) -> ()): Connection
	local connection
	connection = {
		Connected = true,
		Disconnect = function(_self)
			connection.Connected = false
			local index = table.find(self._handlers, connection)
			if index then
				table.remove(self._handlers, index)
			end
		end,
	}
	connection._fn = fn
	table.insert(self._handlers, connection)
	return connection
end

--- Connects `fn` for a single fire, then disconnects.
function Signal:Once(fn: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

--- Fires every current handler with the given arguments.
function Signal:Fire(...: any)
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			connection._fn(...)
		end
	end
end

--- Drops every handler.
function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
