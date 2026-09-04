-- Short-lived movement used only by authenticated CLAW actions.
local Movement = {}
Movement.__index = Movement

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	if type(value) ~= "table" or not finite(value.x) or not finite(value.y) or not finite(value.z) then return nil end
	if math.abs(value.x) > 1e7 or math.abs(value.y) > 1e7 or math.abs(value.z) > 1e7 then return nil end
	return Vector3.new(value.x, value.y, value.z)
end
local function character(player)
	local model = player and player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not root or not humanoid or humanoid.Health <= 0 then return nil end
	return model, root, humanoid
end
local function braking(distance, limit, acceleration, dt)
	local step = acceleration * dt
	return math.min(limit, math.sqrt(step * step + 2 * acceleration * math.max(0, distance - 0.25)) - step)
end
local function property(active, object, key, value)
	active.properties[object] = active.properties[object] or {}
	if active.properties[object][key] == nil then active.properties[object][key] = { value = object[key] } end
	object[key] = value
end

function Movement.new(changed)
	return setmetatable({ running = true, active = nil, generation = 0, state = "idle", changed = changed }, Movement)
end
function Movement:_state(value)
	if self.state == value then return end
	self.state = value
	if self.changed then pcall(self.changed, value) end
end
function Movement:_restore(active)
	for part, canCollide in pairs(active and active.collisions or {}) do
		if part and part.Parent then pcall(function() part.CanCollide = canCollide end) end
	end
	for object, properties in pairs(active and active.properties or {}) do
		for key, value in pairs(properties) do
			if object and object.Parent then pcall(function() object[key] = value.value end) end
		end
	end
	if active and active.root and active.root.Parent then
		pcall(function() active.root.AssemblyLinearVelocity = Vector3.zero end)
	end
end
function Movement:stop(reason)
	self.generation += 1
	local active = self.active
	self.active = nil
	if active then
		if active.connection then active.connection:Disconnect() end
		if active.descendantConnection then active.descendantConnection:Disconnect() end
		if active.mover then active.mover:Destroy() end
		self:_restore(active)
	end
	self:_state(reason or "idle")
	return true
end
function Movement:_noclip(active)
	for _, item in ipairs(active.model:GetDescendants()) do
		if item:IsA("BasePart") then
			if active.collisions[item] == nil then active.collisions[item] = item.CanCollide end
			item.CanCollide = false
		end
	end
end
function Movement:_flight(active)
	property(active, active.manager, "ActiveController", active.air)
	for _, parent in ipairs({ active.root, active.manager }) do
		local sensor = parent:FindFirstChild("GroundSensor")
		if sensor and sensor:IsA("ControllerPartSensor") then property(active, sensor, "SearchDistance", 0) end
	end
	local helio = active.root:FindFirstChild("HelioFlight")
	if helio and helio:IsA("BodyVelocity") then property(active, helio, "MaxForce", Vector3.zero) end
	self:_noclip(active)
	local head = active.model:FindFirstChild("Head")
	local pin = head and head:FindFirstChild("BodyPosition")
	if pin and pin:IsA("BodyPosition") then property(active, pin, "MaxForce", Vector3.zero) end
end
function Movement:_start(provider, label)
	local model, root, humanoid = character(LocalPlayer)
	if not model then return false, "local character unavailable" end
	local manager = model:FindFirstChild("ControllerManager")
	local air = manager and manager:FindFirstChild("AirController")
	if not air then return false, "air controller unavailable" end
	if root.Anchored then return false, "character is anchored" end
	local goal, failure = provider()
	if not goal then return false, failure or "destination unavailable" end
	self:stop()
	local generation = self.generation
	local active = { model = model, root = root, humanoid = humanoid, manager = manager, air = air,
		provider = provider, label = label, velocity = Vector3.zero, started = os.clock(), progress = os.clock(),
		best = (goal - root.Position).Magnitude, collisions = {}, properties = {} }
	local mover = Instance.new("BodyVelocity")
	active.mover = mover
	mover.Name = "ClawCloudMovement"
	pcall(function() mover:AddTag("AllowedBM") end)
	mover:SetAttribute("ClawOwned", true)
	mover.P = 20000
	mover.MaxForce = Vector3.new(1e10, 1e10, 1e10)
	mover.Velocity = Vector3.zero
	mover.Parent = root
	local ok = pcall(self._flight, self, active)
	if not ok then mover:Destroy(); self:_restore(active); return false, "movement setup failed" end
	if model.DescendantAdded then
		active.descendantConnection = model.DescendantAdded:Connect(function(item)
			if self.active == active and item:IsA("BasePart") then
				if active.collisions[item] == nil then active.collisions[item] = item.CanCollide end
				item.CanCollide = false
			end
		end)
	end
	self.active = active
	self:_state("moving " .. label)
	active.connection = RunService.PreSimulation:Connect(function(dt)
		if not self.running or generation ~= self.generation or self.active ~= active then return end
		local success = pcall(function()
			if LocalPlayer.Character ~= model or humanoid.Health <= 0 or not root.Parent or root.Anchored then
				return self:stop("movement interrupted")
			end
			if os.clock() - active.started > 300 then return self:stop("movement timed out") end
			local target, reason = provider()
			if not target then return self:stop(reason or "destination lost") end
			local delta, distance = target - root.Position, (target - root.Position).Magnitude
			if distance <= 1.2 and active.velocity.Magnitude <= 4 then return self:stop("arrived " .. label) end
			if distance < active.best - 0.25 then active.best, active.progress = distance, os.clock()
			elseif os.clock() - active.progress > 6 then return self:stop("movement made no progress") end
			manager.ActiveController = air
			dt = math.clamp(tonumber(dt) or 0, 0, 0.1)
			local acceleration, horizontalLimit, verticalLimit = 80, 200, 24
			local horizontal = Vector3.new(delta.X, 0, delta.Z)
			local speed = braking(horizontal.Magnitude, horizontalLimit, acceleration, dt)
			local wanted = horizontal.Magnitude > 0.001 and horizontal.Unit * speed or Vector3.zero
			local current = Vector3.new(active.velocity.X, 0, active.velocity.Z)
			local change, maximum = wanted - current, acceleration * dt
			if change.Magnitude > maximum then change = change.Unit * maximum end
			current += change
			local wantedY = math.sign(delta.Y) * braking(math.abs(delta.Y), verticalLimit, acceleration, dt)
			local nextY = active.velocity.Y + math.clamp(wantedY - active.velocity.Y, -maximum, maximum)
			active.velocity = Vector3.new(current.X, nextY, current.Z)
			mover.Velocity = active.velocity
			root.AssemblyLinearVelocity = active.velocity
		end)
		if not success then self:stop("movement error") end
	end)
	return true, "movement started"
end
function Movement:bring(mainId, offset)
	mainId = tonumber(mainId)
	offset = vector(offset or { x = 0, y = 0, z = 0 })
	if not mainId or not offset then return false, "invalid bring target" end
	return self:_start(function()
		local target = Players:GetPlayerByUserId(mainId)
		local _, root = character(target)
		if not root then return nil, "main character unavailable" end
		return (root.CFrame * CFrame.new(offset)).Position
	end, "to main")
end
function Movement:park(position, placeId, jobId)
	local goal = vector(position)
	if not goal or placeId ~= game.PlaceId or jobId ~= game.JobId then return false, "saved spot is in another server" end
	return self:_start(function() return goal end, "to park")
end
function Movement:destroy()
	self.running = false
	self:stop("stopped")
end
return Movement
