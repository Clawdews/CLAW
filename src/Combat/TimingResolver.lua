local Stats = game:GetService("Stats")

local TimingResolver = {}
TimingResolver.__index = TimingResolver

function TimingResolver.new(settings)
	return setmetatable({ Settings = settings }, TimingResolver)
end

function TimingResolver:pingSeconds()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
	end)
	return ok and math.max(0, value) or 0
end

function TimingResolver:delay(action, event, target)
	local timing = self.Settings:get("Timing")
	local metadata = action.metadata or {}
	local baseDelay = action.delay
	local attributes = event and event.metadata and event.metadata.attributes
	if type(metadata.attributeDifference) == "table" and type(attributes) == "table" then
		local first = tonumber(attributes[metadata.attributeDifference[1]])
		local second = tonumber(attributes[metadata.attributeDifference[2]])
		if first and second then
			baseDelay = math.max(0, (first - second) * (tonumber(metadata.attributeScale) or 1))
		end
	end
	local distanceScale = tonumber(metadata.distanceScale) or 0
	local maximumDelay = tonumber(metadata.maxDelay)
	local minimumDelay = tonumber(metadata.minDelay)
	local fastSpeedThreshold = tonumber(metadata.fastSpeedThreshold)
	if
		event
		and event.entity
		and type(metadata.entityNamePattern) == "string"
		and string.find(string.lower(event.entity.Name), string.lower(metadata.entityNamePattern), 1, true)
	then
		baseDelay = tonumber(metadata.matchingDelay) or baseDelay
	end
	if event and event.track and fastSpeedThreshold then
		local speed = math.abs(event.track.Speed)
		if speed >= fastSpeedThreshold then
			baseDelay = tonumber(metadata.fastBaseDelay) or baseDelay
			distanceScale = tonumber(metadata.fastDistanceScale) or distanceScale
			maximumDelay = tonumber(metadata.fastMaxDelay) or maximumDelay
		end
	end
	local delay = baseDelay + ((target and target.Distance or 0) * distanceScale)
	if maximumDelay then
		delay = math.min(delay, maximumDelay)
	end
	if minimumDelay then
		delay = math.max(delay, minimumDelay)
	end
	delay = delay + timing.GlobalOffset
	if timing.PingCompensation then
		delay = delay - (self:pingSeconds() * timing.PingScale)
	end

	return math.clamp(delay, timing.MinDelay, timing.MaxDelay)
end

return TimingResolver
