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

function TimingResolver:delay(action, event)
	local timing = self.Settings:get("Timing")
	local delay = action.delay + timing.GlobalOffset
	if timing.PingCompensation then
		delay = delay - (self:pingSeconds() * timing.PingScale)
	end

	if event and event.track then
		local ok, speed = pcall(function()
			return event.track.Speed
		end)
		if ok and type(speed) == "number" and speed ~= 0 then
			delay = delay / math.abs(speed)
		end
	end

	return math.clamp(delay, timing.MinDelay, timing.MaxDelay)
end

return TimingResolver
