local environment = getgenv and getgenv() or _G
local UserInputService = game:GetService("UserInputService")

local InputAdapter = {}
InputAdapter.__index = InputAdapter

local KEY_CODES = {}
for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
	KEY_CODES[string.lower(keyCode.Name)] = keyCode
end

function InputAdapter.new(options)
	options = options or {}
	local virtualInput
	pcall(function()
		virtualInput = game:GetService("VirtualInputManager")
	end)

	return setmetatable({
		VirtualInput = virtualInput,
		Custom = options.custom or {},
		Settings = options.settings,
	}, InputAdapter)
end

local function keyCodeFromName(name)
	return KEY_CODES[string.lower(name)]
end

function InputAdapter:_binding(name)
	if not self.Settings then
		return nil
	end
	local value = self.Settings:get("Bindings." .. tostring(name))
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

function InputAdapter:key(keyCode, isDown)
	if self.VirtualInput then
		local ok = pcall(self.VirtualInput.SendKeyEvent, self.VirtualInput, isDown, keyCode, false, game)
		if ok then
			return true
		end
	end

	local keyFunction = rawget(environment, isDown and "keypress" or "keyrelease")
	if type(keyFunction) == "function" then
		local ok = pcall(keyFunction, keyCode.Value)
		return ok
	end

	return false, "no keyboard input implementation"
end

function InputAdapter:mouse(button, isDown)
	if self.VirtualInput then
		local position = UserInputService:GetMouseLocation()
		local ok = pcall(
			self.VirtualInput.SendMouseButtonEvent,
			self.VirtualInput,
			position.X,
			position.Y,
			button,
			isDown,
			game,
			0
		)
		if ok then
			return true
		end
	end

	local fallbackName = button == 0
		and (isDown and "mouse1press" or "mouse1release")
		or (isDown and "mouse2press" or "mouse2release")
	local fallback = rawget(environment, fallbackName)
	if type(fallback) == "function" then
		local ok, inputError = pcall(fallback)
		return ok, inputError
	end

	return false, "no mouse input implementation"
end

function InputAdapter:tapKey(keyCode, duration)
	local pressed, pressError = self:key(keyCode, true)
	if not pressed then
		return false, pressError
	end

	task.delay(duration or 0.035, function()
		self:key(keyCode, false)
	end)
	return true
end

function InputAdapter:tapMouse(button, duration)
	local pressed, pressError = self:mouse(button, true)
	if not pressed then
		return false, pressError
	end

	task.delay(duration or 0.035, function()
		self:mouse(button, false)
	end)
	return true
end

function InputAdapter:custom(name, ...)
	local callback = self.Custom[name]
	if type(callback) == "function" then
		local ok, success, result = pcall(callback, ...)
		if not ok then
			return false, success
		end
		if success == false then
			return false, result
		end
		return true, success
	end

	local binding = self:_binding(name)
	if not binding then
		return false, "no callback or key binding for " .. tostring(name)
	end
	local normalized = string.lower(binding)
	if normalized == "mouse1" or normalized == "mousebutton1" then
		return self:tapMouse(0)
	elseif normalized == "mouse2" or normalized == "mousebutton2" then
		return self:tapMouse(1)
	end

	local keyCode = keyCodeFromName(binding)
	if not keyCode or keyCode == Enum.KeyCode.Unknown then
		return false, "invalid key binding for " .. tostring(name)
	end
	return self:tapKey(keyCode)
end

return InputAdapter
