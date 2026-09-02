local environment = getgenv and getgenv() or _G
local Action = assert(environment.__CLAW_MODULES["src/Combat/Action.lua"])

local TimingProfile = {}
TimingProfile.__index = TimingProfile

function TimingProfile.new(values)
	values = values or {}
	local hitbox = values.hitbox
	if type(hitbox) == "table" then
		hitbox = Vector3.new(hitbox.X or 0, hitbox.Y or 0, hitbox.Z or 0)
	end
	local self = setmetatable({}, TimingProfile)
	self.id = tostring(values.id or values.name or "unknown")
	self.name = tostring(values.name or self.id)
	self.detector = values.detector or "animation"
	self.tag = values.tag or "Undefined"
	self.minDistance = math.max(0, tonumber(values.minDistance) or 0)
	self.maxDistance = math.max(self.minDistance, tonumber(values.maxDistance) or 0)
	self.hitbox = typeof(hitbox) == "Vector3" and hitbox or Vector3.zero
	self.hitboxOffset = tonumber(values.hitboxOffset) or 0
	self.delayUntilHitbox = values.delayUntilHitbox == true
	self.punishableWindow = math.max(0, tonumber(values.punishableWindow) or 0)
	self.afterWindow = math.max(0, tonumber(values.afterWindow) or 0)
	self.repeatStartDelay = math.max(0, tonumber(values.repeatStartDelay) or 0)
	self.repeatDelay = math.max(0, tonumber(values.repeatDelay) or 0)
	self.preferRepeat = values.preferRepeat == true
	self.allowAttacking = values.allowAttacking == true
	self.facingHitbox = values.facingHitbox ~= false
	self.noDodgeFallback = values.noDodgeFallback == true
	self.noBlockFallback = values.noBlockFallback == true
	self.noVentFallback = values.noVentFallback == true
	self.blockFallbackHold = math.max(0, tonumber(values.blockFallbackHold) or 0.30)
	self.preferBlockFallback = values.preferBlockFallback == true
	self.hyperArmor = values.hyperArmor == true
	self.sourceModule = tostring(values.sourceModule or "")
	self.preferModule = values.preferModule == true
	self.suppressGeneric = values.suppressGeneric == true
	self.ignoreAnimationEnd = values.ignoreAnimationEnd == true
	self.ignoreEarlyAnimationEnd = values.ignoreEarlyAnimationEnd == true
	self.maxAnimationTime = math.max(0, tonumber(values.maxAnimationTime) or 0)
	self.pastHitbox = values.pastHitbox == true
	self.predictFacing = values.predictFacing == true
	self.historySeconds = math.max(0, tonumber(values.historySeconds) or 0)
	self.predictionSeconds = math.max(0, tonumber(values.predictionSeconds) or 0)
	self.disablePrediction = values.disablePrediction == true
	self.useHitboxCFrame = values.useHitboxCFrame == true
	self.allowLocalPlayer = values.allowLocalPlayer == true
	self.ignoreLocalPlayer = values.ignoreLocalPlayer == true
	self.forceLocalPlayer = values.forceLocalPlayer == true
	self.probability = type(values.probability) == "table" and values.probability or {}
	self.actions = {}

	for _, action in ipairs(values.actions or {}) do
		self.actions[#self.actions + 1] = getmetatable(action) == Action and action or Action.new(action)
	end

	return self
end

function TimingProfile:addAction(action)
	self.actions[#self.actions + 1] = getmetatable(action) == Action and action or Action.new(action)
	return self
end

function TimingProfile:clone()
	return TimingProfile.new(self:serialize())
end

function TimingProfile:serialize()
	local actions = {}
	for index, action in ipairs(self.actions) do
		actions[index] = action:serialize()
	end

	return {
		id = self.id,
		name = self.name,
		detector = self.detector,
		tag = self.tag,
		minDistance = self.minDistance,
		maxDistance = self.maxDistance,
		hitbox = { X = self.hitbox.X, Y = self.hitbox.Y, Z = self.hitbox.Z },
		hitboxOffset = self.hitboxOffset,
		delayUntilHitbox = self.delayUntilHitbox,
		punishableWindow = self.punishableWindow,
		afterWindow = self.afterWindow,
		repeatStartDelay = self.repeatStartDelay,
		repeatDelay = self.repeatDelay,
		preferRepeat = self.preferRepeat,
		allowAttacking = self.allowAttacking,
		facingHitbox = self.facingHitbox,
		noDodgeFallback = self.noDodgeFallback,
		noBlockFallback = self.noBlockFallback,
		noVentFallback = self.noVentFallback,
		blockFallbackHold = self.blockFallbackHold,
		preferBlockFallback = self.preferBlockFallback,
		hyperArmor = self.hyperArmor,
		sourceModule = self.sourceModule,
		preferModule = self.preferModule,
		suppressGeneric = self.suppressGeneric,
		ignoreAnimationEnd = self.ignoreAnimationEnd,
		ignoreEarlyAnimationEnd = self.ignoreEarlyAnimationEnd,
		maxAnimationTime = self.maxAnimationTime,
		pastHitbox = self.pastHitbox,
		predictFacing = self.predictFacing,
		historySeconds = self.historySeconds,
		predictionSeconds = self.predictionSeconds,
		disablePrediction = self.disablePrediction,
		useHitboxCFrame = self.useHitboxCFrame,
		allowLocalPlayer = self.allowLocalPlayer,
		ignoreLocalPlayer = self.ignoreLocalPlayer,
		forceLocalPlayer = self.forceLocalPlayer,
		probability = self.probability,
		actions = actions,
	}
end

return TimingProfile
