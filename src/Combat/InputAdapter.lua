local environment = getgenv and getgenv() or _G
local UserInputService = game:GetService("UserInputService")

local InputAdapter = {}
InputAdapter.__index = InputAdapter

function InputAdapter.new(options)
	options = options or {}
	local virtualInput
	pcall(function()
		virtualInput = game:GetService("VirtualInputManager")
	end)

	return setmetatable({
		VirtualInput = virtualInput,
		Custom = options.custom or {},
	}, InputAdapter)
end

function InputAdapter:key(keyCode, isDown)
	if self.VirtualInput then
		local ok = pcall(
			self.VirtualInput.SendKeyEvent,
			self.VirtualInput,
			isDown,
			keyCode,
			false,
			game
		)
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
	if not self.VirtualInput then
		return false, "no mouse input implementation"
	end

	local position = UserInputService:GetMouseLocation()
	local ok, inputError = pcall(
		self.VirtualInput.SendMouseButtonEvent,
		self.VirtualInput,
		position.X,
		position.Y,
		button,
		isDown,
		game,
		0
	)
	return ok, inputError
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
	if type(callback) ~= "function" then
		return false, "no custom input handler for " .. tostring(name)
	end

	local ok, success, result = pcall(callback, ...)
	if not ok then
		return false, success
	end
	if success == false then
		return false, result
	end
	return true, success
end

return InputAdapter
