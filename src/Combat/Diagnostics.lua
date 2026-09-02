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
