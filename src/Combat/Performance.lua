local Performance = {}
Performance.__index = Performance

function Performance.new(settings)
	return setmetatable({
		Settings = settings,
		Stages = {},
		Backoff = 1,
		LastFrameMs = 0,
	}, Performance)
end

function Performance:measure(name, callback, ...)
	local started = os.clock()
	local results = table.pack(pcall(callback, ...))
	local elapsedMs = (os.clock() - started) * 1000
	local stage = self.Stages[name] or { samples = 0, averageMs = 0, peakMs = 0 }
	stage.samples = stage.samples + 1
	stage.averageMs = stage.averageMs + ((elapsedMs - stage.averageMs) / stage.samples)
	stage.peakMs = math.max(stage.peakMs, elapsedMs)
	stage.lastMs = elapsedMs
	self.Stages[name] = stage

	local budget = self.Settings:get("Diagnostics.PerformanceBudgetMs")
	if self.Settings:get("Diagnostics.AdaptiveScan") then
		if elapsedMs > budget then
			self.Backoff = math.min(4, self.Backoff * 1.15)
		else
			self.Backoff = math.max(1, self.Backoff * 0.98)
		end
	end

	if not results[1] then
		error(results[2])
	end
	return table.unpack(results, 2, results.n)
end

function Performance:scanInterval(base)
	return math.max(0.01, base * self.Backoff)
end

function Performance:snapshot()
	local stages = {}
	for name, stage in pairs(self.Stages) do
		stages[name] = {
			samples = stage.samples,
			averageMs = stage.averageMs,
			peakMs = stage.peakMs,
			lastMs = stage.lastMs,
		}
	end
	return { backoff = self.Backoff, stages = stages }
end

return Performance
