--!strict
-- Praetor: moderation and sanctions.
-- Applies warnings, mutes, kicks and bans; handles their duration and removal.
-- Checks on join whether a player is banned.
-- Not responsible for permissions: the caller (Consul, later Lictor) has already decided.
-- Does not detect cheating (Lictor) or investigate (Quaesitor).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local logger = Scriba.scoped("Praetor")

local TOPIC = "Imperium_Praetor"

type Measure = {
	expiresAt: number?, -- nil = permanent
	reason: string,
	by: string,
	date: number,
}

export type State = {
	ban: Measure?,
	mute: Measure?,
	warnings: number,
}

local Praetor = {
	dependencies = { "Tabularius", "Censor", "Praeco", "Lex" },
}

local keyStore: any
local Censor: any
local Praeco: any
local Lex: any

local onlineStates: { [number]: State } = {}

local function active(measure: Measure?): boolean
	return measure ~= nil and (measure.expiresAt == nil or measure.expiresAt > os.time())
end

local function emptyState(): State
	return { warnings = 0 }
end

local function banMessage(measure: Measure): string
	local expiresAt = if measure.expiresAt then os.date("!%d/%m/%Y %H:%M:%S UTC", measure.expiresAt) else "permanent"
	return `You are banned from this game.\nReason: {measure.reason}\nEnds: {expiresAt}`
end

-- Mute: silences the player on every TextChatService channel.
local function applyMute(player: Player)
	local muted = active((onlineStates[player.UserId] or emptyState()).mute)
	for _, object in TextChatService:GetDescendants() do
		if object:IsA("TextSource") and object.UserId == player.UserId then
			object.CanSend = not muted
		end
	end
end

local function update(userId: number, fn: (State) -> ()): State?
	local ok, fresh = keyStore:update(tostring(userId), function(previous: State?)
		local state = previous or emptyState()
		fn(state)
		return state
	end)
	if not ok then
		return nil
	end
	if onlineStates[userId] then
		onlineStates[userId] = fresh
	end
	return fresh
end

local function actorName(actor: Player?): string
	return if actor then actor.Name else "System"
end

-- Tells other servers that a sanction may concern one of their players.
local function broadcast(userId: number, kind: string, reason: string?)
	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, {
			userId = userId,
			kind = kind,
			reason = reason,
		})
		if not ok then
			logger.warning("cross-server broadcast failed:", err)
		end
	end)
end

local function onMessage(userId: number, kind: string, reason: string?)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	if kind == "kick" then
		player:Kick(`You were kicked.\nReason: {reason or "—"}`)
		return
	end
	-- For ban, mute and unmute, read the state again from storage.
	local ok, state = keyStore:read(tostring(userId))
	if not ok then
		return
	end
	onlineStates[userId] = state or emptyState()
	if kind == "ban" and state and active(state.ban) then
		player:Kick(banMessage(state.ban))
	else
		applyMute(player)
	end
end

-- API --------------------------------------------------------------------------
-- All functions return (true) or (false, error_code).

function Praetor.state(userId: number): State?
	if onlineStates[userId] then
		return onlineStates[userId]
	end
	local ok, state = keyStore:read(tostring(userId))
	if not ok then
		return nil
	end
	return state or emptyState()
end

function Praetor.isMuted(player: Player): boolean
	local state = onlineStates[player.UserId]
	return state ~= nil and active(state.mute)
end

function Praetor.isBanned(state: State): boolean
	return active(state.ban)
end

function Praetor.warn(actor: Player?, userId: number, reason: string): (boolean, string?)
	local state = update(userId, function(e)
		e.warnings += 1
	end)
	if not state then
		return false, "save_failed"
	end
	Censor.addSanction(userId, {
		type = "warning",
		reason = reason,
		by = actorName(actor),
		byId = actor and actor.UserId,
		date = os.time(),
	})
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Praeco.notify(player, {
			kind = "warning",
			title = "Warning",
			text = reason,
			duration = 12,
		})
	end
	Signum.emit("praetor.sanction", "warning", userId, actor)
	return true
end

function Praetor.mute(actor: Player?, userId: number, duration: number?, reason: string): (boolean, string?)
	local now = os.time()
	local state = update(userId, function(e)
		e.mute = {
			expiresAt = if duration then now + duration else nil,
			reason = reason,
			by = actorName(actor),
			date = now,
		}
	end)
	if not state then
		return false, "save_failed"
	end
	Censor.addSanction(userId, {
		type = "mute",
		reason = reason,
		by = actorName(actor),
		byId = actor and actor.UserId,
		date = now,
		duration = duration,
	})
	local player = Players:GetPlayerByUserId(userId)
	if player then
		applyMute(player)
		Praeco.notify(player, {
			kind = "warning",
			title = "You are muted",
			text = `{reason} for {Core.formatDuration(duration)}`,
			duration = 10,
		})
	else
		broadcast(userId, "mute")
	end
	Signum.emit("praetor.sanction", "mute", userId, actor)
	return true
end

function Praetor.demute(actor: Player?, userId: number): (boolean, string?)
	local state = update(userId, function(e)
		e.mute = nil
	end)
	if not state then
		return false, "save_failed"
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		applyMute(player)
		Praeco.notify(player, { kind = "success", text = "You can speak again.", duration = 6 })
	else
		broadcast(userId, "demute")
	end
	Signum.emit("praetor.sanction", "demute", userId, actor)
	return true
end

function Praetor.kick(actor: Player?, userId: number, reason: string): (boolean, string?)
	Censor.addSanction(userId, {
		type = "kick",
		reason = reason,
		by = actorName(actor),
		byId = actor and actor.UserId,
		date = os.time(),
	})
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(`You were kicked.\nReason: {reason}`)
	else
		broadcast(userId, "kick", reason)
	end
	Signum.emit("praetor.sanction", "kick", userId, actor)
	return true
end

function Praetor.ban(actor: Player?, userId: number, duration: number?, reason: string): (boolean, string?)
	local now = os.time()
	local measure: Measure = {
		expiresAt = if duration then now + duration else nil,
		reason = reason,
		by = actorName(actor),
		date = now,
	}
	local state = update(userId, function(e)
		e.ban = measure
	end)
	if not state then
		return false, "save_failed"
	end
	Censor.addSanction(userId, {
		type = "ban",
		reason = reason,
		by = measure.by,
		byId = actor and actor.UserId,
		date = now,
		duration = duration,
	})
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:Kick(banMessage(measure))
	else
		broadcast(userId, "ban")
	end
	Signum.emit("praetor.sanction", "ban", userId, actor)
	return true
end

function Praetor.unban(actor: Player?, userId: number): (boolean, string?)
	local alreadyFree = false
	local state = update(userId, function(e)
		alreadyFree = not active(e.ban)
		e.ban = nil
	end)
	if not state then
		return false, "save_failed"
	end
	if alreadyFree then
		return false, "not_banned"
	end
	Censor.addSanction(userId, {
		type = "unban",
		reason = "—",
		by = actorName(actor),
		byId = actor and actor.UserId,
		date = os.time(),
	})
	Signum.emit("praetor.sanction", "unban", userId, actor)
	return true
end

-- Lifecycle -------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local ok, state = keyStore:read(tostring(player.UserId))
	if not ok then
		-- Unreadable save: let the player in rather than blocking everyone.
		logger.warning(`could not read the state of {player.Name}, letting them in`)
		state = nil
	end
	local e: State = state or emptyState()
	if active(e.ban) then
		player:Kick(banMessage(e.ban :: Measure))
		return
	end
	onlineStates[player.UserId] = e
	applyMute(player)
end

function Praetor.init(deps)
	keyStore = deps.Tabularius.keyStore("Praetor")
	Censor = deps.Censor
	Praeco = deps.Praeco
	Lex = deps.Lex

	Lex.define("praetor.default_mute_duration", {
		default = "10m",
		type = "string",
		description = "Default duration offered for a mute (e.g. 10m, 2h, 1d).",
	})
	Lex.define("praetor.default_ban_duration", {
		default = "1d",
		type = "string",
		description = "Default duration offered for a ban (\"perm\" for permanent).",
	})
end

function Praetor.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		onlineStates[player.UserId] = nil
	end)

	-- TextSources appear when the player joins a channel.
	TextChatService.DescendantAdded:Connect(function(object)
		if object:IsA("TextSource") then
			local player = Players:GetPlayerByUserId(object.UserId)
			if player then
				applyMute(player)
			end
		end
	end)

	-- Automatic removal of expired mutes.
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				local state = onlineStates[player.UserId]
				if state and state.mute and not active(state.mute) then
					state.mute = nil
					applyMute(player)
				end
			end
		end
	end)

	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		local data = message.Data
		if type(data) == "table" and Core.isUserId(data.userId) then
			onMessage(data.userId, data.kind, data.reason)
		end
	end)
	if not ok then
		logger.warning("cross-server subscription failed:", err)
	end
end

return Praetor
