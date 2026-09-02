local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES

local Settings = assert(modules["src/Combat/Settings.lua"])
local Persistence = assert(modules["src/Combat/Persistence.lua"])
local State = assert(modules["src/Combat/State.lua"])
local EntityHistory = assert(modules["src/Combat/EntityHistory.lua"])
local Targeting = assert(modules["src/Combat/Targeting.lua"])
local TimingStore = assert(modules["src/Combat/TimingStore.lua"])
local Scheduler = assert(modules["src/Combat/Scheduler.lua"])
local DetectorHub = assert(modules["src/Combat/Detection/DetectorHub.lua"])
local InputAdapter = assert(modules["src/Combat/InputAdapter.lua"])
local ActionExecutor = assert(modules["src/Combat/ActionExecutor.lua"])
local TimingResolver = assert(modules["src/Combat/TimingResolver.lua"])
local DefenseEngine = assert(modules["src/Combat/DefenseEngine.lua"])
local Performance = assert(modules["src/Combat/Performance.lua"])
local ValidationEngine = assert(modules["src/Combat/ValidationEngine.lua"])
local ProbabilityResolver = assert(modules["src/Combat/ProbabilityResolver.lua"])
local FallbackResolver = assert(modules["src/Combat/FallbackResolver.lua"])
local Diagnostics = assert(modules["src/Combat/Diagnostics.lua"])
local StateMonitor = assert(modules["src/Combat/StateMonitor.lua"])
local PresetManager = assert(modules["src/Combat/PresetManager.lua"])
local TimingPersistence = assert(modules["src/Combat/TimingPersistence.lua"])
local AssistanceEngine = assert(modules["src/Combat/AssistanceEngine.lua"])
local HitboxVisualizer = assert(modules["src/Combat/HitboxVisualizer.lua"])
local HitboxWaiter = assert(modules["src/Combat/HitboxWaiter.lua"])

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Combat = {}
Combat.__index = Combat

function Combat.new(options)
	options = options or {}
	local persistence = Persistence.new(options.settingsPath)
	local savedSettings = persistence:load()
	local settings = Settings.new(savedSettings)
	local state = State.new()
	local history = EntityHistory.new(settings:get("Validation.HistorySeconds"))

	local self = setmetatable({
		Settings = settings,
		Persistence = persistence,
		State = state,
		History = history,
		Timings = TimingStore.new(),
		Targeting = nil,
		Scheduler = nil,
		Detectors = nil,
		Input = nil,
		Executor = nil,
		Resolver = nil,
		Defense = nil,
		Performance = nil,
		Validator = nil,
		Probability = nil,
		Fallbacks = nil,
		Diagnostics = nil,
		Monitor = nil,
		Presets = nil,
		TimingIO = nil,
		Assistance = nil,
		Hitboxes = nil,
		HitboxWaiter = nil,
		_connections = {},
		_lifetimeConnections = {},
		_lastScan = 0,
		_saveToken = 0,
	}, Combat)

	self.Targeting = Targeting.new(settings, options.targeting)
	self.Scheduler = Scheduler.new(state)
	local inputOptions = {
		custom = options.input and options.input.custom or nil,
		settings = settings,
	}
	self.Input = InputAdapter.new(inputOptions)
	self.Executor = ActionExecutor.new(settings, state, self.Input)
	self.Resolver = TimingResolver.new(settings)
	self.Performance = Performance.new(settings)
	self.Validator = ValidationEngine.new(settings, state, history, self.Executor)
	self.Probability = ProbabilityResolver.new(settings)
	self.Fallbacks = FallbackResolver.new(settings)
	self.Diagnostics = Diagnostics.new(settings, state, self.Performance)
	self.Hitboxes = HitboxVisualizer.new(settings, state)
	self.HitboxWaiter = HitboxWaiter.new(settings)
	self.Monitor = StateMonitor.new(state)
	self.Presets = PresetManager.new(settings)
	self.TimingIO = TimingPersistence.new(self.Timings, options.timingsPath)
	self.TimingIO:load()
	self.Assistance = AssistanceEngine.new(settings, state, self.Timings, self.Scheduler, self.Input, self.Executor)
	local detectorOptions = options.detectors
		or {
			shared = {
				ignoreTrack = function(track)
					local clawMark = environment.__CLAW_MARK or environment.__ANIM_LAB_V6
					return clawMark and clawMark.OwnGhostTracks and clawMark.OwnGhostTracks[track] == true
				end,
			},
		}
	self.Detectors = DetectorHub.new(settings, self.Timings, detectorOptions)
	self.Defense = DefenseEngine.new(
		settings,
		state,
		self.Timings,
		self.Scheduler,
		self.Executor,
		self.Resolver,
		self.Validator,
		self.Probability,
		self.Fallbacks,
		self.HitboxWaiter
	)
	self._lifetimeConnections[#self._lifetimeConnections + 1] = self.Detectors.Detected:Connect(function(event)
		self.Defense:handle(event)
	end)
	return self
end

function Combat:_bind(signal, callback)
	local connection = signal:Connect(callback)
	self._connections[#self._connections + 1] = connection
	return connection
end

function Combat:_recordTargets(candidates)
	for _, target in ipairs(candidates) do
		self.History:record(target.Character, target.Root.CFrame, target.Root.AssemblyLinearVelocity)
	end
end

function Combat:_step()
	if not self.State.Running or not self.Settings:get("Enabled") then
		return
	end

	local character = Players.LocalPlayer.Character
	if character ~= self.State.Character then
		self.State:setCharacter(character)
	end

	local now = os.clock()
	local scanInterval = self.Performance:scanInterval(self.Settings:get("Targeting.ScanInterval"))
	if now - self._lastScan < scanInterval then
		return
	end
	self._lastScan = now

	self.Performance:measure("target-scan", function()
		local candidates = self.Targeting:scan(character)
		self:_recordTargets(candidates)
		if self.State.Root then
			self.History:record(self.State.Character, self.State.Root.CFrame, self.State.Root.AssemblyLinearVelocity)
		end
		self.State:setTargets(self.Targeting:select(candidates))
	end)
end

function Combat:start()
	if self.State.Running or self.State.Destroyed then
		return false
	end

	self.State:set("Running", true)
	self.State:setCharacter(Players.LocalPlayer.Character)
	self.Monitor:start()
	self.Assistance:start()
	self.Detectors:start()
	self:_bind(RunService.Heartbeat, function()
		self:_step()
	end)
	self:_bind(UserInputService.InputBegan, function(input, processed)
		if processed or input.KeyCode == Enum.KeyCode.Unknown then
			return
		end
		local binding = self.Settings:get("Bindings.ToggleDefense")
		if
			type(binding) == "string"
			and binding ~= ""
			and string.lower(input.KeyCode.Name) == string.lower(binding)
		then
			self:set("Defense.Enabled", not self.Settings:get("Defense.Enabled"))
		end
	end)
	self.State:emit("started")
	return true
end

function Combat:stop()
	if not self.State.Running then
		return false
	end

	self.State:set("Running", false)
	self.Detectors:stop()
	self.Assistance:stop()
	self.Monitor:stop()
	self.Scheduler:cancelAll("combat stopped")
	self.Defense:reset()
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	self.State:resetRuntime()
	self.State:emit("stopped")
	return true
end

function Combat:set(path, value, persist)
	local result = self.Settings:set(path, value)
	if path == "Validation.HistorySeconds" then
		self.History:setWindow(value)
	end
	if path == "Detection.OnlyConfigured" or path == "Detection.Sounds" then
		self.Detectors:refresh()
	end
	if persist ~= false then
		self:queueSave()
	end
	self.State:emit("setting", { path = path, value = value })
	return result
end

function Combat:queueSave(delaySeconds)
	self._saveToken = self._saveToken + 1
	local token = self._saveToken
	task.delay(delaySeconds or 0.35, function()
		if token == self._saveToken and not self.State.Destroyed then
			self:save()
		end
	end)
end

function Combat:save()
	return self.Persistence:save(self.Settings:serialize())
end

function Combat:applyPreset(name)
	local ok, reason = self.Presets:apply(name)
	if ok then
		self.History:setWindow(self.Settings:get("Validation.HistorySeconds"))
		self.Detectors:refresh()
		self:save()
		self.State:emit("preset", name)
	end
	return ok, reason
end

function Combat:registerTiming(values, persist)
	local profile = self.Timings:register(values, true)
	if persist ~= false then
		self.TimingIO:save()
	end
	return profile
end

function Combat:removeTiming(category, id, persist)
	self.Timings:remove(category, id)
	if persist ~= false then
		self.TimingIO:save()
	end
end

function Combat:importTimings(encoded)
	local ok, reason = self.TimingIO:import(encoded)
	if ok then
		self.TimingIO:save()
	end
	return ok, reason
end

function Combat:exportTimings(copyToClipboard)
	if copyToClipboard then
		return self.TimingIO:copy()
	end
	return self.TimingIO:export()
end

function Combat:Destroy()
	self._saveToken = self._saveToken + 1
	self:save()
	self:stop()
	for _, connection in ipairs(self._lifetimeConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._lifetimeConnections)
	self.Detectors:Destroy()
	self.Assistance:Destroy()
	self.Monitor:Destroy()
	self.Diagnostics:Destroy()
	self.Hitboxes:Destroy()
	self.HitboxWaiter:Destroy()
	self.Timings:Destroy()
	self.Scheduler:Destroy()
	self.History:clear()
	self.State:Destroy()
end

return Combat
