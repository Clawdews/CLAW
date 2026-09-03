--==============================================================
--  CLAW MARK v0.4.0
--
--  TABS
--    BURSTER
--    LOGGED ANIMS
--    LIVE / RECENT
--    GHOST FIRE
--    WEBHOOK
--
--  IMPORTANT v6 CHANGES
--
--  BURSTER
--    • Exact fire speed
--    • Optional DELAYED VISUAL replay
--
--      Real track starts
--          ↓
--      hidden + accelerated
--          ↓
--      attack/markers advance quickly
--          ↓
--      rewind
--          ↓
--      wait Visual Delay
--          ↓
--      visible animation plays at Visual Speed
--
--    Defaults:
--      Burster and every rule OFF
--
--  GHOST FIRE
--    • Strict serial mode
--    • Core priority by default
--    • Automatic profile speed / target weight
--    • Explicit CORE / ACTION / LEARN priority test modes
--    • Extremely low visible-weight cap
--    • Huge calculated fade
--    • Hard visual guard
--    • Minimum gap between ghosts
--
--  INSPECTOR
--    • Local or remote player target
--    • Searchable historical logs
--    • Clear
--    • Profile stats
--    • Live + recently vanished tracks
--
--  WEBHOOK
--    • Detects existing getgenv().Loot API
--    • Test / flush existing Loot notifier
--    • Optional standalone webhook sender
--    • Webhook textbox masks itself after setting
--
--  MENU
--    • Change UI keybind
--    • Hide
--    • Reset position
--    • Stop Ghost
--    • Unload
--
--==============================================================

local ENV = getgenv and getgenv() or _G

------------------------------------------------------------
-- Destroy previous copy
------------------------------------------------------------

local previousRuntime =
	ENV.__CLAW_MARK
	or ENV.__ANIM_LAB_V6

if previousRuntime then
	pcall(function()
		previousRuntime:Destroy()
	end)
end

------------------------------------------------------------
-- Services
------------------------------------------------------------

local Players =
	game:GetService("Players")

local UIS =
	game:GetService("UserInputService")

local RunService =
	game:GetService("RunService")

local HttpService =
	game:GetService("HttpService")

local LP =
	Players.LocalPlayer

------------------------------------------------------------
-- Persistent user preferences
------------------------------------------------------------

ENV.__CLAW_MARK_PREFS =
	ENV.__CLAW_MARK_PREFS
	or ENV.__ANIM_LAB_PREFS
	or {
		UIKey = "RightShift",
		UIPosition = nil,
		ActivePage = "BURSTER",
		SelectedAnimation = "7318254065",
		WebhookURL = "",
		WebhookUsername = "CLAW MARK",
		WebhookUserID = "",
	}

local PREFS =
	ENV.__CLAW_MARK_PREFS

-- Compatibility alias for existing user preferences. New code uses CLAW MARK.
ENV.__ANIM_LAB_PREFS =
	PREFS

------------------------------------------------------------
-- Capture available request implementation
------------------------------------------------------------

local function getRequestImplementation()

	--------------------------------------------------------
	-- Resolve this at send time. Some loaders install their
	-- request function after this script has started.
	--------------------------------------------------------

	local synAPI =
		rawget(ENV, "syn")

	local fluxusAPI =
		rawget(ENV, "fluxus")

	local httpAPI =
		rawget(ENV, "http")

	local candidates = {}

	local function addCandidate(candidate)

		if type(candidate) == "function" then
			table.insert(
				candidates,
				candidate
			)
		end
	end

	addCandidate(
		type(synAPI) == "table"
			and synAPI.request
			or nil
	)

	addCandidate(
		type(fluxusAPI) == "table"
			and fluxusAPI.request
			or nil
	)

	addCandidate(
		type(httpAPI) == "table"
			and httpAPI.request
			or nil
	)

	addCandidate(
		rawget(ENV, "http_request")
	)

	addCandidate(
		rawget(ENV, "request")
	)

	for _, candidate
		in ipairs(candidates)
	do
		if type(candidate) == "function" then
			return candidate
		end
	end

	return nil
end

------------------------------------------------------------
-- Resolve the pre-loader Loot bridge
------------------------------------------------------------

local function getLootAPI()

	local candidates = {}

	local function addCandidate(candidate)
		if
			type(candidate) == "table"
			and
			(
				type(candidate.notify) == "function"
				or type(candidate.text) == "function"
			)
		then
			table.insert(candidates, candidate)
		end
	end

	addCandidate(
		rawget(ENV, "__ANIM_LAB_LOOT")
	)

	pcall(function()
		addCandidate(
			type(shared) == "table"
				and shared.__ANIM_LAB_LOOT
				or nil
		)
	end)

	pcall(function()
		addCandidate(
			type(_G) == "table"
				and _G.__ANIM_LAB_LOOT
				or nil
		)
	end)

	-- Keep the traditional public name as a fallback. The private bridge is
	-- checked first because another loaded script may reuse the generic name.
	addCandidate(
		rawget(ENV, "Loot")
	)

	for _, candidate in ipairs(candidates) do
		if type(candidate) == "table" then
			return candidate
		end
	end

	return nil
end

------------------------------------------------------------
-- Priority map
------------------------------------------------------------

local PRIORITIES = {
	Core = Enum.AnimationPriority.Core,
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
	Action3 = Enum.AnimationPriority.Action3,
	Action4 = Enum.AnimationPriority.Action4,
}

------------------------------------------------------------
-- Config
------------------------------------------------------------

local CONFIG = {

	UIKey =
		PREFS.UIKey
		or "RightShift",

	--------------------------------------------------------
	-- Burster
	--------------------------------------------------------

	BursterMaster = false,

	BurstRules = {

		["7318254065"] = {

			name = "Critical",

			enabled = false,

			-- fast hidden phase
			fireSpeed = 3.00,

			-- how long the REAL animation gets to run fast
			fireWindow = 0.060,

			-- Experimental delayed replay looked detached from
			-- the hit. Keep the proven simple 3x path default.
			visualReplay = false,

			-- pause between fast phase and visual phase
			visualDelay = 0.080,

			-- normal-looking playback
			visualSpeed = 1.00,

			visualFade = 0.015,
		},

		["9484850093"] = {

			name = "Flourish",

			enabled = false,

			fireSpeed = 3.00,

			fireWindow = 0.045,

			visualReplay = false,

			visualDelay = 0.065,

			visualSpeed = 0.79,

			visualFade = 0.015,
		},

		["7600450739"] = {

			name = "M1 A",

			enabled = false,

			fireSpeed = 3.00,

			fireWindow = 0.040,

			visualReplay = false,

			visualDelay = 0.060,

			visualSpeed = 0.75,

			visualFade = 0.015,
		},

		["7600485223"] = {

			name = "M1 B",

			enabled = false,

			fireSpeed = 3.00,

			fireWindow = 0.040,

			visualReplay = false,

			visualDelay = 0.060,

			visualSpeed = 0.75,

			visualFade = 0.015,
		},
	},

	--------------------------------------------------------
	-- Inspector
	--------------------------------------------------------

	LoggingEnabled = false,

	PollRate = 0.025,

	RecentTTL = 1.50,

	--------------------------------------------------------
	-- Ghost
	--------------------------------------------------------

	Ghost = {

		AutoProfile = true,

		----------------------------------------------------
		-- IMPORTANT:
		--
		-- CORE is the visually conservative default. ACTION is
		-- an explicit compatibility test for defenders that discard
		-- Core-priority tracks. LEARN remains opt-in.
		--
		-- PR was often using Action animations, but Action
		-- is exactly what makes tiny blend weights visually
		-- noticeable against idle/movement.
		--
		-- Core keeps the track legitimate while letting
		-- ordinary character animation visually dominate.
		----------------------------------------------------

		UseLearnedPriority = false,

		Priority = "Core",

		UseLearnedLooped = false,

		----------------------------------------------------
		-- Manual fallback
		----------------------------------------------------

		Speed = 0.55,

		Lifetime = 0.022,

		TargetWeight = 1.60,

		----------------------------------------------------
		-- Actual visible contribution threshold
		----------------------------------------------------

		VisibleCap = 0.000020,

		----------------------------------------------------
		-- Briefly preserve lower-body Motor6D transforms
		-- while a Ghost track is alive. The guard also logs
		-- the largest pose delta it intercepted.
		----------------------------------------------------

		LegGuard = true,

		----------------------------------------------------
		-- Blend calculation
		----------------------------------------------------

		FadeSafety = 2.25,

		MinFade = 500,

		MaxFade = 5000,

		----------------------------------------------------
		-- Auto-profile lifetime is NEVER allowed to make
		-- ghosts remain around for a normal full animation.
		----------------------------------------------------

		AutoLifeCap = 0.030,

		----------------------------------------------------
		-- Pool
		----------------------------------------------------

		Interval = 0.050,

		Gap = 0.012,

		RandomOrder = false,

		----------------------------------------------------
		-- optional randomization
		----------------------------------------------------

		SpeedJitter = 0,

		WeightJitter = 0,
	},

	--------------------------------------------------------
	-- Webhook
	--------------------------------------------------------

	Webhook = {

		URL =
			PREFS.WebhookURL
			or "",

		Username =
			PREFS.WebhookUsername
			or "CLAW MARK",

		UserID =
			PREFS.WebhookUserID
			or "",
	},
}

------------------------------------------------------------
-- State
------------------------------------------------------------

local State = {

	Destroyed = false,

	Connections = {},

	TargetConnections = {},

	--------------------------------------------------------
	-- Animator state
	--------------------------------------------------------

	LocalAnimator = nil,

	LocalAnimatorConnection = nil,

	TargetPlayer = LP,

	TargetAnimator = nil,

	TargetAnimatorConnection = nil,

	--------------------------------------------------------
	-- Inspector
	--------------------------------------------------------

	Selected =
		type(PREFS.SelectedAnimation) == "string"
			and string.match(PREFS.SelectedAnimation, "%d+")
			or "7318254065",

	Profiles = {},

	LogRows = {},

	TrackTokens =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	LiveRows =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	LastSeen =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	--------------------------------------------------------
	-- Burster
	--------------------------------------------------------

	BurstTokens =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	--------------------------------------------------------
	-- Ghost
	--------------------------------------------------------

	GhostPool = {},

	GhostRunning = false,

	GhostToken = 0,

	OwnGhostTracks =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	ActiveGhosts =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	GhostPoseGuards =
		setmetatable(
			{},
			{ __mode = "k" }
		),

	LastGhostDiagnostic = nil,

	GhostExperiments = {},

	GhostExperimentSequence = 0,

	--------------------------------------------------------
	-- UI
	--------------------------------------------------------

	MouseHover = false,

	OldMouseIcon = nil,

	OldMouseBehavior = nil,

	Minimized = false,

	ActivePage = nil,

	StatusNotice = nil,
}

ENV.__CLAW_MARK =
	State

-- Compatibility alias for scripts that were written against v6.
ENV.__ANIM_LAB_V6 =
	State

local CombatModule =
	ENV.__CLAW_MODULES
	and ENV.__CLAW_MODULES[
		"src/Combat/init.lua"
	]

if CombatModule then
	local ok, combatOrError =
		pcall(function()
			local combat = CombatModule.new()
			combat:start()
			return combat
		end)

	if ok then
		State.Combat = combatOrError
		if ENV.CLAW then
			ENV.CLAW.Combat = combatOrError
		end
	else
		warn("[CLAW] Combat runtime failed to start:", combatOrError)
	end
end

------------------------------------------------------------
-- UI forward reference
------------------------------------------------------------

local UI = {}

------------------------------------------------------------
-- Connections
------------------------------------------------------------

local function bind(signal, fn)

	local c =
		signal:Connect(fn)

	table.insert(
		State.Connections,
		c
	)

	return c
end

local function bindTarget(signal, fn)

	local c =
		signal:Connect(fn)

	table.insert(
		State.TargetConnections,
		c
	)

	return c
end

local function disconnectList(list)

	for _, c
		in ipairs(list)
	do

		pcall(function()
			c:Disconnect()
		end)
	end

	table.clear(list)
end

------------------------------------------------------------
-- Generic helpers
------------------------------------------------------------

local function cleanId(value)

	return
		tostring(
			value or ""
		):match("(%d+)")
end

local function getId(track)

	local ok, id =
		pcall(function()

			return
				track.Animation.AnimationId
		end)

	if not ok then
		return nil
	end

	return cleanId(id)
end

local function safe(fn, fallback)

	local ok, result =
		pcall(fn)

	if ok then
		return result
	end

	return fallback
end

local function clampNumber(
	value,
	minimum,
	maximum,
	fallback
)

	value =
		tonumber(value)

	if not value then
		return fallback
	end

	return
		math.clamp(
			value,
			minimum,
			maximum
		)
end

local function jitter(
	value,
	amount
)

	if not amount
		or amount <= 0
	then
		return value
	end

	return
		value
		+
		(
			(math.random() * 2 - 1)
			* amount
		)
end

------------------------------------------------------------
-- Profile
------------------------------------------------------------

local function makeProfile(id, track)

	local profile = {

		id = id,

		name =
			tostring(
				track.Name
				or "Animation"
			),

		count = 0,

		length = 0,

		speedLast = 0,

		speedMin = math.huge,

		speedMax = 0,

		speedSum = 0,

		speedCount = 0,

		lifeSum = 0,

		lifeCount = 0,

		lifeMin = math.huge,

		lifeMax = 0,

		weightTargetLast = 0,

		weightTargetMax = 0,

		weightCurrentMax = 0,

		priorities = {},

		loopTrue = 0,

		loopFalse = 0,

		lastSeen = os.clock(),
	}

	State.Profiles[id] =
		profile

	return profile
end

local function avgSpeed(profile)

	if
		not profile
		or profile.speedCount == 0
	then
		return 0
	end

	return
		profile.speedSum
		/
		profile.speedCount
end

local function avgLife(profile)

	if
		not profile
		or profile.lifeCount == 0
	then
		return 0
	end

	return
		profile.lifeSum
		/
		profile.lifeCount
end

local function modePriority(profile)

	if not profile then
		return "Action"
	end

	local best =
		"Action"

	local bestCount =
		-1

	for name, count
		in pairs(
			profile.priorities
		)
	do

		if count > bestCount then

			best =
				name

			bestCount =
				count
		end
	end

	return best
end

local function profileLooped(profile)

	if not profile then
		return false
	end

	return
		profile.loopTrue
		>
		profile.loopFalse
end

------------------------------------------------------------
-- Burst rule
------------------------------------------------------------

local function getBurstRule(id)

	if not CONFIG.BurstRules[id] then

		local profile =
			State.Profiles[id]

		local observedSpeed =
			profile
			and avgSpeed(profile)
			or 1

		CONFIG.BurstRules[id] = {

			name =
				profile
				and profile.name
				or "Animation",

			enabled = false,

			fireSpeed =
				math.max(
					observedSpeed,
					1
				),

			fireWindow =
				0.050,

			visualReplay =
				false,

			visualDelay =
				0.075,

			visualSpeed =
				observedSpeed > 0
				and observedSpeed
				or 1,

			visualFade =
				0.015,
		}
	end

	return
		CONFIG.BurstRules[id]
end

--==============================================================
-- BURSTER ENGINE
--==============================================================

local function burstTrack(track)

	if State.OwnGhostTracks[track] then
		return
	end

	if not CONFIG.BursterMaster then
		return
	end

	local id =
		getId(track)

	if not id then
		return
	end

	local rule =
		CONFIG.BurstRules[id]

	if
		not rule
		or not rule.enabled
	then
		return
	end

	--------------------------------------------------------
	-- Every playback gets a generation token.
	--------------------------------------------------------

	local token =
		(State.BurstTokens[track] or 0)
		+ 1

	State.BurstTokens[track] =
		token

	local originalSpeed =
		tonumber(
			track.Speed
		)

	if
		not originalSpeed
		or originalSpeed <= 0
	then

		originalSpeed =
			rule.visualSpeed
			or 1
	end

	local originalWeight =
		safe(
			function()

				return
					track.WeightTarget
			end,
			1
		)

	if
		not originalWeight
		or originalWeight <= 0
	then
		originalWeight = 1
	end

	local fireSpeed =
		tonumber(
			rule.fireSpeed
		)
		or 1

	--------------------------------------------------------
	-- FAST PHASE
	--------------------------------------------------------

	pcall(function()

		track:
			AdjustSpeed(
				fireSpeed
			)
	end)

	--------------------------------------------------------
	-- Delayed visual mode:
	--
	-- Keep the fast track visually suppressed while it
	-- advances markers/state.
	--------------------------------------------------------

	if rule.visualReplay then

		pcall(function()

			track:
				AdjustWeight(
					0,
					0
				)
		end)

		task.spawn(function()

			local started =
				os.clock()

			------------------------------------------------
			-- Keep enforcing:
			--    fast speed
			--    zero visual contribution
			------------------------------------------------

			while
				not State.Destroyed
				and track.IsPlaying
				and
				State.BurstTokens[track]
					== token
				and
				(
					os.clock()
					- started
				)
				<
				rule.fireWindow
			do

				pcall(function()

					track:
						AdjustSpeed(
							fireSpeed
						)

					track:
						AdjustWeight(
							0,
							0
						)
				end)

				RunService.Heartbeat:
					Wait()
			end

			if
				State.Destroyed
				or
				State.BurstTokens[track]
					~= token
				or
				not track.IsPlaying
			then
				return
			end

			------------------------------------------------
			-- Pause + rewind.
			------------------------------------------------

			pcall(function()

				track:
					AdjustSpeed(0)

				track.TimePosition =
					0

				track:
					AdjustWeight(
						0,
						0
					)
			end)

			------------------------------------------------
			-- Delayed visual.
			------------------------------------------------

			task.wait(
				math.max(
					0,
					rule.visualDelay
				)
			)

			if
				State.Destroyed
				or
				State.BurstTokens[track]
					~= token
				or
				not track.IsPlaying
			then
				return
			end

			local visualSpeed =
				tonumber(
					rule.visualSpeed
				)
				or originalSpeed

			------------------------------------------------
			-- Play normal-looking visual AFTER fast phase.
			------------------------------------------------

			pcall(function()

				track.TimePosition =
					0

				track:
					AdjustSpeed(
						visualSpeed
					)

				track:
					AdjustWeight(
						originalWeight,
						math.max(
							0,
							rule.visualFade
						)
					)
			end)

			print(
				string.format(
					"[BURST] %s | FIRE %.2fx %.3fs | VIS %.2fx +%.3fs",
					rule.name
						or id,

					fireSpeed,

					rule.fireWindow,

					visualSpeed,

					rule.visualDelay
				)
			)
		end)

	else

		----------------------------------------------------
		-- Old/simple proven behavior.
		----------------------------------------------------

		task.spawn(function()

			RunService.Heartbeat:
				Wait()

			if
				State.Destroyed
				or not track.IsPlaying
				or
				State.BurstTokens[track]
					~= token
			then
				return
			end

			pcall(function()

				track:
					AdjustSpeed(
						fireSpeed
					)
			end)
		end)

		print(
			string.format(
				"[BURST] %s | %.2fx",
				rule.name
					or id,
				fireSpeed
			)
		)
	end
end

--==============================================================
-- PROFILER
--==============================================================

local function recordTrackStart(track)

	if not CONFIG.LoggingEnabled then
		return
	end

	--------------------------------------------------------
	-- Don't let our own Ghost test tracks contaminate the
	-- learned statistics.
	--------------------------------------------------------

	if
		State.TargetPlayer == LP
		and
		State.OwnGhostTracks[track]
	then
		return
	end

	local id =
		getId(track)

	if not id then
		return
	end

	local profile =
		State.Profiles[id]
		or
		makeProfile(
			id,
			track
		)

	profile.count += 1

	profile.name =
		tostring(
			track.Name
			or profile.name
		)

	profile.lastSeen =
		os.clock()

	local speed =
		tonumber(
			track.Speed
		)
		or 0

	profile.speedLast =
		speed

	profile.speedMin =
		math.min(
			profile.speedMin,
			speed
		)

	profile.speedMax =
		math.max(
			profile.speedMax,
			speed
		)

	profile.speedSum +=
		speed

	profile.speedCount +=
		1

	profile.length =
		tonumber(
			track.Length
		)
		or profile.length

	local priority =
		safe(
			function()

				return
					track.Priority.Name
			end,
			"?"
		)

	profile.priorities[priority] =
		(
			profile.priorities[priority]
			or 0
		)
		+ 1

	local looped =
		safe(
			function()

				return
					track.Looped
			end,
			false
		)

	if looped then
		profile.loopTrue += 1
	else
		profile.loopFalse += 1
	end

	local current =
		safe(
			function()

				return
					track.WeightCurrent
			end,
			0
		)

	local target =
		safe(
			function()

				return
					track.WeightTarget
			end,
			0
		)

	profile.weightCurrentMax =
		math.max(
			profile.weightCurrentMax,
			current
		)

	profile.weightTargetLast =
		target

	profile.weightTargetMax =
		math.max(
			profile.weightTargetMax,
			target
		)

	local token =
		(
			State.TrackTokens[track]
			or 0
		)
		+ 1

	State.TrackTokens[track] =
		token

	local started =
		os.clock()

	if UI.UpdateProfileRow then
		UI.UpdateProfileRow(id)
	end

	task.spawn(function()

		RunService.Heartbeat:
			Wait()

		if
			State.Destroyed
			or
			State.TrackTokens[track]
				~= token
		then
			return
		end

		local c =
			safe(
				function()

					return
						track.WeightCurrent
				end,
				0
			)

		local t =
			safe(
				function()

					return
						track.WeightTarget
				end,
				0
			)

		profile.weightCurrentMax =
			math.max(
				profile.weightCurrentMax,
				c
			)

		profile.weightTargetLast =
			t

		profile.weightTargetMax =
			math.max(
				profile.weightTargetMax,
				t
			)

		if UI.UpdateProfileRow then
			UI.UpdateProfileRow(id)
		end

		----------------------------------------------------
		-- Lifetime profiler
		----------------------------------------------------

		while
			not State.Destroyed
			and
			State.TrackTokens[track]
				== token
			and
			safe(
				function()

					return
						track.IsPlaying
				end,
				false
			)
		do

			task.wait(0.01)
		end

		if
			State.Destroyed
			or
			State.TrackTokens[track]
				~= token
		then
			return
		end

		local lifetime =
			os.clock()
			- started

		profile.lifeSum +=
			lifetime

		profile.lifeCount +=
			1

		profile.lifeMin =
			math.min(
				profile.lifeMin,
				lifetime
			)

		profile.lifeMax =
			math.max(
				profile.lifeMax,
				lifetime
			)

		if UI.UpdateProfileRow then
			UI.UpdateProfileRow(id)
		end

		if
			id
			== State.Selected
			and UI.RefreshGhost
		then

			UI.RefreshGhost()
		end
	end)
end

--==============================================================
-- GHOST ENGINE
--==============================================================

local GHOST_POSE_SIGNAL =
	safe(
		function()
			return RunService.PreSimulation
		end,
		nil
	)
	or RunService.Stepped

local function isLowerBodyMotor(motor)

	if not motor:IsA("Motor6D") then
		return false
	end

	local name =
		string.lower(
			motor.Name
		)

	if
		string.find(name, "hip", 1, true)
		or string.find(name, "knee", 1, true)
		or string.find(name, "ankle", 1, true)
	then
		return true
	end

	local part1Name =
		safe(
			function()
				return string.lower(motor.Part1.Name)
			end,
			""
		)

	return
		string.find(part1Name, "leg", 1, true)
		~= nil
		or
		string.find(part1Name, "foot", 1, true)
		~= nil
end

local function createGhostPoseGuard(track)

	if not CONFIG.Ghost.LegGuard then
		return nil
	end

	local character =
		LP.Character

	if not character then
		return nil
	end

	local guard = {
		snapshot = {},
		maxPosition = 0,
		maxRotation = 0,
		maxJoint = nil,
		signal = GHOST_POSE_SIGNAL,
	}

	for _, descendant
		in ipairs(
			character:GetDescendants()
		)
	do
		if isLowerBodyMotor(descendant) then

			local transform =
				safe(
					function()
						return descendant.Transform
					end,
					nil
				)

			if transform then
				guard.snapshot[descendant] =
					transform
			end
		end
	end

	if next(guard.snapshot) == nil then
		return nil
	end

	function guard:RestoreAndMeasure()

		for motor, baseline
			in pairs(self.snapshot)
		do
			pcall(function()

				local current =
					motor.Transform

				local delta =
					baseline:
						ToObjectSpace(current)

				local position =
					delta.Position.Magnitude

				local rx, ry, rz =
					delta:ToOrientation()

				local rotation =
					math.deg(
						math.max(
							math.abs(rx),
							math.abs(ry),
							math.abs(rz)
						)
					)

				if
					position > self.maxPosition
					or rotation > self.maxRotation
				then
					self.maxPosition =
						math.max(
							self.maxPosition,
							position
						)

					self.maxRotation =
						math.max(
							self.maxRotation,
							rotation
						)

					self.maxJoint =
						motor.Name
				end

				motor.Transform =
					baseline
			end)
		end
	end

	guard.connection =
		GHOST_POSE_SIGNAL:
			Connect(function()
				guard:RestoreAndMeasure()
			end)

	State.GhostPoseGuards[track] =
		guard

	return guard
end

local function releaseGhostPoseGuard(
	track,
	waitForStopFrame
)

	local guard =
		State.GhostPoseGuards[track]

	if not guard then
		return nil
	end

	if waitForStopFrame then
		guard.signal:Wait()
	end

	guard:RestoreAndMeasure()

	pcall(function()
		guard.connection:Disconnect()
	end)

	State.GhostPoseGuards[track] =
		nil

	return guard
end

local function stopGhostTrack(
	track,
	waitForStopFrame
)

	--------------------------------------------------------
	-- Drop the target before stopping. Keeping the pose
	-- guard through one simulation step catches a Stop(0)
	-- transition before it can reach a rendered frame.
	--------------------------------------------------------

	pcall(function()
		track:AdjustWeight(0, 0)
	end)

	pcall(function()
		track:Stop(0)
	end)

	return
		releaseGhostPoseGuard(
			track,
			waitForStopFrame
		)
end

local function stopAllGhosts()

	local tracks = {}

	for track
		in pairs(
			State.ActiveGhosts
		)
	do
		table.insert(
			tracks,
			track
		)
	end

	for _, track
		in ipairs(tracks)
	do

		stopGhostTrack(
			track,
			false
		)

		State.ActiveGhosts[track] =
			nil
	end
end

local function computeGhostParameters(id)

	local ghost =
		CONFIG.Ghost

	local profile =
		State.Profiles[id]

	local speed =
		ghost.Speed

	local lifetime =
		ghost.Lifetime

	local weight =
		ghost.TargetWeight

	local priority =
		ghost.Priority

	local looped =
		false

	if
		ghost.AutoProfile
		and profile
	then

		if profile.speedCount > 0 then

			speed =
				avgSpeed(profile)

			if speed <= 0 then
				speed =
					ghost.Speed
			end
		end

		local learnedLife =
			avgLife(profile)

		if learnedLife > 0 then

			lifetime =
				math.min(
					learnedLife,
					ghost.AutoLifeCap
				)
		end

		if
			profile.weightTargetLast
			and
			profile.weightTargetLast > 0
		then

			weight =
				profile.weightTargetLast
		end

		if ghost.UseLearnedPriority then

			priority =
				modePriority(profile)
		end

		if ghost.UseLearnedLooped then

			looped =
				profileLooped(profile)
		end
	end

	speed =
		math.max(
			0.01,
			jitter(
				speed,
				ghost.SpeedJitter
			)
		)

	weight =
		math.max(
			0.001,
			jitter(
				weight,
				ghost.WeightJitter
			)
		)

	lifetime =
		math.max(
			0.001,
			lifetime
		)

	--------------------------------------------------------
	-- Calculate absurdly slow fade so WeightCurrent barely
	-- rises during the track's tiny lifetime.
	--------------------------------------------------------

	local fade =
		(
			lifetime
			* weight
			/
			math.max(
				ghost.VisibleCap,
				0.000001
			)
		)
		*
		ghost.FadeSafety

	fade =
		math.clamp(
			math.max(
				fade,
				ghost.MinFade
			),
			0.1,
			ghost.MaxFade
		)

	return {
		speed = speed,
		lifetime = lifetime,
		weight = weight,
		fade = fade,
		priority = priority,
		looped = looped,
	}
end

local function ghostFire(id)

	id =
		cleanId(id)

	if
		not id
		or not State.LocalAnimator
	then
		return nil
	end

	--------------------------------------------------------
	-- HARD SERIAL
	--------------------------------------------------------

	stopAllGhosts()

	local params =
		computeGhostParameters(id)

	local anim =
		Instance.new("Animation")

	anim.Name =
		"GHOST_"
		.. id

	anim.AnimationId =
		"rbxassetid://"
		.. id

	local track

	local ok =
		pcall(function()

			track =
				State.LocalAnimator:
					LoadAnimation(anim)
		end)

	if
		not ok
		or not track
	then

		pcall(function()
			anim:Destroy()
		end)

		return nil
	end

	State.OwnGhostTracks[track] =
		true

	State.ActiveGhosts[track] =
		true

	track.Name =
		"GHOST_"
		.. id

	track.Priority =
		PRIORITIES[
			params.priority
		]
		or
		Enum.AnimationPriority.Core

	track.Looped =
		params.looped

	createGhostPoseGuard(
		track
	)

	local played, playError =
		pcall(function()
			track:
				Play(
					params.fade,
					params.weight,
					params.speed
				)
		end)

	if not played then

		warn(
			"[GHOST] play failed",
			playError
		)

		stopGhostTrack(
			track,
			false
		)

		State.ActiveGhosts[track] =
			nil

		State.OwnGhostTracks[track] =
			nil

		pcall(function()
			track:Destroy()
		end)

		pcall(function()
			anim:Destroy()
		end)

		return nil
	end

	task.spawn(function()

		local started =
			os.clock()

		local maximumWeight =
			0

		local guarded =
			false

		while
			not State.Destroyed
			and track.IsPlaying
			and
			(
				os.clock()
				- started
			)
			<
			params.lifetime
		do

			RunService.Heartbeat:
				Wait()

			local current =
				safe(
					function()

						return
							track.WeightCurrent
					end,
					0
				)

			maximumWeight =
				math.max(
					maximumWeight,
					current
				)

			------------------------------------------------
			-- Hard kill if blending rises unexpectedly.
			------------------------------------------------

			if
				current
				>
				CONFIG.Ghost.VisibleCap
				* 1.5
			then

				guarded =
					true

				break
			end
		end

		local current =
			safe(
				function()

					return
						track.WeightCurrent
				end,
				0
			)

		local target =
			safe(
				function()

					return
						track.WeightTarget
				end,
				0
			)

		local position =
			safe(
				function()

					return
						track.TimePosition
				end,
				0
			)

		local poseGuard =
			stopGhostTrack(
				track,
				true
			)

		State.ActiveGhosts[track] =
			nil

		State.GhostExperimentSequence += 1
		local diagnostic = {
			sequence = State.GhostExperimentSequence,
			id = id,
			at = os.clock(),
			priority = params.priority,
			speed = params.speed,
			lifetime = params.lifetime,
			fade = params.fade,
			targetWeight = params.weight,
			visibleCap = CONFIG.Ghost.VisibleCap,
			maxWeight = maximumWeight,
			timePosition = position,
			visualGuard = guarded,
			legGuard = CONFIG.Ghost.LegGuard,

			joint =
				poseGuard
				and poseGuard.maxJoint
				or "-",

			position =
				poseGuard
				and poseGuard.maxPosition
				or 0,

			rotation =
				poseGuard
					and poseGuard.maxRotation
					or 0,

			visualResult = "unrated",
			remoteResult = "unrated",
		}
		State.LastGhostDiagnostic = diagnostic
		table.insert(State.GhostExperiments, diagnostic)
		while #State.GhostExperiments > 40 do
			table.remove(State.GhostExperiments, 1)
		end

		if
			not State.Destroyed
			and UI.RefreshGhost
		then
			task.defer(
				UI.RefreshGhost
			)
		end

		print(
			string.format(
				"[GHOST] %s | S %.3f | LIFE %.4f | FADE %.0f | W %.7f>%.4f | MAX %.7f | POS %.4f | PRI %s%s%s",
				id,
				params.speed,
				params.lifetime,
				params.fade,
				current,
				target,
				maximumWeight,
				position,
				tostring(params.priority),
				guarded
					and " | VIS-GUARD"
					or "",

				poseGuard
					and
					string.format(
						" | LEG %s POS %.6f ROT %.3f",
						poseGuard.maxJoint
							or "-",
						poseGuard.maxPosition,
						poseGuard.maxRotation
					)
					or ""
			)
		)

		task.delay(
			0.10,
			function()

				State.OwnGhostTracks[track] =
					nil

				pcall(function()
					track:Destroy()
				end)

				pcall(function()
					anim:Destroy()
				end)
			end
		)
	end)

	return track, params
end

local function poolHas(id)

	for _, existing
		in ipairs(
			State.GhostPool
		)
	do

		if existing == id then
			return true
		end
	end

	return false
end

local function addGhostPool(id)

	id =
		cleanId(id)

	if
		id
		and not poolHas(id)
	then

		table.insert(
			State.GhostPool,
			id
		)
	end

	if UI.RefreshGhost then
		UI.RefreshGhost()
	end
end

local function stopGhostRunner()

	State.GhostRunning =
		false

	State.GhostToken +=
		1

	stopAllGhosts()

	if UI.RefreshGhost then
		UI.RefreshGhost()
	end
end

local function startGhostRunner()

	if State.GhostRunning then
		return
	end

	if
		#State.GhostPool == 0
	then

		addGhostPool(
			State.Selected
		)
	end

	if
		#State.GhostPool == 0
	then
		return
	end

	State.GhostRunning =
		true

	State.GhostToken +=
		1

	local token =
		State.GhostToken

	if UI.RefreshGhost then
		UI.RefreshGhost()
	end

	task.spawn(function()

		local index = 0

		while
			not State.Destroyed
			and State.GhostRunning
			and
			State.GhostToken
				== token
		do

			------------------------------------------------
			-- Explicitly guarantee previous track is dead
			-- BEFORE the next one exists.
			------------------------------------------------

			stopAllGhosts()

			task.wait(
				CONFIG.Ghost.Gap
			)

			local id

			if CONFIG.Ghost.RandomOrder then

				id =
					State.GhostPool[
						math.random(
							1,
							#State.GhostPool
						)
					]

			else

				index += 1

				if
					index
					>
					#State.GhostPool
				then
					index = 1
				end

				id =
					State.GhostPool[index]
			end

			local _, params =
				ghostFire(id)

			local waitTime =
				CONFIG.Ghost.Interval

			if params then

				waitTime =
					math.max(
						waitTime,
						params.lifetime
							+
						CONFIG.Ghost.Gap
					)
			end

			task.wait(
				waitTime
			)
		end
	end)
end

--==============================================================
-- WEBHOOK ENGINE
--==============================================================

local function webhookPost(payload)

	local url =
		CONFIG.Webhook.URL

	if
		not url
		or url == ""
	then

		warn(
			"[WEBHOOK] no URL set"
		)

		return false,
			"no URL set"
	end

	local rawRequest =
		getRequestImplementation()

	if not rawRequest then

		warn(
			"[WEBHOOK] no request implementation"
		)

		return false,
			"no request implementation"
	end

	local ok, result =
		pcall(
			rawRequest,
			{
				Url = url,

				Method = "POST",

				Headers = {
					["Content-Type"] =
						"application/json",
				},

				Body =
					HttpService:
						JSONEncode(
							payload
						),
			}
		)

	if not ok then

		warn(
			"[WEBHOOK]",
			result
		)

		return false,
			tostring(result)
	end

	if type(result) ~= "table" then

		warn(
			"[WEBHOOK] invalid response",
			type(result)
		)

		return false,
			"request returned "
				..
				type(result)
	end

	local status =
		tonumber(
			result.StatusCode
			or result.Status
			or result.status_code
		)

	if
		status
		and
		(
			status < 200
			or status >= 300
		)
	then

		warn(
			"[WEBHOOK] HTTP",
			status
		)

		local body =
			tostring(
				result.Body
				or result.body
				or ""
			)

		return false,
			"HTTP "
				..
				tostring(status)
				..
				(
					body ~= ""
					and
					(
						": "
						..
						string.sub(body, 1, 160)
					)
					or ""
				)
	end

	if
		not status
		and result.Success ~= true
	then

		warn(
			"[WEBHOOK] response had no status code"
		)

		return false,
			"response had no status code"
	end

	return true,
		nil,
		status
end

local function callLootMethod(
	methodName,
	...
)

	local loot =
		getLootAPI()

	if type(loot) ~= "table" then
		return false,
			"Loot API not found"
	end

	local method =
		loot[methodName]

	if type(method) ~= "function" then
		return false,
			"Loot."
				..
				methodName
				..
				" is not available"
	end

	local ok, result, detail =
		pcall(
			method,
			...
		)

	if not ok then
		return false,
			tostring(result)
	end

	--------------------------------------------------------
	-- pcall only reports whether Lua raised. Respect APIs
	-- that explicitly return false for a delivery failure.
	--------------------------------------------------------

	if result == false then
		return false,
			tostring(
				detail
				or "Loot API reported failure"
			)
	end

	return true,
		result
end

local function syncLootConfiguration()

	local options = {
		username = CONFIG.Webhook.Username,
		userID = CONFIG.Webhook.UserID,
	}

	-- Do not erase a URL that was configured directly in the pre-loader
	-- notifier merely because the GUI has no saved preference yet.
	if
		CONFIG.Webhook.URL
		and CONFIG.Webhook.URL ~= ""
	then
		options.url = CONFIG.Webhook.URL
	end

	return callLootMethod(
		"configure",
		options
	)
end

local function sendWebhookText(message)

	--------------------------------------------------------
	-- Prefer Loot because it captured its request function
	-- before Project Rain loaded. SET URL synchronizes Loot's
	-- private config through Loot.configure.
	--------------------------------------------------------

	local content =
		tostring(message or "")

	local userID =
		tostring(
			CONFIG.Webhook.UserID
			or ""
		):match("^%s*(%d+)%s*$")

	if userID then
		content =
			"<@"
			..
			userID
			..
			"> "
			..
			content
	end

	local lootSuccess, lootDetail =
		callLootMethod(
			"text",
			content
		)

	if lootSuccess then
		return true,
			"via Loot API"
	end

	--------------------------------------------------------
	-- Standalone fallback for use without the Loot module.
	--------------------------------------------------------

	if
		not CONFIG.Webhook.URL
		or CONFIG.Webhook.URL == ""
	then
		return false,
			"Loot API",
			lootDetail
	end

	local directSuccess, directDetail =
		webhookPost({
			username =
				CONFIG.Webhook.Username,

			content =
				content,
		})

	if directSuccess then
		return true,
			"direct fallback"
	end

	return false,
		"Loot/direct",
		tostring(lootDetail)
			..
			"; "
			..
			tostring(directDetail)
end

--==============================================================
-- LOCAL ANIMATOR
--==============================================================

local function hookLocalAnimator(animator)

	State.LocalAnimator =
		animator

	if State.LocalAnimatorConnection then

		pcall(function()

			State.LocalAnimatorConnection:
				Disconnect()
		end)
	end

	State.LocalAnimatorConnection =
		animator.AnimationPlayed:
			Connect(function(track)

				if State.Destroyed then
					return
				end

				burstTrack(track)
			end)

	table.insert(
		State.Connections,
		State.LocalAnimatorConnection
	)
end

local function hookLocalCharacter(character)

	local humanoid =
		character:
			WaitForChild(
				"Humanoid",
				10
			)

	if not humanoid then
		return
	end

	local animator =
		humanoid:
			FindFirstChildOfClass(
				"Animator"
			)
		or
		humanoid:
			WaitForChild(
				"Animator",
				10
			)

	if animator then

		hookLocalAnimator(
			animator
		)
	end
end

--==============================================================
-- TARGET INSPECTOR
--==============================================================

local function clearTargetConnections()

	disconnectList(
		State.TargetConnections
	)

	if State.TargetAnimatorConnection then

		pcall(function()

			State.TargetAnimatorConnection:
				Disconnect()
		end)

		State.TargetAnimatorConnection =
			nil
	end
end

local function clearProfiles()

	State.Profiles = {}

	if UI.ClearLogRows then
		UI.ClearLogRows()
	end
end

local function clearLiveRows()

	for _, row
		in pairs(
			State.LiveRows
		)
	do

		pcall(function()

			row.button:
				Destroy()
		end)
	end

	State.LiveRows =
		setmetatable(
			{},
			{ __mode = "k" }
		)

	State.LastSeen =
		setmetatable(
			{},
			{ __mode = "k" }
		)
end

local function hookTargetAnimator(animator)

	State.TargetAnimator =
		animator

	if State.TargetAnimatorConnection then

		pcall(function()

			State.TargetAnimatorConnection:
				Disconnect()
		end)
	end

	State.TargetAnimatorConnection =
		animator.AnimationPlayed:
			Connect(function(track)

				if State.Destroyed then
					return
				end

				pcall(
					recordTrackStart,
					track
				)
			end)

	table.insert(
		State.TargetConnections,
		State.TargetAnimatorConnection
	)
end

local function attachTargetCharacter(
	player,
	character
)

	task.spawn(function()

		local humanoid =
			character:
				WaitForChild(
					"Humanoid",
					10
				)

		if
			not humanoid
			or
			State.TargetPlayer
				~= player
		then
			return
		end

		local animator =
			humanoid:
				FindFirstChildOfClass(
					"Animator"
				)
			or
			humanoid:
				WaitForChild(
					"Animator",
					10
				)

		if
			animator
			and
			State.TargetPlayer
				== player
		then

			hookTargetAnimator(
				animator
			)
		end
	end)
end

local function setTarget(player)

	if not player then
		return
	end

	clearTargetConnections()

	clearProfiles()

	clearLiveRows()

	State.TargetPlayer =
		player

	State.TargetAnimator =
		nil

	if UI.SetTargetText then

		UI.SetTargetText(
			player
		)
	end

	if player.Character then

		attachTargetCharacter(
			player,
			player.Character
		)
	end

	bindTarget(
		player.CharacterAdded,
		function(character)

			if
				State.TargetPlayer
				== player
			then

				attachTargetCharacter(
					player,
					character
				)
			end
		end
	)
end

local function cycleTarget()

	local players =
		Players:GetPlayers()

	table.sort(
		players,
		function(a, b)

			if a == LP then
				return true
			end

			if b == LP then
				return false
			end

			return
				a.Name < b.Name
		end
	)

	local index = 1

	for i, p
		in ipairs(players)
	do

		if
			p
			== State.TargetPlayer
		then

			index = i
			break
		end
	end

	index += 1

	if index > #players then
		index = 1
	end

	setTarget(
		players[index]
	)
end

--==============================================================
-- COLORS
--==============================================================

local COLORS = {

	BG =
		Color3.fromRGB(
			18,
			18,
			21
		),

	PANEL =
		Color3.fromRGB(
			24,
			24,
			28
		),

	PANEL2 =
		Color3.fromRGB(
			31,
			31,
			36
		),

	BORDER =
		Color3.fromRGB(
			64,
			64,
			72
		),

	TEXT =
		Color3.fromRGB(
			222,
			222,
			228
		),

	MUTED =
		Color3.fromRGB(
			150,
			150,
			160
		),

	GREEN =
		Color3.fromRGB(
			45,
			83,
			53
		),

	RED =
		Color3.fromRGB(
			83,
			43,
			43
		),

	BLUE =
		Color3.fromRGB(
			83,
			108,
			165
		),

	ACCENT =
		Color3.fromRGB(
			116,
			94,
			190
		),
}

--==============================================================
-- UI HELPERS
--==============================================================

local function mkLabel(
	parent,
	text,
	x,
	y,
	w,
	h,
	size
)

	local object =
		Instance.new(
			"TextLabel"
		)

	object.Position =
		UDim2.fromOffset(
			x,
			y
		)

	object.Size =
		UDim2.fromOffset(
			w,
			h
		)

	object.BackgroundTransparency = 1

	object.Text =
		text

	object.TextColor3 =
		COLORS.TEXT

	object.Font =
		Enum.Font.Code

	object.TextSize =
		size or 11

	object.TextXAlignment =
		Enum.TextXAlignment.Left

	object.Parent =
		parent

	return object
end

local function mkButton(
	parent,
	text,
	x,
	y,
	w,
	h
)

	local object =
		Instance.new(
			"TextButton"
		)

	object.Position =
		UDim2.fromOffset(
			x,
			y
		)

	object.Size =
		UDim2.fromOffset(
			w,
			h
		)

	object.BackgroundColor3 =
		COLORS.PANEL2

	object.BorderColor3 =
		COLORS.BORDER

	object.BorderSizePixel = 1

	object.Text =
		text

	object.TextColor3 =
		COLORS.TEXT

	object.Font =
		Enum.Font.Code

	object.TextSize = 10

	object.Parent =
		parent

	return object
end

local function mkBox(
	parent,
	text,
	x,
	y,
	w,
	h
)

	local object =
		Instance.new(
			"TextBox"
		)

	object.Position =
		UDim2.fromOffset(
			x,
			y
		)

	object.Size =
		UDim2.fromOffset(
			w,
			h
		)

	object.BackgroundColor3 =
		COLORS.PANEL2

	object.BorderColor3 =
		COLORS.BORDER

	object.BorderSizePixel = 1

	object.Text =
		text

	object.TextColor3 =
		COLORS.TEXT

	object.PlaceholderColor3 =
		COLORS.MUTED

	object.ClearTextOnFocus =
		false

	object.Font =
		Enum.Font.Code

	object.TextSize = 10

	object.Parent =
		parent

	return object
end

local function mkScroll(
	parent,
	x,
	y,
	w,
	h
)

	local scroll =
		Instance.new(
			"ScrollingFrame"
		)

	scroll.Position =
		UDim2.fromOffset(
			x,
			y
		)

	scroll.Size =
		UDim2.fromOffset(
			w,
			h
		)

	scroll.BackgroundColor3 =
		Color3.fromRGB(
			17,
			17,
			20
		)

	scroll.BorderColor3 =
		COLORS.BORDER

	scroll.BorderSizePixel = 1

	scroll.ScrollBarThickness = 3

	scroll.CanvasSize =
		UDim2.fromOffset(
			0,
			0
		)

	scroll.Parent =
		parent

	local layout =
		Instance.new(
			"UIListLayout"
		)

	layout.SortOrder =
		Enum.SortOrder.LayoutOrder

	layout.Parent =
		scroll

	return scroll, layout
end

--==============================================================
-- GUI
--==============================================================

local Gui =
	Instance.new(
		"ScreenGui"
	)

Gui.Name =
	"_ClawMark"

Gui.ResetOnSpawn =
	false

Gui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

local guiParent

pcall(function()

	if gethui then
		guiParent =
			gethui()
	end
end)

if not guiParent then

	guiParent =
		LP:
			WaitForChild(
				"PlayerGui"
			)
end

local existingGui =
	guiParent:
		FindFirstChild(
			"_ClawMark"
		)

if existingGui then
	pcall(function()
		existingGui:Destroy()
	end)
end

Gui.Parent =
	guiParent

------------------------------------------------------------
-- Main
------------------------------------------------------------

local Main =
	Instance.new(
		"Frame"
	)

Main.Size =
	UDim2.fromOffset(
		680,
		520
	)

local savedUIPosition = PREFS.UIPosition

Main.Position =
	type(savedUIPosition) == "table"
		and UDim2.new(
			tonumber(savedUIPosition.xScale) or 0,
			tonumber(savedUIPosition.xOffset) or 24,
			tonumber(savedUIPosition.yScale) or 0.5,
			tonumber(savedUIPosition.yOffset) or -260
		)
		or UDim2.new(0, 24, 0.5, -260)

Main.BackgroundColor3 =
	COLORS.BG

Main.BorderColor3 =
	COLORS.BORDER

Main.BorderSizePixel = 1

Main.Active = true

Main.Parent =
	Gui

UI.Main =
	Main

------------------------------------------------------------
-- Mouse behavior
------------------------------------------------------------

local function enterUI()

	if State.MouseHover then
		return
	end

	State.MouseHover = true

	State.OldMouseIcon =
		UIS.MouseIconEnabled

	State.OldMouseBehavior =
		UIS.MouseBehavior

	UIS.MouseIconEnabled =
		true

	UIS.MouseBehavior =
		Enum.MouseBehavior.Default
end

local function leaveUI()

	if not State.MouseHover then
		return
	end

	State.MouseHover = false

	if State.OldMouseIcon ~= nil then

		UIS.MouseIconEnabled =
			State.OldMouseIcon
	end

	if State.OldMouseBehavior ~= nil then

		UIS.MouseBehavior =
			State.OldMouseBehavior
	end
end

bind(
	Main.MouseEnter,
	enterUI
)

bind(
	Main.MouseLeave,
	leaveUI
)

bind(
	RunService.RenderStepped,
	function()

		if
			State.Destroyed
			or not State.MouseHover
		then
			return
		end

		UIS.MouseIconEnabled =
			true

		UIS.MouseBehavior =
			Enum.MouseBehavior.Default
	end
)

------------------------------------------------------------
-- Header
------------------------------------------------------------

local Top =
	Instance.new(
		"Frame"
	)

Top.Size =
	UDim2.new(
		1,
		0,
		0,
		30
	)

Top.BackgroundColor3 =
	Color3.fromRGB(
		27,
		27,
		31
	)

Top.BorderSizePixel = 0

Top.Parent =
	Main

mkLabel(
	Top,
	"CLAW MARK v0.4.0",
	8,
	0,
	170,
	30,
	12
)

local TargetButton =
	mkButton(
		Top,
		"TARGET: LOCAL",
		188,
		4,
		140,
		22
	)

local MenuButton =
	mkButton(
		Top,
		"MENU",
		550,
		4,
		52,
		22
	)

local MinimizeButton =
	mkButton(
		Top,
		"_",
		610,
		4,
		28,
		22
	)

local CloseButton =
	mkButton(
		Top,
		"x",
		644,
		4,
		28,
		22
	)

CloseButton.BackgroundColor3 =
	COLORS.RED

------------------------------------------------------------
-- Drag
------------------------------------------------------------

do

	local dragging = false

	local startMouse

	local startPosition

	bind(
		Top.InputBegan,
		function(input)

			if
				input.UserInputType
				==
				Enum.UserInputType.MouseButton1
			then

				dragging =
					true

				startMouse =
					input.Position

				startPosition =
					Main.Position
			end
		end
	)

	bind(
		UIS.InputEnded,
		function(input)

			if
				input.UserInputType
				==
				Enum.UserInputType.MouseButton1
			then

				local wasDragging = dragging

				dragging = false

				if wasDragging then
					PREFS.UIPosition = {
						xScale = Main.Position.X.Scale,
						xOffset = Main.Position.X.Offset,
						yScale = Main.Position.Y.Scale,
						yOffset = Main.Position.Y.Offset,
					}
				end
			end
		end
	)

	bind(
		UIS.InputChanged,
		function(input)

			if
				not dragging
				or
				input.UserInputType
					~=
				Enum.UserInputType.MouseMovement
			then
				return
			end

			local delta =
				input.Position
				-
				startMouse

			Main.Position =
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset
						+ delta.X,

					startPosition.Y.Scale,
					startPosition.Y.Offset
						+ delta.Y
				)
		end
	)
end

--==============================================================
-- TAB BAR
--==============================================================

local TabBar =
	Instance.new(
		"Frame"
	)

TabBar.Position =
	UDim2.fromOffset(
		0,
		30
	)

TabBar.Size =
	UDim2.new(
		1,
		0,
		0,
		29
	)

TabBar.BackgroundColor3 =
	COLORS.PANEL

TabBar.BorderSizePixel = 0

TabBar.Parent =
	Main

local function makeTab(
	text,
	x,
	width
)

	local tab =
		mkButton(
			TabBar,
			text,
			x,
			0,
			width,
			29
		)

	tab.BorderSizePixel = 0

	return tab
end

local BurstTab =
	makeTab(
		"BURSTER",
		0,
		72
	)

local LogsTab =
	makeTab(
		"LOGGED",
		73,
		68
	)

local LiveTab =
	makeTab(
		"LIVE",
		142,
		58
	)

local GhostTab =
	makeTab(
		"GHOST FIRE",
		201,
		82
	)

local CombatTab =
	makeTab(
		"COMBAT",
		284,
		78
	)

local TimingsTab =
	makeTab(
		"TIMINGS",
		363,
		78
	)

local AssistTab =
	makeTab(
		"ASSIST",
		442,
		74
	)

local DebugTab =
	makeTab(
		"DEBUG",
		517,
		68
	)

local WebhookTab =
	makeTab(
		"WEBHOOK",
		586,
		86
	)

------------------------------------------------------------
-- Pages
------------------------------------------------------------

local function makePage()

	local page =
		Instance.new(
			"Frame"
		)

	page.Position =
		UDim2.fromOffset(
			8,
			68
		)

	page.Size =
		UDim2.new(
			1,
			-16,
			1,
			-92
		)

	page.BackgroundTransparency =
		1

	page.Visible =
		false

	page.Parent =
		Main

	return page
end

local BurstPage =
	makePage()

local LogsPage =
	makePage()

local LivePage =
	makePage()

local GhostPage =
	makePage()

local CombatPage =
	makePage()

local TimingsPage =
	makePage()

local AssistPage =
	makePage()

local DebugPage =
	makePage()

local WebhookPage =
	makePage()

local Pages = {
	[BurstTab] =
		BurstPage,

	[LogsTab] =
		LogsPage,

	[LiveTab] =
		LivePage,

	[GhostTab] =
		GhostPage,

	[CombatTab] =
		CombatPage,

	[TimingsTab] =
		TimingsPage,

	[AssistTab] =
		AssistPage,

	[DebugTab] =
		DebugPage,

	[WebhookTab] =
		WebhookPage,
}

local PageNames = {
	[BurstPage] = "BURSTER",
	[LogsPage] = "LOGGED",
	[LivePage] = "LIVE",
	[GhostPage] = "GHOST FIRE",
	[CombatPage] = "COMBAT",
	[TimingsPage] = "TIMINGS",
	[AssistPage] = "ASSIST",
	[DebugPage] = "DEBUG",
	[WebhookPage] = "WEBHOOK",
}

local PagesByName = {}
for page, name in pairs(PageNames) do
	PagesByName[name] = page
end

local function openPage(target)
	State.ActivePage = target
	PREFS.ActivePage = PageNames[target] or "BURSTER"

	for tab, page
		in pairs(Pages)
	do

		local active =
			page == target

		page.Visible =
			active

		tab.BackgroundColor3 =
			active
			and
			Color3.fromRGB(
				42,
				42,
				48
			)
			or
			COLORS.PANEL

		tab.TextColor3 =
			active
			and COLORS.TEXT
			or COLORS.MUTED
	end
end

--==============================================================
-- STATUS BAR
--==============================================================

local Status =
	mkLabel(
		Main,
		"",
		8,
		497,
		660,
		18,
		9
	)

Status.TextColor3 =
	COLORS.MUTED

local function refreshStatus()
	local notice = State.StatusNotice
	if notice and os.clock() < notice.expires then
		Status.Text = notice.text
		Status.TextColor3 = notice.color or COLORS.ACCENT
		return
	end
	State.StatusNotice = nil
	Status.TextColor3 = COLORS.MUTED

	local targetName =
		State.TargetPlayer
		and State.TargetPlayer.Name
		or "?"

	local ghost =
		State.GhostRunning
		and "GHOST:RUN"
		or "GHOST:STOP"

	local combat = State.Combat
	local defense = "SAFE/OFF"
	if combat and combat.Settings:get("Defense.Enabled") and not combat.Settings:get("Enabled") then
		defense = "MASTER:OFF / DEF:ARMED"
	elseif combat and combat.Settings:get("Defense.Enabled") then
		local timingCount = combat.Timings:count()
		defense = timingCount > 0 and ("DEF:READY/" .. tostring(timingCount)) or "DEF:GENERIC"
	end
	local threatCount = combat and combat.State.ThreatSummary and combat.State.ThreatSummary.activePlans or 0

	Status.Text =
		string.format(
			"target:%s  |  %s  |  log:%s  |  %s  |  threats:%d",
			targetName,
			ghost,
			CONFIG.LoggingEnabled
				and "ON"
				or "OFF",
			defense,
			threatCount
		)
end

local function showStatus(message, color, duration)
	local notice = {
		text = tostring(message),
		color = color or COLORS.ACCENT,
		expires = os.clock() + (duration or 3),
	}
	State.StatusNotice = notice
	refreshStatus()
	task.delay(duration or 3, function()
		if not State.Destroyed and State.StatusNotice == notice then
			State.StatusNotice = nil
			refreshStatus()
		end
	end)
end

--==============================================================
-- BURSTER UI
--==============================================================

local BurstID =
	mkLabel(
		BurstPage,
		"",
		0,
		0,
		290,
		20,
		12
	)

local BurstName =
	mkLabel(
		BurstPage,
		"",
		0,
		20,
		290,
		18,
		10
	)

BurstName.TextColor3 =
	COLORS.MUTED

local BurstEnable =
	mkButton(
		BurstPage,
		"ENABLED",
		0,
		48,
		85,
		24
	)

local ReplayToggle =
	mkButton(
		BurstPage,
		"DELAY VIS: ON",
		92,
		48,
		110,
		24
	)

local CopyID =
	mkButton(
		BurstPage,
		"COPY ID",
		209,
		48,
		70,
		24
	)

local BurstMasterPage =
	mkButton(
		BurstPage,
		"MASTER: OFF",
		286,
		48,
		140,
		24
	)

------------------------------------------------------------
-- field helper
------------------------------------------------------------

local function field(
	parent,
	name,
	y
)

	mkLabel(
		parent,
		name,
		0,
		y,
		130,
		22,
		10
	)

	return
		mkBox(
			parent,
			"",
			145,
			y,
			80,
			22
		)
end

local FireSpeedBox =
	field(
		BurstPage,
		"FIRE SPEED",
		88
	)

local FireWindowBox =
	field(
		BurstPage,
		"FIRE WINDOW (sec)",
		116
	)

local VisualDelayBox =
	field(
		BurstPage,
		"VISUAL DELAY (sec)",
		144
	)

local VisualSpeedBox =
	field(
		BurstPage,
		"VISUAL SPEED",
		172
	)

local VisualFadeBox =
	field(
		BurstPage,
		"VISUAL FADE",
		200
	)

local BurstHint =
	mkLabel(
		BurstPage,
		"",
		0,
		237,
		430,
		48,
		9
	)

BurstHint.TextWrapped =
	true

BurstHint.TextColor3 =
	COLORS.MUTED

local function pullBurstFields()

	local rule =
		getBurstRule(
			State.Selected
		)

	rule.fireSpeed =
		clampNumber(
			FireSpeedBox.Text,
			0.1,
			20,
			rule.fireSpeed
		)

	rule.fireWindow =
		clampNumber(
			FireWindowBox.Text,
			0.001,
			1,
			rule.fireWindow
		)

	rule.visualDelay =
		clampNumber(
			VisualDelayBox.Text,
			0,
			1,
			rule.visualDelay
		)

	rule.visualSpeed =
		clampNumber(
			VisualSpeedBox.Text,
			0.01,
			10,
			rule.visualSpeed
		)

	rule.visualFade =
		clampNumber(
			VisualFadeBox.Text,
			0,
			1,
			rule.visualFade
		)

	if UI.RefreshBurst then
		UI.RefreshBurst()
	end
end

for _, box
	in ipairs({
		FireSpeedBox,
		FireWindowBox,
		VisualDelayBox,
		VisualSpeedBox,
		VisualFadeBox,
	})
do

	bind(
		box.FocusLost,
		pullBurstFields
	)
end

UI.RefreshBurst =
	function()

		local id =
			State.Selected

		local rule =
			getBurstRule(id)

		BurstID.Text =
			id

		BurstName.Text =
			rule.name
			or "Animation"

		BurstEnable.Text =
			rule.enabled
			and "ENABLED"
			or "DISABLED"

		BurstEnable.BackgroundColor3 =
			rule.enabled
			and COLORS.GREEN
			or COLORS.PANEL2

		BurstMasterPage.Text =
			CONFIG.BursterMaster
				and "MASTER: ON"
				or "MASTER: OFF"

		BurstMasterPage.BackgroundColor3 =
			CONFIG.BursterMaster
				and COLORS.GREEN
				or COLORS.PANEL2

		ReplayToggle.Text =
			rule.visualReplay
			and "DELAY VIS: ON"
			or "DELAY VIS: OFF"

		ReplayToggle.BackgroundColor3 =
			rule.visualReplay
			and COLORS.GREEN
			or COLORS.RED

		FireSpeedBox.Text =
			string.format(
				"%.3f",
				rule.fireSpeed
			)

		FireWindowBox.Text =
			string.format(
				"%.3f",
				rule.fireWindow
			)

		VisualDelayBox.Text =
			string.format(
				"%.3f",
				rule.visualDelay
			)

		VisualSpeedBox.Text =
			string.format(
				"%.3f",
				rule.visualSpeed
			)

		VisualFadeBox.Text =
			string.format(
				"%.3f",
				rule.visualFade
			)

		BurstHint.Text =
			"Fast phase is visually suppressed. "
			..
			"Increase FIRE WINDOW only if the breaker stops working. "
			..
			"VISUAL DELAY controls how late the normal-looking animation appears."
	end

bind(
	BurstEnable.MouseButton1Click,
	function()

		local rule =
			getBurstRule(
				State.Selected
			)

		rule.enabled =
			not rule.enabled

		UI.RefreshBurst()
	end
)

bind(
	BurstMasterPage.MouseButton1Click,
	function()
		CONFIG.BursterMaster = not CONFIG.BursterMaster
		UI.RefreshBurst()
		if UI.RefreshBurstMasterMenu then
			UI.RefreshBurstMasterMenu()
		end
		showStatus(
			CONFIG.BursterMaster and "Burster master enabled" or "Burster master disabled",
			CONFIG.BursterMaster and COLORS.GREEN or COLORS.ACCENT
		)
	end
)

bind(
	ReplayToggle.MouseButton1Click,
	function()

		local rule =
			getBurstRule(
				State.Selected
			)

		rule.visualReplay =
			not rule.visualReplay

		UI.RefreshBurst()
	end
)

bind(
	CopyID.MouseButton1Click,
	function()

		if setclipboard then

			pcall(
				setclipboard,
				State.Selected
			)
		end
	end
)

--==============================================================
-- LOGGED UI
--==============================================================

local Search =
	mkBox(
		LogsPage,
		"",
		0,
		0,
		210,
		23
	)

Search.PlaceholderText =
	"search id / name"

local AddVisiblePool =
	mkButton(
		LogsPage,
		"+VISIBLE→POOL",
		218,
		0,
		110,
		23
	)

local ClearLogs =
	mkButton(
		LogsPage,
		"CLEAR",
		336,
		0,
		70,
		23
	)

local LoggingToggle =
	mkButton(
		LogsPage,
		"LOGGER: OFF",
		414,
		0,
		112,
		23
	)

local LogCount =
	mkLabel(
		LogsPage,
		"0 UNIQUE",
		534,
		0,
		122,
		23,
		9
	)

LogCount.TextColor3 = COLORS.MUTED

local LogScroll,
	LogLayout =
	mkScroll(
		LogsPage,
		0,
		31,
		444,
		292
	)

local function filterMatch(
	id,
	profile
)

	local query =
		string.lower(
			Search.Text or ""
		)

	if query == "" then
		return true
	end

	local data =
		string.lower(
			tostring(id)
			..
			" "
			..
			tostring(
				profile.name
			)
		)

	return
		string.find(
			data,
			query,
			1,
			true
		)
		~= nil
end

local function updateLogCanvas()

	task.defer(function()

		LogScroll.CanvasSize =
			UDim2.fromOffset(
				0,
				LogLayout.AbsoluteContentSize.Y
			)
	end)
end

local function makeLogRow(id)

	if State.LogRows[id] then
		return
			State.LogRows[id]
	end

	local row =
		mkButton(
			LogScroll,
			"",
			0,
			0,
			442,
			24
		)

	row.Size =
		UDim2.new(
			1,
			-2,
			0,
			24
		)

	row.BorderSizePixel =
		0

	local text =
		mkLabel(
			row,
			"",
			5,
			0,
			428,
			24,
			8
		)

	State.LogRows[id] = {
		button = row,
		text = text,
	}

	bind(
		row.MouseButton1Click,
		function()

			State.Selected =
				id

			PREFS.SelectedAnimation = id

			UI.RefreshBurst()

			if UI.RefreshGhost then
				UI.RefreshGhost()
			end

			openPage(
				BurstPage
			)
		end
	)

	updateLogCanvas()

	return
		State.LogRows[id]
end

UI.UpdateProfileRow =
	function(id)

		local profile =
			State.Profiles[id]

		if not profile then
			return
		end

		local row =
			makeLogRow(id)

		row.button.Visible =
			filterMatch(
				id,
				profile
			)

		row.text.Text =
			string.format(
				"%-13s x%-3d S:%4.2f[%4.2f-%4.2f] L:%4.2f LIFE:%5.3f WT:%5.3f WC:%6.4f %-7s",
				id,
				profile.count,
				avgSpeed(profile),

				profile.speedMin
					== math.huge
					and 0
					or
					profile.speedMin,

				profile.speedMax,

				profile.length,

				avgLife(profile),

				profile.weightTargetLast,

				profile.weightCurrentMax,

				modePriority(profile)
			)

		updateLogCanvas()
		UI.RefreshLogging()
	end

UI.ClearLogRows =
	function()

		for _, row
			in pairs(
				State.LogRows
			)
		do

			pcall(function()

				row.button:
					Destroy()
			end)
		end

		State.LogRows = {}

		updateLogCanvas()
		UI.RefreshLogging()
	end

bind(
	Search:
		GetPropertyChangedSignal(
			"Text"
		),
	function()

		for id, profile
			in pairs(
				State.Profiles
			)
		do

			local row =
				State.LogRows[id]

			if row then

				row.button.Visible =
					filterMatch(
						id,
						profile
					)
			end
		end

		updateLogCanvas()
	end
)

bind(
	ClearLogs.MouseButton1Click,
	function()

		clearProfiles()
		UI.RefreshLogging()
		showStatus("Animation log cleared", COLORS.ACCENT)
	end
)

bind(
	LoggingToggle.MouseButton1Click,
	function()
		CONFIG.LoggingEnabled = not CONFIG.LoggingEnabled
		UI.RefreshLogging()
		showStatus(
			CONFIG.LoggingEnabled
				and "Animation logger enabled for the selected target"
				or "Animation logger paused; existing results kept",
			CONFIG.LoggingEnabled and COLORS.GREEN or COLORS.ACCENT
		)
	end
)

bind(
	AddVisiblePool.MouseButton1Click,
	function()

		for id, profile
			in pairs(
				State.Profiles
			)
		do

			if
				filterMatch(
					id,
					profile
				)
			then

				addGhostPool(id)
			end
		end
		showStatus("Visible animation results added to Ghost pool", COLORS.GREEN)
	end
)

--==============================================================
-- LIVE UI
--==============================================================

local LiveScroll,
	LiveLayout =
	mkScroll(
		LivePage,
		0,
		0,
		444,
		324
	)

local function makeLiveRow(track)

	if State.LiveRows[track] then
		return
			State.LiveRows[track]
	end

	local row =
		mkButton(
			LiveScroll,
			"",
			0,
			0,
			442,
			24
		)

	row.Size =
		UDim2.new(
			1,
			-2,
			0,
			24
		)

	row.BorderSizePixel =
		0

	local text =
		mkLabel(
			row,
			"",
			5,
			0,
			428,
			24,
			8
		)

	State.LiveRows[track] = {
		button = row,
		text = text,
	}

	bind(
		row.MouseButton1Click,
		function()

			local id =
				getId(track)

			if id then

				State.Selected =
					id

				PREFS.SelectedAnimation = id

				UI.RefreshBurst()

				if UI.RefreshGhost then
					UI.RefreshGhost()
				end
			end
		end
	)

	return
		State.LiveRows[track]
end

local function updateLiveCanvas()

	task.defer(function()

		LiveScroll.CanvasSize =
			UDim2.fromOffset(
				0,
				LiveLayout.AbsoluteContentSize.Y
			)
	end)
end

task.spawn(function()

	while not State.Destroyed do

		task.wait(
			CONFIG.PollRate
		)

		local animator =
			State.TargetAnimator

		if not animator then
			continue
		end

		local tracks =
			safe(
				function()

					return
						animator:
							GetPlayingAnimationTracks()
				end,
				{}
			)

		local now =
			os.clock()

		local active = {}

		for _, track
			in ipairs(tracks)
		do

			active[track] =
				true

			State.LastSeen[track] =
				now

			local row =
				makeLiveRow(track)

			local id =
				getId(track)
				or "?"

			local speed =
				safe(
					function()
						return track.Speed
					end,
					0
				)

			local pos =
				safe(
					function()
						return track.TimePosition
					end,
					0
				)

			local wc =
				safe(
					function()
						return track.WeightCurrent
					end,
					0
				)

			local wt =
				safe(
					function()
						return track.WeightTarget
					end,
					0
				)

			local pri =
				safe(
					function()
						return track.Priority.Name
					end,
					"?"
				)

			local looped =
				safe(
					function()
						return track.Looped
					end,
					false
				)

			row.text.TextColor3 =
				COLORS.TEXT

			row.text.Text =
				string.format(
					"● %-13s S:%4.2f P:%5.3f W:%0.6f>%0.4f %-7s L:%s",
					id,
					speed,
					pos,
					wc,
					wt,
					pri,
					looped
						and "Y"
						or "N"
				)
		end

		for track, seen
			in pairs(
				State.LastSeen
			)
		do

			if not active[track] then

				local age =
					now
					-
					seen

				local row =
					State.LiveRows[track]

				if
					age >
					CONFIG.RecentTTL
				then

					State.LastSeen[track] =
						nil

					if row then

						pcall(function()

							row.button:
								Destroy()
						end)

						State.LiveRows[track] =
							nil
					end

				elseif row then

					row.text.TextColor3 =
						COLORS.MUTED

					row.text.Text =
						string.format(
							"· %-13s recent %.2fs",
							getId(track)
								or "?",
							age
						)
				end
			end
		end

		updateLiveCanvas()
	end
end)

--==============================================================
-- GHOST UI
--==============================================================

local GhostID =
	mkLabel(
		GhostPage,
		"",
		0,
		0,
		260,
		20,
		11
	)

local FireOnceButton =
	mkButton(
		GhostPage,
		"FIRE ONCE",
		282,
		0,
		78,
		23
	)

local AddPoolButton =
	mkButton(
		GhostPage,
		"+POOL",
		366,
		0,
		70,
		23
	)

local AutoProfileButton =
	mkButton(
		GhostPage,
		"AUTO PROFILE",
		0,
		31,
		96,
		23
	)

local GhostPriorityButton =
	mkButton(
		GhostPage,
		"PRIORITY: CORE",
		102,
		31,
		110,
		23
	)

local RandomButton =
	mkButton(
		GhostPage,
		"ORDER: SEQ",
		218,
		31,
		91,
		23
	)

local StartGhostButton =
	mkButton(
		GhostPage,
		"START",
		315,
		31,
		58,
		23
	)

StartGhostButton.BackgroundColor3 =
	COLORS.GREEN

local StopGhostButton =
	mkButton(
		GhostPage,
		"STOP",
		379,
		31,
		57,
		23
	)

StopGhostButton.BackgroundColor3 =
	COLORS.RED

local GhostProfileText =
	mkLabel(
		GhostPage,
		"",
		0,
		63,
		436,
		37,
		8
	)

GhostProfileText.TextWrapped =
	true

GhostProfileText.TextColor3 =
	COLORS.MUTED

local function ghostField(
	name,
	x,
	y
)

	mkLabel(
		GhostPage,
		name,
		x,
		y,
		88,
		21,
		9
	)

	return
		mkBox(
			GhostPage,
			"",
			x + 91,
			y,
			70,
			21
		)
end

local GhostSpeed =
	ghostField(
		"SPEED",
		0,
		108
	)

local GhostLife =
	ghostField(
		"LIFETIME",
		0,
		135
	)

local GhostWeight =
	ghostField(
		"TARGET WT",
		0,
		162
	)

local GhostCap =
	ghostField(
		"VIS CAP",
		0,
		189
	)

local GhostInterval =
	ghostField(
		"INTERVAL",
		0,
		216
	)

local GhostGap =
	ghostField(
		"GAP",
		0,
		243
	)

local GhostFadeMin =
	ghostField(
		"MIN FADE",
		190,
		108
	)

local GhostSafety =
	ghostField(
		"FADE SAFE",
		190,
		135
	)

local GhostAutoLife =
	ghostField(
		"AUTO LIFE",
		190,
		162
	)

local PoolLabel =
	mkLabel(
		GhostPage,
		"POOL:",
		190,
		195,
		240,
		18,
		9
	)

local PoolText =
	mkLabel(
		GhostPage,
		"",
		190,
		216,
		246,
		65,
		8
	)

PoolText.TextWrapped =
	true

PoolText.TextYAlignment =
	Enum.TextYAlignment.Top

local ClearPool =
	mkButton(
		GhostPage,
		"CLEAR POOL",
		190,
		286,
		90,
		22
	)

local LegGuardButton =
	mkButton(
		GhostPage,
		"LEGS: GUARDED",
		286,
		286,
		150,
		22
	)

do
local GhostLedger = Instance.new("Frame")
GhostLedger.Position = UDim2.fromOffset(444, 0)
GhostLedger.Size = UDim2.fromOffset(212, 403)
GhostLedger.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
GhostLedger.BorderColor3 = COLORS.BORDER
GhostLedger.BorderSizePixel = 1
GhostLedger.Parent = GhostPage

local GhostLedgerHeading = mkLabel(GhostLedger, "EXPERIMENT LEDGER", 8, 3, 196, 20, 10)
GhostLedgerHeading.TextColor3 = COLORS.ACCENT
local GhostLedgerText = mkLabel(GhostLedger, "No Ghost tests recorded.", 8, 28, 196, 210, 8)
GhostLedgerText.TextYAlignment = Enum.TextYAlignment.Top
GhostLedgerText.TextWrapped = false

local GhostMarkClean = mkButton(GhostLedger, "VISUAL: CLEAN", 8, 248, 94, 23)
local GhostMarkTwitch = mkButton(GhostLedger, "VISUAL: TWITCH", 110, 248, 94, 23)
local GhostRemoteYes = mkButton(GhostLedger, "REMOTE: YES", 8, 277, 94, 23)
local GhostRemoteNo = mkButton(GhostLedger, "REMOTE: NO", 110, 277, 94, 23)
local GhostCopyLedger = mkButton(GhostLedger, "COPY JSON", 8, 306, 94, 23)
local GhostClearLedger = mkButton(GhostLedger, "CLEAR", 110, 306, 94, 23)
local GhostLedgerHint = mkLabel(
	GhostLedger,
	"Run one controlled test, then mark what you saw locally and whether the remote logger detected it.",
	8,
	337,
	196,
	56,
	8
)
GhostLedgerHint.TextWrapped = true
GhostLedgerHint.TextYAlignment = Enum.TextYAlignment.Top
GhostLedgerHint.TextColor3 = COLORS.MUTED

local function refreshGhostLedger()
	local rows = {}
	local first = math.max(1, #State.GhostExperiments - 8)
	for index = first, #State.GhostExperiments do
		local item = State.GhostExperiments[index]
		rows[#rows + 1] = string.format(
			"#%d %s W%.6f R%.2f %s/%s",
			item.sequence or index,
			item.id or "?",
			item.maxWeight or 0,
			item.rotation or 0,
			item.visualResult == "clean" and "C" or item.visualResult == "twitch" and "T" or "?",
			item.remoteResult == "yes" and "R+" or item.remoteResult == "no" and "R-" or "R?"
		)
	end
	GhostLedgerText.Text = #rows > 0 and table.concat(rows, "\n") or "No Ghost tests recorded."
	local last = State.LastGhostDiagnostic
	GhostMarkClean.BackgroundColor3 = last and last.visualResult == "clean" and COLORS.GREEN or COLORS.PANEL2
	GhostMarkTwitch.BackgroundColor3 = last and last.visualResult == "twitch" and COLORS.RED or COLORS.PANEL2
	GhostRemoteYes.BackgroundColor3 = last and last.remoteResult == "yes" and COLORS.GREEN or COLORS.PANEL2
	GhostRemoteNo.BackgroundColor3 = last and last.remoteResult == "no" and COLORS.RED or COLORS.PANEL2
end

local function markLast(field, value, message)
	local last = State.LastGhostDiagnostic
	if not last then
		showStatus("Fire one Ghost test before recording an observation", COLORS.RED)
		return
	end
	last[field] = value
	refreshGhostLedger()
	showStatus(message, (value == "twitch" or value == "no") and COLORS.RED or COLORS.GREEN)
end

bind(GhostMarkClean.MouseButton1Click, function()
	markLast("visualResult", "clean", "Last Ghost test marked visually clean")
end)
bind(GhostMarkTwitch.MouseButton1Click, function()
	markLast("visualResult", "twitch", "Last Ghost test marked with visible twitch")
end)
bind(GhostRemoteYes.MouseButton1Click, function()
	markLast("remoteResult", "yes", "Last Ghost test marked remote-detected")
end)
bind(GhostRemoteNo.MouseButton1Click, function()
	markLast("remoteResult", "no", "Last Ghost test marked not detected remotely")
end)
bind(GhostCopyLedger.MouseButton1Click, function()
	local clipboard = rawget(ENV, "setclipboard")
	if type(clipboard) ~= "function" then
		showStatus("Clipboard API unavailable on this executor", COLORS.RED)
		return
	end
	local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, {
		version = 1,
		clawVersion = ENV.CLAW and ENV.CLAW.Version or "unknown",
		experiments = State.GhostExperiments,
	})
	local okCopy = okEncode and pcall(clipboard, encoded)
	showStatus(
		okCopy and ("Copied " .. tostring(#State.GhostExperiments) .. " Ghost experiments")
			or "Could not copy the Ghost experiment ledger",
		okCopy and COLORS.GREEN or COLORS.RED
	)
end)
bind(GhostClearLedger.MouseButton1Click, function()
	table.clear(State.GhostExperiments)
	State.LastGhostDiagnostic = nil
	refreshGhostLedger()
	showStatus("Ghost experiment ledger cleared", COLORS.ACCENT)
end)

UI.RefreshGhostLedger = refreshGhostLedger
end

local function pullGhostFields()

	CONFIG.Ghost.Speed =
		clampNumber(
			GhostSpeed.Text,
			0.01,
			20,
			CONFIG.Ghost.Speed
		)

	CONFIG.Ghost.Lifetime =
		clampNumber(
			GhostLife.Text,
			0.001,
			1,
			CONFIG.Ghost.Lifetime
		)

	CONFIG.Ghost.TargetWeight =
		clampNumber(
			GhostWeight.Text,
			0.001,
			10,
			CONFIG.Ghost.TargetWeight
		)

	CONFIG.Ghost.VisibleCap =
		clampNumber(
			GhostCap.Text,
			0.000001,
			0.1,
			CONFIG.Ghost.VisibleCap
		)

	CONFIG.Ghost.Interval =
		clampNumber(
			GhostInterval.Text,
			0.005,
			10,
			CONFIG.Ghost.Interval
		)

	CONFIG.Ghost.Gap =
		clampNumber(
			GhostGap.Text,
			0,
			1,
			CONFIG.Ghost.Gap
		)

	CONFIG.Ghost.MinFade =
		clampNumber(
			GhostFadeMin.Text,
			1,
			10000,
			CONFIG.Ghost.MinFade
		)

	CONFIG.Ghost.FadeSafety =
		clampNumber(
			GhostSafety.Text,
			1,
			10,
			CONFIG.Ghost.FadeSafety
		)

	CONFIG.Ghost.AutoLifeCap =
		clampNumber(
			GhostAutoLife.Text,
			0.001,
			1,
			CONFIG.Ghost.AutoLifeCap
		)

	UI.RefreshGhost()
end

for _, box
	in ipairs({
		GhostSpeed,
		GhostLife,
		GhostWeight,
		GhostCap,
		GhostInterval,
		GhostGap,
		GhostFadeMin,
		GhostSafety,
		GhostAutoLife,
	})
do

	bind(
		box.FocusLost,
		pullGhostFields
	)
end

UI.RefreshGhost =
	function()

		local id =
			State.Selected

		GhostID.Text =
			"Selected: "
			..
			id

		local profile =
			State.Profiles[id]

		if profile then

			GhostProfileText.Text =
				string.format(
					"learned: S %.3f [%.3f-%.3f] | LIFE %.4f | WT %.4f | WCmax %.6f | %s",
					avgSpeed(profile),

					profile.speedMin
						== math.huge
						and 0
						or
						profile.speedMin,

					profile.speedMax,

					avgLife(profile),

					profile.weightTargetLast,

					profile.weightCurrentMax,

					modePriority(profile)
				)

		else

			GhostProfileText.Text =
				"no learned profile for selected animation"
		end

		local diagnostic =
			State.LastGhostDiagnostic

		if diagnostic then
			GhostProfileText.Text ..=
				string.format(
					"\nlast: %s | leg %s | pos %.6f | rot %.3f deg",
					diagnostic.priority
						or "?",
					diagnostic.joint,
					diagnostic.position,
					diagnostic.rotation
				)
		end

		AutoProfileButton.Text =
			CONFIG.Ghost.AutoProfile
			and "AUTO: ON"
			or "AUTO: OFF"

		AutoProfileButton.BackgroundColor3 =
			CONFIG.Ghost.AutoProfile
			and COLORS.GREEN
			or COLORS.RED

		GhostPriorityButton.Text =
			CONFIG.Ghost.UseLearnedPriority
			and "PRIORITY: LEARN"
			or
			"PRIORITY: "
				..
				CONFIG.Ghost.Priority

		GhostPriorityButton.BackgroundColor3 =
			CONFIG.Ghost.UseLearnedPriority
			and COLORS.RED
			or
			(
				CONFIG.Ghost.Priority == "Action"
				and COLORS.BLUE
				or COLORS.GREEN
			)

		RandomButton.Text =
			CONFIG.Ghost.RandomOrder
			and "ORDER:RANDOM"
			or "ORDER:SEQ"

		StartGhostButton.Text =
			State.GhostRunning
			and "RUNNING"
			or "START"

		LegGuardButton.Text =
			CONFIG.Ghost.LegGuard
			and "LEGS: GUARDED"
			or "LEGS: FREE"

		LegGuardButton.BackgroundColor3 =
			CONFIG.Ghost.LegGuard
			and COLORS.GREEN
			or COLORS.RED

		GhostSpeed.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.Speed
			)

		GhostLife.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.Lifetime
			)

		GhostWeight.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.TargetWeight
			)

		GhostCap.Text =
			string.format(
				"%.6f",
				CONFIG.Ghost.VisibleCap
			)

		GhostInterval.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.Interval
			)

		GhostGap.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.Gap
			)

		GhostFadeMin.Text =
			string.format(
				"%.0f",
				CONFIG.Ghost.MinFade
			)

		GhostSafety.Text =
			string.format(
				"%.2f",
				CONFIG.Ghost.FadeSafety
			)

		GhostAutoLife.Text =
			string.format(
				"%.4f",
				CONFIG.Ghost.AutoLifeCap
			)

		local pool = {}

		for i, poolID
			in ipairs(
				State.GhostPool
			)
		do

			table.insert(
				pool,
				string.format(
					"%d:%s",
					i,
					poolID
				)
			)
		end

		PoolText.Text =
			#pool > 0
			and
			table.concat(
				pool,
				"  "
			)
			or "(empty)"

		if UI.RefreshGhostLedger then
			UI.RefreshGhostLedger()
		end

		refreshStatus()
	end

bind(
	FireOnceButton.MouseButton1Click,
	function()

		ghostFire(
			State.Selected
		)
	end
)

bind(
	AddPoolButton.MouseButton1Click,
	function()

		addGhostPool(
			State.Selected
		)
	end
)

bind(
	AutoProfileButton.MouseButton1Click,
	function()

		CONFIG.Ghost.AutoProfile =
			not
			CONFIG.Ghost.AutoProfile

		UI.RefreshGhost()
	end
)

bind(
	GhostPriorityButton.MouseButton1Click,
	function()

		-- Controlled A/B selector informed by Lycoris validation:
		-- Core is least visible, Action is more likely to be observed,
		-- and Learn copies the selected animation's recorded priority.
		stopGhostRunner()

		if CONFIG.Ghost.UseLearnedPriority then
			CONFIG.Ghost.UseLearnedPriority = false
			CONFIG.Ghost.Priority = "Core"
		elseif CONFIG.Ghost.Priority == "Core" then
			CONFIG.Ghost.Priority = "Action"
		else
			CONFIG.Ghost.UseLearnedPriority = true
		end

		UI.RefreshGhost()
	end
)

bind(
	RandomButton.MouseButton1Click,
	function()

		CONFIG.Ghost.RandomOrder =
			not
			CONFIG.Ghost.RandomOrder

		UI.RefreshGhost()
	end
)

bind(
	StartGhostButton.MouseButton1Click,
	startGhostRunner
)

bind(
	StopGhostButton.MouseButton1Click,
	stopGhostRunner
)

bind(
	ClearPool.MouseButton1Click,
	function()

		stopGhostRunner()

		State.GhostPool = {}

		UI.RefreshGhost()
	end
)

bind(
	LegGuardButton.MouseButton1Click,
	function()

		CONFIG.Ghost.LegGuard =
			not CONFIG.Ghost.LegGuard

		UI.RefreshGhost()
	end
)

--==============================================================
-- WEBHOOK TAB
--==============================================================

local LootStatus =
	mkLabel(
		WebhookPage,
		"",
		0,
		0,
		430,
		22,
		10
	)

local URLBox =
	mkBox(
		WebhookPage,
		"",
		0,
		35,
		350,
		24
	)

URLBox.PlaceholderText =
	"paste replacement Discord webhook URL"

local SetURL =
	mkButton(
		WebhookPage,
		"SET URL",
		358,
		35,
		78,
		24
	)

local ClearURL =
	mkButton(
		WebhookPage,
		"CLEAR URL",
		358,
		65,
		78,
		24
	)

local UsernameBox =
	field(
		WebhookPage,
		"USERNAME",
		103
	)

UsernameBox.Position =
	UDim2.fromOffset(
		145,
		103
	)

UsernameBox.Text =
	CONFIG.Webhook.Username

local UserIDBox =
	field(
		WebhookPage,
		"USER ID",
		132
	)

UserIDBox.Position =
	UDim2.fromOffset(
		145,
		132
	)

UserIDBox.Text =
	CONFIG.Webhook.UserID

local MessageBox =
	mkBox(
		WebhookPage,
		"CLAW MARK test",
		0,
		175,
		350,
		26
	)

local SendButton =
	mkButton(
		WebhookPage,
		"SEND",
		358,
		175,
		78,
		26
	)

local FlushButton =
	mkButton(
		WebhookPage,
		"FLUSH LOOT",
		0,
		215,
		100,
		24
	)

local TestLootButton =
	mkButton(
		WebhookPage,
		"TEST LOOT",
		108,
		215,
		100,
		24
	)

local WebhookResult =
	mkLabel(
		WebhookPage,
		"",
		0,
		252,
		430,
		38,
		9
	)

WebhookResult.TextColor3 =
	COLORS.MUTED

local function refreshWebhook()

	local loot =
		getLootAPI()

	local hasLoot =
		loot ~= nil

	local lootStatus = nil

	if
		hasLoot
		and type(loot.getStatus) == "function"
	then
		local ok, result =
			pcall(loot.getStatus)

		if ok and type(result) == "table" then
			lootStatus = result
		end
	end

	local requestReady =
		getRequestImplementation()
		~= nil
		or
		(
			lootStatus
			and lootStatus.httpReady
		)

	local urlReady =
		CONFIG.Webhook.URL
		and
		CONFIG.Webhook.URL ~= ""

	LootStatus.Text =
		string.format(
			"Loot API: %s    HTTP: %s    Loot URL: %s",
			hasLoot
				and "DETECTED"
				or "NOT FOUND",

			requestReady
				and "READY"
				or "MISSING",

			(
				(
					lootStatus
					and lootStatus.configured
				)
				or urlReady
			)
				and "SET"
				or "NOT SET"
		)

	if urlReady then

		URLBox.Text =
			"[ webhook configured ]"

	else

		URLBox.Text =
			""
	end

	refreshStatus()
end

bind(
	URLBox.Focused,
	function()

		if
			URLBox.Text
			==
			"[ webhook configured ]"
		then

			URLBox.Text =
				""
		end
	end
)

bind(
	SetURL.MouseButton1Click,
	function()

		local candidate =
			URLBox.Text

		if
			candidate
			and
			candidate ~= ""
			and
			string.find(
				candidate,
				"/api/webhooks/",
				1,
				true
			)
		then

			CONFIG.Webhook.URL =
				candidate

			PREFS.WebhookURL =
				candidate

			URLBox.Text =
				"[ webhook configured ]"

			local synced, syncDetail =
				callLootMethod(
					"configure",
					{
						url = candidate,
					}
				)

			WebhookResult.Text =
				synced
				and "Webhook stored and synced to Loot."
				or
				(
					getLootAPI()
					and
					(
						"Direct URL stored; Loot sync failed: "
						..
						tostring(syncDetail)
					)
					or "Webhook stored for direct sends."
				)

		else

			WebhookResult.Text =
				"That does not look like a Discord webhook URL."
		end

		refreshWebhook()
	end
)

bind(
	ClearURL.MouseButton1Click,
	function()

		CONFIG.Webhook.URL =
			""

		PREFS.WebhookURL =
			""

		local synced, detail =
			callLootMethod(
				"configure",
				{
					url = "",
				}
			)

		URLBox.Text =
			""

		WebhookResult.Text =
			synced
			and "Webhook cleared from direct sender and Loot."
			or
			(
				getLootAPI()
				and
				(
					"Direct URL cleared; Loot sync failed: "
					..
					tostring(detail)
				)
				or "Standalone webhook cleared."
			)

		refreshWebhook()
	end
)

bind(
	UsernameBox.FocusLost,
	function()

		CONFIG.Webhook.Username =
			UsernameBox.Text

		PREFS.WebhookUsername =
			UsernameBox.Text

		local synced, detail =
			callLootMethod(
				"configure",
				{
					username =
						UsernameBox.Text,
				}
			)

		if getLootAPI() and not synced then
			WebhookResult.Text =
				"Loot username sync failed: "
				..
				tostring(detail)
		end
	end
)

bind(
	UserIDBox.FocusLost,
	function()

		CONFIG.Webhook.UserID =
			UserIDBox.Text

		PREFS.WebhookUserID =
			UserIDBox.Text

		local synced, detail =
			callLootMethod(
				"configure",
				{
					userID =
						UserIDBox.Text,
				}
			)

		if getLootAPI() and not synced then
			WebhookResult.Text =
				"Loot user ID sync failed: "
				..
				tostring(detail)
		end
	end
)

bind(
	SendButton.MouseButton1Click,
	function()

		local ok, method, detail =
			sendWebhookText(
				MessageBox.Text
			)

		WebhookResult.Text =
			ok
			and
			(
				"Sent successfully "
				..
				tostring(method)
			)
			or
			(
				"Send failed ("
				..
				tostring(method)
				..
				"): "
				..
				tostring(detail or "unknown error")
			)

		refreshWebhook()
	end
)

bind(
	FlushButton.MouseButton1Click,
	function()

		local ok, detail =
			callLootMethod(
				"flushNow"
			)

		WebhookResult.Text =
			ok
			and "Existing Loot queue flushed."
			or
			(
				"Loot flush failed: "
				..
				tostring(detail)
			)
	end
)

bind(
	TestLootButton.MouseButton1Click,
	function()

		local queued, queueDetail =
			callLootMethod(
				"notify",
				MessageBox.Text,
				{
					rarity = "legendary",
				}
			)

		if not queued then
			WebhookResult.Text =
				"Loot test failed: "
				..
				tostring(queueDetail)

			return
		end

		local flushed, flushDetail =
			callLootMethod(
				"flushNow"
			)

		WebhookResult.Text =
			flushed
			and "Test item queued and Loot flush requested."
			or
			(
				"Test queued; flush failed: "
				..
				tostring(flushDetail)
			)
	end
)

--==============================================================
-- CLAW MARK COMBAT UI
--==============================================================

local CombatRuntime =
	State.Combat

local CombatRefreshers = {}

local function combatRefreshAll()
	for _, refresh in ipairs(CombatRefreshers) do
		pcall(refresh)
	end
	refreshStatus()
end

local function combatSection(
	parent,
	title,
	x,
	y,
	width,
	height
)
	local panel =
		Instance.new("Frame")

	panel.Position =
		UDim2.fromOffset(x, y)

	panel.Size =
		UDim2.fromOffset(width, height)

	panel.BackgroundColor3 =
		Color3.fromRGB(20, 20, 24)

	panel.BorderColor3 =
		COLORS.BORDER

	panel.BorderSizePixel = 1

	panel.Parent =
		parent

	local heading =
		mkLabel(
			panel,
			title,
			8,
			3,
			width - 16,
			20,
			10
		)

	heading.TextColor3 =
		COLORS.ACCENT

	return panel
end

local function combatToggle(
	parent,
	label,
	path,
	x,
	y,
	width,
	enabledColor,
	disabledColor
)
	local button =
		mkButton(
			parent,
			"",
			x,
			y,
			width,
			23
		)

	local function refresh()
		local enabled =
			CombatRuntime
			and CombatRuntime.Settings:get(path)

		button.Text =
			label
			.. ": "
			.. (enabled and "ON" or "OFF")

		button.BackgroundColor3 =
			enabled
			and (enabledColor or COLORS.GREEN)
			or (disabledColor or COLORS.RED)
	end

	CombatRefreshers[#CombatRefreshers + 1] =
		refresh

	bind(
		button.MouseButton1Click,
		function()
			if not CombatRuntime then
				return
			end
			CombatRuntime:set(
				path,
				not CombatRuntime.Settings:get(path)
			)
			combatRefreshAll()
		end
	)

	refresh()
	return button
end

local function combatCycle(
	parent,
	label,
	path,
	values,
	x,
	y,
	width
)
	local button =
		mkButton(
			parent,
			"",
			x,
			y,
			width,
			23
		)

	local function refresh()
		local value =
			CombatRuntime
			and CombatRuntime.Settings:get(path)
			or "N/A"
		button.Text =
			label .. ": " .. tostring(value)
	end

	CombatRefreshers[#CombatRefreshers + 1] =
		refresh

	bind(
		button.MouseButton1Click,
		function()
			if not CombatRuntime then
				return
			end
			local current =
				CombatRuntime.Settings:get(path)
			local index =
				table.find(values, current)
				or 0
			index =
				(index % #values) + 1
			CombatRuntime:set(path, values[index])
			combatRefreshAll()
		end
	)

	refresh()
	return button
end

local function combatNumber(
	parent,
	label,
	path,
	x,
	y,
	minimum,
	maximum
)
	mkLabel(
		parent,
		label,
		x,
		y,
		116,
		22,
		9
	)

	local box =
		mkBox(
			parent,
			"",
			x + 120,
			y,
			72,
			22
		)

	local function refresh()
		local value =
			CombatRuntime
			and CombatRuntime.Settings:get(path)
			or 0
		box.Text =
			tostring(value)
	end

	CombatRefreshers[#CombatRefreshers + 1] =
		refresh

	bind(
		box.FocusLost,
		function()
			if not CombatRuntime then
				return
			end
			local current =
				CombatRuntime.Settings:get(path)
			CombatRuntime:set(
				path,
				clampNumber(
					box.Text,
					minimum,
					maximum,
					current
				)
			)
			refresh()
		end
	)

	refresh()
	return box
end

local function combatText(
	parent,
	label,
	path,
	x,
	y,
	labelWidth,
	boxWidth
)
	mkLabel(parent, label, x, y, labelWidth, 22, 9)
	local box =
		mkBox(
			parent,
			"",
			x + labelWidth + 4,
			y,
			boxWidth,
			22
		)

	local function refresh()
		if not CombatRuntime or box:IsFocused() then
			return
		end
		box.Text = tostring(CombatRuntime.Settings:get(path) or "")
	end

	CombatRefreshers[#CombatRefreshers + 1] = refresh
	bind(box.FocusLost, function()
		if CombatRuntime then
			CombatRuntime:set(path, box.Text)
		end
		refresh()
	end)
	refresh()
	return box
end

do
local function buildCombatUI()
if not CombatRuntime then
	local unavailable =
		mkLabel(
			CombatPage,
			"Combat modules did not initialize. Rebuild CLAW MARK and reload.",
			0,
			0,
			650,
			30,
			11
		)
	unavailable.TextColor3 =
		COLORS.RED
else
	local defensePanel =
		combatSection(
			CombatPage,
			"DEFENSE",
			0,
			0,
			324,
			205
		)

	combatToggle(defensePanel, "MASTER", "Enabled", 8, 28, 148)
	combatToggle(defensePanel, "AUTO DEF", "Defense.Enabled", 164, 28, 148)
	combatCycle(
		defensePanel,
		"PRIMARY",
		"Defense.Preferred",
		{ "Parry", "Dodge", "Block", "FullDodge", "Jump" },
		8,
		57,
		148
	)
	combatToggle(defensePanel, "DODGE FALLBACK", "Defense.DodgeFallback", 164, 57, 148)
	combatToggle(defensePanel, "BLOCK FALLBACK", "Defense.BlockFallback", 8, 86, 148)
	combatToggle(defensePanel, "ROLL ON CD", "Defense.RollOnParryCooldown", 164, 86, 148)
	combatToggle(defensePanel, "VENT FALLBACK", "Defense.VentFallback", 8, 115, 148)
	combatToggle(defensePanel, "ROLL CANCEL", "Defense.RollCancel", 164, 115, 148)
	combatToggle(defensePanel, "PARRY ONLY", "Defense.ParryOnly", 8, 144, 148)
	combatToggle(defensePanel, "PREDICTION", "Defense.UsePredictionMantra", 164, 144, 148)
	combatToggle(defensePanel, "PUNISHMENT", "Defense.UsePunishmentMantra", 8, 173, 148)
	combatToggle(defensePanel, "DIRECT ROLL", "Defense.DirectRoll", 164, 173, 148)

	local targetPanel =
		combatSection(
			CombatPage,
			"TARGETING",
			332,
			0,
			324,
			205
		)

	combatCycle(
		targetPanel,
		"MODE",
		"Targeting.Selection",
		{ "ClosestDistance", "ClosestCrosshair", "LeastHealth", "LowestHealthRatio", "HighestThreat" },
		8,
		28,
		304
	)
	combatNumber(targetPanel, "MAX DISTANCE", "Targeting.MaxDistance", 8, 57, 1, 10000)
	combatNumber(targetPanel, "FOV DEGREES", "Targeting.FOVDegrees", 8, 84, 0, 360)
	combatNumber(targetPanel, "MAX TARGETS", "Targeting.MaxTargets", 8, 111, 1, 64)
	combatToggle(targetPanel, "IGNORE PLAYERS", "Targeting.IgnorePlayers", 205, 57, 107)
	combatToggle(targetPanel, "IGNORE MOBS", "Targeting.IgnoreMobs", 205, 84, 107)
	combatToggle(targetPanel, "IGNORE ALLIES", "Targeting.IgnoreAllies", 205, 111, 107)
	combatToggle(targetPanel, "ON SCREEN", "Targeting.RequireOnScreen", 8, 144, 148)
	combatToggle(targetPanel, "ADAPTIVE SCAN", "Diagnostics.AdaptiveScan", 164, 144, 148)
	combatToggle(targetPanel, "MOB TARGET", "Targeting.CheckMobTarget", 8, 173, 148)
	local targetListsButton =
		mkButton(targetPanel, "TARGET LISTS", 164, 173, 148, 23)

	local validationPanel =
		combatSection(
			CombatPage,
			"VALIDATION + FILTERS",
			0,
			213,
			324,
			205
		)

	combatToggle(validationPanel, "HITBOX", "Validation.Hitbox", 8, 28, 148)
	combatToggle(validationPanel, "FACING", "Validation.Facing", 164, 28, 148)
	combatToggle(validationPanel, "PREDICTION", "Validation.Prediction", 8, 57, 148)
	combatToggle(validationPanel, "VISIBILITY", "Validation.Visibility", 164, 57, 148)
	combatToggle(validationPanel, "STUN", "Validation.Stun", 8, 86, 148)
	combatToggle(validationPanel, "IFRAMES", "Validation.IFrames", 164, 86, 148)
	combatToggle(validationPanel, "TEXTBOX", "Filters.TextboxFocused", 8, 115, 148)
	combatToggle(validationPanel, "INACTIVE", "Filters.WindowInactive", 164, 115, 148)
	combatToggle(validationPanel, "FILTER M1", "Filters.M1", 8, 144, 148)
	combatToggle(validationPanel, "FILTER MANTRA", "Filters.Mantra", 164, 144, 148)
	combatToggle(validationPanel, "FILTER CRIT", "Filters.Critical", 8, 173, 148)
	combatToggle(validationPanel, "FILTER UNKNOWN", "Filters.Undefined", 164, 173, 148)

	local detectionPanel =
		combatSection(
			CombatPage,
			"DETECTION + PRESETS",
			332,
			213,
			324,
			205
		)

	combatToggle(detectionPanel, "ANIMATIONS", "Detection.Animations", 8, 28, 148)
	combatToggle(detectionPanel, "SOUNDS", "Detection.Sounds", 164, 28, 148)
	combatToggle(detectionPanel, "PARTS", "Detection.Parts", 8, 57, 148)
	combatToggle(detectionPanel, "EFFECTS", "Detection.Effects", 164, 57, 148)
	combatToggle(detectionPanel, "INDEXED ONLY", "Detection.OnlyConfigured", 8, 86, 148)
	combatToggle(detectionPanel, "UNKNOWN ANIMS", "Detection.UnknownAnimations", 164, 86, 148)

	local presetNames =
		CombatRuntime.Presets:names()

	local selectedPreset = table.find(presetNames, "Stable") and "Stable" or presetNames[1]

	local presetCycle =
		mkButton(
			detectionPanel,
			"PRESET: " .. string.upper(selectedPreset or "NONE"),
			8,
			115,
			200,
			23
		)

	bind(
		presetCycle.MouseButton1Click,
		function()
			local index = selectedPreset and table.find(presetNames, selectedPreset) or 0
			selectedPreset = presetNames[(index % #presetNames) + 1]
			presetCycle.Text = "PRESET: " .. string.upper(selectedPreset)
			showStatus(CombatRuntime.Presets:describe(selectedPreset), COLORS.ACCENT, 4)
		end
	)

	local applyPreset =
		mkButton(detectionPanel, "APPLY", 216, 115, 96, 23)

	bind(
		applyPreset.MouseButton1Click,
		function()
			if not selectedPreset then
				return
			end
			local ok, reason = CombatRuntime:applyPreset(selectedPreset)
			combatRefreshAll()
			showStatus(
				ok and ("Applied " .. selectedPreset .. " preset") or ("Preset failed: " .. tostring(reason)),
				ok and COLORS.GREEN or COLORS.RED
			)
		end
	)

	local saveCombat =
		mkButton(detectionPanel, "SAVE SETTINGS", 8, 144, 148, 23)

	local reloadCombat =
		mkButton(detectionPanel, "RELOAD TARGETS", 164, 144, 148, 23)

	bind(saveCombat.MouseButton1Click, function()
		local ok, reason = CombatRuntime:save()
		showStatus(ok and "Combat settings saved" or ("Save failed: " .. tostring(reason)), ok and COLORS.GREEN or COLORS.RED)
	end)

	bind(reloadCombat.MouseButton1Click, function()
		CombatRuntime.State:setTargets({})
		CombatRuntime._lastScan = 0
		showStatus("Target scan refreshed", COLORS.GREEN)
	end)

	local advancedTuningButton =
		mkButton(detectionPanel, "ADVANCED TUNING", 8, 173, 304, 23)

	local function makeCombatModal(title, width, height)
		local modal = Instance.new("Frame")
		modal.Position = UDim2.fromOffset(math.floor((656 - width) / 2), math.floor((418 - height) / 2))
		modal.Size = UDim2.fromOffset(width, height)
		modal.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
		modal.BorderColor3 = COLORS.ACCENT
		modal.BorderSizePixel = 1
		modal.Visible = false
		modal.ZIndex = 20
		modal.Parent = CombatPage

		local heading = mkLabel(modal, title, 10, 4, width - 52, 24, 11)
		heading.TextColor3 = COLORS.ACCENT
		local close = mkButton(modal, "X", width - 34, 5, 26, 22)
		bind(close.MouseButton1Click, function()
			modal.Visible = false
		end)
		return modal
	end

	local function raiseModal(modal)
		for _, descendant in ipairs(modal:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex = 21
			end
		end
	end

	local tuningModal = makeCombatModal("ADVANCED TUNING", 430, 389)
	combatToggle(tuningModal, "PROBABILITY", "Probability.Enabled", 10, 35, 198)
	combatToggle(tuningModal, "ALLOW FAILURE", "Probability.AllowFailure", 218, 35, 202)
	combatNumber(tuningModal, "FAILURE %", "Probability.FailureRate", 10, 64, 0, 100)
	combatNumber(tuningModal, "DASH %", "Probability.DashInsteadOfParryRate", 218, 64, 0, 100)
	combatNumber(tuningModal, "IGNORE END %", "Probability.IgnoreAnimationEndRate", 10, 91, 0, 100)
	combatNumber(tuningModal, "GLOBAL OFFSET", "Timing.GlobalOffset", 218, 91, -3, 3)
	combatNumber(tuningModal, "PING SCALE", "Timing.PingScale", 10, 118, 0, 3)
	combatNumber(tuningModal, "PREDICT SEC", "Validation.PredictionSeconds", 218, 118, 0, 1)
	combatToggle(tuningModal, "PING COMP", "Timing.PingCompensation", 10, 149, 198)
	combatToggle(tuningModal, "AUTO-PARRY FRAMES", "Validation.AutoParryFrames", 218, 149, 202)
	combatToggle(tuningModal, "HOLD-BLOCK FILTER", "Filters.HoldingBlock", 10, 178, 198)
	combatToggle(tuningModal, "CHIME FILTER", "Filters.ChimeCountdown", 218, 178, 202)
	combatToggle(tuningModal, "NOTIFICATIONS", "Diagnostics.Notifications", 10, 207, 198)
	combatToggle(tuningModal, "COOLDOWN CHECK", "Validation.Cooldown", 218, 207, 202)
	combatNumber(tuningModal, "HITBOX WAIT", "Timing.MaxHitboxWait", 10, 238, 0.1, 30)
	combatNumber(tuningModal, "POLL SEC", "Timing.HitboxPollInterval", 218, 238, 0.01, 1)
	combatNumber(tuningModal, "ROLL CANCEL", "Defense.RollCancelDelay", 10, 265, 0, 2)
	combatNumber(tuningModal, "BLOCK HOLD", "Defense.BlockFallbackHold", 218, 265, 0, 3)
	combatToggle(tuningModal, "ANIM SANITY", "Validation.AnimationSanity", 10, 296, 198)
	combatToggle(tuningModal, "THREAT GUARD", "ThreatGuard.Enabled", 218, 296, 202)
	combatNumber(tuningModal, "UNKNOWN DELAY", "Defense.UnknownAnimationDelay", 10, 323, 0, 3)
	combatNumber(tuningModal, "UNKNOWN MAX SEC", "Defense.UnknownAnimationMaxLength", 218, 323, 0.1, 30)
	combatText(tuningModal, "TOGGLE DEFENSE KEY", "Bindings.ToggleDefense", 10, 354, 180, 226)
	raiseModal(tuningModal)

	bind(advancedTuningButton.MouseButton1Click, function()
		tuningModal.Visible = true
		combatRefreshAll()
	end)

	local listsModal = makeCombatModal("TARGET LISTS", 500, 310)
	local whitelistLabel = mkLabel(listsModal, "WHITELIST (ONE NAME OR USER ID PER LINE)", 12, 37, 230, 24, 9)
	local blacklistLabel = mkLabel(listsModal, "BLACKLIST (ONE NAME OR USER ID PER LINE)", 258, 37, 230, 24, 9)
	whitelistLabel.TextColor3 = COLORS.GREEN
	blacklistLabel.TextColor3 = COLORS.RED
	local whitelistBox = mkBox(listsModal, "", 12, 63, 230, 190)
	local blacklistBox = mkBox(listsModal, "", 258, 63, 230, 190)
	for _, box in ipairs({ whitelistBox, blacklistBox }) do
		box.MultiLine = true
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = Enum.TextYAlignment.Top
	end

	local function parseTargetList(value)
		local list = {}
		local seen = {}
		for entry in string.gmatch(value or "", "[^,%s]+") do
			if not seen[entry] then
				seen[entry] = true
				list[#list + 1] = entry
			end
		end
		return list
	end
	local function formatTargetList(list)
		local formatted = {}
		for _, value in ipairs(list or {}) do
			formatted[#formatted + 1] = tostring(value)
		end
		return table.concat(formatted, "\n")
	end

	local applyLists = mkButton(listsModal, "APPLY LISTS", 12, 267, 150, 28)
	local listMode = mkButton(listsModal, "", 175, 267, 150, 28)
	local clearLists = mkButton(listsModal, "CLEAR BOTH", 338, 267, 150, 28)
	local function refreshListMode()
		listMode.Text = "MODE: " .. string.upper(CombatRuntime.Settings:get("Targeting.WhitelistMode"))
	end
	bind(applyLists.MouseButton1Click, function()
		CombatRuntime:set("Targeting.Whitelist", parseTargetList(whitelistBox.Text))
		CombatRuntime:set("Targeting.Blacklist", parseTargetList(blacklistBox.Text))
		listsModal.Visible = false
		showStatus("Target lists applied", COLORS.GREEN)
	end)
	bind(clearLists.MouseButton1Click, function()
		whitelistBox.Text = ""
		blacklistBox.Text = ""
	end)
	bind(listMode.MouseButton1Click, function()
		local current = CombatRuntime.Settings:get("Targeting.WhitelistMode")
		CombatRuntime:set("Targeting.WhitelistMode", current == "Exclude" and "Only" or "Exclude")
		refreshListMode()
	end)
	bind(targetListsButton.MouseButton1Click, function()
		whitelistBox.Text = formatTargetList(CombatRuntime.Settings:get("Targeting.Whitelist"))
		blacklistBox.Text = formatTargetList(CombatRuntime.Settings:get("Targeting.Blacklist"))
		refreshListMode()
		listsModal.Visible = true
	end)
	raiseModal(listsModal)
end
end
buildCombatUI()
end

--==============================================================
-- TIMING EDITOR UI
--==============================================================

do
local function buildTimingEditor()
local TimingSelected
local TimingCategory = "animation"
local TimingAction = "Parry"
local TimingActionChance = 100
local TimingActionName = "Parry"
local TimingActionDuration = 0
local TimingActionHitbox = { X = 0, Y = 0, Z = 0 }
local TimingActionIgnoreHitbox = false
local TimingActions = {}
local TimingActionIndex = 1
local function defaultTimingAdvanced()
	return {
		delayUntilHitbox = false,
		preferRepeat = false,
		allowAttacking = false,
		facingHitbox = true,
		hyperArmor = false,
		allowLocalPlayer = false,
		useHitboxCFrame = false,
		ignoreLocalPlayer = false,
		forceLocalPlayer = false,
		noDodgeFallback = false,
		noBlockFallback = false,
		noVentFallback = false,
		preferBlockFallback = false,
		ignoreAnimationEnd = false,
		ignoreEarlyAnimationEnd = false,
		pastHitbox = false,
		predictFacing = false,
		disablePrediction = false,
		repeatStartDelay = 0,
		repeatDelay = 0,
		hitboxOffset = 0,
		historySeconds = 0,
		predictionSeconds = 0,
		maxAnimationTime = 0,
		failureRate = 0,
		dashRate = 0,
		ignoreEndRate = 0,
	}
end
local TimingAdvanced = defaultTimingAdvanced()
local refreshTimingAdvanced = function() end
local refreshTimingActions = function() end

local TimingBrowser = {
	page = 1,
	pageSize = 100,
	filter = "all",
}

TimingBrowser.search = mkBox(TimingsPage, "", 0, 0, 140, 23)
TimingBrowser.search.PlaceholderText = "search timings"
TimingBrowser.filterButton = mkButton(TimingsPage, "TYPE: ALL", 146, 0, 94, 23)

local TimingList,
	TimingListLayout =
	mkScroll(
		TimingsPage,
		0,
		31,
		240,
		336
	)

TimingBrowser.previous = mkButton(TimingsPage, "< PREV", 0, 375, 55, 23)
TimingBrowser.pageLabel = mkLabel(TimingsPage, "PAGE 1/1", 59, 375, 122, 23, 9)
TimingBrowser.pageLabel.TextXAlignment = Enum.TextXAlignment.Center
TimingBrowser.next = mkButton(TimingsPage, "NEXT >", 185, 375, 55, 23)

local timingEditor =
	combatSection(
		TimingsPage,
		"TIMING PROFILE EDITOR",
		248,
		0,
		408,
		403
	)

local timingCategoryButton =
	mkButton(
		timingEditor,
		"TYPE: ANIMATION",
		8,
		28,
		190,
		23
	)

local timingActionButton =
	mkButton(
		timingEditor,
		"ACTION: PARRY",
		206,
		28,
		194,
		23
	)

local function timingBox(label, y, x)
	x = x or 8
	mkLabel(timingEditor, label, x, y, 86, 22, 9)
	return mkBox(timingEditor, "", x + 90, y, 100, 22)
end

local TimingIDBox = timingBox("ID / NAME", 59, 8)
local TimingNameBox = timingBox("LABEL", 86, 8)
local TimingTagBox = timingBox("TAG", 113, 8)
local TimingDelayBox = timingBox("DELAY SEC", 140, 8)
local TimingMinBox = timingBox("MIN DIST", 59, 206)
local TimingMaxBox = timingBox("MAX DIST", 86, 206)
local TimingHitXBox = timingBox("HITBOX X", 113, 206)
local TimingHitYBox = timingBox("HITBOX Y", 140, 206)
local TimingHitZBox = timingBox("HITBOX Z", 167, 206)
local TimingAfterBox = timingBox("AFTER WIN", 167, 8)
local TimingPunishBox = timingBox("PUNISH WIN", 194, 8)
local TimingBlockBox = timingBox("BLOCK HOLD", 194, 206)

local timingSaveButton =
	mkButton(timingEditor, "SAVE PROFILE", 8, 230, 94, 25)

local timingRemoveButton =
	mkButton(timingEditor, "REMOVE", 180, 230, 68, 25)

local timingCopyButton =
	mkButton(timingEditor, "COPY", 256, 230, 62, 25)

local timingAdvancedButton =
	mkButton(timingEditor, "ADV", 326, 230, 74, 25)

local timingActionsButton =
	mkButton(timingEditor, "ACTIONS: 0", 110, 230, 62, 25)

local TimingJSONBox =
	mkBox(
		timingEditor,
		"",
		8,
		265,
		392,
		92
	)

TimingJSONBox.MultiLine = true
TimingJSONBox.ClearTextOnFocus = false
TimingJSONBox.TextXAlignment = Enum.TextXAlignment.Left
TimingJSONBox.TextYAlignment = Enum.TextYAlignment.Top
TimingJSONBox.PlaceholderText = "paste CLAW timing JSON here"

local timingImportButton =
	mkButton(timingEditor, "IMPORT JSON", 8, 365, 126, 25)

local timingLoadButton =
	mkButton(timingEditor, "LOAD FILE", 142, 365, 126, 25)

local timingClearButton =
	mkButton(timingEditor, "CLEAR", 276, 365, 124, 25)

local function clearTimingEditor()
	TimingSelected = nil
	TimingIDBox.Text = ""
	TimingNameBox.Text = ""
	TimingTagBox.Text = "Undefined"
	TimingDelayBox.Text = "0.15"
	TimingMinBox.Text = "0"
	TimingMaxBox.Text = "65"
	TimingHitXBox.Text = "0"
	TimingHitYBox.Text = "0"
	TimingHitZBox.Text = "0"
	TimingAfterBox.Text = "0.12"
	TimingPunishBox.Text = "0.70"
	TimingBlockBox.Text = "0.30"
	TimingActionChance = 100
	TimingActionName = "Parry"
	TimingActionDuration = 0
	TimingActionHitbox = { X = 0, Y = 0, Z = 0 }
	TimingActionIgnoreHitbox = false
	TimingActions = {}
	TimingActionIndex = 1
	TimingAdvanced = defaultTimingAdvanced()
	refreshTimingAdvanced()
	refreshTimingActions()
end

local function loadTimingEditor(profile)
	TimingSelected = profile
	TimingCategory = profile.detector
	TimingIDBox.Text = profile.id
	TimingNameBox.Text = profile.name
	TimingTagBox.Text = profile.tag
	TimingDelayBox.Text = tostring(profile.actions[1] and profile.actions[1].delay or 0)
	TimingAction = profile.actions[1] and profile.actions[1].kind or "Parry"
	TimingActionChance = profile.actions[1] and profile.actions[1].chance or 100
	TimingActionName = profile.actions[1] and profile.actions[1].name or TimingAction
	TimingActionDuration = profile.actions[1] and profile.actions[1].duration or 0
	local firstActionHitbox = profile.actions[1] and profile.actions[1].hitbox or Vector3.zero
	TimingActionHitbox = { X = firstActionHitbox.X, Y = firstActionHitbox.Y, Z = firstActionHitbox.Z }
	TimingActionIgnoreHitbox = profile.actions[1] and profile.actions[1].ignoreHitbox or false
	TimingActions = {}
	for _, action in ipairs(profile.actions) do
		TimingActions[#TimingActions + 1] = action:serialize()
	end
	TimingActionIndex = 1
	TimingMinBox.Text = tostring(profile.minDistance)
	TimingMaxBox.Text = tostring(profile.maxDistance)
	TimingHitXBox.Text = tostring(profile.hitbox.X)
	TimingHitYBox.Text = tostring(profile.hitbox.Y)
	TimingHitZBox.Text = tostring(profile.hitbox.Z)
	TimingAfterBox.Text = tostring(profile.afterWindow)
	TimingPunishBox.Text = tostring(profile.punishableWindow)
	TimingBlockBox.Text = tostring(profile.blockFallbackHold)
	TimingAdvanced = {
		delayUntilHitbox = profile.delayUntilHitbox,
		preferRepeat = profile.preferRepeat,
		allowAttacking = profile.allowAttacking,
		facingHitbox = profile.facingHitbox,
		noDodgeFallback = profile.noDodgeFallback,
		noBlockFallback = profile.noBlockFallback,
		noVentFallback = profile.noVentFallback,
		preferBlockFallback = profile.preferBlockFallback,
		hyperArmor = profile.hyperArmor,
		allowLocalPlayer = profile.allowLocalPlayer,
		useHitboxCFrame = profile.useHitboxCFrame,
		ignoreLocalPlayer = profile.ignoreLocalPlayer,
		forceLocalPlayer = profile.forceLocalPlayer,
		ignoreAnimationEnd = profile.ignoreAnimationEnd,
		ignoreEarlyAnimationEnd = profile.ignoreEarlyAnimationEnd,
		pastHitbox = profile.pastHitbox,
		predictFacing = profile.predictFacing,
		disablePrediction = profile.disablePrediction,
		repeatStartDelay = profile.repeatStartDelay,
		repeatDelay = profile.repeatDelay,
		hitboxOffset = profile.hitboxOffset,
		historySeconds = profile.historySeconds,
		predictionSeconds = profile.predictionSeconds,
		maxAnimationTime = profile.maxAnimationTime,
		failureRate = profile.probability.FailureRate or 0,
		dashRate = profile.probability.DashInsteadOfParryRate or 0,
		ignoreEndRate = profile.probability.IgnoreAnimationEndRate or 0,
	}
	timingCategoryButton.Text = "TYPE: " .. string.upper(TimingCategory)
	timingActionButton.Text = "ACTION: " .. string.upper(TimingAction)
	refreshTimingAdvanced()
	refreshTimingActions()
end

local timingAdvancedModal = Instance.new("Frame")
timingAdvancedModal.Position = UDim2.fromOffset(68, 10)
timingAdvancedModal.Size = UDim2.fromOffset(520, 382)
timingAdvancedModal.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
timingAdvancedModal.BorderColor3 = COLORS.ACCENT
timingAdvancedModal.BorderSizePixel = 1
timingAdvancedModal.Visible = false
timingAdvancedModal.ZIndex = 20
timingAdvancedModal.Parent = TimingsPage

local advancedHeading = mkLabel(timingAdvancedModal, "ADVANCED TIMING PROFILE", 10, 4, 450, 24, 11)
advancedHeading.TextColor3 = COLORS.ACCENT
local advancedClose = mkButton(timingAdvancedModal, "X", 484, 5, 26, 22)

local advancedRefreshers = {}
local function timingAdvancedToggle(label, key, x, y)
	local button = mkButton(timingAdvancedModal, "", x, y, 244, 23)
	local function refresh()
		button.Text = label .. ": " .. (TimingAdvanced[key] and "ON" or "OFF")
		button.BackgroundColor3 = TimingAdvanced[key] and COLORS.GREEN or COLORS.RED
	end
	advancedRefreshers[#advancedRefreshers + 1] = refresh
	bind(button.MouseButton1Click, function()
		TimingAdvanced[key] = not TimingAdvanced[key]
		refresh()
	end)
	return button
end

local function timingAdvancedNumber(label, key, x, y, minimum, maximum, chance)
	mkLabel(timingAdvancedModal, label, x, y, 120, 22, 9)
	local box = mkBox(timingAdvancedModal, "", x + 124, y, 120, 22)
	local function refresh()
		box.Text = tostring(chance and TimingActionChance or TimingAdvanced[key])
	end
	advancedRefreshers[#advancedRefreshers + 1] = refresh
	bind(box.FocusLost, function()
		local current = chance and TimingActionChance or TimingAdvanced[key]
		local value = clampNumber(box.Text, minimum, maximum, current)
		if chance then
			TimingActionChance = value
		else
			TimingAdvanced[key] = value
		end
		refresh()
	end)
	return box
end

local function timingAdvancedCompactNumber(label, key, x, y)
	mkLabel(timingAdvancedModal, label, x, y, 94, 22, 8)
	local box = mkBox(timingAdvancedModal, "", x + 98, y, 62, 22)
	local function refresh()
		box.Text = tostring(TimingAdvanced[key])
	end
	advancedRefreshers[#advancedRefreshers + 1] = refresh
	bind(box.FocusLost, function()
		TimingAdvanced[key] = clampNumber(box.Text, 0, 100, TimingAdvanced[key])
		refresh()
	end)
end

UI.RefreshLogging = function()
	LoggingToggle.Text = CONFIG.LoggingEnabled and "LOGGER: ON" or "LOGGER: OFF"
	LoggingToggle.BackgroundColor3 = CONFIG.LoggingEnabled and COLORS.GREEN or COLORS.PANEL2
	local count = 0
	for _ in pairs(State.Profiles) do
		count += 1
	end
	LogCount.Text = tostring(count) .. " UNIQUE"
	refreshStatus()
end

timingAdvancedToggle("DELAY UNTIL HITBOX", "delayUntilHitbox", 10, 35)
timingAdvancedToggle("FACING HITBOX", "facingHitbox", 266, 35)
timingAdvancedToggle("REPEAT UNTIL END", "preferRepeat", 10, 64)
timingAdvancedToggle("ALLOW WHILE ATTACKING", "allowAttacking", 266, 64)
timingAdvancedToggle("NO DODGE FALLBACK", "noDodgeFallback", 10, 93)
timingAdvancedToggle("NO BLOCK FALLBACK", "noBlockFallback", 266, 93)
timingAdvancedToggle("NO VENT FALLBACK", "noVentFallback", 10, 122)
timingAdvancedToggle("PREFER BLOCK FALLBACK", "preferBlockFallback", 266, 122)
timingAdvancedToggle("IGNORE ANIMATION END", "ignoreAnimationEnd", 10, 151)
timingAdvancedToggle("IGNORE EARLY END", "ignoreEarlyAnimationEnd", 266, 151)
timingAdvancedToggle("PAST HITBOX", "pastHitbox", 10, 180)
timingAdvancedToggle("PREDICT FACING", "predictFacing", 266, 180)
timingAdvancedToggle("DISABLE PREDICTION", "disablePrediction", 10, 209)
local timingCategoryOption = mkButton(timingAdvancedModal, "", 266, 209, 244, 23)
local function refreshTimingCategoryOption()
	if TimingCategory == "animation" then
		timingCategoryOption.Text = "HYPERARMOR: " .. (TimingAdvanced.hyperArmor and "ON" or "OFF")
		timingCategoryOption.BackgroundColor3 = TimingAdvanced.hyperArmor and COLORS.GREEN or COLORS.RED
	elseif TimingCategory == "sound" then
		timingCategoryOption.Text = "ALLOW LOCAL SOUND: " .. (TimingAdvanced.allowLocalPlayer and "ON" or "OFF")
		timingCategoryOption.BackgroundColor3 = TimingAdvanced.allowLocalPlayer and COLORS.GREEN or COLORS.RED
	elseif TimingCategory == "part" then
		timingCategoryOption.Text = "USE PART ROTATION: " .. (TimingAdvanced.useHitboxCFrame and "ON" or "OFF")
		timingCategoryOption.BackgroundColor3 = TimingAdvanced.useHitboxCFrame and COLORS.GREEN or COLORS.RED
	else
		local policy = TimingAdvanced.forceLocalPlayer and "FORCE LOCAL"
			or TimingAdvanced.ignoreLocalPlayer and "IGNORE LOCAL"
			or "ANY OWNER"
		timingCategoryOption.Text = "EFFECT OWNER: " .. policy
		timingCategoryOption.BackgroundColor3 = COLORS.PANEL2
	end
end
advancedRefreshers[#advancedRefreshers + 1] = refreshTimingCategoryOption
bind(timingCategoryOption.MouseButton1Click, function()
	if TimingCategory == "animation" then
		TimingAdvanced.hyperArmor = not TimingAdvanced.hyperArmor
	elseif TimingCategory == "sound" then
		TimingAdvanced.allowLocalPlayer = not TimingAdvanced.allowLocalPlayer
	elseif TimingCategory == "part" then
		TimingAdvanced.useHitboxCFrame = not TimingAdvanced.useHitboxCFrame
	elseif TimingAdvanced.forceLocalPlayer then
		TimingAdvanced.forceLocalPlayer = false
	elseif TimingAdvanced.ignoreLocalPlayer then
		TimingAdvanced.ignoreLocalPlayer = false
		TimingAdvanced.forceLocalPlayer = true
	else
		TimingAdvanced.ignoreLocalPlayer = true
	end
	refreshTimingCategoryOption()
end)

timingAdvancedNumber("REPEAT START", "repeatStartDelay", 10, 242, 0, 10)
timingAdvancedNumber("REPEAT DELAY", "repeatDelay", 266, 242, 0, 10)
timingAdvancedNumber("HITBOX SHIFT", "hitboxOffset", 10, 269, -1000, 1000)
timingAdvancedNumber("HISTORY SEC", "historySeconds", 266, 269, 0, 10)
timingAdvancedNumber("PREDICT SEC", "predictionSeconds", 10, 296, 0, 3)
timingAdvancedNumber("MAX ANIM SEC", "maxAnimationTime", 266, 296, 0, 30)
timingAdvancedNumber("ACTION CHANCE %", nil, 10, 323, 0, 100, true)

local advancedReset = mkButton(timingAdvancedModal, "RESET ADVANCED", 266, 323, 244, 22)
timingAdvancedCompactNumber("FAILURE %", "failureRate", 10, 352)
timingAdvancedCompactNumber("DASH %", "dashRate", 180, 352)
timingAdvancedCompactNumber("IGNORE END %", "ignoreEndRate", 350, 352)

refreshTimingAdvanced = function()
	for _, refresh in ipairs(advancedRefreshers) do
		refresh()
	end
end

bind(advancedReset.MouseButton1Click, function()
	TimingActionChance = 100
	TimingAdvanced = defaultTimingAdvanced()
	refreshTimingAdvanced()
end)

local function closeTimingAdvanced()
	timingAdvancedModal.Visible = false
end
bind(advancedClose.MouseButton1Click, closeTimingAdvanced)
bind(timingAdvancedButton.MouseButton1Click, function()
	refreshTimingAdvanced()
	timingAdvancedModal.Visible = true
end)

for _, descendant in ipairs(timingAdvancedModal:GetDescendants()) do
	if descendant:IsA("GuiObject") then
		descendant.ZIndex = 21
	end
end

local function currentTimingAction()
	local existing = TimingActions[TimingActionIndex] or {}
	return {
		kind = TimingAction,
		name = TimingActionName ~= "" and TimingActionName or existing.name or TimingAction,
		delay = tonumber(TimingDelayBox.Text) or 0.15,
		duration = TimingActionDuration,
		hitbox = {
			X = TimingActionHitbox.X,
			Y = TimingActionHitbox.Y,
			Z = TimingActionHitbox.Z,
		},
		ignoreHitbox = TimingActionIgnoreHitbox,
		chance = TimingActionChance,
		metadata = existing.metadata or {},
	}
end

local timingActionsModal = Instance.new("Frame")
timingActionsModal.Position = UDim2.fromOffset(108, 11)
timingActionsModal.Size = UDim2.fromOffset(440, 380)
timingActionsModal.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
timingActionsModal.BorderColor3 = COLORS.ACCENT
timingActionsModal.BorderSizePixel = 1
timingActionsModal.Visible = false
timingActionsModal.ZIndex = 22
timingActionsModal.Parent = TimingsPage
local actionsHeading = mkLabel(timingActionsModal, "MULTI-ACTION MANAGER", 10, 4, 350, 24, 11)
actionsHeading.TextColor3 = COLORS.ACCENT
local actionsClose = mkButton(timingActionsModal, "X", 404, 5, 26, 22)
local actionsScroll, actionsLayout = mkScroll(timingActionsModal, 10, 35, 420, 205)
local actionHitboxBoxes = {}
for index, axis in ipairs({ "X", "Y", "Z" }) do
	local x = 10 + ((index - 1) * 142)
	mkLabel(timingActionsModal, "ACTION HITBOX " .. axis, x, 247, 92, 22, 8)
	local box = mkBox(timingActionsModal, "0", x + 96, 247, 40, 22)
	actionHitboxBoxes[axis] = box
	bind(box.FocusLost, function()
		TimingActionHitbox[axis] = clampNumber(box.Text, 0, 10000, TimingActionHitbox[axis])
		box.Text = tostring(TimingActionHitbox[axis])
	end)
end
local actionIgnoreHitbox = mkButton(timingActionsModal, "", 10, 276, 150, 24)
mkLabel(timingActionsModal, "DELAY", 168, 276, 42, 22, 8)
local actionDelayBox = mkBox(timingActionsModal, "0.15", 212, 276, 62, 22)
mkLabel(timingActionsModal, "CHANCE", 282, 276, 50, 22, 8)
local actionChanceBox = mkBox(timingActionsModal, "100", 336, 276, 94, 22)
mkLabel(timingActionsModal, "NAME", 10, 307, 48, 22, 8)
local actionNameBox = mkBox(timingActionsModal, "", 60, 307, 166, 22)
mkLabel(timingActionsModal, "DURATION", 238, 307, 70, 22, 8)
local actionDurationBox = mkBox(timingActionsModal, "0", 312, 307, 118, 22)
bind(actionNameBox.FocusLost, function()
	TimingActionName = actionNameBox.Text
end)
bind(actionDurationBox.FocusLost, function()
	TimingActionDuration = clampNumber(actionDurationBox.Text, 0, 30, TimingActionDuration)
	actionDurationBox.Text = tostring(TimingActionDuration)
end)
bind(actionDelayBox.FocusLost, function()
	TimingDelayBox.Text = tostring(clampNumber(actionDelayBox.Text, 0, 30, tonumber(TimingDelayBox.Text) or 0.15))
	actionDelayBox.Text = TimingDelayBox.Text
end)
bind(actionChanceBox.FocusLost, function()
	TimingActionChance = clampNumber(actionChanceBox.Text, 0, 100, TimingActionChance)
	actionChanceBox.Text = tostring(TimingActionChance)
end)
local addCurrentAction = mkButton(timingActionsModal, "ADD", 10, 337, 94, 28)
local updateCurrentAction = mkButton(timingActionsModal, "UPDATE", 112, 337, 96, 28)
local removeCurrentAction = mkButton(timingActionsModal, "REMOVE", 216, 337, 96, 28)
local clearTimingActions = mkButton(timingActionsModal, "CLEAR", 320, 337, 110, 28)

refreshTimingActions = function()
	timingActionsButton.Text = "ACTIONS: " .. tostring(#TimingActions)
	actionIgnoreHitbox.Text = "IGNORE ACTION HITBOX: " .. (TimingActionIgnoreHitbox and "ON" or "OFF")
	actionIgnoreHitbox.BackgroundColor3 = TimingActionIgnoreHitbox and COLORS.GREEN or COLORS.RED
	actionNameBox.Text = TimingActionName
	actionDurationBox.Text = tostring(TimingActionDuration)
	actionDelayBox.Text = TimingDelayBox.Text
	actionChanceBox.Text = tostring(TimingActionChance)
	for axis, box in pairs(actionHitboxBoxes) do
		box.Text = tostring(TimingActionHitbox[axis])
	end
	for _, child in ipairs(actionsScroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for index, action in ipairs(TimingActions) do
		local row = mkButton(
			actionsScroll,
			string.format("%02d  %-10s  %.3fs  %s", index, action.kind, action.delay or 0, action.name or ""),
			0,
			0,
			396,
			25
		)
		row.Size = UDim2.new(1, -4, 0, 25)
		row.ZIndex = 24
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.BackgroundColor3 = index == TimingActionIndex and COLORS.ACCENT or COLORS.PANEL2
		row.MouseButton1Click:Connect(function()
			TimingActionIndex = index
			TimingAction = action.kind
			TimingActionChance = action.chance or 100
			TimingActionName = action.name or action.kind
			TimingActionDuration = action.duration or 0
			local hitbox = action.hitbox or { X = 0, Y = 0, Z = 0 }
			TimingActionHitbox = { X = hitbox.X or 0, Y = hitbox.Y or 0, Z = hitbox.Z or 0 }
			TimingActionIgnoreHitbox = action.ignoreHitbox == true
			TimingDelayBox.Text = tostring(action.delay or 0)
			timingActionButton.Text = "ACTION: " .. string.upper(TimingAction)
			refreshTimingAdvanced()
			refreshTimingActions()
		end)
	end
	task.defer(function()
		actionsScroll.CanvasSize = UDim2.fromOffset(0, actionsLayout.AbsoluteContentSize.Y)
	end)
end

bind(actionIgnoreHitbox.MouseButton1Click, function()
	TimingActionIgnoreHitbox = not TimingActionIgnoreHitbox
	refreshTimingActions()
end)

bind(addCurrentAction.MouseButton1Click, function()
	TimingActionIndex = #TimingActions + 1
	TimingActions[TimingActionIndex] = currentTimingAction()
	refreshTimingActions()
end)
bind(updateCurrentAction.MouseButton1Click, function()
	if #TimingActions == 0 then
		TimingActionIndex = 1
	end
	TimingActions[TimingActionIndex] = currentTimingAction()
	refreshTimingActions()
end)
bind(removeCurrentAction.MouseButton1Click, function()
	if TimingActions[TimingActionIndex] then
		table.remove(TimingActions, TimingActionIndex)
		TimingActionIndex = math.clamp(TimingActionIndex, 1, math.max(1, #TimingActions))
		refreshTimingActions()
	end
end)
bind(clearTimingActions.MouseButton1Click, function()
	TimingActions = {}
	TimingActionIndex = 1
	refreshTimingActions()
end)
bind(timingActionsButton.MouseButton1Click, function()
	refreshTimingActions()
	timingActionsModal.Visible = true
end)
bind(actionsClose.MouseButton1Click, function()
	timingActionsModal.Visible = false
end)
for _, descendant in ipairs(timingActionsModal:GetDescendants()) do
	if descendant:IsA("GuiObject") then
		descendant.ZIndex = 23
	end
end

local function refreshTimingList()
	for _, child in ipairs(TimingList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if not CombatRuntime then
		return
	end

	local matches = {}
	local query = string.lower(TimingBrowser.search.Text or "")
	for _, category in ipairs({ "animation", "sound", "part", "effect" }) do
		if TimingBrowser.filter == "all" or TimingBrowser.filter == category then
			for _, profile in ipairs(CombatRuntime.Timings:list(category)) do
				local searchable = string.lower(table.concat({
					category,
					tostring(profile.id or ""),
					tostring(profile.name or ""),
					tostring(profile.tag or ""),
					tostring(profile.sourceModule or ""),
				}, " "))
				if query == "" or string.find(searchable, query, 1, true) then
					matches[#matches + 1] = { category = category, profile = profile }
				end
			end
		end
	end

	local pageCount = math.max(1, math.ceil(#matches / TimingBrowser.pageSize))
	TimingBrowser.page = math.clamp(TimingBrowser.page, 1, pageCount)
	local first = ((TimingBrowser.page - 1) * TimingBrowser.pageSize) + 1
	local last = math.min(#matches, first + TimingBrowser.pageSize - 1)
	for index = first, last do
		local item = matches[index]
		if item then
			local category = item.category
			local profile = item.profile
			local row = mkButton(
				TimingList,
				string.format("[%s] %s", string.upper(string.sub(category, 1, 1)), profile.name),
				0,
				0,
				238,
				24
			)
			row.Size = UDim2.new(1, -2, 0, 24)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.MouseButton1Click:Connect(function()
				loadTimingEditor(profile)
			end)
		end
	end

	TimingBrowser.pageLabel.Text = string.format(
		"%d/%d  %d MATCH",
		TimingBrowser.page,
		pageCount,
		#matches
	)
	TimingBrowser.previous.BackgroundColor3 = TimingBrowser.page > 1 and COLORS.BLUE or COLORS.PANEL2
	TimingBrowser.next.BackgroundColor3 = TimingBrowser.page < pageCount and COLORS.BLUE or COLORS.PANEL2

	task.defer(function()
		TimingList.CanvasSize =
			UDim2.fromOffset(0, TimingListLayout.AbsoluteContentSize.Y)
	end)
end

bind(TimingBrowser.search:GetPropertyChangedSignal("Text"), function()
	TimingBrowser.page = 1
	refreshTimingList()
end)

bind(TimingBrowser.filterButton.MouseButton1Click, function()
	local filters = { "all", "animation", "sound", "part", "effect" }
	local index = table.find(filters, TimingBrowser.filter) or 0
	TimingBrowser.filter = filters[(index % #filters) + 1]
	TimingBrowser.filterButton.Text = "TYPE: " .. string.upper(TimingBrowser.filter)
	TimingBrowser.page = 1
	refreshTimingList()
end)

bind(TimingBrowser.previous.MouseButton1Click, function()
	TimingBrowser.page = math.max(1, TimingBrowser.page - 1)
	refreshTimingList()
end)

bind(TimingBrowser.next.MouseButton1Click, function()
	TimingBrowser.page += 1
	refreshTimingList()
end)

bind(timingCategoryButton.MouseButton1Click, function()
	local values = { "animation", "sound", "part", "effect" }
	local index = table.find(values, TimingCategory) or 0
	TimingCategory = values[(index % #values) + 1]
	timingCategoryButton.Text = "TYPE: " .. string.upper(TimingCategory)
	refreshTimingAdvanced()
end)

bind(timingActionButton.MouseButton1Click, function()
	local values = { "Parry", "Dodge", "FullDodge", "Block", "Jump", "Slide", "Crouch", "Teleport" }
	local index = table.find(values, TimingAction) or 0
	local previous = TimingAction
	TimingAction = values[(index % #values) + 1]
	if TimingActionName == previous then
		TimingActionName = TimingAction
	end
	timingActionButton.Text = "ACTION: " .. string.upper(TimingAction)
	refreshTimingActions()
end)

bind(timingSaveButton.MouseButton1Click, function()
	if not CombatRuntime or TimingIDBox.Text == "" then
		return
	end
	if #TimingActions == 0 then
		TimingActionIndex = 1
		TimingActions[1] = currentTimingAction()
	else
		TimingActionIndex = math.clamp(TimingActionIndex, 1, #TimingActions)
		TimingActions[TimingActionIndex] = currentTimingAction()
	end
	local ok, result = pcall(CombatRuntime.registerTiming, CombatRuntime, {
		id = TimingIDBox.Text,
		name = TimingNameBox.Text ~= "" and TimingNameBox.Text or TimingIDBox.Text,
		detector = TimingCategory,
		tag = TimingTagBox.Text ~= "" and TimingTagBox.Text or "Undefined",
		minDistance = tonumber(TimingMinBox.Text) or 0,
		maxDistance = tonumber(TimingMaxBox.Text) or 65,
		hitbox = Vector3.new(
			tonumber(TimingHitXBox.Text) or 0,
			tonumber(TimingHitYBox.Text) or 0,
			tonumber(TimingHitZBox.Text) or 0
		),
		hitboxOffset = TimingAdvanced.hitboxOffset,
		delayUntilHitbox = TimingAdvanced.delayUntilHitbox,
		afterWindow = tonumber(TimingAfterBox.Text) or 0.12,
		punishableWindow = tonumber(TimingPunishBox.Text) or 0.70,
		repeatStartDelay = TimingAdvanced.repeatStartDelay,
		repeatDelay = TimingAdvanced.repeatDelay,
		preferRepeat = TimingAdvanced.preferRepeat,
		allowAttacking = TimingAdvanced.allowAttacking,
		facingHitbox = TimingAdvanced.facingHitbox,
		noDodgeFallback = TimingAdvanced.noDodgeFallback,
		noBlockFallback = TimingAdvanced.noBlockFallback,
		noVentFallback = TimingAdvanced.noVentFallback,
		preferBlockFallback = TimingAdvanced.preferBlockFallback,
		hyperArmor = TimingAdvanced.hyperArmor,
		allowLocalPlayer = TimingAdvanced.allowLocalPlayer,
		useHitboxCFrame = TimingAdvanced.useHitboxCFrame,
		ignoreLocalPlayer = TimingAdvanced.ignoreLocalPlayer,
		forceLocalPlayer = TimingAdvanced.forceLocalPlayer,
		ignoreAnimationEnd = TimingAdvanced.ignoreAnimationEnd,
		ignoreEarlyAnimationEnd = TimingAdvanced.ignoreEarlyAnimationEnd,
		pastHitbox = TimingAdvanced.pastHitbox,
		predictFacing = TimingAdvanced.predictFacing,
		disablePrediction = TimingAdvanced.disablePrediction,
		historySeconds = TimingAdvanced.historySeconds,
		predictionSeconds = TimingAdvanced.predictionSeconds,
		maxAnimationTime = TimingAdvanced.maxAnimationTime,
		probability = {
			FailureRate = TimingAdvanced.failureRate,
			DashInsteadOfParryRate = TimingAdvanced.dashRate,
			IgnoreAnimationEndRate = TimingAdvanced.ignoreEndRate,
		},
		blockFallbackHold = tonumber(TimingBlockBox.Text) or 0.30,
		actions = TimingActions,
	}, true)
	if ok then
		TimingJSONBox.Text = ""
		refreshTimingList()
	else
		TimingJSONBox.Text = "Profile error: " .. tostring(result)
	end
end)

bind(timingRemoveButton.MouseButton1Click, function()
	if CombatRuntime and TimingSelected then
		CombatRuntime:removeTiming(TimingSelected.detector, TimingSelected.id, true)
		clearTimingEditor()
		refreshTimingList()
	end
end)

bind(timingCopyButton.MouseButton1Click, function()
	if CombatRuntime then
		CombatRuntime:exportTimings(true)
	end
end)

bind(timingImportButton.MouseButton1Click, function()
	if CombatRuntime and TimingJSONBox.Text ~= "" then
		local ok, reason = CombatRuntime:importTimings(TimingJSONBox.Text)
		if ok then
			TimingJSONBox.Text = ""
			refreshTimingList()
		else
			TimingJSONBox.Text = "Import failed: " .. tostring(reason)
		end
	end
end)

bind(timingLoadButton.MouseButton1Click, function()
	if CombatRuntime then
		local ok, reason = CombatRuntime.TimingIO:load()
		if ok then
			TimingJSONBox.Text = ""
			refreshTimingList()
		else
			TimingJSONBox.Text = "Load failed: " .. tostring(reason)
		end
	end
end)

bind(timingClearButton.MouseButton1Click, clearTimingEditor)

if CombatRuntime then
	bind(CombatRuntime.Timings.Changed, function()
		if TimingsPage.Visible then
			refreshTimingList()
		end
	end)
end

clearTimingEditor()
end
buildTimingEditor()
end

--==============================================================
-- ASSISTANCE UI
--==============================================================

do
local function buildAssistanceUI()
local attackAssistPanel =
	combatSection(AssistPage, "ATTACK ASSISTANCE", 0, 0, 324, 403)

local combatAssistPanel =
	combatSection(AssistPage, "COMBAT ASSISTANCE", 332, 0, 324, 403)

combatToggle(attackAssistPanel, "AUTO FEINT", "AttackAssistance.AutoFeint", 8, 28, 148)
combatToggle(attackAssistPanel, "DELAYED FEINT", "AttackAssistance.DelayedFeint", 164, 28, 148)
combatCycle(
	attackAssistPanel,
	"FEINT MODE",
	"AttackAssistance.AutoFeintMode",
	{ "Passive", "Aggressive" },
	8,
	57,
	304
)
combatNumber(attackAssistPanel, "FEINT DELAY", "AttackAssistance.FeintDelay", 8, 86, 0, 2)
combatNumber(attackAssistPanel, "FEINT LEAD", "AttackAssistance.FeintLead", 8, 113, 0, 1)
combatToggle(attackAssistPanel, "M1 HOLD", "AttackAssistance.HoldM1", 8, 144, 148)
combatToggle(attackAssistPanel, "FLOURISH FEINT", "AttackAssistance.FlourishFeint", 164, 144, 148)
combatToggle(attackAssistPanel, "ACTION ROLL", "AttackAssistance.ActionRolling", 8, 173, 148)
local rollTargetsButton = mkButton(attackAssistPanel, "ROLL TARGETS", 164, 173, 148, 23)
combatNumber(attackAssistPanel, "ROLL COOLDOWN", "AttackAssistance.ActionRollCooldown", 8, 202, 0, 10)
combatNumber(attackAssistPanel, "ROLL CANCEL", "AttackAssistance.ActionRollCancelDelay", 8, 229, 0, 2)
combatToggle(attackAssistPanel, "ANIM SPEED", "AttackAssistance.AnimationSpeed.Enabled", 8, 260, 148)
combatToggle(attackAssistPanel, "CONFIG ONLY", "AttackAssistance.AnimationSpeed.LimitToConfigured", 164, 260, 148)
combatToggle(attackAssistPanel, "EXTREMES", "AttackAssistance.AnimationSpeed.SwitchExtremes", 8, 289, 148)
combatNumber(attackAssistPanel, "SPEED MIN", "AttackAssistance.AnimationSpeed.Minimum", 8, 318, 0.05, 8)
combatNumber(attackAssistPanel, "SPEED MAX", "AttackAssistance.AnimationSpeed.Maximum", 8, 345, 0.05, 8)

combatToggle(combatAssistPanel, "AUTO WISP", "CombatAssistance.Wisp", 8, 28, 148)
combatToggle(combatAssistPanel, "GOLDEN TONGUE", "CombatAssistance.GoldenTongue", 164, 28, 148)
combatToggle(combatAssistPanel, "MANTRA FOLLOWUP", "CombatAssistance.MantraFollowUp", 8, 57, 148)
combatToggle(combatAssistPanel, "AUTO ARDOUR", "CombatAssistance.Ardour", 164, 57, 148)
combatToggle(combatAssistPanel, "FLOW STATE", "CombatAssistance.FlowState", 8, 86, 148)
combatToggle(combatAssistPanel, "RHYTHM", "CombatAssistance.Rhythm", 164, 86, 148)
combatToggle(combatAssistPanel, "RAGDOLL RECOVER", "CombatAssistance.RagdollResponse", 8, 115, 304)
combatToggle(combatAssistPanel, "TONGUE IN COMBAT", "CombatAssistance.GoldenTongueCombatOnly", 8, 144, 304)
combatToggle(combatAssistPanel, "FOLLOWUP REQ HIT", "CombatAssistance.MantraFollowUpRequireHit", 8, 173, 304)
combatNumber(combatAssistPanel, "WISP DELAY", "CombatAssistance.WispDelay", 8, 204, 0, 2)
combatNumber(combatAssistPanel, "ASSIST COOLDOWN", "CombatAssistance.AssistanceCooldown", 8, 231, 0, 5)

local bindingHeading =
	mkLabel(combatAssistPanel, "ASSIST KEY BINDINGS (BLANK = ADAPTER ONLY)", 8, 265, 304, 22, 9)
bindingHeading.TextColor3 = COLORS.ACCENT

local bindingsScroll, bindingsLayout =
	mkScroll(combatAssistPanel, 8, 288, 304, 106)

for _, binding in ipairs({
	{ "DIRECT DODGE", "Bindings.DirectDodge" },
	{ "PREDICTION", "Bindings.Prediction" },
	{ "PUNISHMENT", "Bindings.Punishment" },
	{ "VENT", "Bindings.Vent" },
	{ "WISP", "Bindings.Wisp" },
	{ "GOLDEN TONGUE", "Bindings.GoldenTongue" },
	{ "MANTRA FOLLOW", "Bindings.MantraFollowUp" },
	{ "ARDOUR", "Bindings.Ardour" },
	{ "FLOW STATE", "Bindings.FlowState" },
	{ "RHYTHM", "Bindings.Rhythm" },
	{ "RAGDOLL", "Bindings.RagdollRecover" },
	{ "TELEPORT", "Bindings.Teleport" },
}) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 27)
	row.BackgroundTransparency = 1
	row.Parent = bindingsScroll
	combatText(row, binding[1], binding[2], 4, 2, 122, 154)
end

task.defer(function()
	bindingsScroll.CanvasSize = UDim2.fromOffset(0, bindingsLayout.AbsoluteContentSize.Y)
end)

local rollTargetsModal = Instance.new("Frame")
rollTargetsModal.Position = UDim2.fromOffset(163, 108)
rollTargetsModal.Size = UDim2.fromOffset(330, 202)
rollTargetsModal.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
rollTargetsModal.BorderColor3 = COLORS.ACCENT
rollTargetsModal.BorderSizePixel = 1
rollTargetsModal.Visible = false
rollTargetsModal.ZIndex = 20
rollTargetsModal.Parent = AssistPage
local rollHeading = mkLabel(rollTargetsModal, "ACTION ROLL TARGETS", 10, 4, 270, 24, 11)
rollHeading.TextColor3 = COLORS.ACCENT
local rollClose = mkButton(rollTargetsModal, "X", 294, 5, 26, 22)
local rollTargetButtons = {}

local function hasRollTarget(name)
	return table.find(CombatRuntime.Settings:get("AttackAssistance.ActionRollingActions"), name) ~= nil
end

local function refreshRollTargets()
	local count = 0
	for name, button in pairs(rollTargetButtons) do
		local selected = hasRollTarget(name)
		if selected then
			count = count + 1
		end
		button.Text = name .. ": " .. (selected and "ON" or "OFF")
		button.BackgroundColor3 = selected and COLORS.GREEN or COLORS.RED
	end
	rollTargetsButton.Text = "ROLL TARGETS (" .. tostring(count) .. ")"
end

for index, name in ipairs({ "M1", "Critical", "Cast", "Parry" }) do
	local button = mkButton(rollTargetsModal, "", 10, 35 + ((index - 1) * 32), 310, 25)
	rollTargetButtons[name] = button
	bind(button.MouseButton1Click, function()
		local values = {}
		for _, existing in ipairs(CombatRuntime.Settings:get("AttackAssistance.ActionRollingActions")) do
			if existing ~= name then
				values[#values + 1] = existing
			end
		end
		if not hasRollTarget(name) then
			values[#values + 1] = name
		end
		CombatRuntime:set("AttackAssistance.ActionRollingActions", values)
		refreshRollTargets()
	end)
end

bind(rollTargetsButton.MouseButton1Click, function()
	refreshRollTargets()
	rollTargetsModal.Visible = true
end)
bind(rollClose.MouseButton1Click, function()
	rollTargetsModal.Visible = false
end)
refreshRollTargets()
for _, descendant in ipairs(rollTargetsModal:GetDescendants()) do
	if descendant:IsA("GuiObject") then
		descendant.ZIndex = 21
	end
end
end
buildAssistanceUI()
end

--==============================================================
-- DIAGNOSTICS UI
--==============================================================

do
local function buildDiagnosticsUI()
local debugControls =
	combatSection(DebugPage, "DIAGNOSTICS", 0, 0, 324, 403)

local debugStats =
	combatSection(DebugPage, "LIVE PERFORMANCE", 332, 0, 324, 403)

combatToggle(debugControls, "DIAGNOSTICS", "Diagnostics.Enabled", 8, 28, 148)
combatToggle(debugControls, "DETECT TRACE", "Diagnostics.TraceDetectors", 164, 28, 148)
combatToggle(debugControls, "SCHED TRACE", "Diagnostics.TraceScheduler", 8, 57, 148)
combatToggle(debugControls, "HITBOX VIEW", "Diagnostics.VisualizeHitboxes", 164, 57, 148)
local blockerWarning = mkLabel(debugControls, "FAULT INJECTION - KEEP THESE OFF", 8, 84, 304, 18, 9)
blockerWarning.TextColor3 = COLORS.RED
combatToggle(debugControls, "DISABLE PARRY", "DebugState.BlockParry", 8, 106, 148, COLORS.RED, COLORS.GREEN)
combatToggle(debugControls, "DISABLE DODGE", "DebugState.BlockDodge", 164, 106, 148, COLORS.RED, COLORS.GREEN)
combatToggle(debugControls, "DISABLE VENT", "DebugState.BlockVent", 8, 135, 148, COLORS.RED, COLORS.GREEN)
combatToggle(debugControls, "DISABLE BLOCK", "DebugState.NoBlocking", 164, 135, 148, COLORS.RED, COLORS.GREEN)
combatNumber(debugControls, "BUDGET MS", "Diagnostics.PerformanceBudgetMs", 8, 174, 0.1, 16)
combatNumber(debugControls, "EVENT BUFFER", "Diagnostics.MaxEvents", 8, 201, 10, 2000)

local clearDiagnostics =
	mkButton(debugControls, "CLEAR DIAGNOSTICS", 8, 240, 304, 25)

local copyDiagnostics =
	mkButton(debugControls, "COPY DEBUG", 8, 273, 148, 25)

local copyTimingDatabase =
	mkButton(debugControls, "COPY TIMINGS", 164, 273, 148, 25)

local testParry =
	mkButton(debugControls, "TEST PARRY", 8, 310, 148, 25)

local testDodge =
	mkButton(debugControls, "TEST DODGE", 164, 310, 148, 25)

local InputTestStatus =
	mkLabel(debugControls, "INPUT SELF-TEST: not run", 8, 343, 304, 45, 9)

InputTestStatus.TextWrapped = true
InputTestStatus.TextYAlignment = Enum.TextYAlignment.Top
InputTestStatus.TextColor3 = COLORS.MUTED

bind(clearDiagnostics.MouseButton1Click, function()
	if CombatRuntime then
		CombatRuntime.Diagnostics:clear()
	end
end)

bind(copyDiagnostics.MouseButton1Click, function()
	if CombatRuntime then
		local ok, detail = CombatRuntime:diagnosticReport(true)
		InputTestStatus.Text = ok and "DIAGNOSTIC REPORT: copied" or ("COPY FAILED: " .. tostring(detail))
		InputTestStatus.TextColor3 = ok and COLORS.GREEN or COLORS.RED
		showStatus(ok and "Diagnostic report copied" or tostring(detail), ok and COLORS.GREEN or COLORS.RED)
	end
end)

bind(copyTimingDatabase.MouseButton1Click, function()
	if CombatRuntime then
		local ok, detail = CombatRuntime:exportTimings(true)
		showStatus(ok and "Timing database copied" or tostring(detail), ok and COLORS.GREEN or COLORS.RED)
	end
end)

local function runInputTest(kind)
	if not CombatRuntime then
		return
	end
	local ok, detail = CombatRuntime:testAction(kind)
	local nativeStatus = CombatRuntime.Input.Native.Status
	InputTestStatus.Text = string.format(
		"%s: %s (%s)\nNative: %s",
		string.upper(kind),
		ok and "SENT" or "FAILED",
		tostring(detail or "unknown"),
		tostring(nativeStatus)
	)
	InputTestStatus.TextColor3 = ok and COLORS.GREEN or COLORS.RED
end

bind(testParry.MouseButton1Click, function()
	runInputTest("Parry")
end)

bind(testDodge.MouseButton1Click, function()
	runInputTest("Dodge")
end)

local DebugSummary =
	mkLabel(debugStats, "", 8, 28, 304, 232, 10)

DebugSummary.TextWrapped = false
DebugSummary.TextYAlignment = Enum.TextYAlignment.Top
DebugSummary.TextSize = 9

local DebugReasons =
	mkLabel(debugStats, "", 8, 267, 304, 118, 9)

DebugReasons.TextWrapped = true
DebugReasons.TextYAlignment = Enum.TextYAlignment.Top
DebugReasons.TextColor3 = COLORS.MUTED

local debugAccumulator = 0

bind(RunService.Heartbeat, function(delta)
	if not DebugPage.Visible or not CombatRuntime then
		return
	end
	debugAccumulator = debugAccumulator + delta
	if debugAccumulator < 0.5 then
		return
	end
	debugAccumulator = 0

	local snapshot = CombatRuntime.Diagnostics:snapshot()
	local metrics = snapshot.metrics
	local performance = snapshot.performance
	local targetStage = performance.stages["target-scan"] or {}
	local lastDetection = CombatRuntime.State.LastDetection
	local lastReject = CombatRuntime.State.LastReject
	local lastPlan = CombatRuntime.State.LastPlan
	local lastAction = CombatRuntime.State.LastActionResult
	local lastFailure = CombatRuntime.State.LastFailure
	local nativeStats = CombatRuntime.Input.Native.Stats
	local threatSummary = CombatRuntime.State.ThreatSummary or {}
	local effectStats = CombatRuntime.Detectors.Detectors.ClientEffects
		and CombatRuntime.Detectors.Detectors.ClientEffects.Stats
		or {}
	DebugSummary.Text = string.format(
		"RUNNING      %s\nDEFENSE      %s\nTARGETS      %d\nTIMINGS      %d\nTHREAT GUARD %s A:%d N:%d\nGUARD EVENTS %dC %dD %dB %dP\nEFFECT IO    %dN %dL %dD %dX\nNATIVE       %s\nNATIVE IO    %dB %dU %dR %dC %dD %dX\nNATIVE LAST  %s\nDETECTED     %d\nSCHEDULED    %d\nEXECUTED     %d\nFAILED       %d\nREJECTED     %d\nCANCELLED    %d\nLAST DETECT  %s\nLAST REJECT  %s\nLAST PLAN    %s\nPLAN NAME    %s\nLAST ACTION  %s\nLAST FAIL    %s\nSCAN AVG     %.3f ms\nBACKOFF      %.2fx",
		CombatRuntime.State.Running and "YES" or "NO",
		CombatRuntime.Settings:get("Defense.Enabled") and "ON" or "OFF",
		#CombatRuntime.State.Targets,
		CombatRuntime.Timings:count(),
		tostring(threatSummary.mode or "OFF"),
		threatSummary.activePlans or 0,
		threatSummary.noisySources or 0,
		metrics.ThreatCoalesced or 0,
		metrics.ThreatDropped or 0,
		metrics.ThreatSpamBursts or 0,
		metrics.ThreatPromoted or 0,
		effectStats.ClientEffect or 0,
		effectStats.ClientEffectLarge or 0,
		effectStats.ClientEffectDirect or 0,
		effectStats.Deduplicated or 0,
		tostring(CombatRuntime.Input.Native.Status),
		nativeStats.Blocks or 0,
		nativeStats.Unblocks or 0,
		nativeStats.Retries or 0,
		nativeStats.Coalesced or 0,
		nativeStats.Dodges or 0,
		nativeStats.DodgeCancels or 0,
		string.sub(CombatRuntime.Input.Native.LastTransition or "idle", 1, 38),
		metrics.Detected or 0,
		metrics.Scheduled or 0,
		metrics.Executed or 0,
		metrics.Failed or 0,
		metrics.Rejected or 0,
		metrics.Cancelled or 0,
		lastDetection and (lastDetection.detector .. ":" .. lastDetection.id) or "none",
		lastReject and lastReject.reason or "none",
		lastPlan and string.format("%s @ %.3fs d=%.1f", lastPlan.kind, lastPlan.delay, lastPlan.distance or 0) or "none",
		lastPlan and string.sub(lastPlan.name or lastPlan.profile or "unknown", 1, 38) or "none",
		lastAction and (lastAction.kind .. ":" .. (lastAction.ok and (lastAction.backend or "sent") or lastAction.reason)) or "none",
		lastFailure and string.sub(lastFailure.reason, 1, 44) or "none",
		targetStage.averageMs or 0,
		performance.backoff or 1
	)

	local reasons = {}
	for reason, count in pairs(snapshot.reasons) do
		reasons[#reasons + 1] = reason .. ": " .. tostring(count)
	end
	table.sort(reasons)
	DebugReasons.Text = #reasons > 0
		and ("REJECTION REASONS\n" .. table.concat(reasons, "\n"))
		or "REJECTION REASONS\nnone recorded"
end)
end
buildDiagnosticsUI()
end

--==============================================================
-- MENU
--==============================================================

local Menu =
	Instance.new(
		"Frame"
	)

Menu.Size =
	UDim2.fromOffset(
		185,
		192
	)

Menu.Position =
	UDim2.new(
		1,
		-195,
		0,
		33
	)

Menu.BackgroundColor3 =
	Color3.fromRGB(
		22,
		22,
		26
	)

Menu.BorderColor3 =
	COLORS.BORDER

Menu.BorderSizePixel = 1

Menu.Visible = false

Menu.ZIndex = 20

Menu.Parent =
	Main

mkLabel(
	Menu,
	"QUICK MENU",
	8,
	5,
	160,
	20,
	10
)

mkLabel(
	Menu,
	"UI KEY",
	8,
	30,
	55,
	21,
	9
)

local KeyBox =
	mkBox(
		Menu,
		CONFIG.UIKey,
		65,
		30,
		108,
		21
	)

local HideButton =
	mkButton(
		Menu,
		"HIDE UI",
		8,
		60,
		78,
		23
	)

local StopGhostMenu =
	mkButton(
		Menu,
		"STOP GHOST",
		94,
		60,
		79,
		23
	)

local ResetPos =
	mkButton(
		Menu,
		"RESET POS",
		8,
		90,
		78,
		23
	)

local BurstMaster =
	mkButton(
		Menu,
		"BURST OFF",
		94,
		90,
		79,
		23
	)

local SafeReset =
	mkButton(
		Menu,
		"PANIC / ALL OFF",
		8,
		120,
		165,
		25
	)

SafeReset.BackgroundColor3 = COLORS.RED

local Unload =
	mkButton(
		Menu,
		"UNLOAD",
		8,
		152,
		165,
		25
	)

Unload.BackgroundColor3 =
	COLORS.RED

bind(
	MenuButton.MouseButton1Click,
	function()

		Menu.Visible =
			not Menu.Visible
	end
)

bind(
	KeyBox.FocusLost,
	function()

		local value =
			KeyBox.Text

		local valid =
			pcall(function()

				local _ =
					Enum.KeyCode[value]
			end)

		if
			valid
			and
			Enum.KeyCode[value]
		then

			CONFIG.UIKey =
				value

			PREFS.UIKey =
				value

		else

			KeyBox.Text =
				CONFIG.UIKey
		end
	end
)

bind(
	HideButton.MouseButton1Click,
	function()

		Gui.Enabled =
			false
	end
)

bind(
	StopGhostMenu.MouseButton1Click,
	stopGhostRunner
)

bind(
	ResetPos.MouseButton1Click,
	function()

		Main.Position =
			UDim2.new(
				0,
				24,
				0.5,
				-260
			)

		PREFS.UIPosition = nil
		showStatus("Window position reset", COLORS.GREEN)
	end
)

local function refreshBurstMasterButtons()
	BurstMaster.Text = CONFIG.BursterMaster and "BURST ON" or "BURST OFF"
	BurstMaster.BackgroundColor3 = CONFIG.BursterMaster and COLORS.GREEN or COLORS.PANEL2
	if UI.RefreshBurst then
		UI.RefreshBurst()
	end
end

UI.RefreshBurstMasterMenu = refreshBurstMasterButtons

bind(
	BurstMaster.MouseButton1Click,
	function()

		CONFIG.BursterMaster =
			not
			CONFIG.BursterMaster

		refreshBurstMasterButtons()
	end
)

bind(SafeReset.MouseButton1Click, function()
	stopGhostRunner()
	CONFIG.BursterMaster = false
	CONFIG.LoggingEnabled = false
	if CombatRuntime then
		CombatRuntime:panic()
	end
	refreshBurstMasterButtons()
	if UI.RefreshLogging then
		UI.RefreshLogging()
	end
	combatRefreshAll()
	Menu.Visible = false
	showStatus("PANIC COMPLETE — every active CLAW feature is off", COLORS.GREEN, 5)
end)

refreshBurstMasterButtons()

--==============================================================
-- HEADER EVENTS
--==============================================================

UI.SetTargetText =
	function(player)

		TargetButton.Text =
			player == LP
			and "TARGET: LOCAL"
			or
			(
				"TARGET: "
				..
				string.sub(
					player.Name,
					1,
					9
				)
			)

		refreshStatus()
	end

bind(
	TargetButton.MouseButton1Click,
	cycleTarget
)

bind(
	MinimizeButton.MouseButton1Click,
	function()

		State.Minimized =
			not State.Minimized

		if State.Minimized then

			Main.Size =
				UDim2.fromOffset(
					680,
					30
				)

			TabBar.Visible =
				false

			for _, page
				in pairs(Pages)
			do

				page.Visible =
					false
			end

			Status.Visible =
				false

			Menu.Visible =
				false

		else

			Main.Size =
				UDim2.fromOffset(
					680,
					520
				)

			TabBar.Visible =
				true

			Status.Visible =
				true

			openPage(
				State.ActivePage or BurstPage
			)
		end
	end
)

--==============================================================
-- TAB EVENTS
--==============================================================

bind(
	BurstTab.MouseButton1Click,
	function()

		UI.RefreshBurst()

		openPage(
			BurstPage
		)
	end
)

bind(
	LogsTab.MouseButton1Click,
	function()

		openPage(
			LogsPage
		)
	end
)

bind(
	LiveTab.MouseButton1Click,
	function()

		openPage(
			LivePage
		)
	end
)

bind(
	GhostTab.MouseButton1Click,
	function()

		UI.RefreshGhost()

		openPage(
			GhostPage
		)
	end
)

bind(
	CombatTab.MouseButton1Click,
	function()
		combatRefreshAll()
		openPage(CombatPage)
	end
)

bind(
	TimingsTab.MouseButton1Click,
	function()
		refreshTimingList()
		openPage(TimingsPage)
	end
)

bind(
	AssistTab.MouseButton1Click,
	function()
		combatRefreshAll()
		openPage(AssistPage)
	end
)

bind(
	DebugTab.MouseButton1Click,
	function()
		combatRefreshAll()
		openPage(DebugPage)
	end
)

bind(
	WebhookTab.MouseButton1Click,
	function()

		refreshWebhook()

		openPage(
			WebhookPage
		)
	end
)

--==============================================================
-- UI KEYBIND
--==============================================================

bind(
	UIS.InputBegan,
	function(input, processed)

		if processed
			or State.Destroyed
		then
			return
		end

		if
			input.KeyCode
			==
			Enum.KeyCode[
				CONFIG.UIKey
			]
		then

			Gui.Enabled =
				not Gui.Enabled

			if Gui.Enabled then

				refreshStatus()
			end
		end
	end
)

--==============================================================
-- INITIAL ANIMATOR HOOKS
--==============================================================

if LP.Character then

	task.spawn(
		hookLocalCharacter,
		LP.Character
	)
end

bind(
	LP.CharacterAdded,
	hookLocalCharacter
)

setTarget(LP)

--==============================================================
-- DESTROY
--==============================================================

function State:Destroy()

	if self.Destroyed then
		return
	end

	stopGhostRunner()

	stopAllGhosts()

	if self.Combat then
		pcall(function()
			self.Combat:Destroy()
		end)
		if ENV.CLAW and ENV.CLAW.Combat == self.Combat then
			ENV.CLAW.Combat = nil
		end
		self.Combat = nil
	end

	leaveUI()

	self.Destroyed =
		true

	CONFIG.BursterMaster =
		false

	CONFIG.LoggingEnabled =
		false

	clearTargetConnections()

	for _, c
		in ipairs(
			self.Connections
		)
	do

		pcall(function()

			c:
				Disconnect()
		end)
	end

	table.clear(
		self.Connections
	)

	for track
		in pairs(
			self.OwnGhostTracks
		)
	do

		pcall(function()

			track:
				Stop(0)
		end)

		pcall(function()

			track:
				Destroy()
		end)
	end

	pcall(function()

		Gui:
			Destroy()
	end)

	if ENV.__CLAW_MARK == self then
		ENV.__CLAW_MARK = nil
	end

	if ENV.__ANIM_LAB_V6 == self then
		ENV.__ANIM_LAB_V6 = nil
	end

	print(
		"[CLAW] CLAW MARK unloaded"
	)
end

bind(
	CloseButton.MouseButton1Click,
	function()

		State:Destroy()
	end
)

bind(
	Unload.MouseButton1Click,
	function()

		State:Destroy()
	end
)

--==============================================================
-- INITIAL UI
--==============================================================

UI.RefreshBurst()

UI.RefreshGhost()

UI.RefreshLogging()

local initialLootSync, initialLootDetail =
	syncLootConfiguration()

if getLootAPI() and not initialLootSync then
	warn(
		"[WEBHOOK] initial Loot sync failed:",
		initialLootDetail
	)
end

refreshWebhook()

refreshStatus()

local initialPage = PagesByName[PREFS.ActivePage] or BurstPage
openPage(initialPage)

assert(
	Gui.Parent ~= nil
		and Main.Parent == Gui
		and initialPage.Visible
		and #State.Connections > 0,
	"CLAW MARK UI startup check failed"
)

print(
	"[CLAW] CLAW MARK v0.4.0 online"
)
