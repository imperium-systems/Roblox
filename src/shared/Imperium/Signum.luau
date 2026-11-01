--!strict
-- Signum: event bus.
-- A system emits, interested systems subscribe, and the emitter does not know who listens.
-- Local to one machine: to cross the network, see Veredarius.

type Listener = {
	fn: (...any) -> (),
	priority: number,
}

local Signum = {}

local listeners: { [string]: { Listener } } = {}

-- Subscribes to an event. Higher priorities are called first.
-- Returns an unsubscribe function.
function Signum.on(name: string, fn: (...any) -> (), priority: number?): () -> ()
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	local listener: Listener = { fn = fn, priority = priority or 0 }
	table.insert(list, listener)
	table.sort(list, function(a, b)
		return a.priority > b.priority
	end)

	return function()
		local index = table.find(list, listener)
		if index then
			table.remove(list, index)
		end
	end
end

-- Emits an event. An error in one listener does not prevent the next ones from running.
function Signum.emit(name: string, ...: any)
	local list = listeners[name]
	if not list then
		return
	end
	for _, listener in table.clone(list) do
		local ok, err = pcall(listener.fn, ...)
		if not ok then
			warn(`[Signum] listener of "{name}" failed: {err}`)
		end
	end
end

return Signum
