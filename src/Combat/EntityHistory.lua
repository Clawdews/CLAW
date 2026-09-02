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
	local records = history.records
	while history.head <= #records and records[history.head].at < cutoff do
		history.head = history.head + 1
	end

	-- Compact occasionally instead of shifting the array on every sample.
	if history.head > 64 and history.head > (#records * 0.5) then
		local compacted = {}
		for index = history.head, #records do
			compacted[#compacted + 1] = records[index]
		end
		history.records = compacted
		history.head = 1
	end
end

function EntityHistory:record(entity, cframe, velocity, timestamp)
	if not entity or typeof(cframe) ~= "CFrame" then
		return
	end

	local now = timestamp or os.clock()
	local history = self._records[entity]
	if not history then
		history = { records = {}, head = 1 }
		self._records[entity] = history
	end

	local records = history.records
	records[#records + 1] = {
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
	for index = history.head, #history.records do
		local record = history.records[index]
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
	for index = history.head, #history.records do
		local record = history.records[index]
		local delta = math.abs(record.at - timestamp)
		if delta < closestDelta then
			closest = record
			closestDelta = delta
		end
	end
	return closest
end

function EntityHistory:averageVelocity(entity, seconds)
	local history = self._records[entity]
	if not history then
		return Vector3.zero
	end

	local cutoff = os.clock() - (seconds or 0.20)
	local total = Vector3.zero
	local count = 0
	for index = history.head, #history.records do
		local record = history.records[index]
		if record.at >= cutoff then
			total = total + record.velocity
			count = count + 1
		end
	end
	return count > 0 and total / count or Vector3.zero
end

function EntityHistory:anyRecent(entity, seconds, predicate)
	local history = self._records[entity]
	if not history then
		return false
	end
	local cutoff = os.clock() - (seconds or self._maxSeconds)
	for index = history.head, #history.records do
		local record = history.records[index]
		if record.at >= cutoff and predicate(record) then
			return true
		end
	end
	return false
end

function EntityHistory:predict(entity, seconds)
	local history = self._records[entity]
	local latest = history and history.records[#history.records]
	if not latest then
		return nil
	end

	local predictionSeconds = math.max(0, tonumber(seconds) or 0)
	return latest.cframe + (self:averageVelocity(entity, 0.20) * predictionSeconds)
end

function EntityHistory:yawRate(entity)
	local history = self._records[entity]
	if not history or #history.records - history.head + 1 < 2 then
		return 0
	end

	local previous = history.records[#history.records - 1]
	local latest = history.records[#history.records]
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
