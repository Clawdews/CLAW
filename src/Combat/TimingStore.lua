local environment = getgenv and getgenv() or _G
local TimingProfile = assert(environment.__CLAW_MODULES["src/Combat/TimingProfile.lua"])
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])

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
		Changed = Signal.new(),
		_containers = {
			animation = {},
			sound = {},
			part = {},
			effect = {},
		},
	}, TimingStore)
end

function TimingStore:register(profile, replace, silent)
	profile = getmetatable(profile) == TimingProfile and profile or TimingProfile.new(profile)
	assert(CATEGORIES[profile.detector], "invalid detector category: " .. tostring(profile.detector))

	local container = self._containers[profile.detector]
	if container[profile.id] and not replace then
		error("timing profile already exists: " .. profile.id)
	end
	container[profile.id] = profile
	if not silent then
		self.Changed:Fire("registered", profile.detector, profile.id, profile)
	end
	return profile
end

function TimingStore:has(category, id)
	local container = self._containers[category]
	return container ~= nil and container[tostring(id)] ~= nil
end

function TimingStore:get(category, id)
	local container = self._containers[category]
	return container and container[tostring(id)] or nil
end

function TimingStore:remove(category, id)
	local container = self._containers[category]
	if container then
		local key = tostring(id)
		local removed = container[key]
		container[key] = nil
		if removed then
			self.Changed:Fire("removed", category, key, removed)
		end
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

function TimingStore:clear(category, silent)
	if category then
		table.clear(assert(self._containers[category], "invalid detector category"))
	else
		for name in pairs(CATEGORIES) do
			table.clear(self._containers[name])
		end
	end
	if not silent then
		self.Changed:Fire("cleared", category)
	end
end

function TimingStore:load(values)
	local staged = {
		animation = {},
		sound = {},
		part = {},
		effect = {},
	}
	for category in pairs(CATEGORIES) do
		local profiles = type(values) == "table" and values[category] or {}
		assert(type(profiles) == "table", "invalid timing category: " .. category)
		for _, valuesForProfile in ipairs(profiles) do
			assert(type(valuesForProfile) == "table", "invalid timing profile")
			local normalized = {}
			for key, value in pairs(valuesForProfile) do
				normalized[key] = value
			end
			normalized.detector = category
			local profile = TimingProfile.new(normalized)
			staged[category][profile.id] = profile
		end
	end
	self._containers = staged
	self.Changed:Fire("loaded")
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

function TimingStore:Destroy()
	self:clear(nil, true)
	self.Changed:Destroy()
end

return TimingStore
