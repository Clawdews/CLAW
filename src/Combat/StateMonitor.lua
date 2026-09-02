local Players = game:GetService("Players")

local StateMonitor = {}
StateMonitor.__index = StateMonitor

local FLAGS = {
	InCombat = { "InCombat", "CombatTag", "Danger" },
	IFrames = { "IFrame", "Invulnerable", "Dodging", "Immortal" },
	AutoParryFrames = { "AutoParry", "AutoParryFrame", "AutoParryFrames" },
	Ragdolled = { "Ragdoll", "Ragdolled", "Knocked" },
	Stunned = { "Stun", "Stunned", "ActionLocked" },
	DamagedAnother = { "DamagedAnother" },
	UsingMantra = { "UsingMantra", "CastingSpell", "Casting" },
	Attacking = { "Attacking", "Swinging", "LightAttack", "UsingMove" },
	WispActive = { "Wisp", "WispActive" },
	WispCooldown = { "WispCooldown" },
	GoldenTongueCooldown = { "GoldenTongueCooldown" },
	ArdourActive = { "Ardour", "ArdourActive" },
	FlowStateActive = { "FlowState", "FlowStateActive" },
	SightlessBeam = { "SightlessBeam", "UsingSightlessBeam" },
}

function StateMonitor.new(state)
	return setmetatable({
		State = state,
		Connections = {},
		CharacterConnections = {},
		Running = false,
		RefreshQueued = false,
	}, StateMonitor)
end

function StateMonitor:_bind(list, signal, callback)
	local connection = signal:Connect(callback)
	list[#list + 1] = connection
	return connection
end

function StateMonitor:_disconnect(list)
	for _, connection in ipairs(list) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(list)
end

function StateMonitor:_has(character, names)
	for _, name in ipairs(names) do
		if character:GetAttribute(name) == true or character:FindFirstChild(name, true) then
			return true
		end
	end
	return false
end

function StateMonitor:_setFlag(name, value)
	if self.State.Flags[name] == value then
		return
	end
	self.State.Flags[name] = value
	self.State:emit("flag", { name = name, value = value })
end

function StateMonitor:refresh()
	local character = self.State.Character
	if not character then
		return
	end
	for name, aliases in pairs(FLAGS) do
		self:_setFlag(name, self:_has(character, aliases))
	end
	self:_setFlag("WeaponEquipped", character:FindFirstChildWhichIsA("Tool") ~= nil)
end

function StateMonitor:queueRefresh()
	if self.RefreshQueued then
		return
	end
	self.RefreshQueued = true
	task.defer(function()
		self.RefreshQueued = false
		if self.Running then
			self:refresh()
		end
	end)
end

function StateMonitor:attach(character)
	self:_disconnect(self.CharacterConnections)
	self.State:setCharacter(character)
	if not character then
		return
	end

	self:_bind(self.CharacterConnections, character.DescendantAdded, function()
		self:queueRefresh()
	end)
	self:_bind(self.CharacterConnections, character.DescendantRemoving, function()
		self:queueRefresh()
	end)

	for _, aliases in pairs(FLAGS) do
		for _, attribute in ipairs(aliases) do
			self:_bind(self.CharacterConnections, character:GetAttributeChangedSignal(attribute), function()
				self:queueRefresh()
			end)
		end
	end
	self:refresh()
end

function StateMonitor:start()
	if self.Running then
		return
	end
	self.Running = true
	self:_bind(self.Connections, Players.LocalPlayer.CharacterAdded, function(character)
		self:attach(character)
	end)
	self:attach(Players.LocalPlayer.Character)
end

function StateMonitor:stop()
	self.Running = false
	self:_disconnect(self.CharacterConnections)
	self:_disconnect(self.Connections)
end

function StateMonitor:Destroy()
	self:stop()
end

return StateMonitor
