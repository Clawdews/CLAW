-- Pure state machine. The adapter owns Roblox calls, storage and presentation.
local Core = { VERSION = "0.1.0", LOBBY_PLACE_ID = 4111023553 }
Core.__index = Core
local active = { REQUESTED = true, TRAVELLING = true, WAITING_MAIN = true }
local terminal = { VERIFIED = true, STALE = true, FAILED = true, TIMED_OUT = true,
	WRONG_DESTINATION = true, CANCELLED = true }

local function integer(value)
	return type(value) == "number" and value > 0 and value < 2^53 and value % 1 == 0
end

local function identifier(value)
	return type(value) == "string" and #value > 0 and #value <= 160 and value:match("^[%w_:%-%.]+$") ~= nil
end

function Core.validateTicket(ticket, now)
	if type(ticket) ~= "table" or ticket.version ~= 1 then return false, "Not a CLAW join ticket" end
	if not integer(ticket.controllerId) or not integer(ticket.gameId) or not integer(ticket.placeId) then
		return false, "Ticket has invalid account/place identifiers"
	end
	if not identifier(ticket.jobId) or not identifier(ticket.joinId) or not identifier(ticket.nonce) then
		return false, "Ticket has an invalid server identifier"
	end
	if ticket.placeId == Core.LOBBY_PLACE_ID then return false, "Capture the target inside the world, not the menu" end
	if not integer(ticket.createdAt) or ticket.createdAt > now + 10 or now - ticket.createdAt > 600 then
		return false, "Ticket expired or has an invalid timestamp; copy a fresh one from the main"
	end
	return true
end

function Core.new(adapter)
	return setmetatable({ adapter = adapter, state = "IDLE", detail = "Select a slot in the game menu after loading this test",
		operation = nil, realm = nil, events = {}, lastAttempt = -math.huge }, Core)
end

function Core:_event(kind, detail)
	self.events[#self.events + 1] = { time = self.adapter.now(), kind = kind, detail = tostring(detail) }
	if #self.events > 40 then table.remove(self.events, 1) end
end

function Core:_publish()
	if self.adapter.changed then self.adapter.changed(self) end
end

function Core:_store()
	local payload = {
		version = 1, accountId = self.adapter.current().userId, state = self.state,
		detail = self.detail, operation = self.operation, events = self.events, updatedAt = self.adapter.now(),
	}
	local ok, result = pcall(self.adapter.save, payload)
	return ok and result == true
end

function Core:_transition(state, detail)
	if self.state == state and self.detail == detail then return end
	self.state, self.detail = state, detail
	self:_event(state, detail)
	if self.operation and not self:_store() then self:_event("STORAGE_WARNING", "Could not persist this status") end
	self:_publish()
end

function Core:capture(joinId)
	local current = self.adapter.current()
	local ticket = {
		version = 1, controllerId = current.userId, gameId = current.gameId,
		placeId = current.placeId, jobId = current.jobId, joinId = joinId or current.jobId,
		nonce = self.adapter.nonce(), createdAt = self.adapter.now(),
	}
	local ok, reason = Core.validateTicket(ticket, self.adapter.now())
	if not ok then return nil, reason end
	return ticket
end

function Core:onServers(realm)
	if self.adapter.current().placeId ~= Core.LOBBY_PLACE_ID or type(realm) ~= "string" or realm == "" then return end
	self.realm = realm:sub(1, 100)
	self:_event("SLOT_SELECTED", self.realm)
	if not self.operation then self:_transition("SLOT_READY", "Slot selected; paste the main's ticket and join") end
end

function Core:begin(ticket)
	if self.operation and active[self.state] then return false, "A join is already pending; do not send it twice" end
	local now, current = self.adapter.now(), self.adapter.current()
	local valid, reason = Core.validateTicket(ticket, now)
	if not valid then return false, reason end
	if current.userId == ticket.controllerId then return false, "Use JOIN on the alt, not on the main" end
	if current.gameId ~= ticket.gameId then return false, "Main and alt are not in the same Roblox experience" end
	if current.placeId ~= Core.LOBBY_PLACE_ID then return false, "Return this alt to the game menu first; this test does not log you out" end
	if not self.realm then return false, "Select your alt's slot in the normal game menu AFTER loading this test" end
	if now - self.lastAttempt < 5 then return false, "Wait five seconds before another attempt" end
	if not self.adapter.canJoin() then return false, "Deepwoken PickServer request is not available" end

	self.lastAttempt = now
	self.operation = {
		ticket = table.clone(ticket), accountId = current.userId, originPlaceId = current.placeId,
		originJobId = current.jobId, startedAt = now, deadline = now + 120,
		realm = self.realm, slot = current.slot, requestSent = false,
	}
	self.state, self.detail = "REQUESTED", "One exact-ID join requested; arrival is not confirmed"
	self:_event("REQUESTED", ticket.joinId)
	-- Fail closed if the arrival check would be lost across teleport.
	if not self:_store() then
		self.operation = nil
		self:_transition("FAILED", "Cannot save the pending verification; no join was sent")
		return false, self.detail
	end
	self.operation.requestSent = true
	if not self:_store() then
		self.operation.requestSent = false
		self:_transition("FAILED", "Cannot save request state; no join was sent")
		return false, self.detail
	end
	self:_publish()
	local ok, failure = pcall(self.adapter.join, ticket.joinId)
	if not ok then
		self:_transition("FAILED", "PickServer call failed: " .. tostring(failure):sub(1, 180))
		return false, self.detail
	end
	return true
end

function Core:resume(saved)
	local current = self.adapter.current()
	if type(saved) ~= "table" or saved.version ~= 1 or saved.accountId ~= current.userId then return false end
	local operation = saved.operation
	if type(operation) ~= "table" or operation.accountId ~= current.userId
		or not (active[saved.state] or terminal[saved.state]) then return false end
	local valid = Core.validateTicket(operation.ticket, self.adapter.now())
	if not valid or not integer(operation.startedAt) or not integer(operation.deadline)
		or operation.deadline ~= operation.startedAt + 120 or operation.startedAt > self.adapter.now() + 10
		or operation.startedAt < operation.ticket.createdAt - 10
		or not integer(operation.originPlaceId) or not identifier(operation.originJobId) then return false end
	self.operation = operation
	self.lastAttempt = operation.startedAt
	self.state, self.detail = saved.state, tostring(saved.detail or "Restored join check")
	if type(saved.events) == "table" then
		for _, event in ipairs(saved.events) do
			if #self.events >= 40 then break end
			if type(event) == "table" and integer(event.time) and type(event.kind) == "string" and type(event.detail) == "string" then
				self.events[#self.events + 1] = { time = event.time, kind = event.kind:sub(1, 40), detail = event.detail:sub(1, 200) }
			end
		end
	end
	if active[self.state] then
		if operation.requestSent ~= true then
			self:_transition("FAILED", "Restored incomplete request; nothing will be resent automatically")
		else
			self:_event("RESUMED", "Arrival verification only; never resending a join")
			self:tick()
		end
	elseif self.state == "VERIFIED" then
		self:tick()
	end
	self:_publish()
	return true
end

function Core:teleportStarted()
	if self.operation and self.state == "REQUESTED" then
		self:_transition("TRAVELLING", "Roblox reported teleport start; arrival is not confirmed")
	end
end

function Core:teleportFailed(message)
	if self.operation and active[self.state] then
		self:_transition("FAILED", "Teleport failed: " .. tostring(message):sub(1, 180) .. "; no fallback server selected")
	end
end

function Core:tick()
	local operation = self.operation
	if not operation then return end
	local current, target = self.adapter.current(), operation.ticket
	if self.state == "VERIFIED" then
		if current.userId ~= operation.accountId or current.placeId ~= target.placeId
			or current.jobId ~= target.jobId or current.gameId ~= target.gameId
			or not self.adapter.hasPlayer(target.controllerId) then
			self:_transition("STALE", "The verified server/main presence changed; no automatic rejoin")
		end
		return
	end
	if not active[self.state] then return end
	if self.adapter.now() >= operation.deadline then
		return self:_transition("TIMED_OUT", "No verified arrival within 120 seconds; no automatic retry")
	end
	if current.userId ~= operation.accountId then return self:_transition("FAILED", "Account identity changed") end
	if current.placeId == target.placeId and current.jobId == target.jobId and current.gameId == target.gameId then
		if not self.adapter.hasPlayer(target.controllerId) then
			return self:_transition("WAITING_MAIN", "Exact server matched; waiting for the main's numeric UserId")
		end
		if operation.slot and current.slot and operation.slot ~= current.slot then
			return self:_transition("FAILED", "Server matched but character slot differs from the selected slot")
		end
		return self:_transition("VERIFIED", "Alt identity, exact place/server, and main presence verified")
	end
	if current.placeId ~= operation.originPlaceId or current.jobId ~= operation.originJobId then
		self:_transition("WRONG_DESTINATION", "Arrived somewhere other than the main's captured server; stopped")
	end
end

function Core:cancel()
	if self.operation and active[self.state] then
		self:_transition("CANCELLED", "Tracking cancelled; this cannot undo a teleport Roblox already accepted")
	end
end

function Core:report()
	return {
		version = Core.VERSION, state = self.state, detail = self.detail,
		current = self.adapter.current(), operation = self.operation, events = self.events,
	}
end

return Core
