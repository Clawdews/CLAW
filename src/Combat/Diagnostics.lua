local Diagnostics = {}
Diagnostics.__index = Diagnostics

local StarterGui = game:GetService("StarterGui")

local SCHEDULER_EVENTS = {
	scheduled = true,
	completed = true,
	failed = true,
	cancelled = true,
}

function Diagnostics.new(settings, state, performance)
	local self = setmetatable({
		Settings = settings,
		State = state,
		Performance = performance,
		Buffer = {},
		WriteIndex = 0,
		Count = 0,
		Reasons = {},
		NotificationCooldowns = {},
	}, Diagnostics)

	self.Connection = state.Event:Connect(function(event)
		self:record(event)
	end)
	return self
end

function Diagnostics:_notify(event)
	if not self.Settings:get("Diagnostics.Notifications") then
		return
	end
	local title, message, key
	if event.kind == "assistance-unavailable" then
		local payload = event.payload or {}
		title = "CLAW MARK: binding needed"
		message = string.format("%s: %s", tostring(payload.name), tostring(payload.reason))
		key = "assist:" .. tostring(payload.name)
	elseif event.kind == "module-fallback" then
		local payload = event.payload or {}
		title = "CLAW MARK: generic module fallback"
		message = string.format("%s (%s)", tostring(payload.module), tostring(payload.profile))
		key = "module:" .. tostring(payload.module)
	elseif event.kind == "failed" then
		title = "CLAW MARK: scheduled action failed"
		message = tostring(event.payload and event.payload.result or "unknown error")
		key = "scheduler-failed"
	else
		return
	end

	local now = os.clock()
	if now < (self.NotificationCooldowns[key] or 0) then
		return
	end
	self.NotificationCooldowns[key] = now + 3
	pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
		Title = title,
		Text = message,
		Duration = 3,
	})
end

function Diagnostics:record(event)
	self:_notify(event)
	if not self.Settings:get("Diagnostics.Enabled") then
		return
	end
	if event.kind == "detected" and not self.Settings:get("Diagnostics.TraceDetectors") then
		return
	end
	if SCHEDULER_EVENTS[event.kind] and not self.Settings:get("Diagnostics.TraceScheduler") then
		return
	end
	local maximum = math.max(10, math.floor(self.Settings:get("Diagnostics.MaxEvents")))
	self.WriteIndex = (self.WriteIndex % maximum) + 1
	self.Buffer[self.WriteIndex] = event
	self.Count = math.min(maximum, self.Count + 1)

	if event.kind == "action-rejected" then
		local reason = tostring(event.payload)
		self.Reasons[reason] = (self.Reasons[reason] or 0) + 1
	end
end

function Diagnostics:events()
	local result = {}
	if self.Count == 0 then
		return result
	end
	local maximum = math.max(10, math.floor(self.Settings:get("Diagnostics.MaxEvents")))
	local first = ((self.WriteIndex - self.Count) % maximum) + 1
	for offset = 0, self.Count - 1 do
		local index = ((first + offset - 1) % maximum) + 1
		result[#result + 1] = self.Buffer[index]
	end
	return result
end

function Diagnostics:snapshot()
	return {
		metrics = self.State.Metrics,
		reasons = self.Reasons,
		performance = self.Performance:snapshot(),
		events = self:events(),
	}
end

local function formatLast(value, formatter)
	if not value then
		return "none"
	end
	local ok, result = pcall(formatter, value)
	return ok and tostring(result) or "unavailable"
end

function Diagnostics:report(context)
	context = context or {}
	local state = self.State
	local metrics = state.Metrics
	local native = context.native or {}
	local stats = native.stats or {}
	local settings = self.Settings
	local lines = {
		"CLAW MARK DIAGNOSTIC REPORT",
		"version=" .. tostring(context.version or "unknown"),
		"distribution_ref=" .. tostring(context.distributionRef or "unknown"),
		"runtime=" .. (state.Running and "running" or "stopped"),
		"master=" .. (settings:get("Enabled") and "on" or "off"),
		"defense=" .. (settings:get("Defense.Enabled") and "on" or "off"),
		"targets=" .. tostring(#state.Targets),
		"timings=" .. tostring(context.timingCount or 0),
		"timing_source=" .. tostring(context.timingSource or "unknown"),
		"native=" .. tostring(native.status or "unknown"),
		"native_last=" .. tostring(native.last or "idle"),
		string.format(
			"native_io=blocks:%d unblocks:%d retries:%d coalesced:%d dodges:%d cancels:%d",
			stats.Blocks or 0,
			stats.Unblocks or 0,
			stats.Retries or 0,
			stats.Coalesced or 0,
			stats.Dodges or 0,
			stats.DodgeCancels or 0
		),
		string.format(
			"settings=primary:%s dodge_fallback:%s roll_on_cd:%s roll_cancel:%s direct_roll:%s indexed_only:%s unknown_anims:%s hitbox:%s facing:%s prediction:%s",
			tostring(settings:get("Defense.Preferred")),
			settings:get("Defense.DodgeFallback") and "on" or "off",
			settings:get("Defense.RollOnParryCooldown") and "on" or "off",
			settings:get("Defense.RollCancel") and "on" or "off",
			settings:get("Defense.DirectRoll") and "on" or "off",
			settings:get("Detection.OnlyConfigured") and "on" or "off",
			settings:get("Detection.UnknownAnimations") and "on" or "off",
			settings:get("Validation.Hitbox") and "on" or "off",
			settings:get("Validation.Facing") and "on" or "off",
			settings:get("Validation.Prediction") and "on" or "off"
		),
		string.format(
			"metrics=detected:%d scheduled:%d executed:%d failed:%d rejected:%d cancelled:%d",
			metrics.Detected or 0,
			metrics.Scheduled or 0,
			metrics.Executed or 0,
			metrics.Failed or 0,
			metrics.Rejected or 0,
			metrics.Cancelled or 0
		),
		"last_detection=" .. formatLast(state.LastDetection, function(value)
			return tostring(value.detector) .. ":" .. tostring(value.id)
		end),
		"last_reject=" .. formatLast(state.LastReject, function(value)
			return value.reason
		end),
		"last_plan=" .. formatLast(state.LastPlan, function(value)
			return string.format(
				"%s @ %.3fs distance=%.1f name=%s",
				tostring(value.kind),
				tonumber(value.delay) or 0,
				tonumber(value.distance) or 0,
				tostring(value.name or value.profile or "unknown")
			)
		end),
		"last_action=" .. formatLast(state.LastActionResult, function(value)
			return tostring(value.kind)
				.. ":"
				.. (value.ok and tostring(value.backend or "sent") or tostring(value.reason))
		end),
		"last_failure=" .. formatLast(state.LastFailure, function(value)
			return value.reason
		end),
	}

	local reasons = {}
	for reason, count in pairs(self.Reasons) do
		reasons[#reasons + 1] = { reason = tostring(reason), count = count }
	end
	table.sort(reasons, function(left, right)
		if left.count == right.count then
			return left.reason < right.reason
		end
		return left.count > right.count
	end)
	lines[#lines + 1] = "rejection_reasons="
	if #reasons == 0 then
		lines[#lines + 1] = "  none"
	else
		for _, item in ipairs(reasons) do
			lines[#lines + 1] = string.format("  %s: %d", item.reason, item.count)
		end
	end

	local events = self:events()
	lines[#lines + 1] = "recent_events="
	if #events == 0 then
		lines[#lines + 1] = "  none (enable diagnostics to record the event trace)"
	else
		for index = math.max(1, #events - 11), #events do
			local event = events[index]
			lines[#lines + 1] = string.format("  %.3f %s", tonumber(event.at) or 0, tostring(event.kind))
		end
	end

	return table.concat(lines, "\n")
end

function Diagnostics:clear()
	table.clear(self.Buffer)
	table.clear(self.Reasons)
	table.clear(self.NotificationCooldowns)
	self.WriteIndex = 0
	self.Count = 0
end

function Diagnostics:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self:clear()
end

return Diagnostics
