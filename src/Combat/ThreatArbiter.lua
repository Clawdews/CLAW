local ThreatArbiter = {}
ThreatArbiter.__index = ThreatArbiter

local TRUST = {
	animation = 1,
	sound = 2,
	part = 3,
	effect = 3,
	projectile = 4,
}

local function sourceFor(event)
	return event and (event.entity or event.instance) or nil
end

local function countPlans(record)
	local count = 0
	for _ in pairs(record.plans) do
		count = count + 1
	end
	return count
end

function ThreatArbiter.new(settings, state, scheduler, clock)
	if type(scheduler) == "function" and clock == nil then
		clock = scheduler
		scheduler = nil
	end
	local self = setmetatable({
		Settings = settings,
		State = state,
		Clock = clock or os.clock,
		Scheduler = scheduler,
		Sources = setmetatable({}, { __mode = "k" }),
		FallbackSource = nil,
		ActivePlans = 0,
		NextPlanID = 0,
	}, ThreatArbiter)
	state.ThreatSummary = self:_summary()
	return self
end

function ThreatArbiter:_record(event)
	local source = sourceFor(event)
	if not source then
		if not self.FallbackSource then
			self.FallbackSource = {
				animationTimes = {},
				plans = {},
				plansByEvent = setmetatable({}, { __mode = "k" }),
				noisyUntil = 0,
				lastCorroboratedAt = 0,
				lastNoisyPass = 0,
				lastNotice = 0,
			}
		end
		return self.FallbackSource, "unknown"
	end

	local record = self.Sources[source]
	if not record then
		record = {
			animationTimes = {},
			plans = {},
			plansByEvent = setmetatable({}, { __mode = "k" }),
			noisyUntil = 0,
			lastCorroboratedAt = 0,
			lastNoisyPass = 0,
			lastNotice = 0,
		}
		self.Sources[source] = record
	end
	local name = event.entity and event.entity.Name or event.instance and event.instance.Name or "unknown"
	return record, tostring(name)
end

function ThreatArbiter:_summary(now)
	now = now or self.Clock()
	local noisy = 0
	for _, record in pairs(self.Sources) do
		if record.noisyUntil > now then
			noisy = noisy + 1
		end
	end
	if self.FallbackSource and self.FallbackSource.noisyUntil > now then
		noisy = noisy + 1
	end
	local enabled = self.Settings:get("ThreatGuard.Enabled")
	return {
		enabled = enabled,
		activePlans = self.ActivePlans,
		noisySources = noisy,
		mode = not enabled and "OFF" or noisy > 0 and "DEGRADED" or "NORMAL",
	}
end

function ThreatArbiter:_decision(kind, event, reason, record, force)
	local now = self.Clock()
	self.State.LastThreat = {
		kind = kind,
		reason = tostring(reason or kind),
		detector = event and event.detector or "?",
		id = event and event.id or "?",
		entity = event and event.entity and event.entity.Name or "?",
		at = now,
	}
	self.State.ThreatSummary = self:_summary(now)

	-- A breaker can produce thousands of events per second. Preserve counters,
	-- but rate-limit trace emission so diagnostics do not become the new flood.
	if not force and record and now - record.lastNotice < 0.25 then
		return
	end
	if record then
		record.lastNotice = now
	end
	self.State:emit("threat-" .. kind, {
		event = event,
		reason = reason,
		summary = self.State.ThreatSummary,
	})
end

function ThreatArbiter:_pruneTimes(record, cutoff)
	local retained = {}
	for _, timestamp in ipairs(record.animationTimes) do
		if timestamp >= cutoff then
			retained[#retained + 1] = timestamp
		end
	end
	record.animationTimes = retained
end

function ThreatArbiter:observe(event)
	if not self.Settings:get("ThreatGuard.Enabled") then
		return true
	end

	local record, sourceName = self:_record(event)
	local now = self.Clock()
	if event.detector ~= "animation" then
		if (TRUST[event.detector] or 0) >= 3 then
			record.lastCorroboratedAt = now
		end
		return true
	end

	local window = math.max(0.05, self.Settings:get("ThreatGuard.BurstWindow"))
	local limit = math.max(2, math.floor(self.Settings:get("ThreatGuard.BurstLimit")))
	self:_pruneTimes(record, now - window)

	local corroborated = now - record.lastCorroboratedAt
		<= math.max(0, self.Settings:get("ThreatGuard.CorroborationWindow"))
	if record.noisyUntil > now then
		local passInterval = math.max(0.05, self.Settings:get("ThreatGuard.NoisyPassInterval"))
		if corroborated and now - record.lastNoisyPass >= passInterval then
			record.lastNoisyPass = now
			self.State:increment("ThreatCorroborated")
			self:_decision("corroborated", event, "trusted non-animation evidence", record)
			return true
		end
		self.State:increment("ThreatDropped")
		self:_decision("dropped", event, "animation channel quarantined for " .. sourceName, record)
		return false, "animation spam quarantine"
	end

	record.animationTimes[#record.animationTimes + 1] = now
	if #record.animationTimes > limit then
		record.noisyUntil = now + math.max(0.10, self.Settings:get("ThreatGuard.QuarantineSeconds"))
		record.animationTimes = {}
		self.State:increment("ThreatSpamBursts")
		self.State:increment("ThreatDropped")
		self:_decision("quarantined", event, "animation burst from " .. sourceName, record, true)
		return false, "animation burst quarantined"
	end

	return true
end

function ThreatArbiter:claim(event, dueAt)
	if not self.Settings:get("ThreatGuard.Enabled") then
		return true, nil
	end

	local record = self:_record(event)
	local existing = record.plansByEvent[event]
	if existing and not existing.settled then
		return true, existing
	end

	local separation = math.max(0, self.Settings:get("ThreatGuard.PlanSeparation"))
	local trust = TRUST[event.detector] or 1
	for _, plan in pairs(record.plans) do
		if not plan.settled and math.abs(plan.dueAt - dueAt) <= separation then
			plan.channels[event.detector] = true
			if trust > plan.trust and self.Scheduler then
				local pending = {}
				for scheduled in pairs(plan.tasks) do
					pending[#pending + 1] = scheduled
				end
				for _, scheduled in ipairs(pending) do
					self.Scheduler:cancel(scheduled, "superseded by stronger threat evidence")
				end
				if not plan.settled then
					plan.pending = 0
					self:settle(plan, nil, "superseded by stronger threat evidence")
				end
				self.State:increment("ThreatPromoted")
				self:_decision("promoted", event, "stronger evidence replaced animation plan", record, true)
				break
			end
			plan.trust = math.max(plan.trust, trust)
			self.State:increment("ThreatCoalesced")
			self:_decision("coalesced", event, "overlapping source plan", record)
			return false, nil, "overlapping threat coalesced"
		end
	end

	local maximum = math.max(1, math.floor(self.Settings:get("ThreatGuard.MaxPendingPerSource")))
	local pendingPlans = countPlans(record)
	-- Animation spam cannot spend the slots reserved for a server effect, part,
	-- or projectile. Higher-trust channels get a small independent allowance so
	-- a noisy Animator cannot starve the evidence that would confirm a real hit.
	local budgetReached = event.detector == "animation" and pendingPlans >= maximum
		or event.detector ~= "animation" and pendingPlans >= maximum + 2
	if budgetReached then
		self.State:increment("ThreatDropped")
		self:_decision("dropped", event, "source plan budget reached", record)
		return false, nil, "source threat budget"
	end

	self.NextPlanID = self.NextPlanID + 1
	local plan = {
		id = self.NextPlanID,
		record = record,
		event = event,
		dueAt = dueAt,
		trust = trust,
		channels = { [event.detector] = true },
		tasks = {},
		pending = 0,
		settled = false,
	}
	record.plans[plan.id] = plan
	record.plansByEvent[event] = plan
	self.ActivePlans = self.ActivePlans + 1
	self.State:increment("ThreatAdmitted")
	self:_decision("admitted", event, "source plan admitted", record)
	return true, plan
end

function ThreatArbiter:register(plan, scheduled)
	if not plan or not scheduled or plan.settled or plan.tasks[scheduled] then
		return
	end
	plan.tasks[scheduled] = true
	plan.pending = plan.pending + 1
end

function ThreatArbiter:settle(plan, scheduled, reason)
	if not plan or plan.settled then
		return
	end
	if scheduled and plan.tasks[scheduled] then
		plan.tasks[scheduled] = nil
		plan.pending = math.max(0, plan.pending - 1)
	end
	if plan.pending > 0 then
		return
	end

	plan.settled = true
	plan.record.plans[plan.id] = nil
	plan.record.plansByEvent[plan.event] = nil
	self.ActivePlans = math.max(0, self.ActivePlans - 1)
	self:_decision("settled", plan.event, reason or "plan settled", plan.record)
end

function ThreatArbiter:reset()
	local function resetRecord(record)
		for _, plan in pairs(record.plans) do
			plan.settled = true
		end
		table.clear(record.animationTimes)
		table.clear(record.plans)
		table.clear(record.plansByEvent)
		record.noisyUntil = 0
		record.lastCorroboratedAt = 0
		record.lastNoisyPass = 0
	end
	for _, record in pairs(self.Sources) do
		resetRecord(record)
	end
	if self.FallbackSource then
		resetRecord(self.FallbackSource)
	end
	self.FallbackSource = nil
	self.ActivePlans = 0
	self.State.ThreatSummary = self:_summary()
	self.State.LastThreat = nil
end

function ThreatArbiter:Destroy()
	self:reset()
	table.clear(self.Sources)
end

return ThreatArbiter
