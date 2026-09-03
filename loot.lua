local CONFIG = {
	WEBHOOK_URL = "",
	USERNAME    = "Loot Log",
	AVATAR      = "",
	FLUSH_EVERY = 2,   -- seconds between batches
	BATCH_SIZE  = 12,  -- max item lines merged into one message
	USER_ID     = "",  -- your Discord user ID, for pings
	DEBUG_SCAN  = false, -- true = dump loot-ish labels to console at startup
	PING_ITEMS  = {    -- lowercase names that trigger an @ mention
		["ether core"] = true,
	},
}


local environment = getgenv and getgenv() or _G
local supplied = environment.CLAW_LOOT_CONFIG
if type(supplied) == "table" then
	for key in pairs(CONFIG) do
		if supplied[key] ~= nil then CONFIG[key] = supplied[key] end
	end
end

if type(CONFIG.WEBHOOK_URL) ~= "string" or CONFIG.WEBHOOK_URL == "" then
	warn("[Loot] set WEBHOOK_URL in CLAW_LOOT_CONFIG before loading")
	return
end

local RAW_REQUEST = (syn and syn.request)
	or (fluxus and fluxus.request)
	or (http and http.request)
	or http_request
	or request

local Loot = (function()
	local HttpService = game:GetService("HttpService")
	local Players     = game:GetService("Players")

	local api = {}

	if not RAW_REQUEST then
		warn("[Loot] no HTTP request function on this executor - disabled")
		api.notify = function() end
		api.text   = function() end
		api.flushNow = function() end
		return api
	end

	local RARITY = {
		common    = { color = 0x9E9E9E, rank = 1 },
		uncommon  = { color = 0x4CAF50, rank = 2 },
		rare      = { color = 0x2196F3, rank = 3 },
		epic      = { color = 0x9C27B0, rank = 4 },
		legendary = { color = 0xFFC107, rank = 5 },
	}
	local DEFAULT_COLOR = 0x2B2D31

	local queue, queueIndex = {}, {}
	local pingWanted, sessionCount, workerAlive = false, 0, false

	local function me()
		local p = Players.LocalPlayer
		return p and p.Name or "?"
	end


	local function post(payload, attempt)
		attempt = attempt or 1

		local ok, res = pcall(RAW_REQUEST, {
			Url = CONFIG.WEBHOOK_URL,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["User-Agent"]   = "Roblox/WinInet",
			},
			Body = HttpService:JSONEncode(payload),
		})

		if not ok then
			warn("[Loot] request failed: " .. tostring(res))
			return false
		end

		local status = res.StatusCode or res.status_code or 0

		if status == 429 and attempt <= 3 then
			local delay, body = 2, (res.Body or res.body)
			if body then
				local good, parsed = pcall(HttpService.JSONDecode, HttpService, body)
				if good and type(parsed) == "table" and tonumber(parsed.retry_after) then
					delay = tonumber(parsed.retry_after)
					if delay > 100 then delay = delay / 1000 end
				end
			end
			task.wait(delay + 0.25)
			return post(payload, attempt + 1)
		end

		if status < 200 or status >= 300 then
			warn("[Loot] webhook returned HTTP " .. tostring(status))
			return false
		end
		return true
	end


	local function buildEmbed(items)
		local lines, bestRank, color = {}, 0, DEFAULT_COLOR
		for _, item in ipairs(items) do
			local suffix = item.amount > 1 and string.format(" **x%d**", item.amount) or ""
			table.insert(lines, string.format("- %s%s", item.name, suffix))
			local r = RARITY[string.lower(item.rarity or "")]
			if r and r.rank > bestRank then bestRank, color = r.rank, r.color end
		end
		return {
			title = (#items == 1) and "Item obtained"
				or string.format("%d items obtained", #items),
			description = table.concat(lines, "\n"),
			color = color,
			footer = { text = string.format("%s | session total: %d | server: %s",
				me(), sessionCount, string.sub(tostring(game.JobId), 1, 8)) },
			timestamp = DateTime.now():ToIsoDate(),
		}
	end

	local function flush()
		if #queue == 0 then return end
		local batch = {}
		for _ = 1, math.min(CONFIG.BATCH_SIZE, #queue) do
			table.insert(batch, table.remove(queue, 1))
		end
		queueIndex = {}
		for i, item in ipairs(queue) do queueIndex[string.lower(item.name)] = i end

		local content = (pingWanted and CONFIG.USER_ID ~= "")
			and ("<@" .. CONFIG.USER_ID .. ">") or nil
		pingWanted = false

		post({
			username   = CONFIG.USERNAME,
			avatar_url = (CONFIG.AVATAR ~= "" and CONFIG.AVATAR) or nil,
			content    = content,
			embeds     = { buildEmbed(batch) },
		})
	end

	local function startWorker()
		if workerAlive then return end
		workerAlive = true
		task.spawn(function()
			while true do
				task.wait(CONFIG.FLUSH_EVERY)
				if #queue > 0 then pcall(flush) end
			end
		end)
	end


	function api.notify(name, opts)
		name = tostring(name)
		opts = opts or {}
		local amount = tonumber(opts.amount) or 1
		local key = string.lower(name)

		sessionCount = sessionCount + amount
		if CONFIG.PING_ITEMS[key] then pingWanted = true end

		local at = queueIndex[key]
		if at and queue[at] then
			queue[at].amount = queue[at].amount + amount
		else
			table.insert(queue, { name = name, amount = amount, rarity = opts.rarity })
			queueIndex[key] = #queue
		end
		startWorker()
	end

	function api.text(message)
		task.spawn(post, {
			username   = CONFIG.USERNAME,
			avatar_url = (CONFIG.AVATAR ~= "" and CONFIG.AVATAR) or nil,
			content    = tostring(message),
		})
	end

	function api.flushNow() pcall(flush) end


	task.spawn(function()
		local roots, added = {}, {}
		local function addRoot(r)
			if typeof(r) == "Instance" and not added[r] then
				added[r] = true
				table.insert(roots, r)
			end
		end

		pcall(function() if gethui then addRoot(gethui()) end end)
		pcall(function() addRoot(game:GetService("CoreGui")) end)
		pcall(function()
			local p = Players.LocalPlayer
			if p then addRoot(p:WaitForChild("PlayerGui", 15)) end
		end)

		local lastSeen = setmetatable({}, { __mode = "k" })

		local function report(obj)
			local ok, txt = pcall(function() return obj.Text end)
			if not ok or type(txt) ~= "string" then return end
			local name = string.match(txt, "^%s*Looted:%s*(.+)$")
			if not name then return end
			if lastSeen[obj] == txt then return end
			lastSeen[obj] = txt

			local starred = string.find(name, "\226\152\133", 1, true) ~= nil -- star
			name = string.gsub(name, "\226\152\133", "")
			name = string.match(name, "^%s*(.-)%s*$")
			if name ~= "" then
				api.notify(name, { rarity = starred and "legendary" or "common" })
			end
		end

		local function hook(obj)
			if obj:IsA("TextLabel") or obj:IsA("TextButton") then
				report(obj)
				obj:GetPropertyChangedSignal("Text"):Connect(function() report(obj) end)
			end
		end

		for _, root in ipairs(roots) do
			pcall(function()
				for _, d in ipairs(root:GetDescendants()) do pcall(hook, d) end
				root.DescendantAdded:Connect(function(d) pcall(hook, d) end)
			end)
		end

		function api.debugScan()
			print("[Loot] scanning " .. #roots .. " roots")
			for _, root in ipairs(roots) do
				pcall(function()
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA("TextLabel") or d:IsA("TextButton") then
							local ok, t = pcall(function() return d.Text end)
							if ok and type(t) == "string" and string.find(t, "Loot") then
								print(("[Loot] %s | %q"):format(d:GetFullName(), t))
							end
						end
					end
				end)
			end
			print("[Loot] scan done")
		end

		if CONFIG.DEBUG_SCAN then task.delay(20, api.debugScan) end


		print(("[Loot] online - watching %d UI roots"):format(#roots))
	end)

	return api
end)()

if getgenv then getgenv().Loot = Loot else _G.Loot = Loot end
return Loot
