local ProbabilityResolver = {}
ProbabilityResolver.__index = ProbabilityResolver

local function rate(profile, name, fallback)
	local value = profile.probability and profile.probability[name]
	return math.clamp(tonumber(value) or fallback, 0, 100)
end

function ProbabilityResolver.new(settings, seed)
	return setmetatable({
		Settings = settings,
		Random = Random.new(seed or math.floor(os.clock() * 100000)),
	}, ProbabilityResolver)
end

function ProbabilityResolver:_roll(chance)
	return self.Random:NextNumber(0, 100) <= chance
end

function ProbabilityResolver:resolve(action, profile)
	if not self.Settings:get("Probability.Enabled") then
		return action
	end

	local probability = self.Settings:get("Probability")
	local failureRate = rate(profile, "FailureRate", probability.FailureRate)
	if probability.AllowFailure and self:_roll(failureRate) then
		return nil, "intentional-failure"
	end

	local resolved = action:clone()
	local actionChance = probability[resolved.kind]
	if type(actionChance) == "number" and not self:_roll(actionChance) then
		return nil, "action-probability"
	end

	if resolved.kind == "Parry" then
		local dashRate = rate(profile, "DashInsteadOfParryRate", probability.DashInsteadOfParryRate)
		if self:_roll(dashRate) then
			resolved.kind = "Dodge"
			resolved.name = resolved.name .. " (dash variation)"
		end
	end

	resolved.metadata.ignoreAnimationEnd =
		self:_roll(rate(profile, "IgnoreAnimationEndRate", probability.IgnoreAnimationEndRate))
	return resolved
end

return ProbabilityResolver
