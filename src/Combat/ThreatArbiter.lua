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

local function makeRecord()
	return {
		animationTimes = {},
		admissionTimes = {},
		abortTimes = {},
		lastAnimationAt = {},
		plans = {},
		plansByEvent = setmetatable({}, { __mode = "k" }),
		noisyUntil = 0,
		rearmUntil = 0,
		lastNotice = 0,
		sourceName = "unknown",
	}
end

local function pruneTimes(timestamps, cutoff)
	local write = 1
	for read = 1, #timestamps do
		local timestamp = timestamps[read]
		if timestamp >= cutoff then
			timestamps[write] = timestamp
			write = write + 1
		end
	end
	for index = #timestamps, write, -1 do
		timestamps[index] = nil
	end
end

function ThreatArbiter.new(settings, state, scheduler, clock, onQuarantine)
	if type(scheduler) == "function" and clock == nil then
		clock = scheduler
		scheduler = nil
	end
	local self = setmetatable({
		Settings = settings,
		State = state,
		Clock = clock or os.clock,
		Scheduler = scheduler,
		OnQuarantine = onQuarantine,
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
			self.FallbackSource = makeRecord()
		end
		return self.FallbackSource, "unknown"
	end

	local record = self.Sources[source]
	if not record then
		record = makeRecord()
		self.Sources[source] = record
	end
	local name = event.entity and event.entity.Name or event.instance and event.instance.Name or "unknown"
	record.sourceName = tostring(name)
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

function ThreatArbiter:_cancelAnimationPlans(record, reason)
	if not self.Scheduler then
		return
	end
	local pending = {}
	for _, plan in pairs(record.plans) do
		if not plan.settled and plan.event.detector == "animation" then
			for scheduled in pairs(plan.tasks) do
				pending[#pending + 1] = scheduled
			end
		end
	end
	for _, scheduled in ipairs(pending) do
		self.Scheduler:cancel(scheduled, reason)
	end
end

function ThreatArbiter:_quarantine(record, event, reason, metric)
	local now = self.Clock()
	record.noisyUntil = math.max(
		record.noisyUntil,
		now + math.max(0.10, self.Settings:get("ThreatGuard.QuarantineSeconds"))
	)
	record.rearmUntil = math.max(record.rearmUntil, record.noisyUntil)
	table.clear(record.animationTimes)
	table.clear(record.admissionTimes)
	table.clear(record.abortTimes)
	table.clear(record.lastAnimationAt)
	self:_cancelAnimationPlans(record, reason)
	if type(self.OnQuarantine) == "function" then
		local called, released = pcall(self.OnQuarantine, reason)
		if called and released ~= false then
			self.State:increment("ThreatInputReleases")
		end
	end
	self.State:increment(metric)
	self.State:increment("ThreatDropped")
	self:_decision("quarantined", event, reason, record, true)
end

function ThreatArbiter:observe(event)
	if not self.Settings:get("ThreatGuard.Enabled") then
		return true
	end

	local record, sourceName = self:_record(event)
	local now = self.Clock()
	if event.detector ~= "animation" then
		if (TRUST[event.detector] or 0) >= 3 then
			if record.noisyUntil > now then
				self.State:increment("ThreatCorroborated")
				self:_decision("corroborated", event, "trusted evidence bypassed animation quarantine", record)
			end
		end
		return true
	end

	local window = math.max(0.05, self.Settings:get("ThreatGuard.BurstWindow"))
	local limit = math.max(2, math.floor(self.Settings:get("ThreatGuard.BurstLimit")))
	pruneTimes(record.animationTimes, now - window)

	if record.noisyUntil > now then
		self.State:increment("ThreatDropped")
		self:_decision("dropped", event, "animation channel quarantined for " .. sourceName, record)
		return false, "animation spam quarantine"
	end

	record.animationTimes[#record.animationTimes + 1] = now
	if #record.animationTimes > limit then
		self:_quarantine(record, event, "animation burst from " .. sourceName, "ThreatSpamBursts")
		return false, "animation burst quarantined"
	end

	return true
end

function ThreatArbiter:claim(event, dueAt)
	if not self.Settings:get("ThreatGuard.Enabled") then
		return true, nil
	end

	local record, sourceName = self:_record(event)
	local existing = record.plansByEvent[event]
	if existing and not existing.settled then
		return true, existing
	end

	local now = self.Clock()
	if event.detector == "animation" then
		if record.noisyUntil > now then
			self.State:increment("ThreatDropped")
			self:_decision("dropped", event, "animation channel quarantined for " .. sourceName, record)
			return false, nil, "animation spam quarantine"
		end
		local animationID = tostring(event.id or "")
		local lastSameAnimation = record.lastAnimationAt[animationID]
		local sameAnimationRearm = math.max(0, self.Settings:get("ThreatGuard.SameAnimationRearm"))
		if lastSameAnimation and now - lastSameAnimation < sameAnimationRearm then
			self.State:increment("ThreatRearmDrops")
			self.State:increment("ThreatDropped")
			self:_decision("dropped", event, "same animation rearm lease", record)
			return false, nil, "same animation rearm"
		end
		if now < record.rearmUntil then
			self.State:increment("ThreatRearmDrops")
			self.State:increment("ThreatDropped")
			self:_decision("dropped", event, "source rearm lease", record)
			return false, nil, "source rearm"
		end

		local churnWindow = math.max(0.25, self.Settings:get("ThreatGuard.ChurnWindow"))
		local churnLimit = math.max(2, math.floor(self.Settings:get("ThreatGuard.ChurnLimit")))
		pruneTimes(record.admissionTimes, now - churnWindow)
		if #record.admissionTimes >= churnLimit then
			self:_quarantine(
				record,
				event,
				"sustained animation-plan churn from " .. sourceName,
				"ThreatChurnBursts"
			)
			return false, nil, "source churn quarantined"
		end
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
	if event.detector == "animation" then
		record.admissionTimes[#record.admissionTimes + 1] = now
		record.lastAnimationAt[tostring(event.id or "")] = now
		record.rearmUntil = math.max(
			record.rearmUntil,
			now + math.max(0, self.Settings:get("ThreatGuard.SourceRearm"))
		)
	end
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

	if plan.event.detector == "animation" then
		local now = self.Clock()
		local quarantined = false
		local rearm = math.max(0, self.Settings:get("ThreatGuard.SourceRearm"))
		plan.record.rearmUntil = math.max(plan.record.rearmUntil, now + rearm)
		local outcome = string.lower(tostring(reason or ""))
		if string.find(outcome, "animation ended", 1, true) then
			local abortWindow = math.max(0.25, self.Settings:get("ThreatGuard.AbortWindow"))
			local abortLimit = math.max(2, math.floor(self.Settings:get("ThreatGuard.AbortLimit")))
			pruneTimes(plan.record.abortTimes, now - abortWindow)
			plan.record.abortTimes[#plan.record.abortTimes + 1] = now
			self.State:increment("ThreatAborted")
			if #plan.record.abortTimes >= abortLimit and plan.record.noisyUntil <= now then
				self:_quarantine(
					plan.record,
					plan.event,
					"repeated early animation aborts from " .. plan.record.sourceName,
					"ThreatChurnBursts"
				)
				quarantined = true
			end
		end
		if quarantined then
			return
		end
	end
	self:_decision("settled", plan.event, reason or "plan settled", plan.record)
end

function ThreatArbiter:reset()
	local function resetRecord(record)
		for _, plan in pairs(record.plans) do
			plan.settled = true
		end
		table.clear(record.animationTimes)
		table.clear(record.admissionTimes)
		table.clear(record.abortTimes)
		table.clear(record.lastAnimationAt)
		table.clear(record.plans)
		table.clear(record.plansByEvent)
		record.noisyUntil = 0
		record.rearmUntil = 0
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
