--!strict
-- Scriba: engine technical logs.
-- Does not track staff or player actions: that is the role of Censor.

local RunService = game:GetService("RunService")

local Signum = require(script.Parent.Signum)

local LEVELS = {
	debug = 1,
	info = 2,
	warning = 3,
	err = 4,
}

export type Logger = {
	debug: (...any) -> (),
	info: (...any) -> (),
	warning: (...any) -> (),
	err: (...any) -> (),
}

local Scriba = {}

-- Minimum displayed level. More verbose in Studio.
Scriba.level = if RunService:IsStudio() then LEVELS.debug else LEVELS.info

local function joinArgs(...: any): string
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	return table.concat(parts, " ", 1, parts.n)
end

-- Returns a logger prefixed with the system name.
function Scriba.scoped(system: string): Logger
	local prefix = `[{system}]`

	return {
		debug = function(...)
			if Scriba.level <= LEVELS.debug then
				print(prefix, joinArgs(...))
			end
		end,
		info = function(...)
			if Scriba.level <= LEVELS.info then
				print(prefix, joinArgs(...))
			end
		end,
		warning = function(...)
			if Scriba.level <= LEVELS.warning then
				warn(prefix, joinArgs(...))
			end
		end,
		err = function(...)
			local message = joinArgs(...)
			warn(prefix, "ERROR", message)
			-- Nuntius can subscribe to relay serious errors outside the game.
			Signum.emit("scriba.error", system, message)
		end,
	}
end

return Scriba
