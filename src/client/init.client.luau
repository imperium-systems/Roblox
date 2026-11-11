-- Imperium client entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedRoot = ReplicatedStorage:WaitForChild("ImperiumShared", 15)
if not sharedRoot then
	warn("[Imperium] ImperiumShared was not found in ReplicatedStorage. See README in the model.")
	return
end

local Conditor = require(sharedRoot:WaitForChild("Imperium"):WaitForChild("Conditor"))

local systems = script:WaitForChild("Imperium")

Conditor.run({
	systems:WaitForChild("Praeco"),
	systems:WaitForChild("Tribune"),
	systems:WaitForChild("Consul"),
})
