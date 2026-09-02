local environment = getgenv and getgenv() or _G
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])

local State = {}
State.__index = State

function State.new()
	local self = setmetatable({}, State)
	self.Running = false
	self.Destroyed = false
	self.Character = nil
	self.Root = nil
	self.Humanoid = nil
	self.Targets = {}
	self.PrimaryTarget = nil
	self.ActiveTasks = {}
	self.Cooldowns = {}
	self.Flags = {}
	self.LastEvent = nil
	self.LastDetection = nil
	self.LastReject = nil
	self.LastPlan = nil
	self.LastActionResult = nil
	self.LastFailure = nil
	self.Metrics = {
		Detected = 0,
		Scheduled = 0,
		Executed = 0,
		Failed = 0,
		Cancelled = 0,
		Rejected = 0,
	}
	self.Changed = Signal.new()
	self.Event = Signal.new()
	return self
end

function State:set(key, value)
	local previous = self[key]
	if previous == value then
		return value
	end

	self[key] = value
	self.Changed:Fire(key, value, previous)
	return value
end

function State:setCharacter(character)
	self.Character = character
	self.Root = character and character:FindFirstChild("HumanoidRootPart") or nil
	self.Humanoid = character and character:FindFirstChildWhichIsA("Humanoid") or nil
	self.Changed:Fire("Character", character)
end

function State:setTargets(targets)
	self.Targets = targets or {}
	self.PrimaryTarget = self.Targets[1]
	self.Changed:Fire("Targets", self.Targets)
end

function State:emit(kind, payload)
	self.LastEvent = {
		kind = kind,
		payload = payload,
		at = os.clock(),
	}
	self.Event:Fire(self.LastEvent)
end

function State:increment(metric, amount)
	self.Metrics[metric] = (self.Metrics[metric] or 0) + (amount or 1)
end

function State:resetRuntime()
	self:setTargets({})
	table.clear(self.ActiveTasks)
	table.clear(self.Cooldowns)
	table.clear(self.Flags)
	self.LastEvent = nil
	self.LastDetection = nil
	self.LastReject = nil
	self.LastPlan = nil
	self.LastActionResult = nil
	self.LastFailure = nil
end

function State:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	self.Running = false
	self:resetRuntime()
	self.Changed:Destroy()
	self.Event:Destroy()
end

return State
