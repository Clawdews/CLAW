local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(state, clock)
	return setmetatable({
		state = state,
		clock = clock or os.clock,
		_nextID = 0,
		_tasks = {},
		_destroyed = false,
	}, Scheduler)
end

function Scheduler:schedule(identifier, delaySeconds, windows, callback, ...)
	assert(not self._destroyed, "scheduler is destroyed")
	assert(type(callback) == "function", "scheduled callback must be a function")

	windows = windows or {}
	self._nextID = self._nextID + 1
	local id = self._nextID
	local now = self.clock()
	local scheduled = {
		id = id,
		identifier = tostring(identifier or id),
		createdAt = now,
		dueAt = now + math.max(0, tonumber(delaySeconds) or 0),
		punishableWindow = math.max(0, tonumber(windows.punishable) or 0),
		afterWindow = math.max(0, tonumber(windows.after) or 0),
		status = "scheduled",
	}
	local arguments = table.pack(...)

	self._tasks[id] = scheduled
	self.state.ActiveTasks[id] = scheduled
	self.state:increment("Scheduled")
	self.state:emit("scheduled", scheduled)

	scheduled.thread = task.delay(math.max(0, scheduled.dueAt - self.clock()), function()
		if scheduled.status ~= "scheduled" or self._destroyed then
			return
		end

		scheduled.status = "running"
		local callbackResults = table.pack(pcall(callback, table.unpack(arguments, 1, arguments.n)))
		local ok = callbackResults[1]
		local result = callbackResults[2]
		local detail = callbackResults[3]
		scheduled.status = ok and result ~= false and "completed" or "failed"
		scheduled.result = result
		scheduled.detail = detail
		scheduled.error = scheduled.status == "failed"
			and (ok and tostring(detail or "scheduled callback returned false") or tostring(result))
			or nil
		scheduled.completedAt = self.clock()
		if scheduled.status == "completed" then
			self.state:increment("Executed")
		else
			self.state:increment("Failed")
			self.state.LastFailure = {
				identifier = scheduled.identifier,
				reason = scheduled.error,
				at = scheduled.completedAt,
			}
		end
		self.state:emit(scheduled.status, scheduled)
		self._tasks[id] = nil
		self.state.ActiveTasks[id] = nil
	end)

	return scheduled
end

function Scheduler:isBlocking(timestamp)
	local now = timestamp or self.clock()
	for _, scheduled in pairs(self._tasks) do
		if scheduled.status == "scheduled" then
			local start = scheduled.dueAt - scheduled.punishableWindow
			local finish = scheduled.dueAt + scheduled.afterWindow
			if now >= start and now <= finish then
				return true, scheduled
			end
		end
	end
	return false
end

function Scheduler:cancel(id, reason)
	local scheduled = type(id) == "table" and id or self._tasks[id]
	if not scheduled or scheduled.status ~= "scheduled" then
		return false
	end

	scheduled.status = "cancelled"
	scheduled.reason = reason or "cancelled"
	if scheduled.thread then
		pcall(task.cancel, scheduled.thread)
	end
	if type(scheduled.onCancel) == "function" then
		pcall(scheduled.onCancel, scheduled.reason)
	end
	self._tasks[scheduled.id] = nil
	self.state.ActiveTasks[scheduled.id] = nil
	self.state:increment("Cancelled")
	self.state:emit("cancelled", scheduled)
	return true
end

function Scheduler:cancelAll(reason)
	local pending = {}
	for _, scheduled in pairs(self._tasks) do
		pending[#pending + 1] = scheduled
	end
	for _, scheduled in ipairs(pending) do
		self:cancel(scheduled, reason)
	end
end

function Scheduler:Destroy()
	if self._destroyed then
		return
	end
	self:cancelAll("scheduler destroyed")
	self._destroyed = true
end

return Scheduler
