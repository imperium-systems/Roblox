-- Imperium server entry point.
-- List order does not matter: Conditor sorts by declared dependencies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- The Toolbox model is ungrouped by hand: a misplaced folder must show up immediately.
if script.Parent ~= ServerScriptService then
	warn("[Imperium] ImperiumServer must be in ServerScriptService. See README in the model.")
	return
end
if not ReplicatedStorage:FindFirstChild("ImperiumShared") then
	warn("[Imperium] ImperiumShared was not found in ReplicatedStorage. See README in the model.")
	return
end

local Conditor = require(ReplicatedStorage.ImperiumShared.Imperium.Conditor)

local systems = script.Imperium

Conditor.run({
	-- Viae
	systems.Tabularius,
	-- Core
	systems.Lex,
	-- Forum
	systems.Praeco,
	systems.Tribune,
	-- Curia
	systems.Senatus,
	systems.Censor,
	systems.Praetor,
	systems.Lictor,
	systems.Quaesitor,
	systems.Nuntius,
	systems.Praefectus,
	systems.Consul,
})
