--!strict
-- Senatus: staff ranks and permissions.
-- Answers "is this player allowed to...?". Handles inheritance between ranks.
-- Handles neither game ranks (Cursus) nor VIP status (Eques).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local config = require(script.Parent.Parent.Config.Senatus) :: any

local logger = Scriba.scoped("Senatus")

export type Rank = {
	id: string,
	name: string,
	level: number,
	color: Color3,
	permissions: { [string]: true },
}

local Senatus = {}

local ranks: { [string]: Rank } = {}
local playerRanks: { [Player]: Rank } = {}

local function compileRanks()
	local raw: { [string]: any } = {}
	for _, definition in config.ranks do
		raw[definition.id] = definition
	end

	local function permissionsOf(id: string, seen: { [string]: boolean }): { [string]: true }
		assert(not seen[id], `[Senatus] circular inheritance around "{id}"`)
		seen[id] = true
		local definition = raw[id]
		assert(definition, `[Senatus] unknown rank: "{id}"`)
		local result: { [string]: true } = {}
		if definition.inherits then
			for permission in permissionsOf(definition.inherits, seen) do
				result[permission] = true
			end
		end
		for _, permission in definition.permissions do
			result[permission] = true
		end
		return result
	end

	for id, definition in raw do
		ranks[id] = {
			id = id,
			name = definition.name,
			level = definition.level,
			color = definition.color,
			permissions = permissionsOf(id, {}),
		}
	end
end

local function best(a: Rank?, b: Rank?): Rank?
	if not a then
		return b
	end
	if not b then
		return a
	end
	return if b.level > a.level then b else a
end

local function rankFromGroup(groupRank: number): Rank?
	local found: Rank? = nil
	for threshold, id in config.group.ranks do
		if groupRank >= threshold then
			found = best(found, ranks[id])
		end
	end
	return found
end

-- Computes the rank of a UserId, online or not. May yield (web calls).
local function computeRank(userId: number, player: Player?): Rank?
	local rank: Rank? = nil

	local id = config.members[userId]
	if id then
		rank = best(rank, ranks[id])
	end

	-- In Studio: your own account in solo Play, or Player1 on a local test server.
	-- Player2, Player3... stay regular players so sanctions can be tested.
	if config.studioIsFounder and RunService:IsStudio() and player and (userId > 0 or userId == -1) then
		rank = best(rank, ranks.founder)
	end

	if config.creatorIsFounder then
		if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
			rank = best(rank, ranks.founder)
		end
	end

	-- Group ranks: the configured group, and the owner of the creator group.
	local configuredGroup = config.group.id
	local creatorGroup = if config.creatorIsFounder and game.CreatorType == Enum.CreatorType.Group
		then game.CreatorId
		else 0
	if configuredGroup ~= 0 or creatorGroup ~= 0 then
		local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, userId)
		if ok then
			for _, group in groups do
				if group.Id == configuredGroup then
					rank = best(rank, rankFromGroup(group.Rank))
				end
				if group.Id == creatorGroup and group.Rank == 255 then
					rank = best(rank, ranks.founder)
				end
			end
		else
			logger.warning(`could not read the groups of {userId}:`, groups)
		end
	end

	return rank
end

-- API ----------------------------------------------------------------------

function Senatus.rank(player: Player): Rank?
	return playerRanks[player]
end

function Senatus.level(player: Player): number
	local rank = playerRanks[player]
	return if rank then rank.level else 0
end

-- Level of a player who may be offline. May yield.
function Senatus.levelOf(userId: number): number
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return Senatus.level(player)
	end
	local rank = computeRank(userId, nil)
	return if rank then rank.level else 0
end

-- "praetor.ban" is granted by "praetor.ban", "praetor.*" or "*".
function Senatus.can(player: Player, permission: string): boolean
	local rank = playerRanks[player]
	if not rank then
		return false
	end
	local p = rank.permissions
	if p["*"] or p[permission] then
		return true
	end
	local family = string.match(permission, "^([^%.]+)%.")
	return family ~= nil and p[family .. ".*"] == true
end

-- Staff can only act on someone below them.
function Senatus.canActOn(actor: Player, targetUserId: number): boolean
	if actor.UserId == targetUserId then
		return false
	end
	return Senatus.level(actor) > Senatus.levelOf(targetUserId)
end

-- Known permissions, so the interface knows what to show.
local KNOWN_PERMISSIONS = {
	"consul.open",
	"consul.teleport",
	"censor.view",
	"censor.log",
	"lictor.view",
	"lictor.clear",
	"tribune.handle",
	"tribune.manage",
	"praetor.warn",
	"praetor.mute",
	"praetor.kick",
	"praetor.ban",
	"praetor.unban",
	"praefectus.announce",
	"praefectus.lock",
	"praefectus.restart",
	"lex.edit",
}

function Senatus.permissionsOf(player: Player): { [string]: boolean }
	local result = {}
	for _, permission in KNOWN_PERMISSIONS do
		result[permission] = Senatus.can(player, permission)
	end
	return result
end

function Senatus.isStaff(player: Player): boolean
	return Senatus.level(player) > 0
end

-- Lifecycle ---------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local rank = computeRank(player.UserId, player)
	if not player.Parent then
		return
	end
	if rank then
		playerRanks[player] = rank
		logger.info(`{player.Name}: {rank.name}`)
	end
	Signum.emit("senatus.rank", player, rank)
end

function Senatus.init()
	compileRanks()
end

function Senatus.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		playerRanks[player] = nil
	end)
end

return Senatus
