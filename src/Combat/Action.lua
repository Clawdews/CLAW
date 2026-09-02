local Action = {}
Action.__index = Action

local VALID_KINDS = {
	Parry = true,
	Block = true,
	Dodge = true,
	FullDodge = true,
	Jump = true,
	Slide = true,
	Crouch = true,
	Teleport = true,
	Feint = true,
	M1 = true,
	Custom = true,
}

function Action.new(values)
	values = values or {}
	local kind = values.kind or "Parry"
	assert(VALID_KINDS[kind], "unsupported combat action: " .. tostring(kind))

	local hitbox = values.hitbox
	if type(hitbox) == "table" then
		hitbox = Vector3.new(hitbox.X or 0, hitbox.Y or 0, hitbox.Z or 0)
	end

	return setmetatable({
		kind = kind,
		name = values.name or kind,
		delay = math.max(0, tonumber(values.delay) or 0),
		duration = math.max(0, tonumber(values.duration) or 0),
		hitbox = typeof(hitbox) == "Vector3" and hitbox or Vector3.zero,
		ignoreHitbox = values.ignoreHitbox == true,
		chance = math.clamp(tonumber(values.chance) or 100, 0, 100),
		metadata = type(values.metadata) == "table" and values.metadata or {},
	}, Action)
end

function Action:clone()
	return Action.new(self:serialize())
end

function Action:serialize()
	local metadata = {}
	for key, value in pairs(self.metadata) do
		metadata[key] = value
	end
	return {
		kind = self.kind,
		name = self.name,
		delay = self.delay,
		duration = self.duration,
		hitbox = { X = self.hitbox.X, Y = self.hitbox.Y, Z = self.hitbox.Z },
		ignoreHitbox = self.ignoreHitbox,
		chance = self.chance,
		metadata = metadata,
	}
end

function Action:shouldRun(random)
	if self.chance >= 100 then
		return true
	end
	local roll = random and random:NextNumber(0, 100) or math.random() * 100
	return roll <= self.chance
end

return Action
