local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES
local Signal = assert(modules["src/Runtime/Signal.lua"])
local AnimationDetector = assert(modules["src/Combat/Detection/AnimationDetector.lua"])
local SoundDetector = assert(modules["src/Combat/Detection/SoundDetector.lua"])
local PartDetector = assert(modules["src/Combat/Detection/PartDetector.lua"])
local EffectDetector = assert(modules["src/Combat/Detection/EffectDetector.lua"])
local ClientEffectDetector = assert(modules["src/Combat/Detection/ClientEffectDetector.lua"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DetectorHub = {}
DetectorHub.__index = DetectorHub

function DetectorHub.new(settings, timings, options)
	options = options or {}
	local shared = options.shared or {}
	local mobAnimationIDs = {}
	local function refreshMobAnimationIDs()
		table.clear(mobAnimationIDs)
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local animations = assets and assets:FindFirstChild("Anims")
		local mobs = animations and animations:FindFirstChild("Mobs")
		if not mobs then
			return
		end
		for _, animation in ipairs(mobs:GetDescendants()) do
			if animation:IsA("Animation") and animation.Name ~= "RunningAttack" then
				local id = tostring(animation.AnimationId or ""):match("(%d+)")
				if id then
					mobAnimationIDs[id] = true
				end
			end
		end
	end
	refreshMobAnimationIDs()
	local function classifyAnimation(id, animator)
		if not mobAnimationIDs[tostring(id)] then
			return nil
		end
		local entity = animator and animator:FindFirstAncestorWhichIsA("Model")
		if entity and Players:GetPlayerFromCharacter(entity) then
			return {
				playerMobAnimation = true,
				trustReason = "player replayed replicated mob animation",
			}
		end
		return nil
	end
	local function combatAnimation(track)
		if not track then
			return false
		end
		local ok, priority, looped, length = pcall(function()
			return track.Priority, track.Looped, track.Length
		end)
		if not ok or looped then
			return false
		end
		local actionPriority = priority == Enum.AnimationPriority.Action
			or priority == Enum.AnimationPriority.Action2
			or priority == Enum.AnimationPriority.Action3
			or priority == Enum.AnimationPriority.Action4
		if not actionPriority then
			return false
		end
		local maximum = settings:get("Defense.UnknownAnimationMaxLength")
		return length <= 0 or length <= maximum
	end
	local function accept(category, id, instance, track)
		-- Lycoris never sends the local character's animation tracks into the
		-- defense pipeline. Local attack assistance has its own animator hook,
		-- so rejecting them here removes misleading defense events without
		-- affecting action rolling, feints, or animation-speed assistance.
		local localCharacter = Players.LocalPlayer.Character
		if
			category == "animation"
			and localCharacter
			and instance
			and instance:IsDescendantOf(localCharacter)
		then
			return false
		end
		if timings:has(category, id) then
			return true
		end
		-- Unknown animation defense is a separate, visible policy. It catches
		-- newly introduced weapon animations without opening noisy sound, part,
		-- or effect detectors when indexed-only detection is selected.
		if category == "animation"
			and settings:get("Detection.UnknownAnimations")
			and settings:get("Enabled")
			and settings:get("Defense.Enabled")
		then
			return combatAnimation(track)
		end
		return not settings:get("Detection.OnlyConfigured")
	end
	local function detectorOptions(specific)
		local combined = {}
		for key, value in pairs(shared) do
			combined[key] = value
		end
		for key, value in pairs(specific or {}) do
			combined[key] = value
		end
		combined.accept = combined.accept or accept
		return combined
	end
	local animationOptions = {}
	for key, value in pairs(options.animation or {}) do
		animationOptions[key] = value
	end
	animationOptions.classify = animationOptions.classify or classifyAnimation
	local self = setmetatable({
		Settings = settings,
		Timings = timings,
		Detected = Signal.new(),
		Connections = {},
		Running = false,
		RefreshAnimationTrust = refreshMobAnimationIDs,
		Detectors = {
			Animations = AnimationDetector.new(detectorOptions(animationOptions)),
			Sounds = SoundDetector.new(detectorOptions(options.sound)),
			Parts = PartDetector.new(detectorOptions(options.part)),
			Effects = EffectDetector.new(detectorOptions(options.effect)),
			ClientEffects = ClientEffectDetector.new(detectorOptions(options.clientEffect)),
		},
	}, DetectorHub)

	for settingName, detector in pairs(self.Detectors) do
		self.Connections[#self.Connections + 1] = detector.Detected:Connect(function(event)
			local setting = settingName == "ClientEffects" and "Effects" or settingName
			if self.Settings:get("Detection." .. setting) then
				self.Detected:Fire(event)
			end
		end)
	end

	self.Connections[#self.Connections + 1] = timings.Changed:Connect(function()
		self.Detectors.Sounds:refresh()
	end)

	return self
end

function DetectorHub:start()
	if self.Running then
		return
	end
	self.Running = true
	self.RefreshAnimationTrust()
	self:sync()
end

function DetectorHub:sync(settingName)
	if not self.Running then
		return
	end
	for name, detector in pairs(self.Detectors) do
		local setting = name == "ClientEffects" and "Effects" or name
		if not settingName or setting == settingName then
			if self.Settings:get("Detection." .. setting) then
				detector:start()
			else
				detector:stop()
			end
		end
	end
end

function DetectorHub:stop()
	if not self.Running then
		return
	end
	self.Running = false
	for _, detector in pairs(self.Detectors) do
		detector:stop()
	end
end

function DetectorHub:refresh()
	if self.Running then
		self.Detectors.Sounds:refresh()
	end
end

function DetectorHub:Destroy()
	self:stop()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, detector in pairs(self.Detectors) do
		detector:Destroy()
	end
	self.Detected:Destroy()
end

return DetectorHub
