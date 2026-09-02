local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Targeting = {}
Targeting.__index = Targeting

local function listed(list, player, character)
	local name = string.lower(player and player.Name or character.Name)
	local displayName = player and string.lower(player.DisplayName) or nil
	local userID = player and tostring(player.UserId) or nil

	for _, value in ipairs(list or {}) do
		local normalized = string.lower(tostring(value))
		if normalized == name or (displayName and normalized == displayName) or (userID and normalized == userID) then
			return true
		end
	end

	return false
end

local function mobTargetsLocalPlayer(character, localCharacter)
	local localPlayer = Players.LocalPlayer
	local targetNames = { "Target", "CombatTarget", "CurrentTarget", "AggroTarget" }
	for _, name in ipairs(targetNames) do
		local object = character:FindFirstChild(name, true)
		if object and object:IsA("ObjectValue") and object.Value ~= nil then
			return object.Value == localCharacter or object.Value == localPlayer
		end
		local attribute = character:GetAttribute(name)
		if attribute ~= nil then
			local normalized = tostring(attribute)
			return normalized == localCharacter.Name
				or normalized == localPlayer.Name
				or normalized == tostring(localPlayer.UserId)
		end
	end
	-- Some entities do not replicate an aggro target. In that case, preserve the
	-- target instead of introducing a false negative.
	return true
end

function Targeting.new(settings, options)
	options = options or {}
	return setmetatable({
		settings = settings,
		isAlly = options.isAlly,
		entitySource = options.entitySource,
		friendCache = setmetatable({}, { __mode = "k" }),
	}, Targeting)
end

function Targeting:_isAlly(player)
	local localPlayer = Players.LocalPlayer
	local allied = player.Team ~= nil and player.Team == localPlayer.Team
	local localGuild = localPlayer:GetAttribute("Guild")
	if not allied and type(localGuild) == "string" and localGuild ~= "" then
		allied = player:GetAttribute("Guild") == localGuild
	end
	if not allied then
		local cached = self.friendCache[player]
		if cached == nil then
			local ok, status = pcall(localPlayer.GetFriendStatus, localPlayer, player)
			cached = ok and status == Enum.FriendStatus.Friend
			self.friendCache[player] = cached
		end
		allied = cached
	end
	if type(self.isAlly) == "function" then
		local ok, customAllied = pcall(self.isAlly, player)
		allied = ok and customAllied or allied
	end
	return allied
end

function Targeting:_entities()
	if type(self.entitySource) == "function" then
		local ok, entities = pcall(self.entitySource)
		if ok and type(entities) == "table" then
			return entities
		end
	end

	local live = workspace:FindFirstChild("Live")
	if live then
		return live:GetChildren()
	end

	local entities = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			entities[#entities + 1] = player.Character
		end
	end
	return entities
end

function Targeting:scan(localCharacter)
	local config = self.settings:get("Targeting")
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not localRoot or not camera then
		return {}
	end

	local mouse = UserInputService:GetMouseLocation()
	local candidates = {}

	for _, character in ipairs(self:_entities()) do
		if character == localCharacter or not character:IsA("Model") then
			continue
		end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			continue
		end

		local player = Players:GetPlayerFromCharacter(character)
		if player and config.IgnorePlayers then
			continue
		end
		if not player and config.IgnoreMobs then
			continue
		end
		if not player and config.CheckMobTarget and not mobTargetsLocalPlayer(character, localCharacter) then
			continue
		end
		local whitelisted = listed(config.Whitelist, player, character)
		if config.WhitelistMode == "Only" and #config.Whitelist > 0 and not whitelisted then
			continue
		end
		if config.WhitelistMode == "Exclude" and whitelisted then
			continue
		end
		if listed(config.Blacklist, player, character) then
			continue
		end
		if player and config.IgnoreAllies then
			if self:_isAlly(player) then
				continue
			end
		end

		local offset = root.Position - localRoot.Position
		local distance = offset.Magnitude
		if distance > config.MaxDistance or distance <= 0.001 then
			continue
		end

		local facingDot = camera.CFrame.LookVector:Dot(offset.Unit)
		local minimumDot = math.cos(math.rad(math.clamp(config.FOVDegrees, 0, 360) * 0.5))
		if config.FOVDegrees < 360 and facingDot < minimumDot then
			continue
		end

		local screenPosition, onScreen = camera:WorldToViewportPoint(root.Position)
		if config.RequireOnScreen and not onScreen then
			continue
		end

		local crosshairDistance = Vector2.new(screenPosition.X - mouse.X, screenPosition.Y - mouse.Y).Magnitude
		candidates[#candidates + 1] = {
			Character = character,
			Player = player,
			Humanoid = humanoid,
			Root = root,
			Distance = distance,
			CrosshairDistance = crosshairDistance,
			FacingDot = facingDot,
			OnScreen = onScreen,
			HealthRatio = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1,
		}
	end

	return candidates
end

function Targeting:select(candidates)
	local config = self.settings:get("Targeting")
	local selection = config.Selection

	table.sort(candidates, function(first, second)
		if selection == "ClosestCrosshair" then
			return first.CrosshairDistance < second.CrosshairDistance
		elseif selection == "LeastHealth" then
			return first.Humanoid.Health < second.Humanoid.Health
		elseif selection == "LowestHealthRatio" then
			return first.HealthRatio < second.HealthRatio
		elseif selection == "HighestThreat" then
			local firstScore = first.Distance - (first.FacingDot * 10)
			local secondScore = second.Distance - (second.FacingDot * 10)
			return firstScore < secondScore
		end
		return first.Distance < second.Distance
	end)

	local selected = {}
	local limit = math.max(1, math.floor(config.MaxTargets))
	for index = 1, math.min(limit, #candidates) do
		selected[index] = candidates[index]
	end
	return selected
end

function Targeting:best(localCharacter)
	return self:select(self:scan(localCharacter))
end

function Targeting:find(localCharacter, model)
	for _, target in ipairs(self:best(localCharacter)) do
		if target.Character == model then
			return target
		end
	end
	return nil
end

return Targeting
