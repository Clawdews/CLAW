-- Experimental transport check only. Never dispatches movement or other alt commands.
local environment = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local localPlayer = assert(Players.LocalPlayer, "Wait until the local player has loaded")
local supplied = environment.CLAW_ANIMATION_PROBE_CONFIG or {}
local relayConfig = environment.CLAW_RELAY_CONFIG or {}
local sender = supplied.Role == "sender"
local controllerId = tonumber(supplied.ControllerUserId or relayConfig.ControllerUserId) or 0
local controllerName = tostring(supplied.ControllerName or relayConfig.ControllerName or "")

-- This full URL is an interpretation of Uni's shorthand, NOT a verified transport.
local template = supplied.AnimationIdTemplate or "http://www.roblox.com/asset/?id=0%s"
assert(type(template) == "string" and #template <= 256, "AnimationIdTemplate must be a short string")
local _, placeholders = template:gsub("%%s", "")
assert(placeholders == 1 and not template:gsub("%%s", ""):find("%%"), "Template needs exactly one %s placeholder")
assert(sender or controllerId > 0 or controllerName ~= "", "Receiver needs the main's ControllerName or ControllerUserId")

local function matches(player)
	if sender then return player == localPlayer end
	if controllerId > 0 then return player.UserId == controllerId end
	return player.Name:lower() == controllerName:lower()
end
assert(sender or not matches(localPlayer), "Run the receiver on an alt, not the main")

local previous = environment.CLAW_ANIMATION_PROBE
if previous and type(previous.Destroy) == "function" then previous:Destroy() end

local Probe = {
	Running = true, Sender = sender, Connections = {}, PlayerConnections = {}, CharacterConnections = {},
	Observed = 0, Received = 0, Sent = 0, LocalEcho = 0, Seen = {},
	LastId = "none", Result = "waiting for controller animator", LastSent = -math.huge,
}
environment.CLAW_ANIMATION_PROBE = Probe

local function disconnect(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

function Probe:Status()
	local role = self.Sender and "SENDER" or "RECEIVER"
	return string.format("%s | seen %d | remote pings %d | local echoes %d\n%s\nLast ID: %s",
		role, self.Observed, self.Received, self.LocalEcho, self.Result, self.LastId)
end

function Probe:_refresh()
	if self.Label then self.Label.Text = self:Status() end
end

function Probe:_observe(track)
	if not self.Running then return end
	self.Observed += 1
	local ok, id = pcall(function() return tostring(track.Animation.AnimationId) end)
	self.LastId = ok and id:sub(1, 180) or "unreadable animation ID"
	if ok then
		local token = id:match("CLAWRELAY_PING_(%x+)")
		if token and #token == 32 and not self.Seen[token] and self.Received + self.LocalEcho < 5 then
			self.Seen[token] = true
			if self.Sender then
				self.LocalEcho += 1
				self.Result = "local echo only; check the alt for delivery"
			else
				self.Received += 1
				self.Result = "RECEIVED PING " .. token:sub(1, 8)
				print("[CLAW PROBE] " .. self.Result .. " from " .. self.Controller.Name)
			end
		end
	end
	self:_refresh()
end

function Probe:_bindAnimator(character)
	if not self.Running or not self.Controller or self.Controller.Character ~= character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator == self.Animator then return end
	if self.AnimationConnection then self.AnimationConnection:Disconnect() end
	self.AnimationConnection = nil
	self.Animator = animator
	if animator then
		self.AnimationConnection = animator.AnimationPlayed:Connect(function(track) self:_observe(track) end)
		self.Result = self.Sender and "ready; send one test ping" or "listening to main; no commands will run"
	end
	self:_refresh()
end

function Probe:_bindCharacter(character)
	disconnect(self.CharacterConnections)
	self:_clearTrack()
	if self.AnimationConnection then self.AnimationConnection:Disconnect() end
	self.AnimationConnection = nil
	self.Animator = nil
	self.Result = "waiting for controller animator"
	if character then
		self.CharacterConnections[#self.CharacterConnections + 1] = character.DescendantAdded:Connect(function(child)
			if child:IsA("Animator") or child:IsA("Humanoid") then self:_bindAnimator(character) end
		end)
		self.CharacterConnections[#self.CharacterConnections + 1] = character.DescendantRemoving:Connect(function(child)
			if child == self.Animator then
				if self.AnimationConnection then self.AnimationConnection:Disconnect() end
				self.AnimationConnection = nil
				self.Animator = nil
				self.Result = "controller animator removed; waiting"
				self:_refresh()
			end
		end)
		self:_bindAnimator(character)
	end
	self:_refresh()
end

function Probe:_bindPlayer(player)
	if not matches(player) or self.Controller == player then return end
	disconnect(self.PlayerConnections)
	self.Controller = player
	self.PlayerConnections[#self.PlayerConnections + 1] = player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end)
	self.PlayerConnections[#self.PlayerConnections + 1] = player.CharacterRemoving:Connect(function()
		self:_bindCharacter(nil)
	end)
	self:_bindCharacter(player.Character)
end

function Probe:_clearTrack()
	if self.Track then
		pcall(function() self.Track:Stop(0); self.Track:Destroy() end)
		self.Track = nil
	end
	if self.Animation then self.Animation:Destroy(); self.Animation = nil end
end

function Probe:Ping()
	if not self.Running or not self.Sender then return false, "only the sender can ping" end
	if not self.Animator or not self.Animator.Parent then return false, "main animator unavailable" end
	if self.Busy or os.clock() - self.LastSent < 3 then return false, "wait three seconds between tests" end
	if self.Sent >= 5 then return false, "five-test limit reached; reload to test again" end
	self.Busy = true
	self.LastSent = os.clock()
	self.Sent += 1
	self:_clearTrack()
	local token = HttpService:GenerateGUID(false):gsub("%-", "")
	self.Result = "attempting ping " .. token:sub(1, 8)
	self:_refresh()
	local animator = self.Animator
	local ok, reason = pcall(function()
		local animation = Instance.new("Animation")
		self.Animation = animation
		animation.AnimationId = string.format(template, "CLAWRELAY_PING_" .. token)
		local track = animator:LoadAnimation(animation)
		if not self.Running or self.Animator ~= animator then
			track:Destroy()
			error("sender character changed or probe stopped")
		end
		self.Track = track
		track.Looped = false
		track:Play(0, 0.0001, 1)
	end)
	self.Busy = false
	if not self.Running then return false, "probe stopped" end
	if not ok then
		self:_clearTrack()
		self.Result = "load/play failed: " .. tostring(reason):sub(1, 160)
		self:_refresh()
		return false, self.Result
	end
	self.Result = "play requested " .. token:sub(1, 8) .. "; delivery NOT confirmed here"
	self:_refresh()
	local ownedTrack = self.Track
	task.delay(3, function()
		if self.Track == ownedTrack then self:_clearTrack() end
	end)
	return true, token
end

function Probe:Destroy()
	if not self.Running then return end
	self.Running = false
	disconnect(self.Connections)
	disconnect(self.PlayerConnections)
	disconnect(self.CharacterConnections)
	if self.AnimationConnection then self.AnimationConnection:Disconnect() end
	self:_clearTrack()
	if self.Gui then self.Gui:Destroy() end
	if environment.CLAW_ANIMATION_PROBE == self then environment.CLAW_ANIMATION_PROBE = nil end
end

-- Small test panel; it doesn't capture keyboard input or hook game code.
if supplied.ShowPanel ~= false then
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClawAnimationProbe"
	gui.ResetOnSpawn = false
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(350, 160)
	panel.Position = UDim2.fromOffset(16, 230)
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	panel.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, -48)
	label.Position = UDim2.fromOffset(10, 8)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.TextSize = 14
	label.Font = Enum.Font.Code
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = panel
	Probe.Label = label
	Probe.Gui = gui
	local function button(text, x, callback)
		local item = Instance.new("TextButton")
		item.Text = text
		item.Size = UDim2.fromOffset(155, 28)
		item.Position = UDim2.fromOffset(x, 122)
		item.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
		item.TextColor3 = Color3.fromRGB(240, 240, 245)
		item.Parent = panel
		Probe.Connections[#Probe.Connections + 1] = item.Activated:Connect(callback)
	end
	if sender then
		button("SEND TEST PING", 10, function()
			local ok, reason = Probe:Ping()
			if not ok then Probe.Result = reason; Probe:_refresh() end
		end)
	end
	button("CLOSE PROBE", 185, function() Probe:Destroy() end)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

for _, player in ipairs(Players:GetPlayers()) do Probe:_bindPlayer(player) end
Probe.Connections[#Probe.Connections + 1] = Players.PlayerAdded:Connect(function(player) Probe:_bindPlayer(player) end)
Probe.Connections[#Probe.Connections + 1] = Players.PlayerRemoving:Connect(function(player)
	if Probe.Controller ~= player then return end
	disconnect(Probe.PlayerConnections)
	Probe.Controller = nil
	Probe:_bindCharacter(nil)
end)
Probe:_refresh()
print("[CLAW PROBE] Experimental ping only. A local echo is not proof of remote delivery.")
return Probe
