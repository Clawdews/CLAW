local RunService = game:GetService("RunService")

local HitboxWaiter = {}
HitboxWaiter.__index = HitboxWaiter

function HitboxWaiter.new(settings)
	return setmetatable({
		Settings = settings,
		Entries = {},
		Connection = nil,
	}, HitboxWaiter)
end

function HitboxWaiter:_disconnectIfIdle()
	if next(self.Entries) == nil and self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

function HitboxWaiter:_step()
	local now = os.clock()
	for key, entry in pairs(self.Entries) do
		if now >= entry.expiresAt then
			self.Entries[key] = nil
			entry.callback(false, "hitbox-wait-timeout")
		elseif now >= entry.nextCheck then
			entry.nextCheck = now + entry.interval
			local ok, ready, terminalReason = pcall(entry.predicate)
			if not ok or terminalReason then
				self.Entries[key] = nil
				entry.callback(false, terminalReason or tostring(ready))
			elseif ready then
				self.Entries[key] = nil
				entry.callback(true)
			end
		end
	end
	self:_disconnectIfIdle()
end

function HitboxWaiter:wait(key, predicate, callback)
	self:cancel(key)
	local now = os.clock()
	self.Entries[key] = {
		predicate = predicate,
		callback = callback,
		nextCheck = now,
		interval = math.max(0.01, self.Settings:get("Timing.HitboxPollInterval")),
		expiresAt = now + math.max(0.1, self.Settings:get("Timing.MaxHitboxWait")),
	}
	if not self.Connection then
		self.Connection = RunService.Heartbeat:Connect(function()
			self:_step()
		end)
	end
end

function HitboxWaiter:cancel(key, reason)
	local entry = self.Entries[key]
	if not entry then
		return false
	end
	self.Entries[key] = nil
	if reason then
		entry.callback(false, reason)
	end
	self:_disconnectIfIdle()
	return true
end

function HitboxWaiter:cancelAll(reason)
	local entries = self.Entries
	self.Entries = {}
	if reason then
		for _, entry in pairs(entries) do
			entry.callback(false, reason)
		end
	end
	self:_disconnectIfIdle()
end

function HitboxWaiter:Destroy()
	self:cancelAll()
end

return HitboxWaiter
