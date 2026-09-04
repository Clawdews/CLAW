local Auto = require("../control/auto")
local Core = require("../join/core")
local passed = 0
local function test(name, fn) fn(); passed += 1; print("PASS " .. name) end
local function fixture(saved)
	local f = { now = 2000000000, current = { userId = 22, gameId = 99, placeId = Auto.LOBBY, jobId = "lobby" },
		picks = 0, joins = 0, menus = 0, confirms = 0, ready = false, storage = true, joinState = "IDLE", present = false }
	f.profile = { accountId = "22", mainId = "11", role = "alt", slot = "chosen-slot", follow = true }
	f.target = { enabled = true, key = "99.123.main-job", expiresAt = f.now + 35,
		ticket = { version = 1, controllerId = 11, gameId = 99, placeId = 123, jobId = "main-job", joinId = "main-job",
			createdAt = f.now, nonce = "revision-1" } }
	f.adapter = { now = function() return f.now end, current = function() return f.current end,
		save = function() f.saved = f.auto and f.auto:serialize(); return f.storage end,
		joinState = function() return f.joinState end,
		validTicket = function(ticket) return Core.validateTicket(ticket, f.now) end,
		hasMain = function() return f.present end, allowMenuReturn = true,
		returnMenu = function() f.menus += 1; return true end,
		confirmMenu = function() f.confirms += 1; return f.prompt == true end,
		pickSlot = function(slot) assert(slot == "chosen-slot"); f.picks += 1; return true end,
		slotReady = function() return f.ready end,
		beginJoin = function(ticket) assert(ticket.jobId == "main-job"); f.joins += 1; f.joinState = "REQUESTED"; return true end,
	}
	f.auto = Auto.new(f.adapter, saved)
	f.auto:setProfile(f.profile); f.auto:setTarget(f.target)
	return f
end
test("select slot, wait for server signal, join and verify", function()
	local f = fixture(); f.auto:tick(); assert(f.picks == 1 and f.joins == 0)
	f.auto:tick(); assert(f.picks == 1 and f.joins == 0)
	f.ready = true; f.auto:tick(); assert(f.joins == 1)
	f.auto:tick(); assert(f.joins == 1 and f.auto.status == "REQUESTED")
	f.joinState = "VERIFIED"; f.auto:tick(); assert(f.auto.status == "VERIFIED")
end)
test("main never receives automatic game actions", function()
	local f = fixture(); f.profile.role = "main"; f.auto:tick()
	assert(f.picks == 0 and f.menus == 0 and f.joins == 0)
end)
test("paused configuration sends nothing", function()
	local f = fixture(); f.profile.follow = false; f.auto:tick(); assert(f.picks == 0)
end)
test("wrong account profile cannot arm auto-follow", function()
	local f = fixture(); f.auto.profile = nil; f.profile.accountId = "33"
	assert(not f.auto:setProfile(f.profile)); f.auto:tick(); assert(f.picks == 0)
end)
test("expired destination is not used", function()
	local f = fixture(); f.now += 36; f.auto:tick(); assert(f.picks == 0 and f.auto.status == "WAITING_MAIN")
end)
test("target cannot claim another main", function()
	local f = fixture(); f.target.ticket.controllerId = 33; f.auto:tick(); assert(f.picks == 0)
end)
test("malformed ticket and mismatched target key fail closed", function()
	local f = fixture(); f.target.key = "fake"; f.auto:setTarget(f.target)
	f.auto:tick(); assert(f.picks == 0)
	f.auto:setTarget({ enabled = true, key = "99.123.main-job", expiresAt = f.now + 999999, ticket = f.target.ticket })
	f.auto:tick(); assert(f.picks == 0)
end)
test("already with main does not teleport again", function()
	local f = fixture(); f.current.placeId = 123; f.current.jobId = "main-job"; f.present = true
	f.auto:tick(); assert(f.auto.status == "WITH_MAIN" and f.joins == 0 and f.menus == 0)
end)
test("matching server without main waits", function()
	local f = fixture(); f.current.placeId = 123; f.current.jobId = "main-job"
	f.auto:tick(); assert(f.auto.status == "WAITING_MAIN_PRESENCE" and f.menus == 0)
end)
test("wrong character slot is not reported as success", function()
	local f = fixture(); f.current.placeId = 123; f.current.jobId = "main-job"; f.current.slot = "wrong"
	f.present = true; f.auto:tick(); assert(f.auto.status:find("wrong character"))
end)
test("unknown slot never guesses a character", function()
	local f = fixture(); f.profile.slot = nil; f.auto:tick(); assert(f.picks == 0 and f.menus == 0)
end)
test("storage failure prevents requests", function()
	local f = fixture(); f.storage = false; f.auto:tick(); assert(f.picks == 0 and f.joins == 0)
end)
test("pause arriving during persistence prevents the next action", function()
	local f = fixture(); f.adapter.save = function() f.profile.follow = false; return true end
	f.auto:tick(); assert(f.picks == 0 and f.joins == 0 and f.menus == 0)
end)
test("non-finite target expiry is rejected", function()
	local f = fixture(); f.target.expiresAt = 0 / 0; f.auto:setTarget(f.target)
	f.auto:tick(); assert(f.picks == 0)
end)
test("return to menu is explicit local opt-in", function()
	local f = fixture(); f.current.placeId = 456; f.adapter.allowMenuReturn = false; f.auto:tick()
	assert(f.menus == 0 and f.auto.attempt == nil and f.auto.status:find("WAITING_MENU"))
	f.current.placeId = Auto.LOBBY; f.auto:tick(); assert(f.picks == 1)
end)

test("legacy menu-disabled hold recovers after manual menu return without retry", function()
	local f = fixture({ attempt = { key = "99.123.main-job", phase = "HOLD", deadline = 2000000001,
		startedAt = 2000000000, reason = "return to menu disabled in local config" } })
	f.adapter.allowMenuReturn = false; f.auto:tick(); assert(f.picks == 1 and f.menus == 0)
end)

test("region mismatch blocks PickServer even after a slot-ready event", function()
	local f = fixture(); f.adapter.requireRegionCheck = true
	f.adapter.chooseSlot = function() return "chosen-slot" end
	f.adapter.regionMatches = function() return false, "REGION_MISMATCH" end
	f.auto:tick(); f.ready = true; f.auto:tick()
	assert(f.picks == 1 and f.joins == 0 and f.auto.attempt.phase == "HOLD")
	for _ = 1, 50 do f.auto:tick() end; assert(f.picks == 1)
end)

test("approved slot change during selection stops before joining", function()
	local f = fixture(); f.adapter.requireRegionCheck = true
	local chosen = "chosen-slot"; f.adapter.chooseSlot = function() return chosen end
	f.adapter.regionMatches = function() return true end
	f.auto:tick(); chosen = "new-slot"; f.ready = true; f.auto:tick(); assert(f.joins == 0)
end)

test("missing compatible slot does not select a character or leave the world", function()
	local f = fixture(); f.adapter.requireRegionCheck = true
	f.adapter.chooseSlot = function() return nil, "NO_COMPATIBLE_SLOT" end
	f.auto:tick(); assert(f.picks == 0 and f.menus == 0 and f.joins == 0)
end)
test("menu request issued once and confirmation issued once", function()
	local f = fixture(); f.current.placeId = 456; f.auto:tick(); f.auto:tick(); assert(f.menus == 1)
	f.prompt = true; f.auto:tick(); local count = f.confirms; f.auto:tick(); assert(f.confirms == count)
	f.current.placeId = Auto.LOBBY; f.auto:tick(); assert(f.picks == 1)
end)
test("reload in menu resumes without another logout request", function()
	local f = fixture(); f.current.placeId = 456; f.auto:tick()
	local g = fixture(f.auto:serialize()); g.auto:tick(); assert(g.menus == 0 and g.picks == 1)
end)
test("slot timeout holds instead of retrying", function()
	local f = fixture(); f.auto:tick(); f.now += 31; f.target.expiresAt = f.now + 35; f.auto:tick()
	assert(f.auto.attempt.phase == "HOLD"); f.auto:tick(); assert(f.picks == 1)
end)
test("join failure waits for explicit retry despite repeated packets", function()
	local f = fixture(); f.auto:tick(); f.ready = true; f.auto:tick(); f.joinState = "FAILED"; f.auto:tick()
	for _ = 1, 100 do f.auto:setTarget(f.target); f.auto:tick() end
	assert(f.picks == 1 and f.joins == 1)
	f.profile.retry = "retry-1"; f.auto:setProfile(f.profile); f.auto:tick(); assert(f.picks == 2)
end)
test("retry cannot abandon a running join", function()
	local f = fixture(); f.auto:tick(); f.ready = true; f.auto:tick()
	f.profile.retry = "retry-1"; f.auto:setProfile(f.profile); f.auto:tick(); assert(f.joins == 1)
end)
test("disconnect before slot completion prevents joining", function()
	local f = fixture(); f.auto:tick(); f.auto:disconnected(); f.ready = true; f.auto:tick(); assert(f.joins == 0)
end)
test("pause does not claim to undo an accepted teleport", function()
	local f = fixture(); f.auto:tick(); f.ready = true; f.auto:tick()
	f.profile.follow = false; f.joinState = "VERIFIED"; f.auto:tick()
	assert(f.auto.status == "VERIFIED" and f.joins == 1)
end)
test("new target does not reuse the old slot signal", function()
	local f = fixture(); f.auto:tick(); f.now += 11
	f.target.key = "99.124.other-job"; f.target.ticket.placeId = 124; f.target.ticket.jobId = "other-job"
	f.auto:setTarget(f.target); f.auto:tick(); assert(f.picks == 2 and f.joins == 0)
end)
test("another script leaving the menu stops the pending join", function()
	local f = fixture(); f.auto:tick(); f.current.placeId = 789; f.auto:tick()
	assert(f.auto.attempt.phase == "HOLD" and f.joins == 0)
end)
test("reload with a saved join never resends it", function()
	local f = fixture(); f.auto:tick(); f.ready = true; f.auto:tick()
	local g = fixture(f.auto:serialize()); g.joinState = "REQUESTED"; g.auto:tick()
	assert(g.picks == 0 and g.joins == 0 and g.auto.status == "REQUESTED")
end)
print(tostring(passed) .. " auto-follow tests passed")
