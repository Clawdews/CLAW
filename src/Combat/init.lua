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

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
		_connections = {},
		_lifetimeConnections = {},
		_lastScan = 0,
	}, Combat)

	self.Targeting = Targeting.new(settings, options.targeting)
	self.Scheduler = Scheduler.new(state)
	self.Input = InputAdapter.new(options.input)
	self.Executor = ActionExecutor.new(settings, state, self.Input)
	self.Resolver = TimingResolver.new(settings)
	local detectorOptions = options.detectors or {
		shared = {
			ignoreTrack = function(track)
				local animationLab = environment.__ANIM_LAB_V6
				return animationLab
					and animationLab.OwnGhostTracks
					and animationLab.OwnGhostTracks[track] == true
			end,
		},
	}
	self.Detectors = DetectorHub.new(settings, detectorOptions)
	self.Defense = DefenseEngine.new(
		settings,
		state,
		self.Timings,
		self.Scheduler,
		self.Executor,
		self.Resolver
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
		self.History:record(
			target.Character,
			target.Root.CFrame,
			target.Root.AssemblyLinearVelocity
		)
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
	if now - self._lastScan < self.Settings:get("Targeting.ScanInterval") then
		return
	end
	self._lastScan = now

	local candidates = self.Targeting:scan(character)
	self:_recordTargets(candidates)
	self.State:setTargets(self.Targeting:select(candidates))
end

function Combat:start()
	if self.State.Running or self.State.Destroyed then
		return false
	end

	self.State:set("Running", true)
	self.State:setCharacter(Players.LocalPlayer.Character)
	self.Detectors:start()
	self:_bind(RunService.Heartbeat, function()
		self:_step()
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
	self.Scheduler:cancelAll("combat stopped")
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
	if persist ~= false then
		self:save()
	end
	self.State:emit("setting", { path = path, value = value })
	return result
end

function Combat:save()
	return self.Persistence:save(self.Settings:serialize())
end

function Combat:Destroy()
	self:stop()
	for _, connection in ipairs(self._lifetimeConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._lifetimeConnections)
	self.Detectors:Destroy()
	self.Scheduler:Destroy()
	self.History:clear()
	self.State:Destroy()
end

return Combat
