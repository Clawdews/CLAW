local environment = getgenv and getgenv() or _G
local HttpService = game:GetService("HttpService")

local TimingPersistence = {}
TimingPersistence.__index = TimingPersistence

function TimingPersistence.new(store, path)
	return setmetatable({
		Store = store,
		Path = path or "CLAW/timings.json",
		Version = 1,
	}, TimingPersistence)
end

function TimingPersistence:export()
	return HttpService:JSONEncode({
		version = self.Version,
		timings = self.Store:serialize(),
	})
end

function TimingPersistence:import(encoded, merge)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or type(data) ~= "table" or type(data.timings) ~= "table" then
		return false, "invalid timing data"
	end
	if data.version ~= self.Version then
		return false, "unsupported timing version"
	end
	local method = merge and self.Store.merge or self.Store.load
	local loaded, loadError = pcall(method, self.Store, data.timings)
	if not loaded then
		return false, tostring(loadError)
	end
	return true
end

function TimingPersistence:load(merge)
	local readfile = rawget(environment, "readfile")
	local isfile = rawget(environment, "isfile")
	if type(readfile) ~= "function" then
		return false, "executor file APIs are unavailable"
	end
	if type(isfile) == "function" then
		local ok, exists = pcall(isfile, self.Path)
		if not ok or not exists then
			return false, "timing file does not exist"
		end
	end
	local ok, encoded = pcall(readfile, self.Path)
	if not ok then
		return false, tostring(encoded)
	end
	return self:import(encoded, merge)
end

function TimingPersistence:save()
	local writefile = rawget(environment, "writefile")
	if type(writefile) ~= "function" then
		return false, "executor file APIs are unavailable"
	end
	local makefolder = rawget(environment, "makefolder")
	if type(makefolder) == "function" then
		pcall(makefolder, "CLAW")
	end
	local ok, result = pcall(writefile, self.Path, self:export())
	return ok, ok and nil or tostring(result)
end

function TimingPersistence:copy()
	local setclipboard = rawget(environment, "setclipboard")
	if type(setclipboard) ~= "function" then
		return false, "clipboard API is unavailable"
	end
	local ok, result = pcall(setclipboard, self:export())
	return ok, ok and nil or tostring(result)
end

return TimingPersistence
