local environment = getgenv and getgenv() or _G
local Action = assert(environment.__CLAW_MODULES["src/Combat/Action.lua"])

local DynamicWeaponResolver = {}

local SUPPORTED_MODULES = {
	WeaponTest = "M1",
	WeaponFlourishTest = "Flourish",
	WeaponRunningAttackTest = "Running",
	WeaponAerialAttackTest = "Aerial",
	WeaponUppercutTest = "Uppercut",
}

local function valueOf(instance)
	if not instance then
		return nil
	end
	local ok, value = pcall(function()
		return instance.Value
	end)
	return ok and value or nil
end

local function weaponData(entity)
	if not entity then
		return nil
	end

	local handWeapon
	if entity:GetAttribute("MOB_rich_name") then
		local left = entity:FindFirstChild("LeftHand")
		local right = entity:FindFirstChild("RightHand")
		handWeapon = (left and left:FindFirstChild("HandWeapon"))
			or (right and right:FindFirstChild("HandWeapon"))
	else
		local thrown = workspace:FindFirstChild("Thrown")
		local attachment = thrown and thrown:FindFirstChild("Attach_" .. entity.Name)
		handWeapon = attachment and attachment:FindFirstChild("HandWeapon")
	end
	if not handWeapon then
		return nil
	end

	local stats = handWeapon:FindFirstChild("Stats")
	local swingValue = stats and stats:FindFirstChild("SwingSpeed")
	local lengthValue = stats and stats:FindFirstChild("Length")
	local typeValue = handWeapon:FindFirstChild("Type")
	local swingSpeed = tonumber(valueOf(swingValue))
	local length = tonumber(valueOf(lengthValue))
	local weaponType = tostring(valueOf(typeValue) or "")
	if not swingSpeed or swingSpeed <= 0 or not length or length <= 0 or weaponType == "" then
		return nil
	end

	return {
		swingSpeed = swingSpeed,
		length = length,
		weaponType = weaponType,
	}
end

function DynamicWeaponResolver.weaponInfo(event)
	return weaponData(event and event.entity)
end

local function inferredWeaponType(profile)
	local name = string.lower(tostring(profile and profile.name or ""))
	for _, candidate in ipairs({
		"Greatcannon",
		"Greathammer",
		"Greatsword",
		"Greataxe",
		"Twinblade",
		"Dagger",
		"Rapier",
		"Pistol",
		"Rifle",
		"Spear",
		"Staff",
		"Sword",
		"Club",
		"Fist",
		"Bow",
	}) do
		if string.find(name, string.lower(candidate), 1, true) then
			return candidate
		end
	end
	return "Sword"
end

local function trackSpeed(event)
	local speed = 1
	if event and event.track then
		pcall(function()
			speed = math.abs(event.track.Speed)
		end)
	end
	return math.max(0.01, tonumber(speed) or 1)
end

local function m1Windup(weaponType, speed, swingSpeed, profileName)
	local atDefaultSpeed = math.abs(speed - 1) <= 0.001
	if weaponType == "Greataxe" then
		return atDefaultSpeed and (0.171 + (0.250 / swingSpeed)) or ((0.171 / speed) + 0.120)
	elseif weaponType == "Greathammer" then
		return atDefaultSpeed and (0.150 + (0.250 / swingSpeed)) or ((0.150 / speed) + 0.200)
	elseif weaponType == "Greatcannon" then
		return atDefaultSpeed and (0.155 + 0.300) or ((0.155 / speed) + 0.160)
	elseif weaponType == "Rapier" then
		return (0.155 / speed) + 0.120
	elseif weaponType == "Bow" then
		return (0.147 / speed) + 0.160
	elseif weaponType == "Pistol" and not string.find(profileName, "Shot", 1, true) then
		return 0.350 / swingSpeed
	elseif weaponType == "Pistol" then
		return speed <= 0.01 and 0.100 or 0.075 / speed
	elseif weaponType == "Rifle" and string.find(profileName, "2", 1, true) then
		return speed <= 0.01 and 0.100 or 0.200 / speed
	elseif weaponType == "Rifle" then
		return (0.174 / speed) + 0.125
	elseif weaponType == "Club" then
		return (0.180 / speed) + 0.100
	elseif weaponType == "Twinblade" then
		return (0.150 / speed) + 0.050
	elseif weaponType == "Spear" then
		return (0.150 / speed) + 0.100
	elseif weaponType == "Greatsword" then
		return (0.158 / speed) + 0.150
	elseif weaponType == "Fist" then
		return (0.140 / speed) + 0.130
	elseif weaponType == "Dagger" then
		return (0.150 / speed) + 0.075
	elseif weaponType == "Staff" then
		return 0.350
	elseif weaponType == "Sword" then
		return (0.150 / speed) + 0.100
	end
	return nil
end

local function flourishWindup(weaponType, speed, swingSpeed)
	if weaponType == "Greataxe" then
		return (0.180 / speed) + 0.100
	elseif weaponType == "Greathammer" then
		return (0.140 / speed) + 0.140
	elseif weaponType == "Greatsword" then
		return (0.170 / speed) + 0.050
	elseif weaponType == "Twinblade" then
		return (0.166 / speed) + 0.140
	elseif weaponType == "Bow" then
		return (0.172 / speed) + 0.140
	elseif weaponType == "Pistol" then
		return 0.500 / swingSpeed
	elseif weaponType == "Greatcannon" then
		return (0.173 / speed) + 0.160
	elseif weaponType == "Dagger" then
		return (0.165 / speed) + 0.100
	elseif weaponType == "Rapier" then
		return (0.163 / speed) + 0.120
	elseif weaponType == "Spear" then
		return (0.135 / speed) + 0.180
	elseif weaponType == "Fist" then
		return (0.160 / speed) + 0.140
	elseif weaponType == "Sword" or weaponType == "Staff" then
		return (0.160 / speed) + 0.120
	elseif weaponType == "Club" or weaponType == "Rifle" then
		return (0.160 / speed) + 0.150
	end
	return nil
end

local function runningWindup(weaponType, speed, swingSpeed)
	if weaponType == "Dagger" then
		return (0.147 / speed) + 0.140
	elseif weaponType == "Greatsword" or weaponType == "Greatcannon" then
		return (0.160 / speed) + 0.180 + (0.100 / swingSpeed)
	elseif weaponType == "Spear" then
		return (0.150 / speed) + 0.170 + (0.100 / swingSpeed)
	elseif weaponType == "Pistol" then
		return 0.300 / speed
	elseif weaponType == "Rifle" then
		return (0.169 / speed) + 0.180 + (0.100 / swingSpeed)
	elseif weaponType == "Sword" then
		return (0.135 / speed) + 0.150 + (0.150 / swingSpeed)
	elseif weaponType == "Rapier" then
		return (0.238 / speed) + 0.060
	elseif weaponType == "Club" then
		return (0.173 / speed) + 0.140 + (0.150 / swingSpeed)
	elseif weaponType == "Bow" then
		return (0.160 / speed) + 0.130
	elseif weaponType == "Twinblade" then
		return (0.164 / speed) + 0.140 + (0.150 / swingSpeed)
	elseif weaponType == "Fist" then
		return (0.153 / speed) + 0.150
	end
	return nil
end

local function aerialWindup(weaponType, speed, swingSpeed, profileName)
	if weaponType == "Dagger" then
		return (0.165 / speed) + 0.100
	elseif weaponType == "Greataxe" then
		return (0.168 / speed) + 0.125
	elseif weaponType == "Twinblade" then
		return (0.160 / speed) + 0.100
	elseif weaponType == "Bow" then
		return (0.145 / speed) + 0.170
	elseif weaponType == "Club" then
		return (0.163 / speed) + 0.140
	elseif weaponType == "Pistol" then
		return 0.500 / swingSpeed
	elseif weaponType == "Rifle" and not string.find(profileName, "Fist", 1, true) then
		return speed <= 0.01 and 0.100 or 0.300 / speed
	elseif weaponType == "Rifle" then
		return (0.199 / speed) + 0.100
	elseif weaponType == "Greatsword" then
		return (0.166 / speed) + 0.160
	elseif weaponType == "Rapier" then
		return (0.225 / speed) + 0.080
	elseif weaponType == "Greatcannon" then
		return (0.163 / speed) + 0.183
	elseif weaponType == "Greathammer" then
		return (0.150 / speed) + 0.170
	elseif weaponType == "Fist" then
		return (0.160 / speed) + 0.130
	elseif weaponType == "Sword" or weaponType == "Staff" then
		return (0.160 / speed) + 0.100
	elseif weaponType == "Spear" then
		return (0.150 / speed) + 0.170
	end
	return nil
end

local function uppercutWindup(weaponType, speed, swingSpeed)
	if weaponType == "Dagger" then
		return (0.166 / speed) + 0.120
	elseif weaponType == "Greataxe" then
		return (0.141 / speed) + 0.100
	elseif weaponType == "Greathammer" then
		return (0.150 / speed) + 0.100
	elseif weaponType == "Greatsword" then
		return (0.157 / speed) + 0.100
	elseif weaponType == "Greatcannon" then
		return (0.166 / speed) + 0.100
	elseif weaponType == "Twinblade" then
		return (0.163 / speed) + 0.130
	elseif weaponType == "Bow" then
		return (0.150 / speed) + 0.140
	elseif weaponType == "Club" then
		return (0.166 / speed) + 0.140
	elseif weaponType == "Pistol" then
		return 0.166 / speed + 0.150
	elseif weaponType == "Rifle" then
		return (0.159 / speed) + 0.140
	elseif weaponType == "Rapier" then
		return (0.181 / speed) + 0.130
	elseif weaponType == "Fist" then
		return (0.150 / speed) + 0.120
	elseif weaponType == "Sword" or weaponType == "Staff" then
		return (0.150 / speed) + 0.100
	elseif weaponType == "Spear" then
		return (0.163 / speed) + 0.100 + (0.050 / swingSpeed)
	end
	return nil
end

local function resolvedAction(template, label, delay, hitbox, weaponType)
	local action = template and template:clone() or Action.new({ kind = "Parry" })
	action.kind = "Parry"
	action.name = string.format("Dynamic %s (%s)", label, weaponType)
	action.delay = action.metadata.preserveDelay == true and action.delay or math.max(0, delay)
	action.hitbox = hitbox
	action.metadata.dynamicWeapon = label
	action.metadata.weaponType = weaponType
	return action
end

function DynamicWeaponResolver.resolve(profile, event, sourceActions)
	local label = profile and SUPPORTED_MODULES[profile.sourceModule]
	if not label then
		return sourceActions
	end

	local data = weaponData(event and event.entity)
	local weaponType = data and data.weaponType or inferredWeaponType(profile)
	local speed = trackSpeed(event)
	local swingSpeed = data and data.swingSpeed or 1
	local length = data and data.length or 8
	local profileName = tostring(profile.name or "")
	local windup
	local hitbox

	if label == "M1" then
		windup = m1Windup(weaponType, speed, swingSpeed, profileName)
		hitbox = Vector3.new(length * 2.3, length * 2.3, length * 2.3)
	elseif label == "Flourish" then
		windup = flourishWindup(weaponType, speed, swingSpeed)
		hitbox = Vector3.new(length * 2.1, length * 2.1, length * 2.1)
	elseif label == "Running" then
		windup = runningWindup(weaponType, speed, swingSpeed)
		hitbox = weaponType == "Twinblade"
			and Vector3.new(length * 2.5, length * 2, length * 3.5)
			or Vector3.new(length * 2.5, length * 2, length * 2.5)
	elseif label == "Aerial" then
		windup = aerialWindup(weaponType, speed, swingSpeed, profileName)
		hitbox = Vector3.new(length * 2, length * 3.5, length * 3)
	elseif label == "Uppercut" then
		windup = uppercutWindup(weaponType, speed, swingSpeed)
		hitbox = Vector3.new(length * 2, length * 2, length * 2.2)
	end

	if not windup then
		windup = sourceActions[1] and sourceActions[1].delay or 0.25
	end
	local first = resolvedAction(sourceActions[1], label, windup, hitbox, weaponType)
	if label ~= "Running" or weaponType ~= "Twinblade" then
		return { first }
	end

	local second = first:clone()
	second.name = first.name .. " (follow-up)"
	second.delay = first.delay + (0.300 / swingSpeed)
	return { first, second }
end

return DynamicWeaponResolver
