local ThreatArbiter = require("../src/Combat/ThreatArbiter")

local now = 100
local values = {
	["ThreatGuard.Enabled"] = true,
	["ThreatGuard.BurstWindow"] = 0.35,
	["ThreatGuard.BurstLimit"] = 8,
	["ThreatGuard.QuarantineSeconds"] = 1.25,
	["ThreatGuard.MaxPendingPerSource"] = 2,
	["ThreatGuard.PlanSeparation"] = 0.08,
	["ThreatGuard.CorroborationWindow"] = 0.18,
	["ThreatGuard.NoisyPassInterval"] = 0.20,
}

local settings = {}
function settings:get(path)
	return values[path]
end

local state = {
	Metrics = {},
	Events = {},
}
function state:increment(name, amount)
	self.Metrics[name] = (self.Metrics[name] or 0) + (amount or 1)
end
function state:emit(kind, payload)
	self.Events[#self.Events + 1] = { kind = kind, payload = payload }
end

local scheduler = { Cancelled = 0 }
function scheduler:cancel(scheduled, reason)
	self.Cancelled = self.Cancelled + 1
	if scheduled.onCancel then
		scheduled.onCancel(reason)
	end
	return true
end

local arbiter = ThreatArbiter.new(settings, state, scheduler, function()
	return now
end)
local attacker = { Name = "Breaker" }

local function animation(id)
	return {
		detector = "animation",
		id = tostring(id),
		entity = attacker,
		instance = attacker,
	}
end

for index = 1, 8 do
	assert(arbiter:observe(animation(index)) == true, "ordinary burst budget rejected too early")
	now = now + 0.01
end
local ninthAllowed, ninthReason = arbiter:observe(animation(9))
assert(ninthAllowed == false and ninthReason == "animation burst quarantined", "burst did not quarantine")
assert(state.Metrics.ThreatSpamBursts == 1, "spam burst was not counted")

local duringAllowed, duringReason = arbiter:observe(animation(10))
assert(duringAllowed == false and duringReason == "animation spam quarantine", "quarantine did not hold")

now = now + 2
local first = animation("first")
local second = animation("second")
local third = animation("third")
assert(arbiter:observe(first))
assert(arbiter:observe(second))
assert(arbiter:observe(third))

local firstAllowed, firstPlan = arbiter:claim(first, now + 0.20)
local secondAllowed, secondPlan = arbiter:claim(second, now + 0.50)
local thirdAllowed, _, thirdReason = arbiter:claim(third, now + 0.80)
assert(firstAllowed and firstPlan, "first source plan was not admitted")
assert(secondAllowed and secondPlan, "second source plan was not admitted")
assert(thirdAllowed == false and thirdReason == "source threat budget", "animation plan budget did not hold")

-- Non-animation evidence has reserved capacity. An Animator flood must not
-- starve a real replicated effect from the same attacker.
local effect = {
	detector = "effect",
	id = "CommittedAttack",
	entity = attacker,
	instance = attacker,
}
assert(arbiter:observe(effect))
local effectAllowed, effectPlan = arbiter:claim(effect, now + 1.10)
assert(effectAllowed and effectPlan, "trusted evidence was starved by animation plans")

local overlap = {
	detector = "part",
	id = "Hitbox",
	entity = attacker,
	instance = attacker,
}
assert(arbiter:observe(overlap))
local overlapAllowed, _, overlapReason = arbiter:claim(overlap, now + 1.14)
assert(overlapAllowed == false and overlapReason == "overlapping threat coalesced", "overlap was not coalesced")
assert(state.Metrics.ThreatCoalesced == 1, "coalesced metric was not counted")

local firstTask = {}
arbiter:register(firstPlan, firstTask)
arbiter:settle(firstPlan, firstTask, "test complete")
assert(state.ThreatSummary.activePlans == 2, "settled plan was not released")

arbiter:reset()
assert(state.ThreatSummary.activePlans == 0, "reset left active plans")

-- Stronger evidence replaces, rather than merely merging into, a lower-trust
-- animation plan in the same contact window.
local weak = animation("weak")
assert(arbiter:observe(weak))
local weakAllowed, weakPlan = arbiter:claim(weak, now + 2)
assert(weakAllowed and weakPlan)
local weakTask = {}
arbiter:register(weakPlan, weakTask)
weakTask.onCancel = function(reason)
	arbiter:settle(weakPlan, weakTask, reason)
end
local strong = {
	detector = "effect",
	id = "strong",
	entity = attacker,
	instance = attacker,
}
assert(arbiter:observe(strong))
local strongAllowed, strongPlan = arbiter:claim(strong, now + 2.04)
assert(strongAllowed and strongPlan, "strong evidence did not replace animation plan")
assert(scheduler.Cancelled == 1, "superseded animation task was not cancelled")
assert(state.Metrics.ThreatPromoted == 1, "stronger evidence promotion was not counted")

print("ThreatArbiter scenarios passed")
