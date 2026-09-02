local environment = getgenv and getgenv() or _G
local TimingProfile = assert(environment.__CLAW_MODULES["src/Combat/TimingProfile.lua"])

local TimingStore = {}
TimingStore.__index = TimingStore

local CATEGORIES = {
	animation = true,
	sound = true,
	part = true,
	effect = true,
}

function TimingStore.new()
	return setmetatable({
		_containers = {
			animation = {},
			sound = {},
			part = {},
			effect = {},
		},
	}, TimingStore)
end

function TimingStore:register(profile, replace)
	profile = getmetatable(profile) == TimingProfile and profile or TimingProfile.new(profile)
	assert(CATEGORIES[profile.detector], "invalid detector category: " .. tostring(profile.detector))

	local container = self._containers[profile.detector]
	if container[profile.id] and not replace then
		error("timing profile already exists: " .. profile.id)
	end
	container[profile.id] = profile
	return profile
end

function TimingStore:get(category, id)
	local container = self._containers[category]
	return container and container[tostring(id)] or nil
end

function TimingStore:remove(category, id)
	local container = self._containers[category]
	if container then
		container[tostring(id)] = nil
	end
end

function TimingStore:list(category)
	local result = {}
	local container = assert(self._containers[category], "invalid detector category")
	for _, profile in pairs(container) do
		result[#result + 1] = profile
	end
	table.sort(result, function(first, second)
		return first.name < second.name
	end)
	return result
end

function TimingStore:load(values)
	for category in pairs(CATEGORIES) do
		for _, profile in ipairs(type(values) == "table" and values[category] or {}) do
			profile.detector = category
			self:register(profile, true)
		end
	end
	return self
end

function TimingStore:serialize()
	local result = {}
	for category in pairs(CATEGORIES) do
		result[category] = {}
		for index, profile in ipairs(self:list(category)) do
			result[category][index] = profile:serialize()
		end
	end
	return result
end

function TimingStore:count()
	local count = 0
	for category in pairs(CATEGORIES) do
		for _ in pairs(self._containers[category]) do
			count = count + 1
		end
	end
	return count
end

return TimingStore
