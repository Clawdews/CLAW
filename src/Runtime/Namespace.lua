local environment = getgenv and getgenv() or _G

environment.CLAW = environment.CLAW or {}
environment.CLAW.Name = "CLAW MARK"
environment.CLAW.Version = "0.3.9"
environment.CLAW.Modules = environment.__CLAW_MODULES or {}
environment.CLAW.StartedAt = environment.CLAW.StartedAt or os.clock()

function environment.CLAW:GetModule(name)
	return self.Modules[name]
end

return environment.CLAW
