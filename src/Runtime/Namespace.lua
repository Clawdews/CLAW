local environment = getgenv and getgenv() or _G

environment.CLAW = environment.CLAW or {}
environment.CLAW.Version = "0.1.0-dev"
environment.CLAW.Modules = environment.__CLAW_MODULES or {}
environment.CLAW.StartedAt = environment.CLAW.StartedAt or os.clock()

return environment.CLAW
