--!strict
-- Minimal Lua signal. Unlike BindableEvent it passes tables by reference and
-- keeps metatables, so services can hand each other live state.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { { fn: (T...) -> (), conn: Connection } } = {}
	local self = {}

	function self.Connect(_self, fn: (T...) -> ()): Connection
		local conn = { Connected = true } :: any
		local entry = { fn = fn, conn = conn }
		function conn.Disconnect(c)
			if not c.Connected then
				return
			end
			c.Connected = false
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end
		table.insert(handlers, entry)
		return conn
	end

	function self.Once(s, fn: (T...) -> ()): Connection
		local conn: Connection
		conn = s:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function self.Fire(_self, ...: T...)
		-- Copy so handlers can disconnect while firing.
		local snapshot = table.clone(handlers)
		for _, entry in snapshot do
			if entry.conn.Connected then
				task.spawn(entry.fn, ...)
			end
		end
	end

	function self.Wait(s): T...
		local thread = coroutine.running()
		s:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.DisconnectAll(_self)
		for _, entry in table.clone(handlers) do
			entry.conn:Disconnect()
		end
	end

	return (self :: any) :: Signal<T...>
end

return Signal
