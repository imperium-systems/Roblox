--!strict
-- Censor: registry.
-- Keeps each player's record (first join, playtime, usernames, sanctions)
-- and the log of staff actions. Guarantees traceability.
-- Does not handle technical logs (Scriba).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signum = require(ReplicatedStorage.ImperiumShared.Imperium.Signum)

local LOG_SIZE = 200
local MAX_SANCTIONS = 50

export type PlayerRecord = {
	firstSeen: number,
	lastSeen: number,
	playtime: number,
	usernames: { string },
	sanctions: { Sanction },
}

export type Sanction = {
	type: string,
	reason: string,
	by: string,
	byId: number?,
	date: number,
	duration: number?,
}

export type LogEntry = {
	date: number,
	actor: string,
	actorId: number,
	action: string,
	target: string?,
	targetId: number?,
	details: string?,
}

local Censor = {
	dependencies = { "Tabularius" },
}

local keyStore: any
local joinTimes: { [Player]: number } = {}

local function emptyRecord(): PlayerRecord
	return {
		firstSeen = os.time(),
		lastSeen = os.time(),
		playtime = 0,
		usernames = {},
		sanctions = {},
	}
end

function Censor.record(userId: number): PlayerRecord?
	local ok, record = keyStore:read(`player_{userId}`)
	if not ok then
		return nil
	end
	return record
end

-- Adds a sanction to the player's record (called by Praetor).
function Censor.addSanction(userId: number, sanction: Sanction)
	keyStore:update(`player_{userId}`, function(record: PlayerRecord?)
		local f = record or emptyRecord()
		table.insert(f.sanctions, sanction)
		while #f.sanctions > MAX_SANCTIONS do
			table.remove(f.sanctions, 1)
		end
		return f
	end)
end

-- Writes a staff action to the log.
function Censor.logAction(actor: Player, action: string, target: { name: string, userId: number }?, details: string?)
	local entry: LogEntry = {
		date = os.time(),
		actor = actor.Name,
		actorId = actor.UserId,
		action = action,
		target = target and target.name,
		targetId = target and target.userId,
		details = details,
	}
	task.spawn(function()
		keyStore:update("log", function(list: { LogEntry }?)
			local l = list or {}
			table.insert(l, entry)
			while #l > LOG_SIZE do
				table.remove(l, 1)
			end
			return l
		end)
	end)
	Signum.emit("censor.entry", entry)
end

-- Most recent entries first.
function Censor.getLog(limit: number?): { LogEntry }
	local ok, list = keyStore:read("log")
	if not ok or not list then
		return {}
	end
	local result = {}
	for i = #list, math.max(1, #list - (limit or LOG_SIZE) + 1), -1 do
		table.insert(result, list[i])
	end
	return result
end

function Censor.sessionDuration(player: Player): number
	local joinTime = joinTimes[player]
	return if joinTime then os.time() - joinTime else 0
end

-- Lifecycle ---------------------------------------------------------------

local function onPlayerAdded(player: Player)
	joinTimes[player] = os.time()
	keyStore:update(`player_{player.UserId}`, function(record: PlayerRecord?)
		local f = record or emptyRecord()
		f.lastSeen = os.time()
		if f.usernames[#f.usernames] ~= player.Name then
			table.insert(f.usernames, player.Name)
		end
		return f
	end)
end

local function onPlayerRemoving(player: Player)
	local duration = Censor.sessionDuration(player)
	joinTimes[player] = nil
	keyStore:update(`player_{player.UserId}`, function(record: PlayerRecord?)
		local f = record or emptyRecord()
		f.playtime += duration
		f.lastSeen = os.time()
		return f
	end)
end

function Censor.init(deps)
	keyStore = deps.Tabularius.keyStore("Censor")
end

function Censor.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function Censor.stop()
	for _, player in Players:GetPlayers() do
		onPlayerRemoving(player)
	end
end

return Censor
