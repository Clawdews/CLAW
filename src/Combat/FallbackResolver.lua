local environment = getgenv and getgenv() or _G
local Action = assert(environment.__CLAW_MODULES["src/Combat/Action.lua"])

local FallbackResolver = {}
FallbackResolver.__index = FallbackResolver

function FallbackResolver.new(settings)
	return setmetatable({ Settings = settings }, FallbackResolver)
end

function FallbackResolver:resolve(action, reason, profile)
	if reason == "iframes" or reason == "distance" or reason == "occluded" then
		return nil
	end

	if action.kind == "Dodge" and self.Settings:get("Defense.ParryOnly") then
		return Action.new({ kind = "Parry", name = action.name .. " (parry-only)" })
	end

	if action.kind == "Parry" and reason == "cooldown" and self.Settings:get("Defense.RollOnParryCooldown") then
		return Action.new({ kind = "Dodge", name = action.name .. " (cooldown roll)" })
	end
	if self.Settings:get("Defense.BlockFallback") and profile.preferBlockFallback and not profile.noBlockFallback then
		return Action.new({
			kind = "Block",
			name = action.name .. " (preferred block fallback)",
			duration = profile.blockFallbackHold,
		})
	end

	if self.Settings:get("Defense.UsePredictionMantra") then
		return Action.new({ kind = "Custom", name = "Prediction", metadata = { customName = "Prediction" } })
	end
	if self.Settings:get("Defense.UsePunishmentMantra") then
		return Action.new({ kind = "Custom", name = "Punishment", metadata = { customName = "Punishment" } })
	end
	if self.Settings:get("Defense.BlockFallback") and not profile.noBlockFallback then
		return Action.new({
			kind = "Block",
			name = action.name .. " (block fallback)",
			duration = profile.blockFallbackHold,
		})
	end
	if self.Settings:get("Defense.VentFallback") and not profile.noVentFallback then
		return Action.new({ kind = "Custom", name = "Vent", metadata = { customName = "Vent" } })
	end
	if
		self.Settings:get("Defense.DodgeFallback")
		and not profile.noDodgeFallback
		and self.Settings:get("Defense.AllowDodge")
	then
		return Action.new({ kind = "Dodge", name = action.name .. " (dodge fallback)" })
	end
	return nil
end

return FallbackResolver
