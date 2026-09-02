local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_nextID = 0,
		_handlers = {},
		_destroyed = false,
	}, Signal)
end

function Signal:Connect(handler)
	assert(not self._destroyed, "cannot connect to a destroyed signal")
	assert(type(handler) == "function", "signal handler must be a function")

	self._nextID = self._nextID + 1
	local id = self._nextID
	self._handlers[id] = handler

	local signal = self
	local connection = { Connected = true }

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false
		signal._handlers[id] = nil
	end

	return connection
end

function Signal:Fire(...)
	if self._destroyed then
		return
	end

	for _, handler in pairs(self._handlers) do
		task.spawn(handler, ...)
	end
end

function Signal:Destroy()
	self._destroyed = true
	table.clear(self._handlers)
end

return Signal
