local environment = getgenv and getgenv() or _G
local UserInputService = game:GetService("UserInputService")
local NativeInputBridge = assert(environment.__CLAW_MODULES["src/Combat/NativeInputBridge.lua"])

local InputAdapter = {}
InputAdapter.__index = InputAdapter

local KEY_CODES = {}
for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
	KEY_CODES[string.lower(keyCode.Name)] = keyCode
end

local VIRTUAL_KEY_CODES = {
	Backspace = 0x08,
	Tab = 0x09,
	Return = 0x0D,
	Escape = 0x1B,
	Space = 0x20,
	PageUp = 0x21,
	PageDown = 0x22,
	End = 0x23,
	Home = 0x24,
	Left = 0x25,
	Up = 0x26,
	Right = 0x27,
	Down = 0x28,
	Insert = 0x2D,
	Delete = 0x2E,
	LeftShift = 0x10,
	RightShift = 0x10,
	LeftControl = 0x11,
	RightControl = 0x11,
	LeftAlt = 0x12,
	RightAlt = 0x12,
}

local function virtualKeyCode(keyCode)
	local name = keyCode.Name
	if #name == 1 then
		local byte = string.byte(string.upper(name))
		if byte and ((byte >= 0x30 and byte <= 0x39) or (byte >= 0x41 and byte <= 0x5A)) then
			return byte
		end
	end
	local functionNumber = string.match(name, "^F(%d+)$")
	if functionNumber then
		local index = tonumber(functionNumber)
		if index and index >= 1 and index <= 24 then
			return 0x6F + index
		end
	end
	return VIRTUAL_KEY_CODES[name] or keyCode.Value
end

local function firstFunction(names)
	for _, name in ipairs(names) do
		local callback = rawget(environment, name)
		if type(callback) == "function" then
			return callback, name
		end
	end
	return nil, nil
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
		LastInput = nil,
		Native = NativeInputBridge.new(),
	}, InputAdapter)
end

function InputAdapter:warmup()
	return self.Native:initialize(true)
end

function InputAdapter:nativeBlock(duration, deflect)
	local ok, detail = self.Native:block(duration, deflect)
	self.LastInput = {
		kind = "native",
		name = deflect and "Parry" or "Block",
		backend = ok and "LycorisNative" or "fallback",
		isDown = ok,
		ok = ok,
		detail = detail,
		at = os.clock(),
	}
	return ok, detail
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
	local callback, backend = firstFunction(isDown and { "keypress", "key_press" } or { "keyrelease", "key_release" })
	if callback then
		local ok, inputError = pcall(callback, virtualKeyCode(keyCode))
		self.LastInput = {
			kind = "key",
			name = keyCode.Name,
			backend = backend,
			isDown = isDown,
			ok = ok,
			detail = ok and nil or tostring(inputError),
			at = os.clock(),
		}
		if ok then
			return true, backend
		end
	end

	if self.VirtualInput then
		local ok = pcall(self.VirtualInput.SendKeyEvent, self.VirtualInput, isDown, keyCode, false, game)
		if ok then
			self.LastInput = {
				kind = "key",
				name = keyCode.Name,
				backend = "VirtualInputManager",
				isDown = isDown,
				ok = true,
				at = os.clock(),
			}
			return true, "VirtualInputManager"
		end
	end

	self.LastInput = {
		kind = "key",
		name = keyCode.Name,
		backend = "none",
		isDown = isDown,
		ok = false,
		detail = "no keyboard input implementation",
		at = os.clock(),
	}
	return false, "no keyboard input implementation"
end

function InputAdapter:mouse(button, isDown)
	local fallbackName = button == 0
		and (isDown and "mouse1press" or "mouse1release")
		or (isDown and "mouse2press" or "mouse2release")
	local fallback = rawget(environment, fallbackName)
	if type(fallback) == "function" then
		local ok, inputError = pcall(fallback)
		self.LastInput = {
			kind = "mouse",
			name = button == 0 and "Mouse1" or "Mouse2",
			backend = fallbackName,
			isDown = isDown,
			ok = ok,
			detail = ok and nil or tostring(inputError),
			at = os.clock(),
		}
		if ok then
			return true, fallbackName
		end
	end

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
			self.LastInput = {
				kind = "mouse",
				name = button == 0 and "Mouse1" or "Mouse2",
				backend = "VirtualInputManager",
				isDown = isDown,
				ok = true,
				at = os.clock(),
			}
			return true, "VirtualInputManager"
		end
	end

	self.LastInput = {
		kind = "mouse",
		name = button == 0 and "Mouse1" or "Mouse2",
		backend = "none",
		isDown = isDown,
		ok = false,
		detail = "no mouse input implementation",
		at = os.clock(),
	}
	return false, "no mouse input implementation"
end

function InputAdapter:tapKey(keyCode, duration)
	local pressed, pressDetail = self:key(keyCode, true)
	if not pressed then
		return false, pressDetail
	end

	task.delay(duration or 0.035, function()
		self:key(keyCode, false)
	end)
	return true, pressDetail
end

function InputAdapter:tapMouse(button, duration)
	local pressed, pressDetail = self:mouse(button, true)
	if not pressed then
		return false, pressDetail
	end

	task.delay(duration or 0.035, function()
		self:mouse(button, false)
	end)
	return true, pressDetail
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

function InputAdapter:Destroy()
	self.Native:Destroy()
end

return InputAdapter
