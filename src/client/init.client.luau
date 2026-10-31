-- Point d'entrée client d'Imperium.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Conditor = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium"):WaitForChild("Conditor"))

local systemes = script:WaitForChild("Imperium")

Conditor.lancer({
	systemes:WaitForChild("Praeco"),
	systemes:WaitForChild("Consul"),
})
