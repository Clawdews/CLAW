local EntityHistory = {}
EntityHistory.__index = EntityHistory

function EntityHistory.new(maxSeconds)
	return setmetatable({
		_maxSeconds = maxSeconds or 3,
		_records = setmetatable({}, { __mode = "k" }),
	}, EntityHistory)
end

function EntityHistory:setWindow(seconds)
	self._maxSeconds = math.max(0.1, tonumber(seconds) or self._maxSeconds)
end

function EntityHistory:_prune(history, now)
	local cutoff = now - self._maxSeconds
	local firstValid = 1

	while firstValid <= #history and history[firstValid].at < cutoff do
		firstValid = firstValid + 1
	end

	if firstValid > 1 then
		for _ = 1, firstValid - 1 do
			table.remove(history, 1)
		end
	end
end

function EntityHistory:record(entity, cframe, velocity, timestamp)
	if not entity or typeof(cframe) ~= "CFrame" then
		return
	end

	local now = timestamp or os.clock()
	local history = self._records[entity]
	if not history then
		history = {}
		self._records[entity] = history
	end

	history[#history + 1] = {
		at = now,
		cframe = cframe,
		velocity = typeof(velocity) == "Vector3" and velocity or Vector3.zero,
	}
	self:_prune(history, now)
end

function EntityHistory:recent(entity, seconds, timestamp)
	local history = self._records[entity]
	if not history then
		return {}
	end

	local cutoff = (timestamp or os.clock()) - (seconds or self._maxSeconds)
	local result = {}
	for _, record in ipairs(history) do
		if record.at >= cutoff then
			result[#result + 1] = record
		end
	end
	return result
end

function EntityHistory:closest(entity, timestamp)
	local history = self._records[entity]
	if not history then
		return nil
	end

	local closest
	local closestDelta = math.huge
	for _, record in ipairs(history) do
		local delta = math.abs(record.at - timestamp)
		if delta < closestDelta then
			closest = record
			closestDelta = delta
		end
	end
	return closest
end

function EntityHistory:averageVelocity(entity, seconds)
	local records = self:recent(entity, seconds or 0.20)
	if #records == 0 then
		return Vector3.zero
	end

	local total = Vector3.zero
	for _, record in ipairs(records) do
		total = total + record.velocity
	end
	return total / #records
end

function EntityHistory:predict(entity, seconds)
	local history = self._records[entity]
	local latest = history and history[#history]
	if not latest then
		return nil
	end

	local predictionSeconds = math.max(0, tonumber(seconds) or 0)
	return latest.cframe + (self:averageVelocity(entity, 0.20) * predictionSeconds)
end

function EntityHistory:yawRate(entity)
	local history = self._records[entity]
	if not history or #history < 2 then
		return 0
	end

	local previous = history[#history - 1]
	local latest = history[#history]
	local deltaTime = latest.at - previous.at
	if deltaTime <= 0.0001 then
		return 0
	end

	local first = Vector3.new(previous.cframe.LookVector.X, 0, previous.cframe.LookVector.Z)
	local second = Vector3.new(latest.cframe.LookVector.X, 0, latest.cframe.LookVector.Z)
	if first.Magnitude <= 0.0001 or second.Magnitude <= 0.0001 then
		return 0
	end

	first = first.Unit
	second = second.Unit
	local angle = math.atan2(first:Cross(second).Y, math.clamp(first:Dot(second), -1, 1))
	return angle / deltaTime
end

function EntityHistory:clear(entity)
	if entity then
		self._records[entity] = nil
	else
		table.clear(self._records)
	end
end

return EntityHistory
