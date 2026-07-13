--- A **queued event bus** — the core of shared-command communication. Handlers
--- `subscribe` to named events; `post` delivers to everyone listening *and*
--- retains the payload, so a handler that subscribes late still receives every
--- earlier post (no race between a fast `post` and a slow `subscribe`). Each
--- subscriber sees each post exactly once, in order.
---
--- This is the realm-neutral core; the shared-command wrapper layers a
--- RemoteFunction round-trip on top so a cross-realm `post` returns a guaranteed
--- value. Headless-testable on its own.
--- @section Utility
--- @client

local EventBus = {}
EventBus.__index = EventBus

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }

local MAX_QUEUE = 256 -- per-event retention cap, to bound a long-lived bus

--- Creates an empty bus.
function EventBus.new()
	return setmetatable({
		_subs = {} :: { [string]: { any } },
		_queue = {} :: { [string]: { any } }, -- retained posts, replayed to late subscribers
	}, EventBus)
end

--- Subscribes `handler` to `event`. Any posts already made to `event` are
--- replayed to it immediately, in order. Returns a connection.
function EventBus:subscribe(event: string, handler: (...any) -> ()): Connection
	local list = self._subs[event]
	if not list then
		list = {}
		self._subs[event] = list
	end
	local connection
	connection = {
		Connected = true,
		Disconnect = function(_self)
			connection.Connected = false
			local index = table.find(list, connection)
			if index then
				table.remove(list, index)
			end
		end,
	}
	connection._handler = handler
	table.insert(list, connection)

	local queued = self._queue[event]
	if queued then
		for _, pack in queued do
			handler(table.unpack(pack, 1, pack.n))
		end
	end
	return connection
end

--- Subscribes for a single delivery, then disconnects.
function EventBus:once(event: string, handler: (...any) -> ()): Connection
	local connection
	connection = self:subscribe(event, function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

--- Posts to `event`: delivers to current subscribers and retains the payload for
--- future ones. Both realms may post; posts interleave in call order. Returns the
--- list of non-nil handler return values (for request/response over the bus).
function EventBus:post(event: string, ...: any): { any }
	local returns = {}
	local list = self._subs[event]
	if list then
		for _, connection in table.clone(list) do
			if connection.Connected then
				local result = connection._handler(...)
				if result ~= nil then
					table.insert(returns, result)
				end
			end
		end
	end
	local queue = self._queue[event]
	if not queue then
		queue = {}
		self._queue[event] = queue
	end
	table.insert(queue, table.pack(...))
	if #queue > MAX_QUEUE then
		table.remove(queue, 1)
	end
	return returns
end

--- Clears retained posts (and, with no event, all of them). Subscriptions stay.
function EventBus:clear(event: string?)
	if event then
		self._queue[event] = nil
	else
		table.clear(self._queue)
	end
end

--- Drops every subscription and retained post.
function EventBus:destroy()
	table.clear(self._subs)
	table.clear(self._queue)
end

return EventBus
