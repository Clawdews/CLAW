-- The complete Combat surface we are implementing. Keeping this catalog in code
-- prevents a UI control or backend capability from quietly disappearing during
-- the modular rewrite.
return {
	Targeting = {
		"target selection",
		"distance and angle limits",
		"entity-type filters",
		"whitelist and blacklist rules",
		"local-player state filters",
	},
	Detection = {
		"animation detection",
		"sound detection",
		"part and projectile detection",
		"effect and status detection",
	},
	Defense = {
		"parry",
		"block",
		"dodge",
		"full dodge",
		"jump",
		"slide",
		"crouch",
		"teleport response",
	},
	Timing = {
		"global timing profiles",
		"per-move timing overrides",
		"startup and active-window scheduling",
		"latency compensation",
		"cooldown and iframe tracking",
	},
	Validation = {
		"range prediction",
		"entity history",
		"facing and visibility validation",
		"fallback actions",
		"punishment and roll-cancel handling",
		"probability and conditional filters",
	},
	AttackAssistance = {
		"automatic feint assistance",
		"delayed feints",
		"M1 hold assistance",
		"flourish feint handling",
		"action rolling",
		"animation-speed controls",
	},
	CombatAssistance = {
		"Wisp assistance",
		"Golden Tongue assistance",
		"mantra follow-up assistance",
		"Ardour assistance",
		"Flow State assistance",
		"Rhythm assistance",
		"ragdoll response",
	},
	Diagnostics = {
		"live combat state",
		"detector event trace",
		"scheduler decisions",
		"timing-profile inspection",
		"lifecycle cleanup",
	},
}
