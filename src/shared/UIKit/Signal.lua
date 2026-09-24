--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Signal
	Zuständigkeit:
		Sehr leichtgewichtige, allokationsarme Pub/Sub-Klasse für interne
		UIKit-Kommunikation (z. B. Device.Changed, Settings.Changed,
		Toast-Warteschlange). Bewusst KEIN BindableEvent-Wrapper, um pro
		Signal keine zusätzliche Instance zu erzeugen (Performance bei
		vielen kurzlebigen UI-Widgets).

	Rojo-Einhängepunkt:
		src/shared/UIKit/Signal.lua -> ReplicatedStorage.UIKit.Signal
		(Kind-Modul von UIKit, wird von init.lua und anderen UIKit-Modulen
		per require(script.Parent.Signal) o.ä. genutzt.)
]]

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = {
	fn: (...any) -> (),
	once: boolean,
	connected: boolean,
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_listeners = {} :: { Listener },
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local listener: Listener = { fn = fn, once = false, connected = true }
	table.insert((self :: any)._listeners, listener)

	local connection = {}
	connection.Connected = true
	connection.Disconnect = function(_self)
		listener.connected = false
		connection.Connected = false
		local listeners = (self :: any)._listeners
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
	return (connection :: any) :: Connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		if connection and connection.Connected then
			connection:Disconnect()
		end
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Kopie ziehen, damit Disconnects während des Feuerns nicht die
	-- laufende Iteration verfälschen.
	local listeners = table.clone((self :: any)._listeners) :: { Listener }
	for _, listener in listeners do
		if listener.connected then
			task.spawn(listener.fn, ...)
		end
	end
end

function Signal:DisconnectAll()
	table.clear((self :: any)._listeners)
end

return Signal
