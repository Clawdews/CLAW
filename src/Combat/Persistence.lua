local environment = getgenv and getgenv() or _G
local HttpService = game:GetService("HttpService")

local Persistence = {}
Persistence.__index = Persistence

function Persistence.new(path)
	return setmetatable({
		path = path or "CLAW/combat-settings.json",
		version = 2,
	}, Persistence)
end

function Persistence:available()
	return type(rawget(environment, "readfile")) == "function" and type(rawget(environment, "writefile")) == "function"
end

function Persistence:_ensureFolder()
	local makefolder = rawget(environment, "makefolder")
	local isfolder = rawget(environment, "isfolder")
	if type(makefolder) ~= "function" then
		return
	end

	if type(isfolder) == "function" then
		local ok, exists = pcall(isfolder, "CLAW")
		if ok and exists then
			return
		end
	end

	pcall(makefolder, "CLAW")
end

function Persistence:load()
	if not self:available() then
		return nil, "executor file APIs are unavailable"
	end

	local isfile = rawget(environment, "isfile")
	if type(isfile) == "function" then
		local ok, exists = pcall(isfile, self.path)
		if not ok or not exists then
			return nil, "settings file does not exist"
		end
	end

	local okRead, encoded = pcall(rawget(environment, "readfile"), self.path)
	if not okRead or type(encoded) ~= "string" then
		return nil, "settings file could not be read"
	end

	local okDecode, envelope = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not okDecode or type(envelope) ~= "table" then
		return nil, "settings file is invalid JSON"
	end

	if envelope.version ~= self.version or type(envelope.combat) ~= "table" then
		return nil, "settings file version is unsupported"
	end

	return envelope.combat
end

function Persistence:save(settings)
	if not self:available() then
		return false, "executor file APIs are unavailable"
	end

	self:_ensureFolder()

	local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, {
		version = self.version,
		combat = settings,
	})
	if not okEncode then
		return false, "settings could not be encoded"
	end

	local okWrite, writeError = pcall(rawget(environment, "writefile"), self.path, encoded)
	if not okWrite then
		return false, tostring(writeError)
	end

	return true
end

return Persistence
