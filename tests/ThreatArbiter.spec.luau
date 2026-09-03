local ThreatArbiter = require("../src/Combat/ThreatArbiter")

local now = 100
local values = {
	["ThreatGuard.Enabled"] = true,
	["ThreatGuard.BurstWindow"] = 0.35,
	["ThreatGuard.BurstLimit"] = 8,
	["ThreatGuard.QuarantineSeconds"] = 1.25,
	["ThreatGuard.MaxPendingPerSource"] = 2,
	["ThreatGuard.PlanSeparation"] = 0.08,
	["ThreatGuard.SourceRearm"] = 0.16,
	["ThreatGuard.SameAnimationRearm"] = 0.30,
	["ThreatGuard.EpisodeWindow"] = 2.50,
	["ThreatGuard.EpisodeMinimum"] = 12,
	["ThreatGuard.EpisodeUnique"] = 5,
	["ThreatGuard.EpisodeRepeat"] = 2,
	["ThreatGuard.ChurnWindow"] = 2.00,
	["ThreatGuard.ChurnLimit"] = 5,
	["ThreatGuard.AbortWindow"] = 1.50,
	["ThreatGuard.AbortLimit"] = 3,
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

local function animation(id, source)
	source = source or attacker
	return {
		detector = "animation",
		id = tostring(id),
		entity = source,
		instance = source,
	}
end

for index = 1, 8 do
	assert(arbiter:observe(animation(index)) == true, "ordinary burst budget rejected too early")
	now = now + 0.01
end
local ninthAllowed, ninthReason = arbiter:observe(animation(9))
assert(ninthAllowed == false and ninthReason == "animation burst signature isolated", "burst was not contained")
assert(state.Metrics.ThreatSpamBursts == 1, "spam burst was not counted")
assert((state.Metrics.ThreatSignaturesMuted or 0) == 1, "isolated signature was not counted")

local repeatedBurstAllowed, repeatedBurstReason = arbiter:observe(animation(9))
assert(
	repeatedBurstAllowed == false and repeatedBurstReason == "animation signature isolated",
	"isolated burst signature was admitted"
)
assert(arbiter:observe(animation(10)) == true, "a novel animation could not escape signature isolation")

now = now + 3
local first = animation("first")
local second = animation("second")
local third = animation("third")
assert(arbiter:observe(first))
assert(arbiter:observe(second))
assert(arbiter:observe(third))

local firstAllowed, firstPlan = arbiter:claim(first, now + 0.20)
now = now + 0.17
local secondAllowed, secondPlan = arbiter:claim(second, now + 0.50)
now = now + 0.17
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

-- A settled plan owns a short source lease. The slot cannot reopen on the
-- next frame, but stronger replicated evidence is never held behind it.
arbiter:reset()
local leased = animation("leased")
assert(arbiter:observe(leased))
local leasedAllowed, leasedPlan = arbiter:claim(leased, now + 0.40)
assert(leasedAllowed and leasedPlan)
local leasedTask = {}
arbiter:register(leasedPlan, leasedTask)
arbiter:settle(leasedPlan, leasedTask, "executed")
local rearmEvent = animation("too-soon")
assert(arbiter:observe(rearmEvent))
local rearmAllowed, _, rearmReason = arbiter:claim(rearmEvent, now + 0.50)
assert(rearmAllowed == false and rearmReason == "source rearm", "source lease reopened immediately")
assert(state.Metrics.ThreatRearmDrops == 1, "source rearm drop was not counted")
now = now + 0.17
local repeatedAnimation = animation("leased")
assert(arbiter:observe(repeatedAnimation))
local repeatedAllowed, _, repeatedReason = arbiter:claim(repeatedAnimation, now + 0.50)
assert(
	repeatedAllowed == false and repeatedReason == "same animation rearm",
	"same animation reopened before its longer lease"
)
assert(state.Metrics.ThreatRearmDrops == 2, "same-animation rearm drop was not counted")
local leaseEffect = {
	detector = "effect",
	id = "lease-bypass",
	entity = attacker,
	instance = attacker,
}
assert(arbiter:observe(leaseEffect))
local leaseEffectAllowed = arbiter:claim(leaseEffect, now + 0.70)
assert(leaseEffectAllowed == true, "strong evidence was blocked by animation rearm")

-- A passive breaker can stay below the raw burst threshold while repeatedly
-- opening and settling plans. The longer admission window must still contain
-- that paced churn, without relying on animation-event volume alone.
arbiter:reset()
local churnBefore = state.Metrics.ThreatChurnBursts or 0
for index = 1, 5 do
	local event = animation("paced-" .. index)
	assert(arbiter:observe(event))
	local allowed, plan = arbiter:claim(event, now + 0.30)
	assert(allowed and plan, "paced plan rejected before churn limit")
	local scheduled = {}
	arbiter:register(plan, scheduled)
	arbiter:settle(plan, scheduled, "executed")
	now = now + 0.18
end
local pacedBreaker = animation("paced-breaker")
assert(arbiter:observe(pacedBreaker))
local pacedAllowed, _, pacedReason = arbiter:claim(pacedBreaker, now + 0.30)
assert(pacedAllowed == false and pacedReason == "churning animation signature isolated", "paced churn escaped isolation")
assert((state.Metrics.ThreatChurnBursts or 0) == churnBefore + 1, "paced churn metric was not counted")
local realDuringChurn = animation("real-during-churn")
assert(arbiter:observe(realDuringChurn), "churn isolation shut down the entire Animator")

-- Repeated early track aborts are a second breaker signature. A single feint
-- is harmless; three rapid aborts isolate only the repeatedly aborted ID.
arbiter:reset()
now = now + 2
local abortBefore = state.Metrics.ThreatChurnBursts or 0
for index = 1, 3 do
	local event = animation("abort-" .. index)
	assert(arbiter:observe(event))
	local allowed, plan = arbiter:claim(event, now + 0.30)
	assert(allowed and plan, "abort test plan was not admitted")
	local scheduled = {}
	arbiter:register(plan, scheduled)
	arbiter:settle(plan, scheduled, "animation ended")
	now = now + 0.18
end
assert((state.Metrics.ThreatAborted or 0) == 3, "early abort outcomes were not counted")
assert((state.Metrics.ThreatChurnBursts or 0) == abortBefore + 1, "early aborts did not trigger isolation")
local repeatedAbort = animation("abort-3")
local repeatedAbortAllowed, repeatedAbortReason = arbiter:observe(repeatedAbort)
assert(
	repeatedAbortAllowed == false and repeatedAbortReason == "animation signature isolated",
	"aborted signature was admitted again"
)
local noisyEscape = animation("real-during-abort-noise")
assert(arbiter:observe(noisyEscape), "abort isolation shut down unrelated animation IDs")
local trustedDuringQuarantine = {
	detector = "part",
	id = "real-hitbox",
	entity = attacker,
	instance = attacker,
}
assert(arbiter:observe(trustedDuringQuarantine), "trusted detector was isolated with animations")
local trustedAllowed = arbiter:claim(trustedDuringQuarantine, now + 0.40)
assert(trustedAllowed == true, "trusted detector could not bypass animation isolation")
local otherAttacker = { Name = "LegitimateSource" }
local isolatedEvent = animation("isolated-source", otherAttacker)
assert(arbiter:observe(isolatedEvent), "one source quarantined a different attacker")
local isolatedAllowed = arbiter:claim(isolatedEvent, now + 0.40)
assert(isolatedAllowed == true, "one source consumed a different attacker's plan budget")
now = now + 2
local recoveredEvent = animation("recovered")
assert(arbiter:observe(recoveredEvent), "source did not leave isolation")
local recoveredAllowed = arbiter:claim(recoveredEvent, now + 0.40)
assert(recoveredAllowed == true, "source plan admission did not recover after isolation")

-- A passive seven-ID breaker stays under the short burst threshold. The
-- episode detector must learn and isolate the repeating signatures without
-- blocking a new real animation from the same character.
arbiter:reset()
now = now + 3
local protected = animation("protected-real")
local protectedAllowed, protectedPlan = arbiter:claim(protected, now + 0.50)
assert(protectedAllowed and protectedPlan, "protected plan setup failed")
local protectedTask = {}
protectedTask.onCancel = function(reason)
	arbiter:settle(protectedPlan, protectedTask, reason)
end
arbiter:register(protectedPlan, protectedTask)
local cancelledBeforeEpisode = scheduler.Cancelled
local episodeIDs = { "fake-1", "fake-2", "fake-3", "fake-4", "fake-5", "fake-6" }
for index = 1, 11 do
	assert(arbiter:observe(animation(episodeIDs[((index - 1) % #episodeIDs) + 1])))
	now = now + 0.08
end
local episodeAllowed, episodeReason = arbiter:observe(animation("fake-6"))
assert(
	episodeAllowed == false and episodeReason == "animation signature isolated",
	"repeating multi-ID episode was not isolated"
)
local repeatedFakeAllowed = arbiter:observe(animation("fake-1"))
assert(repeatedFakeAllowed == false, "known episode signature escaped isolation")
assert(arbiter:observe(animation("actual-strike")), "episode isolation blocked a novel real strike")
assert(scheduler.Cancelled == cancelledBeforeEpisode, "episode isolation cancelled an unrelated pending plan")

-- The evidence windows themselves remain bounded under an absurd unique-ID
-- flood; this should exercise fixed-size work rather than growing per event.
arbiter:reset()
now = now + 3
for index = 1, 5000 do
	arbiter:observe(animation("unique-" .. tostring(index)))
end
assert(arbiter:observe(animation("real-after-flood")), "bounded unique flood closed the source channel")

print("ThreatArbiter scenarios passed")
