local HitboxVisualizer = {}
HitboxVisualizer.__index = HitboxVisualizer

local MAX_POOL = 16

function HitboxVisualizer.new(settings, state)
	local self = setmetatable({
		Settings = settings,
		State = state,
		Folder = nil,
		Pool = {},
		Active = {},
		Serial = 0,
	}, HitboxVisualizer)
	self.Connection = state.Event:Connect(function(event)
		if event.kind == "defense-profile" then
			self:show(event.payload)
		end
	end)
	return self
end

function HitboxVisualizer:_folder()
	if self.Folder and self.Folder.Parent then
		return self.Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "_CLAW_MARK_Hitboxes"
	folder.Parent = workspace
	self.Folder = folder
	return folder
end

function HitboxVisualizer:_acquire()
	local part = table.remove(self.Pool)
	if part then
		return part
	end
	part = Instance.new("Part")
	part.Name = "CLAW_MARK_Hitbox"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(235, 78, 119)
	part.Transparency = 0.72
	return part
end

function HitboxVisualizer:_release(part, serial)
	if self.Active[part] ~= serial then
		return
	end
	self.Active[part] = nil
	part.Parent = nil
	if #self.Pool < MAX_POOL then
		self.Pool[#self.Pool + 1] = part
	else
		part:Destroy()
	end
end

function HitboxVisualizer:show(payload)
	if not self.Settings:get("Diagnostics.VisualizeHitboxes") then
		return
	end
	local event = payload and payload.event
	local profile = payload and payload.profile
	if not event or not profile or profile.hitbox.Magnitude <= 0 then
		return
	end
	local source
	if event.root and event.root.Parent then
		source = event.root.CFrame
	elseif event.instance and event.instance:IsA("BasePart") then
		source = event.instance.CFrame
	end
	if not source then
		return
	end

	local part = self:_acquire()
	self.Serial = self.Serial + 1
	local serial = self.Serial
	self.Active[part] = serial
	part.Size = Vector3.new(
		math.max(0.05, profile.hitbox.X),
		math.max(0.05, profile.hitbox.Y),
		math.max(0.05, profile.hitbox.Z)
	)
	part.CFrame = source * CFrame.new(0, 0, -profile.hitboxOffset)
	part.Parent = self:_folder()
	task.delay(0.15, function()
		self:_release(part, serial)
	end)
end

function HitboxVisualizer:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	for part in pairs(self.Active) do
		part:Destroy()
	end
	for _, part in ipairs(self.Pool) do
		part:Destroy()
	end
	table.clear(self.Active)
	table.clear(self.Pool)
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
end

return HitboxVisualizer
