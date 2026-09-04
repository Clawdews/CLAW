-- Account-follow lifecycle. No network or game services in this module.
local Auto = { VERSION = "0.2.0-beta.1", LOBBY = 4111023553 }
Auto.__index = Auto
local pending = { REQUESTED = true, TRAVELLING = true, WAITING_MAIN = true }
local phases = { RETURN_MENU = true, WAIT_SLOT = true, JOINING = true, DONE = true, HOLD = true }
function Auto.new(adapter, saved)
	local self = setmetatable({ adapter = adapter, profile = nil, target = nil, status = "CONNECTING",
		attempt = nil, retry = nil }, Auto)
	if type(saved) == "table" and type(saved.attempt) == "table" then
		local a = saved.attempt
		if type(a.key) == "string" and #a.key <= 240 and phases[a.phase]
			and type(a.deadline) == "number" and a.deadline > 0 and a.deadline < math.huge then
			self.attempt = table.clone(a)
			self.retry = saved.retry
		end
	end
	return self
end
function Auto:serialize() return { attempt = self.attempt, retry = self.retry } end
function Auto:statusAs(value)
	if self.status == value then return end
	self.status = value
	if self.adapter.changed then self.adapter.changed(value) end
end
function Auto:save()
	local ok, saved = pcall(self.adapter.save)
	self.storageBlocked = not (ok and saved == true)
	if not ok or saved ~= true then self:statusAs("ATTENTION: storage unavailable"); return false end
	return true
end
function Auto:hold(reason)
	if self.attempt then self.attempt.phase = "HOLD"; self.attempt.reason = tostring(reason):sub(1, 120); self:save() end
	self:statusAs("ATTENTION: " .. tostring(reason))
end
function Auto:canAct()
	local p, t = self.profile, self.target
	return p and p.role == "alt" and p.follow == true and t and t.expiresAt > self.adapter.now()
		and tostring(p.mainId) == tostring(t.ticket.controllerId) and self.attempt and self.attempt.key == t.key
end
function Auto:setProfile(profile)
	if type(profile) ~= "table" or tostring(profile.accountId) ~= tostring(self.adapter.current().userId) then return false end
	if profile.role ~= "main" and profile.role ~= "alt" then return false end
	if profile.retry and self.retry ~= profile.retry then
		self.retry = profile.retry
		-- Do not abandon an already-issued join; retry is for stopped attempts only.
		if not pending[self.adapter.joinState()] and (not self.attempt or self.attempt.phase == "HOLD" or self.attempt.phase == "DONE") then
			self.attempt = nil
		end
		if not self:save() then return false end
	end
	self.profile = profile
	return true
end
function Auto:setTarget(target)
	if type(target) ~= "table" or target.enabled ~= true then self.target = nil; return end
	if type(target.key) ~= "string" or #target.key > 240 or type(target.expiresAt) ~= "number"
		or target.expiresAt ~= target.expiresAt or target.expiresAt % 1 ~= 0
		or target.expiresAt > self.adapter.now() + 60 or not self.adapter.validTicket(target.ticket) then
		self.target = nil; return
	end
	local ticket = target.ticket
	local expectedKey = tostring(ticket.gameId) .. "." .. tostring(ticket.placeId) .. "." .. ticket.jobId
	if target.key ~= expectedKey then self.target = nil; return end
	self.target = target
end
function Auto:disconnected() self.profile = nil; self.target = nil; self:statusAs("RECONNECTING") end
function Auto:selectSlot()
	local slot = self.attempt.slot or self.profile.slot
	if type(slot) ~= "string" or slot == "" then return self:hold("character slot not saved") end
	self.attempt.slot = slot
	self.attempt.phase, self.attempt.deadline = "WAIT_SLOT", self.adapter.now() + 30
	if not self:save() then return end
	if not self:canAct() or (self.adapter.requireRegionCheck and self:chooseSlot() ~= slot)
		or (not self.adapter.requireRegionCheck and self.profile.slot ~= slot) then return self:hold("destination or slot changed before selection") end
	local ok, result = pcall(self.adapter.pickSlot, slot)
	if not ok or result ~= true then return self:hold("slot selection request failed") end
	self:statusAs("WAIT_SLOT")
end
function Auto:chooseSlot()
	if not self.adapter.requireRegionCheck then return self.profile.slot end
	return self.adapter.chooseSlot(self.profile, self.target.ticket.placeId)
end
function Auto:tick()
	if self.storageBlocked then return self:statusAs("ATTENTION: storage unavailable; use /claw retry after fixing it") end
	local joinState = self.adapter.joinState()
	if self.attempt and self.attempt.phase == "JOINING" then
		if pending[joinState] then return self:statusAs(joinState) end
		if joinState == "VERIFIED" then
			self.attempt.phase = "DONE"; self:save(); return self:statusAs("VERIFIED")
		end
		return self:hold("join " .. tostring(joinState) .. "; use /claw retry")
	end
	local profile, target, current = self.profile, self.target, self.adapter.current()
	if not profile then return self:statusAs("CONNECTING") end
	if profile.role == "main" then return self:statusAs("MAIN") end
	if profile.follow ~= true then return self:statusAs("PAUSED") end
	if not target or target.expiresAt <= self.adapter.now() or tostring(target.ticket.controllerId) ~= tostring(profile.mainId) then
		return self:statusAs("WAITING_MAIN")
	end
	if current.gameId ~= target.ticket.gameId then return self:statusAs("ATTENTION: wrong experience") end
	if current.placeId == target.ticket.placeId and current.jobId == target.ticket.jobId then
		if self.adapter.requireRegionCheck then
			if not current.slot or not profile.approvedSlots or profile.approvedSlots[current.slot] ~= true then
				return self:statusAs("ATTENTION: current character is not approved")
			end
		elseif profile.slot and current.slot and profile.slot ~= current.slot then return self:statusAs("ATTENTION: wrong character slot") end
		return self:statusAs(self.adapter.hasMain(target.ticket.controllerId)
			and (joinState == "VERIFIED" and "VERIFIED" or "WITH_MAIN") or "WAITING_MAIN_PRESENCE")
	end
	local slot, slotReason = self:chooseSlot()
	if type(slot) ~= "string" or slot == "" then return self:statusAs(slotReason or "NEEDS_SLOT: load once inside your chosen character") end
	-- Being outside the menu with automatic exits disabled is waiting, not a failed attempt.
	-- Recover old holds with this exact reason after a manual menu return; no remote was sent.
	if self.attempt and self.attempt.phase == "HOLD" and self.attempt.reason == "return to menu disabled in local config" then
		self.attempt = nil
		if not self:save() then return end
	end
	if self.attempt and self.attempt.key == target.key then
		local a = self.attempt
		if a.phase == "DONE" or a.phase == "HOLD" then
			return self:statusAs("ATTENTION: " .. tostring(a.reason or "previous attempt completed") .. "; use /claw retry")
		end
		if self.adapter.now() >= a.deadline then return self:hold(a.phase .. " timed out") end
		if a.phase == "RETURN_MENU" then
			if current.placeId == Auto.LOBBY then return self:selectSlot() end
			if not a.confirmed then
				-- The adapter confirms only the game's exact Return to Main Menu prompt.
				if self.adapter.confirmMenu() then a.confirmed = true; self:save() end
			end
			return self:statusAs("RETURN_MENU")
		end
		if a.phase == "WAIT_SLOT" then
			if current.placeId ~= Auto.LOBBY then return self:hold("another script left the menu") end
			if not self.adapter.slotReady() then return self:statusAs("WAIT_SLOT") end
			if self.adapter.requireRegionCheck then
				if a.slot ~= slot then return self:hold("approved character changed during selection") end
				local match, reason = self.adapter.regionMatches(target.ticket.placeId)
				if not match then return self:hold(reason or "selected character region does not match main") end
			end
			a.phase = "JOINING"
			if not self:save() then return end
			if not self:canAct() then return self:hold("destination changed before join") end
			local ok, result, reason = pcall(self.adapter.beginJoin, target.ticket)
			if not ok or result ~= true then return self:hold(reason or "join request failed") end
			return self:statusAs("JOINING")
		end
	end
	-- One attempt per destination, persisted before any remote. Repeated target packets do not retry.
	if current.placeId ~= Auto.LOBBY and self.adapter.allowMenuReturn ~= true then
		return self:statusAs("WAITING_MENU: return this alt to the character menu; automatic exits are off")
	end
	if self.attempt and self.adapter.now() - (self.attempt.startedAt or 0) < 10 then return self:statusAs("WAITING_TARGET_SETTLE") end
	self.attempt = { key = target.key, slot = slot, phase = "RETURN_MENU", deadline = self.adapter.now() + 60, startedAt = self.adapter.now() }
	if current.placeId == Auto.LOBBY then return self:selectSlot() end
	if not self:save() then return end
	if not self:canAct() then return self:hold("destination changed before menu request") end
	local ok, result = pcall(self.adapter.returnMenu)
	if not ok or result ~= true then return self:hold("return-to-menu request unavailable") end
	self:statusAs("RETURN_MENU")
end
return Auto
