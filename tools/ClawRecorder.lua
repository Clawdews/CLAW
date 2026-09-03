-- CLAW RECORDER v0.3.0
-- Passive combat telemetry for building timing catalogs alongside another hub.

local ENV = getgenv and getgenv() or _G
local previous = rawget(ENV, "__CLAW_RECORDER")
if type(previous) == "table" and type(previous.Destroy) == "function" then
	pcall(previous.Destroy, previous)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local SESSION_STARTED_AT = os.clock()
local SESSION_STARTED_UNIX = os.time()
local SESSION_ID = string.format("%d_%s", SESSION_STARTED_UNIX, string.sub(HttpService:GenerateGUID(false), 1, 8))
local ROOT_PATH = "CLAW_RECORDER"
local SESSION_PATH = ROOT_PATH .. "/" .. SESSION_ID
local CHUNK_SIZE = 2000
local MAX_MEMORY_EVENTS = 4000
local MAX_SAMPLES_PER_OUTCOME = 96
local MAX_ACTIVE_AGE = 10
local RAW_ANIMATION_INITIAL_SAMPLES = 12
local RAW_ANIMATION_SAMPLE_INTERVAL = 5
local AUTOSAVE_INTERVAL = 15

local function executorFunction(name)
	local callback = rawget(ENV, name)
	return type(callback) == "function" and callback or nil
end

local writefile = executorFunction("writefile")
local makefolder = executorFunction("makefolder")
local setclipboard = executorFunction("setclipboard")

local function round(value, places)
	local scale = 10 ^ (places or 4)
	return math.floor((tonumber(value) or 0) * scale + 0.5) / scale
end

local function scalarSnapshot(value, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local valueType = typeof(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return value
	elseif valueType == "Vector3" then
		return { X = round(value.X), Y = round(value.Y), Z = round(value.Z) }
	elseif valueType == "CFrame" then
		local position = value.Position
		return { X = round(position.X), Y = round(position.Y), Z = round(position.Z) }
	elseif valueType == "Instance" then
		return { class = value.ClassName, name = value.Name }
	elseif type(value) ~= "table" or depth >= 2 or seen[value] then
		return nil
	end
	seen[value] = true
	local result = {}
	local count = 0
	for key, child in pairs(value) do
		if count >= 24 then
			break
		end
		local keyType = type(key)
		if keyType == "string" or keyType == "number" then
			local snapshot = scalarSnapshot(child, depth + 1, seen)
			if snapshot ~= nil then
				result[tostring(key)] = snapshot
				count = count + 1
			end
		end
	end
	return result
end

local function normalizeAnimationId(value)
	local text = tostring(value or "")
	return string.match(text, "(%d+)") or text
end

local function pingMilliseconds()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return ok and round(value, 2) or nil
end

local State = {
	Version = "0.3.0",
	Destroyed = false,
	Recording = true,
	Connections = {},
	CharacterConnections = {},
	AnimatorConnections = setmetatable({}, { __mode = "k" }),
	TrackConnections = {},
	LocalTrackConnections = {},
	EffectLifetimes = setmetatable({}, { __mode = "k" }),
	EntityIds = setmetatable({}, { __mode = "k" }),
	EntitySequence = 0,
	AnimationSequence = 0,
	RawAnimationSchedule = {},
	SourceActivity = {},
	SuspiciousAnimations = {},
	EffectCounts = {},
	EffectClassesSeen = {},
	Active = setmetatable({}, { __mode = "k" }),
	Recent = {},
	LocalActive = setmetatable({}, { __mode = "k" }),
	LocalRecent = {},
	Catalog = {},
	OffenseCatalog = {},
	Buffer = {},
	Chunks = {},
	Sequence = 0,
	ChunkSequence = 0,
	AnimationCount = 0,
	LocalAnimationCount = 0,
	OutcomeCount = 0,
	OffenseOutcomeCount = 0,
	LinkedCount = 0,
	OffenseLinkedCount = 0,
	DroppedCount = 0,
	LastOutcome = nil,
	LastOffenseOutcome = nil,
	LastSave = 0,
	LastError = nil,
	Flushing = false,
	Checkpointing = false,
	EffectStatus = "not found",
	FileStatus = writefile and "ready" or "clipboard only",
}

ENV.__CLAW_RECORDER = State

local function connect(signal, callback, bucket)
	if not signal then
		return nil
	end
	local connector = signal.Connect or signal.connect
	if type(connector) ~= "function" then
		return nil
	end
	local ok, connection = pcall(connector, signal, callback)
	if not ok or not connection then
		return nil
	end
	local target = bucket or State.Connections
	target[#target + 1] = connection
	return connection
end

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(bucket)
end

local function disconnectMapped(bucket, key)
	local connections = bucket[key]
	if connections then
		if type(connections) ~= "table" then
			connections = { connections }
		end
		for _, connection in ipairs(connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		bucket[key] = nil
	end
end

local function ensureFolders()
	if not makefolder then
		return false
	end
	pcall(makefolder, ROOT_PATH)
	pcall(makefolder, SESSION_PATH)
	return true
end

ensureFolders()

local function relativeTime(now)
	return round((now or os.clock()) - SESSION_STARTED_AT, 6)
end

local function catalogCount()
	local count = 0
	for _ in pairs(State.Catalog) do
		count = count + 1
	end
	return count
end

local function offenseCatalogCount()
	local count = 0
	for _ in pairs(State.OffenseCatalog) do
		count = count + 1
	end
	return count
end

local flush
local checkpoint

local function pushEvent(kind, data)
	if State.Destroyed or not State.Recording then
		return nil
	end
	State.Sequence = State.Sequence + 1
	local event = data or {}
	event.seq = State.Sequence
	event.type = kind
	event.t = relativeTime()
	State.Buffer[#State.Buffer + 1] = event
	if not writefile and #State.Buffer > MAX_MEMORY_EVENTS then
		table.remove(State.Buffer, 1)
		State.DroppedCount = State.DroppedCount + 1
	elseif writefile and #State.Buffer >= CHUNK_SIZE then
		task.defer(function()
			flush("chunk threshold")
		end)
	end
	return event
end

local function weaponSnapshot(entity)
	if not entity then
		return nil
	end
	local handWeapon
	if entity:GetAttribute("MOB_rich_name") then
		local left = entity:FindFirstChild("LeftHand")
		local right = entity:FindFirstChild("RightHand")
		handWeapon = (left and left:FindFirstChild("HandWeapon")) or (right and right:FindFirstChild("HandWeapon"))
	else
		local thrown = workspace:FindFirstChild("Thrown")
		local attachment = thrown and thrown:FindFirstChild("Attach_" .. entity.Name)
		handWeapon = attachment and attachment:FindFirstChild("HandWeapon")
	end
	if not handWeapon then
		return nil
	end
	local stats = handWeapon:FindFirstChild("Stats")
	local swing = stats and stats:FindFirstChild("SwingSpeed")
	local length = stats and stats:FindFirstChild("Length")
	local weaponType = handWeapon:FindFirstChild("Type")
	local function valueOf(instance)
		local ok, value = pcall(function()
			return instance.Value
		end)
		return ok and value or nil
	end
	return {
		type = tostring(valueOf(weaponType) or "unknown"),
		swingSpeed = tonumber(valueOf(swing)),
		oldSwingSpeed = swing and (tonumber(swing:GetAttribute("OldValue")) or tonumber(valueOf(swing))) or nil,
		length = tonumber(valueOf(length)),
	}
end

local function geometrySnapshot(entity)
	local localCharacter = LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local root = entity and entity:FindFirstChild("HumanoidRootPart")
	if not localRoot or not root then
		return nil
	end
	local offset = localRoot.Position - root.Position
	local unit = offset.Magnitude > 0.001 and offset.Unit or Vector3.zero
	local relative = root.CFrame:PointToObjectSpace(localRoot.Position)
	return {
		distance = round(offset.Magnitude, 3),
		facingDot = round(root.CFrame.LookVector:Dot(unit), 5),
		relative = { X = round(relative.X), Y = round(relative.Y), Z = round(relative.Z) },
		attackerVelocity = {
			X = round(root.AssemblyLinearVelocity.X),
			Y = round(root.AssemblyLinearVelocity.Y),
			Z = round(root.AssemblyLinearVelocity.Z),
		},
		localVelocity = {
			X = round(localRoot.AssemblyLinearVelocity.X),
			Y = round(localRoot.AssemblyLinearVelocity.Y),
			Z = round(localRoot.AssemblyLinearVelocity.Z),
		},
	}
end

local function animationProperties(track)
	local values = {
		id = "unknown",
		speed = 1,
		length = 0,
		priority = "Unknown",
		weight = 0,
		looped = false,
		timePosition = 0,
	}
	pcall(function()
		values.id = normalizeAnimationId(track.Animation.AnimationId)
		values.speed = round(track.Speed, 5)
		values.length = round(track.Length, 5)
		values.priority = track.Priority.Name
		values.weight = round(track.WeightTarget, 5)
		values.looped = track.Looped
		values.timePosition = round(track.TimePosition, 5)
	end)
	return values
end

local function entitySnapshot(entity)
	local player = entity and Players:GetPlayerFromCharacter(entity)
	local sourceId = State.EntityIds[entity]
	if not sourceId then
		State.EntitySequence = State.EntitySequence + 1
		sourceId = string.format("%s%d", player and "p" or "m", State.EntitySequence)
		State.EntityIds[entity] = sourceId
	end
	return {
		sourceId = sourceId,
		kind = player and "player" or "mob",
		label = player and "player" or tostring(entity and (entity:GetAttribute("MOB_rich_name") or entity.Name) or "unknown"),
	}
end

local function catalogFor(id)
	local catalog = State.Catalog[id]
	if catalog then
		return catalog
	end
	catalog = {
		id = id,
		observations = 0,
		completed = 0,
		cancelled = 0,
		outcomes = {},
		samples = {},
		playback = {},
		durations = {},
		keyframes = {},
		sources = {},
	}
	State.Catalog[id] = catalog
	return catalog
end

local function offenseCatalogFor(id)
	local catalog = State.OffenseCatalog[id]
	if catalog then
		return catalog
	end
	catalog = {
		id = id,
		observations = 0,
		completed = 0,
		outcomes = {},
		samples = {},
		playback = {},
		durations = {},
	}
	State.OffenseCatalog[id] = catalog
	return catalog
end

local function shouldLogAnimation(id, now)
	local schedule = State.RawAnimationSchedule[id]
	if not schedule then
		schedule = { count = 0, last = 0 }
		State.RawAnimationSchedule[id] = schedule
	end
	schedule.count = schedule.count + 1
	if schedule.count <= RAW_ANIMATION_INITIAL_SAMPLES or now - schedule.last >= RAW_ANIMATION_SAMPLE_INTERVAL then
		schedule.last = now
		return true
	end
	return false
end

local function classifyAnimation(sourceId, id, priority, now)
	local activity = State.SourceActivity[sourceId]
	if not activity then
		activity = { recent = {} }
		State.SourceActivity[sourceId] = activity
	end
	local recent = activity.recent
	for index = #recent, 1, -1 do
		if now - recent[index].t > 2.5 then
			table.remove(recent, index)
		end
	end
	if string.find(priority or "", "Action", 1, true) then
		recent[#recent + 1] = { t = now, id = id }
	end
	local counts = {}
	for _, item in ipairs(recent) do
		counts[item.id] = (counts[item.id] or 0) + 1
	end
	local unique = 0
	for _ in pairs(counts) do
		unique = unique + 1
	end
	if #recent >= 20 and unique >= 5 then
		State.SuspiciousAnimations[sourceId] = State.SuspiciousAnimations[sourceId] or {}
		for animationId, count in pairs(counts) do
			if count >= 3 then
				State.SuspiciousAnimations[sourceId][animationId] = true
			end
		end
	end
	return State.SuspiciousAnimations[sourceId] and State.SuspiciousAnimations[sourceId][id] == true
end

local function appendBounded(list, value, maximum)
	list[#list + 1] = value
	if #list > maximum then
		table.remove(list, 1)
	end
end

local function beginAnimation(animator, track)
	if State.Destroyed or not State.Recording then
		return
	end
	local entity = animator:FindFirstAncestorWhichIsA("Model")
	if not entity or entity == LocalPlayer.Character then
		return
	end
	local properties = animationProperties(track)
	if properties.id == "unknown" or properties.id == "" then
		return
	end

	local now = os.clock()
	local geometry = geometrySnapshot(entity)
	local entityInfo = entitySnapshot(entity)
	State.AnimationSequence = State.AnimationSequence + 1
	local attack = {
		seq = State.AnimationSequence,
		startedAt = now,
		endedAt = nil,
		id = properties.id,
		entity = entity,
		entityInfo = entityInfo,
		track = track,
		start = properties,
		geometry = geometry,
		weapon = weaponSnapshot(entity),
		speedSamples = { { t = 0, speed = properties.speed } },
		lastSpeed = properties.speed,
		lastSpeedSample = now,
		lastTimePosition = properties.timePosition,
		outcomes = 0,
	}
	attack.suspicious = classifyAnimation(entityInfo.sourceId, properties.id, properties.priority, now)
	attack.rawLogged = shouldLogAnimation(properties.id, now)
	State.Active[track] = attack
	State.Recent[#State.Recent + 1] = attack
	if #State.Recent > 160 then
		table.remove(State.Recent, 1)
	end
	State.AnimationCount = State.AnimationCount + 1

	local catalog = catalogFor(properties.id)
	catalog.observations = catalog.observations + 1
	local source = catalog.sources[entityInfo.sourceId]
	if not source then
		source = { kind = entityInfo.kind, label = entityInfo.label, observations = 0, suspicious = 0 }
		catalog.sources[entityInfo.sourceId] = source
	end
	source.observations = source.observations + 1
	if attack.suspicious then
		source.suspicious = source.suspicious + 1
	end
	appendBounded(catalog.playback, {
		speed = properties.speed,
		length = properties.length,
		priority = properties.priority,
		distance = geometry and geometry.distance or nil,
		weapon = attack.weapon,
		ping = pingMilliseconds(),
		source = entityInfo,
		suspicious = attack.suspicious,
	}, MAX_SAMPLES_PER_OUTCOME)

	if attack.rawLogged then
		pushEvent("animation_start", {
			animationEventSeq = attack.seq,
			animation = properties,
			entity = entityInfo,
			geometry = geometry,
			weapon = attack.weapon,
			ping = pingMilliseconds(),
			suspicious = attack.suspicious,
		})
	end

	local trackConnections = {}
	local okStopped, stoppedConnection = pcall(function()
		return track.Stopped:Connect(function()
			disconnectMapped(State.TrackConnections, track)
			if State.Destroyed then
				return
			end
			local active = State.Active[track]
			if not active then
				return
			end
			local stoppedAt = os.clock()
			active.endedAt = stoppedAt
			local final = animationProperties(track)
			local elapsed = stoppedAt - active.startedAt
			local observedPosition = math.max(active.lastTimePosition or 0, final.timePosition or 0)
			local speed = math.max(math.abs(active.start.speed or 1), 0.01)
			local expectedDuration = active.start.length > 0 and active.start.length / speed or 0
			local early = not active.start.looped
				and expectedDuration > 0
				and elapsed + 0.06 < expectedDuration
				and observedPosition + 0.06 * speed < active.start.length
			local entry = catalogFor(active.id)
			entry.completed = entry.completed + 1
			if early then
				entry.cancelled = entry.cancelled + 1
			end
			appendBounded(entry.durations, {
				elapsed = round(elapsed, 6),
				early = early,
				observedTimePosition = round(observedPosition, 5),
				speedSamples = active.speedSamples,
			}, MAX_SAMPLES_PER_OUTCOME)
			if active.rawLogged then
				pushEvent("animation_end", {
					animationEventSeq = active.seq,
					animationId = active.id,
					elapsed = round(elapsed, 6),
					early = early,
					observedTimePosition = round(observedPosition, 5),
					final = final,
					speedSamples = active.speedSamples,
				})
			end
			State.Active[track] = nil
		end)
	end)
	if okStopped and stoppedConnection then
		trackConnections[#trackConnections + 1] = stoppedConnection
	end
	local okKeyframe, keyframeConnection = pcall(function()
		return track.KeyframeReached:Connect(function(name)
			local active = State.Active[track]
			if active and not State.Destroyed then
				local elapsed = round(os.clock() - active.startedAt, 6)
				local keyframeName = tostring(name)
				local entry = catalogFor(active.id)
				entry.keyframes[keyframeName] = entry.keyframes[keyframeName] or { count = 0, samples = {} }
				entry.keyframes[keyframeName].count = entry.keyframes[keyframeName].count + 1
				appendBounded(entry.keyframes[keyframeName].samples, elapsed, 48)
				if active.rawLogged then
					pushEvent("animation_keyframe", {
						animationEventSeq = active.seq,
						animationId = active.id,
						name = keyframeName,
						elapsed = elapsed,
						timePosition = animationProperties(track).timePosition,
					})
				end
			end
		end)
	end)
	if okKeyframe and keyframeConnection then
		trackConnections[#trackConnections + 1] = keyframeConnection
	end
	if #trackConnections > 0 then
		State.TrackConnections[track] = trackConnections
	end
end

-- The local mirror is intentionally read-only. It lets the catalog distinguish
-- "APC defended an incoming attack" from "the opponent defended my attack."
local function beginLocalAnimation(track)
	if State.Destroyed or not State.Recording then
		return
	end
	local properties = animationProperties(track)
	if properties.id == "unknown"
		or properties.id == ""
		or not string.find(properties.priority or "", "Action", 1, true)
	then
		return
	end

	local now = os.clock()
	State.AnimationSequence = State.AnimationSequence + 1
	local attack = {
		seq = State.AnimationSequence,
		startedAt = now,
		endedAt = nil,
		id = properties.id,
		track = track,
		start = properties,
		weapon = weaponSnapshot(LocalPlayer.Character),
		lastTimePosition = properties.timePosition,
	}
	attack.rawLogged = shouldLogAnimation("local:" .. properties.id, now)
	State.LocalActive[track] = attack
	appendBounded(State.LocalRecent, attack, 80)
	State.LocalAnimationCount = State.LocalAnimationCount + 1

	local catalog = offenseCatalogFor(properties.id)
	catalog.observations = catalog.observations + 1
	appendBounded(catalog.playback, {
		speed = properties.speed,
		length = properties.length,
		priority = properties.priority,
		weapon = attack.weapon,
		ping = pingMilliseconds(),
	}, MAX_SAMPLES_PER_OUTCOME)

	if attack.rawLogged then
		pushEvent("local_animation_start", {
			animationEventSeq = attack.seq,
			animation = properties,
			weapon = attack.weapon,
			ping = pingMilliseconds(),
		})
	end

	local okStopped, stoppedConnection = pcall(function()
		return track.Stopped:Connect(function()
			disconnectMapped(State.LocalTrackConnections, track)
			if State.Destroyed then
				return
			end
			local active = State.LocalActive[track]
			if not active then
				return
			end
			local stoppedAt = os.clock()
			active.endedAt = stoppedAt
			local final = animationProperties(track)
			local elapsed = stoppedAt - active.startedAt
			local observedPosition = math.max(active.lastTimePosition or 0, final.timePosition or 0)
			local entry = offenseCatalogFor(active.id)
			entry.completed = entry.completed + 1
			appendBounded(entry.durations, {
				elapsed = round(elapsed, 6),
				observedTimePosition = round(observedPosition, 5),
			}, MAX_SAMPLES_PER_OUTCOME)
			if active.rawLogged then
				pushEvent("local_animation_end", {
					animationEventSeq = active.seq,
					animationId = active.id,
					elapsed = round(elapsed, 6),
					observedTimePosition = round(observedPosition, 5),
					final = final,
				})
			end
			State.LocalActive[track] = nil
		end)
	end)
	if okStopped and stoppedConnection then
		State.LocalTrackConnections[track] = stoppedConnection
	end
end

local function attachAnimator(animator)
	if State.AnimatorConnections[animator] then
		return
	end
	local entity = animator:FindFirstAncestorWhichIsA("Model")
	if not entity or entity == LocalPlayer.Character then
		return
	end
	local ok, connection = pcall(function()
		return animator.AnimationPlayed:Connect(function(track)
			beginAnimation(animator, track)
		end)
	end)
	if ok and connection then
		State.AnimatorConnections[animator] = connection
	end
end

local function attachLive(live)
	for _, descendant in ipairs(live:GetDescendants()) do
		if descendant:IsA("Animator") then
			attachAnimator(descendant)
		end
	end
	connect(live.DescendantAdded, function(descendant)
		if descendant:IsA("Animator") then
			attachAnimator(descendant)
		end
	end)
end

local function priorityPenalty(priority)
	if string.find(priority or "", "Action", 1, true) then
		return -0.65
	elseif priority == "Movement" then
		return 1.25
	elseif priority == "Idle" or priority == "Core" then
		return 1.5
	end
	return 0.4
end

local function bestAttack(now)
	local candidates = {}
	for index = #State.Recent, 1, -1 do
		local attack = State.Recent[index]
		local age = now - attack.startedAt
		if age > 3 then
			break
		end
		if age >= 0 then
			local score = age * 0.25 + priorityPenalty(attack.start.priority)
			local distance = attack.geometry and attack.geometry.distance or 0
			score = score + math.max(0, distance - 35) / 75
			local facing = attack.geometry and attack.geometry.facingDot
			if facing and facing < 0 then
				score = score + math.abs(facing) * 0.75
			end
			if attack.endedAt and now - attack.endedAt > 0.35 then
				score = score + 1
			end
			if attack.suspicious then
				score = score + 4
			end
			candidates[#candidates + 1] = {
				attack = attack,
				score = score,
			}
		end
	end
	table.sort(candidates, function(left, right)
		return left.score < right.score
	end)
	local best = candidates[1]
	local snapshots = {}
	for index = 1, math.min(#candidates, 8) do
		local candidate = candidates[index]
		local attack = candidate.attack
		snapshots[#snapshots + 1] = {
			animationEventSeq = attack.seq,
			animationId = attack.id,
			delay = round(now - attack.startedAt, 6),
			score = round(candidate.score, 5),
			priority = attack.start.priority,
			distance = attack.geometry and attack.geometry.distance or nil,
			active = attack.endedAt == nil,
			source = attack.entityInfo,
			suspicious = attack.suspicious,
		}
	end
	return best and best.attack or nil, best and best.score or math.huge, snapshots
end

local lastOutcomeAt = {}

local function recordOutcome(kind, source, detail)
	if State.Destroyed or not State.Recording then
		return
	end
	local now = os.clock()
	local dedupe = tostring(kind) .. ":" .. tostring(source)
	if now - (lastOutcomeAt[dedupe] or 0) < 0.025 then
		return
	end
	lastOutcomeAt[dedupe] = now
	State.OutcomeCount = State.OutcomeCount + 1
	local attack, score, candidates = bestAttack(now)
	local match
	if attack then
		local delay = now - attack.startedAt
		attack.outcomes = attack.outcomes + 1
		State.LinkedCount = State.LinkedCount + 1
		match = {
			animationEventSeq = attack.seq,
			animationId = attack.id,
			delay = round(delay, 6),
			score = round(score, 5),
			startSpeed = attack.start.speed,
			length = attack.start.length,
			distance = attack.geometry and attack.geometry.distance or nil,
			weapon = attack.weapon,
			ping = pingMilliseconds(),
			outcomeGeometry = geometrySnapshot(attack.entity),
			source = attack.entityInfo,
			suspicious = attack.suspicious,
		}
		local catalog = catalogFor(attack.id)
		catalog.outcomes[kind] = (catalog.outcomes[kind] or 0) + 1
		catalog.samples[kind] = catalog.samples[kind] or {}
		appendBounded(catalog.samples[kind], match, MAX_SAMPLES_PER_OUTCOME)
	end
	State.LastOutcome = {
		kind = kind,
		animationId = match and match.animationId or nil,
		delay = match and match.delay or nil,
		at = now,
	}
	pushEvent("outcome", {
		kind = kind,
		source = source,
		detail = scalarSnapshot(detail),
		match = match,
		candidates = candidates,
	})
end

local function bestLocalAttack(now)
	local candidates = {}
	for index = #State.LocalRecent, 1, -1 do
		local attack = State.LocalRecent[index]
		local age = now - attack.startedAt
		if age > 3 then
			break
		end
		if age >= 0 then
			local score = age * 0.35
			if attack.endedAt and now - attack.endedAt > 0.4 then
				score = score + 1
			end
			candidates[#candidates + 1] = { attack = attack, score = score }
		end
	end
	table.sort(candidates, function(left, right)
		return left.score < right.score
	end)
	local best = candidates[1]
	local snapshots = {}
	for index = 1, math.min(#candidates, 6) do
		local candidate = candidates[index]
		local attack = candidate.attack
		snapshots[#snapshots + 1] = {
			animationEventSeq = attack.seq,
			animationId = attack.id,
			delay = round(now - attack.startedAt, 6),
			score = round(candidate.score, 5),
			priority = attack.start.priority,
			active = attack.endedAt == nil,
		}
	end
	return best and best.attack or nil, best and best.score or math.huge, snapshots
end

local function recordOffenseOutcome(kind, source, detail)
	if State.Destroyed or not State.Recording then
		return
	end
	local now = os.clock()
	local dedupe = "offense:" .. tostring(kind) .. ":" .. tostring(source)
	if now - (lastOutcomeAt[dedupe] or 0) < 0.025 then
		return
	end
	lastOutcomeAt[dedupe] = now
	State.OffenseOutcomeCount = State.OffenseOutcomeCount + 1
	local attack, score, candidates = bestLocalAttack(now)
	local match
	if attack then
		State.OffenseLinkedCount = State.OffenseLinkedCount + 1
		match = {
			animationEventSeq = attack.seq,
			animationId = attack.id,
			delay = round(now - attack.startedAt, 6),
			score = round(score, 5),
			startSpeed = attack.start.speed,
			length = attack.start.length,
			weapon = attack.weapon,
			ping = pingMilliseconds(),
		}
		local catalog = offenseCatalogFor(attack.id)
		catalog.outcomes[kind] = (catalog.outcomes[kind] or 0) + 1
		catalog.samples[kind] = catalog.samples[kind] or {}
		appendBounded(catalog.samples[kind], match, MAX_SAMPLES_PER_OUTCOME)
	end
	State.LastOffenseOutcome = {
		kind = kind,
		animationId = match and match.animationId or nil,
		delay = match and match.delay or nil,
		at = now,
	}
	pushEvent("offense_outcome", {
		kind = kind,
		source = source,
		detail = scalarSnapshot(detail),
		match = match,
		candidates = candidates,
	})
end

local EFFECT_OUTCOMES = {
	ParryCool = "parry_attempt",
	ParryFrame = "parry_frame",
	Parry = "parry_signal",
	ParrySuccess = "parry_success",
	Blocking = "block_state",
	Stun = "stun",
	Knocked = "knocked",
	Dodge = "dodge_signal",
	Dodged = "dodge_signal",
	DodgeFrame = "dodge_frame",
	Immortal = "iframe",
}

local TRACKED_EFFECTS = {
	ParryCool = true,
	ParryFrame = true,
	Parry = true,
	ParrySuccess = true,
	Parried = true,
	AutoParry = true,
	Blocking = true,
	ExtraBlocking = true,
	GenerousParry = true,
	Stun = true,
	Knocked = true,
	Ragdoll = true,
	Dodge = true,
	Dodged = true,
	DodgeFrame = true,
	Immortal = true,
	NoRoll = true,
	PreventRoll = true,
	RollCancelled = true,
	LightAttack = true,
	LandedLightAttack = true,
	MantraCasted = true,
	MidAttack = true,
	UsingSpell = true,
	UsingAbility = true,
	FeintIntent = true,
	FeintCool = true,
	CancelAnim = true,
	WeaponEndlag = true,
	M1Buffer = true,
}

local function effectClass(effect)
	local ok, class = pcall(function()
		return effect.Class
	end)
	return ok and tostring(class or "") or ""
end

local function attachEffects()
	local moduleScript = ReplicatedStorage:FindFirstChild("EffectReplicator")
	if not moduleScript then
		State.EffectStatus = "missing"
		return
	end
	local ok, effects = pcall(require, moduleScript)
	if not ok or type(effects) ~= "table" then
		State.EffectStatus = "require failed"
		return
	end
	State.EffectStatus = "connected"
	connect(effects.EffectAdded, function(effect)
		local class = effectClass(effect)
		State.EffectCounts[class] = (State.EffectCounts[class] or 0) + 1
		if effect ~= nil then
			State.EffectLifetimes[effect] = { class = class, startedAt = os.clock() }
		end
		if TRACKED_EFFECTS[class] then
			pushEvent("effect_added", { class = class, data = scalarSnapshot(effect) })
		elseif not State.EffectClassesSeen[class] then
			State.EffectClassesSeen[class] = true
			pushEvent("effect_class_seen", { class = class })
		end
		local outcome = EFFECT_OUTCOMES[class]
		if outcome then
			recordOutcome(outcome, "effect:" .. class, { class = class })
		end
		if class == "Parried" then
			recordOffenseOutcome("local_attack_parried", "effect:Parried", { class = class })
		elseif class == "LandedLightAttack" then
			recordOffenseOutcome("local_attack_landed", "effect:LandedLightAttack", { class = class })
		end
	end)
	connect(effects.EffectRemoved, function(effect)
		local lifetime = effect ~= nil and State.EffectLifetimes[effect] or nil
		if effect ~= nil then
			State.EffectLifetimes[effect] = nil
		end
		local class = effectClass(effect)
		if TRACKED_EFFECTS[class] then
			pushEvent("effect_removed", {
				class = class,
				duration = lifetime and round(os.clock() - lifetime.startedAt, 6) or nil,
				data = scalarSnapshot(effect),
			})
		end
	end)
	for _, effect in pairs(effects.Effects or {}) do
		local class = effectClass(effect)
		State.EffectClassesSeen[class] = true
		pushEvent("effect_present", { class = class, data = scalarSnapshot(effect) })
	end
end

local watchedMeters = setmetatable({}, { __mode = "k" })

local function watchMeter(instance)
	if watchedMeters[instance] or not instance:IsA("ValueBase") then
		return
	end
	local lower = string.lower(instance.Name)
	if not string.find(lower, "break", 1, true) and not string.find(lower, "posture", 1, true) then
		return
	end
	watchedMeters[instance] = true
	local last = instance.Value
	connect(instance.Changed, function(value)
		local previousValue = last
		last = value
		pushEvent("meter_change", {
			name = instance.Name,
			from = scalarSnapshot(previousValue),
			to = scalarSnapshot(value),
		})
		recordOutcome("posture_change", "value:" .. instance.Name, { from = previousValue, to = value })
	end, State.CharacterConnections)
end

local function attachCharacter(character)
	disconnectAll(State.CharacterConnections)
	for track in pairs(State.LocalTrackConnections) do
		disconnectMapped(State.LocalTrackConnections, track)
	end
	table.clear(State.LocalActive)
	table.clear(State.LocalRecent)
	table.clear(watchedMeters)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid then
		local animator = humanoid:FindFirstChildWhichIsA("Animator") or humanoid:WaitForChild("Animator", 5)
		if animator then
			connect(animator.AnimationPlayed, beginLocalAnimation, State.CharacterConnections)
		end
		local lastHealth = humanoid.Health
		connect(humanoid.HealthChanged, function(health)
			local previousHealth = lastHealth
			lastHealth = health
			local delta = health - previousHealth
			if delta < 0 or delta >= 1 then
				pushEvent("health_change", {
					from = round(previousHealth, 4),
					to = round(health, 4),
					delta = round(delta, 4),
				})
			end
			if delta < 0 then
				local damage = round(-delta, 4)
				recordOutcome("health_hit", "humanoid", {
					damage = damage,
					health = round(health, 4),
					classification = damage < 2 and "chip_or_dot" or "impact_candidate",
				})
			end
		end, State.CharacterConnections)
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		watchMeter(descendant)
	end
	connect(character.DescendantAdded, function(descendant)
		watchMeter(descendant)
		if string.sub(descendant.Name, 1, 10) == "REP_SOUND_" then
			pushEvent("local_sound", { name = descendant.Name })
		end
	end, State.CharacterConnections)
end

local function attachClientEffects()
	local requests = ReplicatedStorage:FindFirstChild("Requests")
	if not requests then
		return
	end
	for _, channel in ipairs({ "ClientEffect", "ClientEffectLarge", "ClientEffectDirect" }) do
		local remote = requests:FindFirstChild(channel)
		if remote and remote:IsA("RemoteEvent") then
			connect(remote.OnClientEvent, function(name, data)
				pushEvent("client_effect", {
					channel = channel,
					name = tostring(name or ""),
					data = scalarSnapshot(data),
				})
			end)
		end
	end
end

local function exportCatalog()
	return {
		version = 3,
		recorderVersion = State.Version,
		session = {
			id = SESSION_ID,
			startedUnix = SESSION_STARTED_UNIX,
			placeId = game.PlaceId,
			duration = relativeTime(),
			animations = State.AnimationCount,
			localAnimations = State.LocalAnimationCount,
			outcomes = State.OutcomeCount,
			offenseOutcomes = State.OffenseOutcomeCount,
			linked = State.LinkedCount,
			offenseLinked = State.OffenseLinkedCount,
			dropped = State.DroppedCount,
		},
		effectCounts = State.EffectCounts,
		suspiciousAnimations = State.SuspiciousAnimations,
		catalog = State.Catalog,
		offenseCatalog = State.OffenseCatalog,
	}
end

local function writeJSON(path, value)
	if not writefile then
		return false, "writefile unavailable"
	end
	local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, value)
	if not okEncode then
		return false, tostring(encoded)
	end
	local okWrite, reason = pcall(writefile, path, encoded)
	return okWrite, okWrite and #encoded or tostring(reason)
end

local function saveSummary()
	local catalogOK, catalogDetail = writeJSON(SESSION_PATH .. "/catalog.json", exportCatalog())
	local manifestOK, manifestDetail = writeJSON(SESSION_PATH .. "/manifest.json", {
		version = 2,
		sessionId = SESSION_ID,
		path = SESSION_PATH,
		chunks = State.Chunks,
		liveFile = "events_live.json",
		liveEventCount = #State.Buffer,
		eventCount = State.Sequence,
		animationCount = State.AnimationCount,
		outcomeCount = State.OutcomeCount,
		linkedCount = State.LinkedCount,
		updatedUnix = os.time(),
	})
	State.LastSave = os.clock()
	State.FileStatus = catalogOK and manifestOK and "saved" or "partial save"
	State.LastError = (not catalogOK and catalogDetail) or (not manifestOK and manifestDetail) or nil
	return catalogOK and manifestOK
end

checkpoint = function(reason)
	if State.Checkpointing or State.Flushing or not writefile then
		return false
	end
	State.Checkpointing = true
	ensureFolders()
	local liveOK, liveDetail = writeJSON(SESSION_PATH .. "/events_live.json", {
		version = 2,
		sessionId = SESSION_ID,
		reason = reason,
		events = State.Buffer,
	})
	local summaryOK = saveSummary()
	State.Checkpointing = false
	if not liveOK then
		State.LastError = liveDetail
		State.FileStatus = "checkpoint failed"
	end
	return liveOK and summaryOK
end

flush = function(reason)
	if State.Flushing or #State.Buffer == 0 then
		return false, State.Flushing and "flush already running" or "buffer empty"
	end
	if not writefile then
		State.FileStatus = "clipboard only"
		return false, "writefile unavailable"
	end
	State.Flushing = true
	ensureFolders()
	local pending = State.Buffer
	State.Buffer = {}
	State.ChunkSequence = State.ChunkSequence + 1
	local chunkName = string.format("events_%04d.json", State.ChunkSequence)
	local chunkPath = SESSION_PATH .. "/" .. chunkName
	local ok, detail = writeJSON(chunkPath, {
		version = 1,
		sessionId = SESSION_ID,
		chunk = State.ChunkSequence,
		reason = reason,
		events = pending,
	})
	if not ok then
		local restored = pending
		for _, event in ipairs(State.Buffer) do
			restored[#restored + 1] = event
		end
		State.Buffer = restored
		State.ChunkSequence = State.ChunkSequence - 1
		State.LastError = detail
		State.FileStatus = "save failed"
		State.Flushing = false
		return false, detail
	end
	State.Chunks[#State.Chunks + 1] = chunkName
	writeJSON(SESSION_PATH .. "/events_live.json", {
		version = 2,
		sessionId = SESSION_ID,
		reason = "rotated",
		events = {},
	})
	local summaryOK = saveSummary()
	State.Flushing = false
	return summaryOK, detail
end

-- Small, non-modal, input-transparent HUD.
local Gui = Instance.new("ScreenGui")
Gui.Name = "_ClawRecorder"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local guiParent
pcall(function()
	if gethui then
		guiParent = gethui()
	end
end)
guiParent = guiParent or LocalPlayer:WaitForChild("PlayerGui")
local oldGui = guiParent:FindFirstChild(Gui.Name)
if oldGui then
	oldGui:Destroy()
end
Gui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(360, 186)
Main.Position = UDim2.fromOffset(18, 86)
Main.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
Main.BorderColor3 = Color3.fromRGB(95, 75, 145)
Main.BorderSizePixel = 1
Main.Active = false
Main.Parent = Gui

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 28)
Header.BackgroundColor3 = Color3.fromRGB(26, 27, 34)
Header.BorderSizePixel = 0
Header.Active = true
Header.Parent = Main

local function label(parent, text, x, y, width, height, size, color)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromOffset(x, y)
	item.Size = UDim2.fromOffset(width, height)
	item.Font = Enum.Font.Code
	item.Text = text
	item.TextSize = size or 13
	item.TextColor3 = color or Color3.fromRGB(220, 220, 225)
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

local function button(parent, text, x, y, width, callback)
	local item = Instance.new("TextButton")
	item.Position = UDim2.fromOffset(x, y)
	item.Size = UDim2.fromOffset(width, 25)
	item.BackgroundColor3 = Color3.fromRGB(38, 39, 48)
	item.BorderColor3 = Color3.fromRGB(72, 73, 88)
	item.Font = Enum.Font.Code
	item.Text = text
	item.TextSize = 12
	item.TextColor3 = Color3.fromRGB(225, 225, 230)
	item.AutoButtonColor = true
	item.Parent = parent
	connect(item.MouseButton1Click, callback)
	return item
end

label(Header, "CLAW RECORDER v0.3", 9, 0, 230, 28, 13, Color3.fromRGB(189, 151, 255))
local Close = button(Header, "X", 327, 2, 27, function()
	State:Destroy()
end)
Close.Size = UDim2.fromOffset(27, 23)
Close.BackgroundColor3 = Color3.fromRGB(92, 43, 49)

local Status = label(Main, "", 10, 34, 340, 20, 12)
local Counters = label(Main, "", 10, 55, 340, 20, 12)
local Detail = label(Main, "", 10, 76, 340, 20, 11, Color3.fromRGB(170, 170, 180))
local Path = label(Main, "", 10, 98, 340, 20, 10, Color3.fromRGB(135, 180, 145))

local PauseButton
PauseButton = button(Main, "PAUSE", 10, 128, 78, function()
	State.Recording = not State.Recording
	PauseButton.Text = State.Recording and "PAUSE" or "RESUME"
end)
button(Main, "SAVE NOW", 96, 128, 82, function()
	flush("manual")
end)
button(Main, "COPY PATH", 186, 128, 78, function()
	if setclipboard then
		pcall(setclipboard, SESSION_PATH)
	end
end)
button(Main, "COPY CATALOG", 272, 128, 78, function()
	if setclipboard then
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, exportCatalog())
		if ok then
			pcall(setclipboard, encoded)
		end
	end
end)

label(Main, "Observer only • no combat/input/animation writes", 10, 158, 340, 20, 10, Color3.fromRGB(125, 125, 140))

do
	local dragging = false
	local startMouse
	local startPosition
	connect(Header.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			startMouse = input.Position
			startPosition = Main.Position
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - startMouse
			Main.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

local lastStep = 0
connect(RunService.Heartbeat, function()
	if State.Destroyed then
		return
	end
	local now = os.clock()
	if now - lastStep < 0.1 then
		return
	end
	lastStep = now
	for track, attack in pairs(State.Active) do
		if now - attack.startedAt > MAX_ACTIVE_AGE then
			State.Active[track] = nil
		else
			local properties = animationProperties(track)
			attack.lastTimePosition = math.max(attack.lastTimePosition or 0, properties.timePosition or 0)
			if math.abs(properties.speed - attack.lastSpeed) > 0.001 and now - attack.lastSpeedSample >= 0.05 then
				attack.lastSpeed = properties.speed
				attack.lastSpeedSample = now
				appendBounded(attack.speedSamples, {
					t = round(now - attack.startedAt, 5),
					speed = properties.speed,
				}, 24)
				if attack.rawLogged then
					pushEvent("animation_speed", {
						animationEventSeq = attack.seq,
						animationId = attack.id,
						elapsed = round(now - attack.startedAt, 6),
						speed = properties.speed,
					})
				end
			end
		end
	end
	for track, attack in pairs(State.LocalActive) do
		if now - attack.startedAt > MAX_ACTIVE_AGE then
			State.LocalActive[track] = nil
		else
			local properties = animationProperties(track)
			attack.lastTimePosition = math.max(attack.lastTimePosition or 0, properties.timePosition or 0)
		end
	end
	for index = #State.Recent, 1, -1 do
		if now - State.Recent[index].startedAt > 6 then
			table.remove(State.Recent, index)
		end
	end
	for index = #State.LocalRecent, 1, -1 do
		if now - State.LocalRecent[index].startedAt > 6 then
			table.remove(State.LocalRecent, index)
		end
	end
	for track in pairs(State.TrackConnections) do
		if not State.Active[track] or now - State.Active[track].startedAt > MAX_ACTIVE_AGE then
			State.Active[track] = nil
			disconnectMapped(State.TrackConnections, track)
		end
	end
	for track in pairs(State.LocalTrackConnections) do
		if not State.LocalActive[track] or now - State.LocalActive[track].startedAt > MAX_ACTIVE_AGE then
			State.LocalActive[track] = nil
			disconnectMapped(State.LocalTrackConnections, track)
		end
	end
	for animator, connection in pairs(State.AnimatorConnections) do
		if animator.Parent == nil then
			pcall(function()
				connection:Disconnect()
			end)
			State.AnimatorConnections[animator] = nil
		end
	end
	if writefile and now - State.LastSave >= AUTOSAVE_INTERVAL then
		checkpoint("autosave")
	end

	Status.Text = string.format(
		"%s  |  effects:%s  |  files:%s",
		State.Recording and "RECORDING" or "PAUSED",
		State.EffectStatus,
		State.FileStatus
	)
	Status.TextColor3 = State.Recording and Color3.fromRGB(112, 210, 133) or Color3.fromRGB(220, 178, 92)
	Counters.Text = string.format(
		"enemy:%d/%d  local:%d/%d  defense:%d  reply:%d",
		State.AnimationCount,
		catalogCount(),
		State.LocalAnimationCount,
		offenseCatalogCount(),
		State.OutcomeCount,
		State.OffenseOutcomeCount
	)
	local last = State.LastOutcome
	if State.LastOffenseOutcome and (not last or (State.LastOffenseOutcome.at or 0) > (last.at or 0)) then
		last = State.LastOffenseOutcome
	end
	Detail.Text = last and string.format(
		"last: %s  %s  %s",
		last.kind,
		last.animationId or "unlinked",
		last.delay and string.format("@ %.3fs", last.delay) or ""
	) or "last: waiting for combat outcome"
	Path.Text = "device: " .. SESSION_PATH .. "/catalog.json"
end)

connect(LocalPlayer.CharacterAdded, attachCharacter)
if LocalPlayer.Character then
	task.spawn(attachCharacter, LocalPlayer.Character)
end

local live = workspace:FindFirstChild("Live")
if live then
	attachLive(live)
end
connect(workspace.ChildAdded, function(child)
	if child.Name == "Live" then
		attachLive(child)
	end
end)

attachEffects()
attachClientEffects()

function State:Destroy()
	if self.Destroyed then
		return
	end
	if #self.Buffer > 0 then
		flush("unload")
	end
	self.Destroyed = true
	disconnectAll(self.CharacterConnections)
	disconnectAll(self.Connections)
	for track in pairs(self.TrackConnections) do
		disconnectMapped(self.TrackConnections, track)
	end
	for track in pairs(self.LocalTrackConnections) do
		disconnectMapped(self.LocalTrackConnections, track)
	end
	for animator, connection in pairs(self.AnimatorConnections) do
		pcall(function()
			connection:Disconnect()
		end)
		self.AnimatorConnections[animator] = nil
	end
	pcall(function()
		Gui:Destroy()
	end)
	if ENV.__CLAW_RECORDER == self then
		ENV.__CLAW_RECORDER = nil
	end
	print("[CLAW RECORDER] unloaded; catalog:", SESSION_PATH .. "/catalog.json")
end

pushEvent("session_start", {
	version = State.Version,
	placeId = game.PlaceId,
	filesystem = writefile ~= nil,
})

print("[CLAW RECORDER] recording to", SESSION_PATH)
return State
