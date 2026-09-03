local environment = getgenv and getgenv() or _G

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LocalPlayer = Players.LocalPlayer
end
assert(LocalPlayer, "CLAW RELAY: LocalPlayer is unavailable")
local DEFAULTS = {
	ControllerUserId = 0,
	ControllerName = "",
	CommandPrefix = ";alts",
	BringSeconds = 3,
	BringSpeed = 40,
	BringVerticalSpeed = 16,
	BringAcceleration = 80,
	BringTimeout = 300,
	ReleaseHeadPin = true,
	FormationRadius = 5,
	FormationSlot = 0,
	AutoStart = true,
	AutoStartAttempts = 12,
	TrustedUserIds = {},
	TrustedNames = {},
	ProximitySafety = false,
	ProximityDistance = 80,
	ProximityGraceSeconds = 2,
	ProximityPollSeconds = 0.25,
}

local function copyArray(value)
	local result = {}
	if type(value) == "table" then
		for _, item in ipairs(value) do
			result[#result + 1] = item
		end
	end
	return result
end

local function finiteNumber(value)
	local number = tonumber(value)
	if number and number == number and math.abs(number) < math.huge then
		return number
	end
	return nil
end

local function loadConfig()
	local supplied = type(environment.CLAW_RELAY_CONFIG) == "table" and environment.CLAW_RELAY_CONFIG or {}
	local config = {}
	for key, default in pairs(DEFAULTS) do
		local value = supplied[key]
		if value == nil then
			value = default
		end
		config[key] = type(default) == "table" and copyArray(value) or value
	end
	config.ControllerUserId = math.max(0, math.floor(tonumber(config.ControllerUserId) or 0))
	config.ControllerName = tostring(config.ControllerName or ""):match("^%s*(.-)%s*$")
	config.CommandPrefix = tostring(config.CommandPrefix or ";alts"):match("^%s*(.-)%s*$")
	config.BringSeconds = math.clamp(finiteNumber(config.BringSeconds) or 3, 0.25, 600)
	config.BringSpeed = math.clamp(finiteNumber(config.BringSpeed) or 40, 5, 120)
	config.BringVerticalSpeed = math.clamp(finiteNumber(config.BringVerticalSpeed) or 16, 2, 60)
	config.BringAcceleration = math.clamp(finiteNumber(config.BringAcceleration) or 80, 10, 240)
	config.BringTimeout = math.clamp(finiteNumber(config.BringTimeout) or 300, 10, 600)
	config.FormationRadius = math.clamp(tonumber(config.FormationRadius) or 5, 0, 30)
	config.FormationSlot = math.max(0, math.floor(tonumber(config.FormationSlot) or 0))
	config.AutoStartAttempts = math.clamp(math.floor(tonumber(config.AutoStartAttempts) or 12), 1, 60)
	config.ProximityDistance = math.clamp(tonumber(config.ProximityDistance) or 80, 5, 1000)
	config.ProximityGraceSeconds = math.clamp(tonumber(config.ProximityGraceSeconds) or 2, 0.25, 30)
	config.ProximityPollSeconds = math.clamp(tonumber(config.ProximityPollSeconds) or 0.25, 0.1, 5)
	return config
end

local Config = loadConfig()

local function configuredController()
	return Config.ControllerUserId > 0 or Config.ControllerName ~= ""
end

assert(configuredController(), "CLAW RELAY: set ControllerUserId or ControllerName in CLAW_RELAY_CONFIG")
assert(Config.CommandPrefix ~= "", "CLAW RELAY: CommandPrefix cannot be empty")

local function isController(player)
	if not player then
		return false
	end
	if Config.ControllerUserId > 0 then
		return player.UserId == Config.ControllerUserId
	end
	return string.lower(player.Name) == string.lower(Config.ControllerName)
end

if isController(LocalPlayer) then
	warn("[CLAW RELAY] This account is configured as the controller; follower runtime not started")
	return nil
end

local previous = rawget(environment, "CLAW_RELAY")
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy, previous, "reload")
end

local Relay = {
	Name = "CLAW RELAY",
	Version = "0.2.0",
	Config = Config,
	Running = true,
	Connections = {},
	Controller = nil,
	ControllerChat = nil,
	MovementGeneration = 0,
	MovementActive = false,
	Movement = nil,
	LastMovement = "not started",
	MenuGeneration = 0,
	PhaseEnabled = false,
	SafetyEnabled = Config.ProximitySafety == true,
	SafetyTriggered = false,
	UnsafeSince = setmetatable({}, { __mode = "k" }),
	OriginalCollision = setmetatable({}, { __mode = "k" }),
}
Relay.__index = Relay

local function log(message)
	print("[CLAW RELAY] " .. tostring(message))
end

local function warnRelay(message)
	warn("[CLAW RELAY] " .. tostring(message))
end

function Relay:_connect(signal, callback)
	local connection = signal:Connect(callback)
	self.Connections[#self.Connections + 1] = connection
	return connection
end

function Relay:_character(player)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, root, humanoid
end

function Relay:_applyNoclip()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if self.OriginalCollision[descendant] == nil then
				self.OriginalCollision[descendant] = descendant.CanCollide
			end
			descendant.CanCollide = false
		end
	end
end

function Relay:_restoreCollision()
	for part, original in pairs(self.OriginalCollision) do
		if part and part.Parent then
			part.CanCollide = original
		end
		self.OriginalCollision[part] = nil
	end
end

function Relay:_formationOffset()
	local slot = Config.FormationSlot
	if slot <= 0 then
		slot = (math.abs(LocalPlayer.UserId) % 24) + 1
	end
	local zeroBased = slot - 1
	local ring = math.floor(zeroBased / 8)
	local angle = math.rad((zeroBased % 8) * 45 + (ring % 2) * 22.5)
	local radius = Config.FormationRadius + ring * 2.5
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), slot
end

local function flightProperty(movement, instance, property, value)
	local properties = movement.Properties[instance]
	if not properties then
		properties = {}
		movement.Properties[instance] = properties
	end
	local saved = properties[property]
	if not saved then
		saved = { Original = instance[property] }
		properties[property] = saved
	end
	saved.Applied = value
	instance[property] = value
end

function Relay:cancelMovement(reason)
	self.MovementGeneration = self.MovementGeneration + 1
	self.MovementActive = false
	local movement = self.Movement
	self.Movement = nil
	if movement then
		if movement.Connection then movement.Connection:Disconnect() end
		if movement.Mover then movement.Mover:Destroy() end
		if LocalPlayer.Character == movement.Character and movement.Root.Parent then
			pcall(function() movement.Root.AssemblyLinearVelocity = Vector3.zero end)
		end
		for instance, properties in pairs(movement.Properties) do
			for property, saved in pairs(properties) do
				pcall(function()
					if instance.Parent and instance[property] == saved.Applied then
						instance[property] = saved.Original
					end
				end)
			end
		end
	end
	if not self.PhaseEnabled then self:_restoreCollision() end
	if reason then
		self.LastMovement = tostring(reason)
		log("movement stopped: " .. self.LastMovement)
	end
end

function Relay:_flightState(movement)
	flightProperty(movement, movement.Manager, "ActiveController", movement.Air)
	for _, parent in ipairs({ movement.Root, movement.Manager }) do
		local sensor = parent:FindFirstChild("GroundSensor")
		if sensor and sensor:IsA("ControllerPartSensor") then
			flightProperty(movement, sensor, "SearchDistance", 0)
		end
	end
	local helio = movement.Root:FindFirstChild("HelioFlight")
	if helio and helio:IsA("BodyVelocity") then
		flightProperty(movement, helio, "MaxForce", Vector3.zero)
	end
	self:_applyNoclip()

	-- Only the specific head pin handled by PX; never sweep other body movers.
	local head = movement.Character:FindFirstChild("Head")
	local pin = head and head:FindFirstChild("BodyPosition")
	if Config.ReleaseHeadPin and pin and pin:IsA("BodyPosition") then
		if movement.PinsReleased >= 3 then
			return false, "head movement pin keeps returning"
		end
		pin:Destroy()
		movement.PinsReleased = movement.PinsReleased + 1
		log("released head movement pin (" .. movement.PinsReleased .. ")")
	end
	return true
end

function Relay:_stepFlight(movement, dt)
	if not self.Running or LocalPlayer.Character ~= movement.Character or not movement.Root.Parent
		or movement.Humanoid.Health <= 0 then
		return self:cancelMovement("character unavailable")
	end
	if not self.Controller or self.Controller.Character ~= movement.TargetCharacter
		or not movement.TargetRoot.Parent or movement.TargetHumanoid.Health <= 0 then
		return self:cancelMovement("controller character changed")
	end
	if movement.Root.Anchored then return self:cancelMovement("character is anchored") end
	if movement.Mover.Parent ~= movement.Root then return self:cancelMovement("flight mover removed") end
	if not movement.Manager.Parent or not movement.Air.Parent then
		return self:cancelMovement("air controller unavailable")
	end
	local now = os.clock()
	if now - movement.Started >= Config.BringTimeout then return self:cancelMovement("travel timeout") end
	dt = finiteNumber(dt)
	if not dt or dt <= 0 then return end

	local position = movement.Root.Position
	-- Stop on a large external correction instead of dragging back along a stale tween.
	if dt <= 0.25 then
		local expected = movement.PreviousPosition + movement.Velocity * dt
		if (position - expected).Magnitude > 12 then
			return self:cancelMovement("position changed unexpectedly; possible knockback or server correction")
		end
	end
	movement.PreviousPosition = position
	local delta = movement.Goal - position
	local distance = delta.Magnitude
	if distance <= 1.2 and movement.Velocity.Magnitude <= 4 then
		return self:cancelMovement("arrived")
	end
	if distance < movement.BestDistance - 0.25 then
		movement.BestDistance = distance
		movement.LastProgress = now
	elseif now - movement.LastProgress > 6 then
		return self:cancelMovement("no progress for 6 seconds")
	end

	local ok, reason = self:_flightState(movement)
	if not ok then return self:cancelMovement(reason) end
	local limit = math.min(Config.BringSpeed, movement.PaceLimit)
	local desired = distance > 0.001 and delta.Unit * math.min(limit, distance * 2) or Vector3.zero
	desired = Vector3.new(desired.X, math.clamp(desired.Y, -Config.BringVerticalSpeed, Config.BringVerticalSpeed), desired.Z)
	local change = desired - movement.Velocity
	local maxChange = Config.BringAcceleration * math.min(dt, 0.1)
	if change.Magnitude > maxChange then change = change.Unit * maxChange end
	movement.Velocity = movement.Velocity + change
	movement.Mover.Velocity = movement.Velocity
	movement.Root.AssemblyLinearVelocity = movement.Velocity
end

function Relay:bring(seconds)
	local targetCharacter, targetRoot, targetHumanoid = self:_character(self.Controller)
	local character, root, humanoid = self:_character(LocalPlayer)
	if not targetCharacter then return false, "controller character is unavailable" end
	if not character then return false, "local character is unavailable" end
	local manager = character:FindFirstChild("ControllerManager")
	local air = manager and manager:FindFirstChild("AirController")
	if not air then return false, "Deepwoken air controller is unavailable; try after spawning" end
	if root.Anchored then return false, "character is anchored" end

	self:cancelMovement()
	local generation = self.MovementGeneration
	local offset, slot = self:_formationOffset()
	local goal = (targetRoot.CFrame * CFrame.new(offset)).Position
	local distance = (goal - root.Position).Magnitude
	if distance <= 1.2 then
		self.LastMovement = "already at destination"
		log(self.LastMovement)
		return true
	end
	local duration = math.clamp(finiteNumber(seconds) or Config.BringSeconds, 0.25, 600)
	local movement = {
		Character = character, Root = root, Humanoid = humanoid, Manager = manager, Air = air,
		TargetCharacter = targetCharacter, TargetRoot = targetRoot, TargetHumanoid = targetHumanoid,
		Goal = goal, PaceLimit = distance / duration, Velocity = Vector3.zero,
		PreviousPosition = root.Position, BestDistance = distance,
		Started = os.clock(), LastProgress = os.clock(), Properties = {}, PinsReleased = 0,
	}
	self.Movement = movement
	self.MovementActive = true
	local ok, reason = pcall(function()
		local mover = Instance.new("BodyVelocity")
		movement.Mover = mover
		mover.Name = "RollCancel2"
		mover:AddTag("AllowedBM")
		mover:SetAttribute("ClawRelayOwned", true)
		mover.P = 20000
		mover.MaxForce = Vector3.new(1e10, 1e10, 1e10)
		mover.Velocity = Vector3.zero
		mover.Parent = root
		local ready, failure = self:_flightState(movement)
		if not ready then error(failure) end
		root.AssemblyLinearVelocity = Vector3.zero
		movement.Connection = RunService.PreSimulation:Connect(function(dt)
			if generation ~= self.MovementGeneration then return end
			local success, message = pcall(self._stepFlight, self, movement, dt)
			if not success then self:cancelMovement("flight error: " .. tostring(message)) end
		end)
	end)
	if not ok then
		self:cancelMovement("flight setup failed")
		return false, tostring(reason)
	end
	self.LastMovement = "flying"
	log(string.format("bringing slot %d: %.0f studs, max %.0f studs/s, vertical max %.0f",
		slot, distance, math.min(Config.BringSpeed, movement.PaceLimit), Config.BringVerticalSpeed))
	return true
end

function Relay:setPhase(enabled)
	self.PhaseEnabled = enabled == true
	if self.PhaseEnabled then
		self:_applyNoclip()
	elseif not self.MovementActive then
		self:_restoreCollision()
	end
	log("phase " .. (self.PhaseEnabled and "ON" or "OFF"))
end

function Relay:_requests()
	return ReplicatedStorage:FindFirstChild("Requests")
end

function Relay:returnToMenu(reason)
	self:cancelMovement()
	local requests = self:_requests()
	local remote = requests and requests:FindFirstChild("ReturnToMenu")
	if not remote then
		return false, "ReturnToMenu remote is unavailable"
	end

	self.MenuGeneration = self.MenuGeneration + 1
	local generation = self.MenuGeneration
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	task.spawn(function()
		local deadline = os.clock() + 15
		while self.Running and generation == self.MenuGeneration and os.clock() < deadline do
			pcall(function()
				remote:FireServer()
			end)
			local prompt = playerGui and playerGui:FindFirstChild("ChoicePrompt")
			if prompt and prompt:GetAttribute("Title") == "Return to Main Menu" then
				local choice = prompt:FindFirstChild("Choice")
				if choice then
					pcall(function()
						choice:FireServer(true)
					end)
				end
			end
			task.wait(0.25)
		end
		if self.Running and generation == self.MenuGeneration then
			warnRelay("return-to-menu request timed out")
		end
	end)
	log("requesting main menu" .. (reason and (": " .. reason) or ""))
	return true
end

function Relay:_trustedSets()
	local ids = {}
	local names = {}
	for _, value in ipairs(Config.TrustedUserIds) do
		local id = tonumber(value)
		if id and id > 0 then
			ids[math.floor(id)] = true
		end
	end
	for _, value in ipairs(Config.TrustedNames) do
		names[string.lower(tostring(value))] = true
	end
	ids[LocalPlayer.UserId] = true
	if Config.ControllerUserId > 0 then
		ids[Config.ControllerUserId] = true
	elseif Config.ControllerName ~= "" then
		names[string.lower(Config.ControllerName)] = true
	end
	return ids, names
end

function Relay:_isTrusted(player)
	local ids, names = self:_trustedSets()
	return ids[player.UserId] == true or names[string.lower(player.Name)] == true
end

function Relay:_pollSafety()
	if not self.SafetyEnabled or self.SafetyTriggered then
		table.clear(self.UnsafeSince)
		return
	end
	local _, localRoot = self:_character(LocalPlayer)
	if not localRoot then
		table.clear(self.UnsafeSince)
		return
	end

	local now = os.clock()
	local present = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not self:_isTrusted(player) then
			local _, root = self:_character(player)
			if root and (root.Position - localRoot.Position).Magnitude <= Config.ProximityDistance then
				present[player] = true
				self.UnsafeSince[player] = self.UnsafeSince[player] or now
				if now - self.UnsafeSince[player] >= Config.ProximityGraceSeconds then
					self.SafetyTriggered = true
					local ok, reason = self:returnToMenu("untrusted player nearby")
					if not ok then
						self.SafetyTriggered = false
						self.UnsafeSince[player] = now
						warnRelay("proximity log failed: " .. tostring(reason))
					end
					return
				end
			end
		end
	end
	for player in pairs(self.UnsafeSince) do
		if not present[player] then
			self.UnsafeSince[player] = nil
		end
	end
end

function Relay:_status()
	local controller = self.Controller and self.Controller.Name or "waiting"
	local movement = self.Movement
	local remaining = movement and (movement.Goal - movement.Root.Position).Magnitude or 0
	return string.format(
		"v%s controller=%s movement=%s speed=%.0f vertical=%.0f remaining=%.1f phase=%s safety=%s last=%s",
		self.Version,
		controller,
		self.MovementActive and "moving" or "idle",
		Config.BringSpeed,
		Config.BringVerticalSpeed,
		remaining,
		self.PhaseEnabled and "on" or "off",
		self.SafetyEnabled and "on" or "off",
		self.LastMovement
	)
end

function Relay:_executeCommand(commandLine)
	local command, remainder = string.match(commandLine, "^(%S+)%s*(.-)%s*$")
	command = string.lower(command or "")
	if command == "" or command == "help" then
		log("commands: bring [minimum seconds], speed [5-120], stop, phase [on/off], menu, safety [on/off], status")
	elseif command == "bring" or command == "tween" then
		if remainder ~= "" and not finiteNumber(remainder) then
			return warnRelay("usage: bring [minimum seconds]")
		end
		local ok, reason = self:bring(finiteNumber(remainder))
		if not ok then warnRelay(reason) end
	elseif command == "speed" then
		if remainder == "" then return log("bring speed: " .. Config.BringSpeed .. " studs/s") end
		local speed = finiteNumber(remainder)
		if not speed or speed < 5 or speed > 120 then
			return warnRelay("speed must be between 5 and 120 studs/s")
		end
		Config.BringSpeed = speed
		log("bring speed: " .. speed .. " studs/s")
	elseif command == "stop" then
		self:cancelMovement("controller command")
	elseif command == "phase" then
		local mode = string.lower(remainder)
		if mode == "on" then
			self:setPhase(true)
		elseif mode == "off" then
			self:setPhase(false)
		else
			self:setPhase(not self.PhaseEnabled)
		end
	elseif command == "menu" or command == "log" then
		local ok, reason = self:returnToMenu("controller command")
		if not ok then warnRelay(reason) end
	elseif command == "safety" then
		local mode = string.lower(remainder)
		self.SafetyEnabled = mode == "on" or (mode ~= "off" and not self.SafetyEnabled)
		self.SafetyTriggered = false
		table.clear(self.UnsafeSince)
		log("proximity safety " .. (self.SafetyEnabled and "ON" or "OFF"))
	elseif command == "status" then
		log(self:_status())
	elseif command ~= "" then
		warnRelay("unknown command: " .. command)
	end
end

function Relay:_onChat(message)
	message = tostring(message or ""):match("^%s*(.-)%s*$")
	local prefix = Config.CommandPrefix
	if string.lower(string.sub(message, 1, #prefix)) ~= string.lower(prefix) then
		return
	end
	local nextCharacter = string.sub(message, #prefix + 1, #prefix + 1)
	if nextCharacter ~= "" and not string.match(nextCharacter, "%s") then
		return
	end
	self:_executeCommand(string.sub(message, #prefix + 1):match("^%s*(.-)%s*$"))
end

function Relay:_bindController(player)
	if not isController(player) or self.Controller == player then
		return
	end
	if self.ControllerChat then
		self.ControllerChat:Disconnect()
	end
	self.Controller = player
	self.ControllerChat = player.Chatted:Connect(function(message)
		self:_onChat(message)
	end)
	log("controller connected: " .. player.Name)
end

function Relay:_autoStart()
	if Config.AutoStart ~= true or LocalPlayer.Character then
		return
	end
	task.spawn(function()
		for _ = 1, Config.AutoStartAttempts do
			if not self.Running or LocalPlayer.Character then
				return
			end
			local requests = self:_requests()
			local startMenu = requests and requests:FindFirstChild("StartMenu")
			local start = startMenu and startMenu:FindFirstChild("Start")
			if start then
				pcall(function()
					start:FireServer()
				end)
			end
			task.wait(1)
		end
		if not LocalPlayer.Character then
			warnRelay("auto-start timed out")
		end
	end)
end

function Relay:Destroy(reason)
	if not self.Running then
		return
	end
	self.Running = false
	self.MenuGeneration = self.MenuGeneration + 1
	self:cancelMovement()
	self.PhaseEnabled = false
	self:_restoreCollision()
	if self.ControllerChat then
		self.ControllerChat:Disconnect()
		self.ControllerChat = nil
	end
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	if rawget(environment, "CLAW_RELAY") == self then
		environment.CLAW_RELAY = nil
	end
	log("stopped" .. (reason and (": " .. tostring(reason)) or ""))
end

environment.CLAW_RELAY = Relay

for _, player in ipairs(Players:GetPlayers()) do
	Relay:_bindController(player)
end
Relay:_connect(Players.PlayerAdded, function(player)
	Relay:_bindController(player)
end)
Relay:_connect(Players.PlayerRemoving, function(player)
	if player == Relay.Controller then
		Relay.Controller = nil
		if Relay.ControllerChat then
			Relay.ControllerChat:Disconnect()
			Relay.ControllerChat = nil
		end
		Relay:cancelMovement("controller left")
		warnRelay("controller left the server")
	end
end)
Relay:_connect(LocalPlayer.CharacterAdded, function()
	Relay.SafetyTriggered = false
	table.clear(Relay.UnsafeSince)
	if Relay.PhaseEnabled then
		task.defer(function()
			Relay:_applyNoclip()
		end)
	end
end)
Relay:_connect(LocalPlayer.CharacterRemoving, function()
	Relay:cancelMovement("respawning")
end)
Relay:_connect(RunService.Stepped, function()
	if Relay.PhaseEnabled and not Relay.MovementActive then
		Relay:_applyNoclip()
	end
end)

task.spawn(function()
	while Relay.Running do
		Relay:_pollSafety()
		task.wait(Config.ProximityPollSeconds)
	end
end)

Relay:_autoStart()
log(Relay.Name .. " v" .. Relay.Version .. " ready; controller=" .. (Config.ControllerName ~= "" and Config.ControllerName or tostring(Config.ControllerUserId)))
log("type " .. Config.CommandPrefix .. " help from the controller account")

return Relay
