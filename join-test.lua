-- Experimental, manual one-alt join test. Does not load or modify CLAW RELAY.
local BASE = "https://raw.githubusercontent.com/Clawdews/CLAW/server-join/"
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Teleport = game:GetService("TeleportService")
local Replicated = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "CLAW JOIN must run on a client")
local source = game:HttpGet(BASE .. "join/core.lua?cache=" .. Http:GenerateGUID(false))
local chunk, compileError = loadstring(source, "@CLAW/join/core.lua")
assert(chunk, compileError)
local Core = chunk()
assert(Core.VERSION == "0.1.0", "CLAW JOIN core version mismatch; reload the test")

local env = getgenv()
if env.CLAW_JOIN_TEST and type(env.CLAW_JOIN_TEST.destroy) == "function" then
	env.CLAW_JOIN_TEST:destroy(false)
end

local KEY = "CLAW_JOIN_TEST_v1_" .. tostring(player.UserId)
local FOLDER = "CLAW_JOIN_TEST"
local FILE = FOLDER .. "/" .. tostring(player.UserId) .. ".json"
local connections, storage, revision = {}, { teleport = false, file = false }, 0
local ui, core, closed, notice = {}, nil, false, ""
local api = {}
local function connect(signal, fn)
	local connection = signal:Connect(fn)
	connections[#connections + 1] = connection
	return connection
end
local function decode(raw)
	if type(raw) ~= "string" or #raw > 32768 then return nil end
	local ok, value = pcall(Http.JSONDecode, Http, raw)
	return ok and type(value) == "table" and value or nil
end
local function readSaved()
	local candidates = {}
	local ok, raw = pcall(Teleport.GetTeleportSetting, Teleport, KEY)
	if ok then candidates[#candidates + 1] = decode(raw) end
	if type(readfile) == "function" then
		ok, raw = pcall(readfile, FILE)
		if ok then candidates[#candidates + 1] = decode(raw) end
	end
	local newest
	for _, saved in ipairs(candidates) do
		if saved.accountId == player.UserId and type(saved.updatedAt) == "number"
			and type(saved.storageRevision) == "number" then
			if not newest or saved.updatedAt > newest.updatedAt
				or (saved.updatedAt == newest.updatedAt and saved.storageRevision > newest.storageRevision) then
				newest = saved
			end
		end
	end
	if newest then revision = newest.storageRevision end
	return newest
end
local saved = readSaved()
local function save(payload)
	revision += 1
	payload.storageRevision = revision
	local raw = Http:JSONEncode(payload)
	storage.teleport = pcall(function()
		Teleport:SetTeleportSetting(KEY, raw)
		assert(Teleport:GetTeleportSetting(KEY) == raw, "Teleport storage read-back failed")
	end)
	storage.file = false
	if type(writefile) == "function" and type(readfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function" then
		storage.file = pcall(function()
			if not isfolder(FOLDER) then makefolder(FOLDER) end
			writefile(FILE, raw)
			assert(readfile(FILE) == raw, "File storage read-back failed")
		end)
	end
	return storage.teleport or storage.file
end
local function current()
	return { userId = player.UserId, gameId = game.GameId, placeId = game.PlaceId,
		jobId = game.JobId, slot = player:GetAttribute("DataSlot") }
end
local function request(name, menu)
	local requests = Replicated:FindFirstChild("Requests")
	local parent = requests
	if menu then parent = requests and requests:FindFirstChild("StartMenu") end
	local remote = parent and parent:FindFirstChild(name)
	return remote and remote:IsA("RemoteEvent") and remote or nil
end
local function render()
	if closed or not ui.status then return end
	ui.status.Text = core.state .. "\n" .. core.detail .. (notice ~= "" and "\n\n" .. notice or "")
	ui.status.TextColor3 = core.state == "VERIFIED" and Color3.fromRGB(118, 225, 165)
		or Color3.fromRGB(213, 218, 232)
end
core = Core.new({
	now = os.time, current = current, nonce = function() return Http:GenerateGUID(false) end,
	save = save, changed = render,
	canJoin = function() return request("PickServer", true) ~= nil end,
	join = function(id)
		local remote = request("PickServer", true)
		assert(remote, "PickServer disappeared before the request")
		remote:FireServer(id)
	end,
	hasPlayer = function(id) return Players:GetPlayerByUserId(id) ~= nil end,
})
if game.PlaceId ~= Core.LOBBY_PLACE_ID then
	core.detail = "Copy a target ticket here, then paste it on one alt in the menu"
end
local function show(message)
	notice = message
	render()
end
local function copy(text, success)
	ui.ticket.Text = text
	local clipboard = setclipboard or toclipboard
	if type(clipboard) == "function" and pcall(clipboard, text) then show(success)
	else show("Clipboard unavailable. Copy the text from the box manually.") end
end
local function report()
	local value = core:report()
	value.storage = storage
	value.slotSignalSeen = core.realm ~= nil
	value.pickServerAvailable = request("PickServer", true) ~= nil
	value.route = "Deepwoken StartMenu.PickServer; default joinId is an unconfirmed JobId candidate"
	return Http:JSONEncode(value)
end
local function create(class, properties, parent)
	local object = Instance.new(class)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end
local palette = { panel = Color3.fromRGB(24, 26, 33), box = Color3.fromRGB(34, 37, 47),
	text = Color3.fromRGB(227, 231, 240), muted = Color3.fromRGB(171, 178, 196) }
local gui = create("ScreenGui", { Name = "ClawJoinTest", ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20 }, player:WaitForChild("PlayerGui"))
local frame = create("Frame", { Size = UDim2.fromOffset(500, 466), AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 48), BackgroundColor3 = palette.panel, BorderSizePixel = 0 }, gui)
create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
local scale = create("UIScale", { Scale = 1 }, frame)
local function resize()
	local camera = workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(math.min((camera.ViewportSize.X - 32) / 500,
			(camera.ViewportSize.Y - 64) / 466), 0.3, 1)
	end
end
resize()
local function label(text, x, y, width, height, size, parent)
	return create("TextLabel", { Text = text, Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1, TextColor3 = palette.text,
		TextSize = size or 13, Font = Enum.Font.Gotham, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, parent or frame)
end
label("CLAW / JOIN TEST", 16, 13, 300, 22, 16)
local function button(text, x, y, width, callback, parent)
	local b = create("TextButton", { Text = text, Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, 32), BackgroundColor3 = palette.box, BorderSizePixel = 0,
		TextColor3 = palette.text, TextSize = 12, Font = Enum.Font.Gotham }, parent or frame)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
	connect(b.Activated, function()
		local ok, failure = pcall(callback)
		if not ok then show("Test error: " .. tostring(failure):sub(1, 180)) end
	end)
	return b
end
local body = create("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(500, 422),
	BackgroundTransparency = 1 }, frame)
label(game.PlaceId == Core.LOBBY_PLACE_ID
	and "ALT: select your slot in the normal menu, paste the main's ticket, then join. Load this test again after arrival."
	or "MAIN: stay in this server and copy a target ticket for your alt. No movement, auto-logout or background joining.",
	16, 0, 468, 44, 13, body)
local function textbox(placeholder, x, y, width, height, multiline)
	local box = create("TextBox", { PlaceholderText = placeholder, Text = "",
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height), ClearTextOnFocus = false,
		MultiLine = multiline or false, TextWrapped = true, TextSize = 12, Font = Enum.Font.Code,
		BackgroundColor3 = palette.box, BorderSizePixel = 0, TextColor3 = palette.text,
		PlaceholderColor3 = palette.muted, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center }, body)
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, box)
	return box
end
local override = textbox("Main only: optional raw PR server-ID override (otherwise JobId)", 16, 50, 468, 34)
ui.ticket = textbox("Paste the main's JSON ticket here. Copy report also places its text here.", 16, 94, 468, 100, true)
button("COPY MAIN TARGET", 16, 204, 228, function()
	local id = override.Text:match("^%s*(.-)%s*$")
	local ticket, reason = core:capture(id ~= "" and id or nil)
	if not ticket then return show(reason) end
	copy(Http:JSONEncode(ticket), "Target copied. Valid for 10 minutes; keep the main in this server.")
end, body)
button("JOIN EXACT SERVER", 256, 204, 228, function()
	notice = ""
	local ticket = decode(ui.ticket.Text)
	if not ticket then return show("Paste a valid JSON target ticket, not a loadstring or a report.") end
	local ok, reason = core:begin(ticket)
	if not ok then show(reason) end
end, body)
button("COPY REPORT", 16, 246, 228, function() copy(report(), "Report copied. It contains account/server IDs, not credentials.") end, body)
button("CANCEL TRACKING", 256, 246, 228, function() core:cancel() end, body)
ui.status = label("", 16, 294, 468, 116, 13, body)
local collapsed = false
local minimize
minimize = button("-", 410, 5, 32, function()
	collapsed = not collapsed
	body.Visible = not collapsed
	frame.Size = UDim2.fromOffset(500, collapsed and 44 or 466)
	minimize.Text = collapsed and "+" or "-"
end)
button("X", 452, 5, 32, function() api:destroy(true) end)

function api:destroy(cancel)
	if closed then return end
	if cancel then core:cancel() end
	closed = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	gui:Destroy()
	if env.CLAW_JOIN_TEST == self then env.CLAW_JOIN_TEST = nil end
end
function api:report() return report() end
env.CLAW_JOIN_TEST = api

-- Bind before the user picks a slot; do not guess or auto-select their character.
local showRemote, showConnection
local function bindSlotSignal()
	local remote = request("ShowServers", false)
	if remote == showRemote then return end
	if showConnection then showConnection:Disconnect() end
	showRemote, showConnection = remote, nil
	if remote then
		showConnection = connect(remote.OnClientEvent, function(realm) core:onServers(realm) end)
	end
end
bindSlotSignal()
connect(player.OnTeleport, function(state)
	if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then core:teleportStarted() end
end)
connect(Teleport.TeleportInitFailed, function(who, result, message)
	if who == player then core:teleportFailed(tostring(result) .. ": " .. tostring(message)) end
end)
local elapsed = 0
connect(Run.Heartbeat, function(dt)
	elapsed += dt
	if elapsed < 1 then return end
	elapsed = 0
	bindSlotSignal()
	core:tick()
	resize()
end)
if saved and not core:resume(saved) then
	show("Ignored an expired or invalid saved check. No request was sent.")
end
if env.CLAW_RELAY then
	show("CLAW RELAY is also loaded. For this test, disable competing auto-start/server-hop scripts on this alt; nothing was changed for you.")
end
render()
print("[CLAW JOIN] v" .. Core.VERSION .. " " .. core.state .. " — no join is sent until you click JOIN")
return api
