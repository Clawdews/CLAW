return function(source)
	local function signal()
		local listeners, value = {}, {}
		function value:Connect(callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			listeners[#listeners + 1] = { connection, callback }
			return connection
		end
		function value:Fire(...)
			for _, pair in ipairs(listeners) do if pair[1].Connected then pair[2](...) end end
		end
		return value
	end

	local vectorMeta = {}
	function vectorMeta.__index(value, key)
		if key == "Magnitude" then return math.sqrt(value.X * value.X + value.Y * value.Y + value.Z * value.Z) end
		if key == "Unit" then
			local length = vectorMeta.__index(value, "Magnitude")
			return length > 0 and setmetatable({ X = value.X / length, Y = value.Y / length, Z = value.Z / length }, vectorMeta)
				or setmetatable({ X = 0, Y = 0, Z = 0 }, vectorMeta)
		end
	end
	function vectorMeta.__add(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, vectorMeta) end
	function vectorMeta.__sub(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vectorMeta) end
	function vectorMeta.__mul(a, b)
		if type(a) == "number" then a, b = b, a end
		return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, vectorMeta)
	end
	local Vector3 = { new = function(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMeta) end }
	Vector3.zero = Vector3.new(0, 0, 0)
	local cframeMeta = {}
	function cframeMeta.__mul(a, b) return setmetatable({ Position = a.Position + b.Position }, cframeMeta) end
	local CFrame = { new = function(value) return setmetatable({ Position = value }, cframeMeta) end }

	local function node(class, name)
		local object = { ClassName = class, Name = name, children = {}, DescendantAdded = signal() }
		function object:IsA(expected) return self.ClassName == expected or expected == "BasePart" and self.basePart == true end
		function object:FindFirstChild(childName) return self.children[childName] end
		function object:FindFirstChildOfClass(expected)
			for _, child in pairs(self.children) do if child.ClassName == expected then return child end end
		end
		function object:GetDescendants()
			local found = {}
			local function visit(parent)
				for _, child in pairs(parent.children or {}) do found[#found + 1] = child; visit(child) end
			end
			visit(self); return found
		end
		function object:Add(child)
			self.children[child.Name] = child; child.Parent = self; self.DescendantAdded:Fire(child); return child
		end
		return object
	end
	local function character(position)
		local model = node("Model", "Character")
		local root = node("Part", "HumanoidRootPart"); root.basePart = true; root.Position = position
		root.CFrame = setmetatable({ Position = position }, cframeMeta); root.Anchored = false; root.CanCollide = true
		root.AssemblyLinearVelocity = Vector3.zero
		local humanoid = node("Humanoid", "Humanoid"); humanoid.Health = 100
		local manager = node("ControllerManager", "ControllerManager")
		local ground = node("GroundController", "GroundController")
		local air = node("AirController", "AirController"); manager.ActiveController = ground
		manager:Add(air)
		local sensor = node("ControllerPartSensor", "GroundSensor"); sensor.SearchDistance = 6; manager:Add(sensor)
		local helio = node("BodyVelocity", "HelioFlight"); helio.MaxForce = Vector3.new(5, 5, 5); root:Add(helio)
		local head = node("Part", "Head"); head.basePart = true; head.CanCollide = true
		local pin = node("BodyPosition", "BodyPosition"); pin.MaxForce = Vector3.new(9, 9, 9); pin.destroyed = false
		function pin:Destroy() self.destroyed = true; self.Parent = nil end
		head:Add(pin)
		local torso = node("Part", "Torso"); torso.basePart = true; torso.CanCollide = true
		model:Add(root); model:Add(humanoid); model:Add(manager); model:Add(head); model:Add(torso)
		return model, root, manager, ground, air, sensor, helio, head, pin, torso
	end

	local localModel, localRoot, manager, ground, air, sensor, helio, _, pin, torso = character(Vector3.new(0, 0, 0))
	local mainModel = character(Vector3.new(100, 10, 0))
	local localPlayer = { UserId = 22, Character = localModel }
	local mainPlayer = { UserId = 11, Character = mainModel }
	local players = { LocalPlayer = localPlayer }
	function players:GetPlayerByUserId(userId) return userId == 11 and mainPlayer or nil end
	local run = { PreSimulation = signal() }
	local created = {}
	local Instance = {}
	function Instance.new(class)
		local object = node(class, class); object.destroyed = false
		function object:AddTag() end
		function object:SetAttribute() end
		function object:Destroy() self.destroyed = true; self.Parent = nil end
		created[#created + 1] = object; return object
	end
	local game = { PlaceId = 6032399813, JobId = "server" }
	function game:GetService(name)
		return assert(({ Players = players, RunService = run })[name], name)
	end
	local environment = setmetatable({ game = game, Vector3 = Vector3, CFrame = CFrame, Instance = Instance }, { __index = getfenv() })
	local chunk = assert(loadstring(source, "movement")); setfenv(chunk, environment)
	local Movement = chunk()

	local states = {}
	local movement = Movement.new(function(state) states[#states + 1] = state end)
	local ok, reason = movement:bring("11", { x = 0, y = 2, z = -6 })
	assert(ok and reason == "movement started" and movement.state == "moving to main")
	assert(manager.ActiveController == air and sensor.SearchDistance == 0 and torso.CanCollide == false)
	assert(pin.destroyed == false and pin.MaxForce.X == 0 and helio.MaxForce.X == 0)
	local mover = created[#created]; assert(mover.Parent == localRoot and mover.destroyed == false)
	run.PreSimulation:Fire(0.1)
	assert(mover.Velocity.Magnitude > 0 and localRoot.AssemblyLinearVelocity.Magnitude > 0)
	local added = node("Part", "NewPart"); added.basePart = true; added.CanCollide = true; localModel:Add(added)
	assert(added.CanCollide == false)
	movement:stop("manual stop")
	assert(movement.state == "manual stop" and mover.destroyed == true and manager.ActiveController == ground)
	assert(sensor.SearchDistance == 6 and torso.CanCollide == true and added.CanCollide == true)
	assert(pin.destroyed == false and pin.MaxForce.X == 9 and helio.MaxForce.X == 5)
	assert(localRoot.AssemblyLinearVelocity.Magnitude == 0)

	ok, reason = movement:bring("99", { x = 0, y = 0, z = 0 })
	assert(ok == false and reason == "main character unavailable")
	ok, reason = movement:park({ x = 1, y = 2, z = 3 }, game.PlaceId, "another-server")
	assert(ok == false and reason == "saved spot is in another server")
	movement:destroy(); assert(movement.running == false)
	print("PASS movement restores game state, stops cleanly and rejects invalid destinations")
end
