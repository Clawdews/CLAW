local Core = require("../join/core")
local passed, failed = 0, 0
local function equal(actual, expected)
	assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end
local function clone(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = clone(item) end
	return copy
end
local function test(name, run)
	local ok, reason = pcall(run)
	if ok then passed += 1; print("PASS " .. name)
	else failed += 1; print("FAIL " .. name .. ": " .. tostring(reason)) end
end
local function fixture()
	local f = { now = 2000000000, user = { userId = 22, gameId = 99, placeId = Core.LOBBY_PLACE_ID,
		jobId = "lobby-job", slot = "alt-slot" }, sends = {}, saves = 0, mainPresent = false, writable = true, remote = true }
	f.ticket = { version = 1, controllerId = 11, gameId = 99, placeId = 123,
		jobId = "main-job", joinId = "main-job", nonce = "nonce-1", createdAt = f.now }
	f.adapter = {
		now = function() return f.now end, current = function() return f.user end,
		nonce = function() return "nonce-new" end,
		changed = function() end,
		save = function(payload)
			f.saves += 1
			if not f.writable or f.failSave == f.saves then return false end
			f.saved = clone(payload)
			return true
		end,
		canJoin = function() return f.remote end,
		join = function(id)
			assert(f.saved and f.saved.operation.requestSent, "must persist before sending")
			if f.remoteError then error("test remote error") end
			table.insert(f.sends, id)
		end,
		hasPlayer = function(id) return id == 11 and f.mainPresent end,
	}
	f.core = Core.new(f.adapter)
	function f:start()
		self.core:onServers("Etrean")
		assert(self.core:begin(self.ticket))
	end
	function f:arrive()
		self.user.placeId, self.user.jobId = self.ticket.placeId, self.ticket.jobId
	end
	return f
end

test("main captures actual place/job/user IDs", function()
	local f = fixture(); f.user.userId = 11; f:arrive()
	local ticket = assert(f.core:capture())
	equal(ticket.controllerId, 11); equal(ticket.jobId, "main-job"); equal(ticket.joinId, "main-job")
end)
test("PR override changes join ID, never expected arrival JobId", function()
	local f = fixture(); f:arrive()
	local ticket = assert(f.core:capture("pr-server-id"))
	equal(ticket.joinId, "pr-server-id"); equal(ticket.jobId, "main-job")
end)
test("cannot capture main menu as destination", function()
	local f = fixture(); equal(f.core:capture(), nil)
end)
test("invalid tickets are rejected", function()
	local f = fixture()
	for _, patch in ipairs({ { version = 2 }, { controllerId = -1 }, { placeId = 0 }, { gameId = 0 },
		{ jobId = "" }, { joinId = "http://bad/path" }, { nonce = "x\ny" }, { createdAt = f.now + 11 },
		{ createdAt = f.now - 601 }, { controllerId = 1.5 }, { placeId = Core.LOBBY_PLACE_ID } }) do
		local ticket = clone(f.ticket)
		for key, value in pairs(patch) do ticket[key] = value end
		equal(Core.validateTicket(ticket, f.now), false)
	end
	equal(Core.validateTicket(nil, f.now), false)
end)
test("main cannot join itself", function()
	local f = fixture(); f.user.userId = 11; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false); equal(#f.sends, 0)
end)
test("wrong experience rejected", function()
	local f = fixture(); f.user.gameId = 100; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false)
end)
test("world client is never automatically logged out", function()
	local f = fixture(); f:arrive(); equal(f.core:begin(f.ticket), false); equal(#f.sends, 0)
end)
test("must observe slot selection after loading", function()
	local f = fixture(); equal(f.core:begin(f.ticket), false)
	f.core:onServers(nil); equal(f.core.realm, nil)
	f.core:onServers(23); equal(f.core.realm, nil)
	f.core:onServers("Etrean"); equal(f.core.state, "SLOT_READY")
end)
test("missing remote refuses join", function()
	local f = fixture(); f.remote = false; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false); equal(#f.sends, 0)
end)
test("exact ID sent once without consulting a filtered server list", function()
	local f = fixture(); f.ticket.joinId = "not-listed-to-alt"; f:start()
	equal(#f.sends, 1); equal(f.sends[1], "not-listed-to-alt"); equal(f.core.state, "REQUESTED")
	f.core:tick(); equal(f.core:begin(f.ticket), false); equal(#f.sends, 1)
end)
test("first storage failure prevents request", function()
	local f = fixture(); f.writable = false; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false); equal(#f.sends, 0); equal(f.core.state, "FAILED")
end)
test("second storage failure also prevents request", function()
	local f = fixture(); f.failSave = 2; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false); equal(#f.sends, 0); equal(f.core.operation.requestSent, false)
end)
test("remote exception reports failure with no fallback", function()
	local f = fixture(); f.remoteError = true; f.core:onServers("Etrean")
	equal(f.core:begin(f.ticket), false); equal(f.core.state, "FAILED"); equal(#f.sends, 0)
end)
test("teleport start is not success", function()
	local f = fixture(); f:start(); f.core:teleportStarted()
	equal(f.core.state, "TRAVELLING")
end)
test("successful arrival requires main presence", function()
	local f = fixture(); f:start(); f:arrive(); f.core:tick()
	equal(f.core.state, "WAITING_MAIN")
	f.mainPresent = true; f.core:tick(); equal(f.core.state, "VERIFIED")
end)
test("main presence in wrong server is not success", function()
	local f = fixture(); f:start(); f:arrive(); f.user.jobId = "wrong-job"; f.mainPresent = true
	f.core:tick(); equal(f.core.state, "WRONG_DESTINATION")
end)
test("matching JobId but wrong place rejected", function()
	local f = fixture(); f:start(); f:arrive(); f.user.placeId = 777; f.mainPresent = true
	f.core:tick(); equal(f.core.state, "WRONG_DESTINATION")
end)
test("matching place/job but wrong experience rejected", function()
	local f = fixture(); f:start(); f:arrive(); f.user.gameId = 777; f.mainPresent = true
	f.core:tick(); equal(f.core.state, "WRONG_DESTINATION")
end)
test("changed character slot is reported", function()
	local f = fixture(); f:start(); f:arrive(); f.mainPresent = true; f.user.slot = "different-slot"
	f.core:tick(); equal(f.core.state, "FAILED")
end)
test("changed account fails verification", function()
	local f = fixture(); f:start(); f:arrive(); f.mainPresent = true; f.user.userId = 44
	f.core:tick(); equal(f.core.state, "FAILED")
end)
test("120 second timeout never retries", function()
	local f = fixture(); f:start(); f.now += 120; f.core:tick()
	equal(f.core.state, "TIMED_OUT"); equal(#f.sends, 1)
end)
test("teleport failure never selects a fallback", function()
	local f = fixture(); f:start(); f.core:teleportFailed("server full")
	equal(f.core.state, "FAILED"); f.now += 10; f.core:tick(); equal(#f.sends, 1)
end)
test("reload after arrival verifies without another join", function()
	local f = fixture(); f:start(); local saved = clone(f.saved)
	f:arrive(); f.mainPresent = true; f.core = Core.new(f.adapter)
	equal(f.core:resume(saved), true); equal(f.core.state, "VERIFIED"); equal(#f.sends, 1)
end)
test("reload in lobby only resumes waiting", function()
	local f = fixture(); f:start(); local saved = clone(f.saved); f.core = Core.new(f.adapter)
	equal(f.core:resume(saved), true); equal(f.core.state, "REQUESTED"); equal(#f.sends, 1)
end)
test("incomplete saved request is never sent on reload", function()
	local f = fixture(); f:start(); f.saved.operation.requestSent = false
	f.core = Core.new(f.adapter); equal(f.core:resume(f.saved), true)
	equal(f.core.state, "FAILED"); equal(#f.sends, 1)
end)
test("another account's saved operation is ignored", function()
	local f = fixture(); f:start(); f.saved.accountId = 33; f.core = Core.new(f.adapter)
	equal(f.core:resume(f.saved), false); equal(f.core.state, "IDLE")
end)
test("corrupted saved state and deadlines are ignored", function()
	local f = fixture(); f:start()
	for _, patch in ipairs({ { state = "UNKNOWN" }, { deadline = f.now + 1000000 }, { requestAccount = 33 } }) do
		local saved = clone(f.saved)
		if patch.state then saved.state = patch.state end
		if patch.deadline then saved.operation.deadline = patch.deadline end
		if patch.requestAccount then saved.operation.accountId = patch.requestAccount end
		equal(Core.new(f.adapter):resume(saved), false)
	end
end)
test("expired saved operation never sends or verifies", function()
	local f = fixture(); f:start(); f.now += 601
	equal(Core.new(f.adapter):resume(f.saved), false); equal(#f.sends, 1)
end)
test("verified status becomes stale when main leaves", function()
	local f = fixture(); f:start(); f:arrive(); f.mainPresent = true; f.core:tick()
	f.mainPresent = false; f.core:tick(); equal(f.core.state, "STALE"); equal(#f.sends, 1)
end)
test("verified status becomes stale when account changes", function()
	local f = fixture(); f:start(); f:arrive(); f.mainPresent = true; f.core:tick()
	f.user.userId = 44; f.core:tick(); equal(f.core.state, "STALE")
end)
test("cancelled request is not reported as an undone teleport", function()
	local f = fixture(); f:start(); f.core:cancel(); equal(f.core.state, "CANCELLED")
	f:arrive(); f.mainPresent = true; f.core:tick(); equal(f.core.state, "CANCELLED"); equal(#f.sends, 1)
end)
test("terminal saved state does not trigger work on reload", function()
	local f = fixture(); f:start(); f.core:cancel(); local saved = clone(f.saved)
	f.core = Core.new(f.adapter); equal(f.core:resume(saved), true)
	equal(f.core.state, "CANCELLED"); equal(#f.sends, 1)
end)
test("manual retry still observes cooldown", function()
	local f = fixture(); f:start(); f.core:teleportFailed("test")
	equal(f.core:begin(f.ticket), false); f.now += 5
	equal(f.core:begin(f.ticket), true); equal(#f.sends, 2)
end)
test("idle tick and teleport events cannot initiate a join", function()
	local f = fixture(); f.core:tick(); f.core:teleportStarted(); f.core:teleportFailed("other script")
	equal(f.core.state, "IDLE"); equal(#f.sends, 0)
end)
test("event history is bounded", function()
	local f = fixture()
	for i = 1, 200 do f.core:onServers("realm-" .. i) end
	equal(#f.core:report().events, 40)
end)
print(string.format("\n%d passed; %d failed", passed, failed))
assert(failed == 0, "join-core regression tests failed")
