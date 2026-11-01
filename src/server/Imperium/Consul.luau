--!strict
-- Consul: admin panel, server side.
-- Single entry point for panel requests: validates each request, checks the permission
-- with Senatus, then delegates to the responsible system (Praetor, Praefectus, Lex, Censor).
-- Does not perform sanctions or server operations itself.
-- Every staff action is written to the Censor log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)
local Veredarius = require(Imperium.Veredarius)

local logger = Scriba.scoped("Consul")

local Consul = {
	dependencies = { "Senatus", "Praetor", "Praefectus", "Censor", "Lex", "Praeco" },
}

local Senatus: any
local Praetor: any
local Praefectus: any
local Censor: any
local Lex: any
local Praeco: any

type Response = { [string]: any }
type Action = {
	permission: string,
	execute: (actor: Player, data: { [string]: any }) -> Response,
}

local function failure(code: string): Response
	return { ok = false, err = code }
end

local function success(data: Response?): Response
	local r = data or {}
	r.ok = true
	return r
end

-- All free text from staff goes through the Roblox filter before others see it.
local function filterText(text: string, author: Player): string?
	local ok, result = pcall(function()
		local filter = TextService:FilterStringAsync(text, author.UserId)
		return filter:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		-- In Studio, the filter often rejects test players: let the text through.
		if RunService:IsStudio() then
			return text
		end
		logger.warning("text filtering failed:", result)
		return nil
	end
	return result
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok then name else `#{userId}`
end

-- Reads and validates the fields shared by sanctions: target, filtered reason, duration.
local function readSanction(
	actor: Player,
	d: { [string]: any },
	withDuration: boolean
): (Response?, number?, string?, number?)
	if not Core.isUserId(d.userId) then
		return failure("player_not_found")
	end
	if not Senatus.canActOn(actor, d.userId) then
		return failure("insufficient_rank")
	end
	local reason = "—"
	if d.reason ~= nil then
		if not Core.isText(d.reason, 200) then
			return failure("invalid_text")
		end
		if string.match(d.reason, "%S") then
			local filter = filterText(d.reason, actor)
			if not filter then
				return failure("filtering_failed")
			end
			reason = filter
		end
	end
	local duration: number? = nil
	if withDuration then
		if not Core.isText(d.duration, 20) then
			return failure("invalid_duration")
		end
		local ok, seconds = Core.parseDuration(d.duration)
		if not ok then
			return failure("invalid_duration")
		end
		duration = seconds
	end
	return nil, d.userId, reason, duration
end

local function praetorResult(
	actor: Player,
	action: string,
	userId: number,
	details: string,
	ok: boolean,
	err: string?
): Response
	if not ok then
		return failure(err or "internal_error")
	end
	Censor.logAction(actor, action, { name = nameOf(userId), userId = userId }, details)
	return success()
end

local function character(player: Player): Model?
	local model = player.Character
	if model and model.PrimaryPart then
		return model
	end
	return nil
end

-- View of an online player for the panel list.
local function playerSummary(player: Player): Response
	local rank = Senatus.rank(player)
	return {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		rank = rank and rank.name,
		rankColor = rank and rank.color,
		level = Senatus.level(player),
		muted = Praetor.isMuted(player),
		session = Censor.sessionDuration(player),
	}
end

-- Actions ----------------------------------------------------------------------------

local actions: { [string]: Action } = {}

actions["access"] = {
	permission = "consul.open",
	execute = function(actor)
		local rank = Senatus.rank(actor)
		return success({
			permissions = Senatus.permissionsOf(actor),
			rank = rank.name,
			rankColor = rank.color,
			level = rank.level,
			version = Core.VERSION,
			settings = {
				muteDuration = Lex.get("praetor.default_mute_duration"),
				banDuration = Lex.get("praetor.default_ban_duration"),
				restartDelay = Lex.get("praefectus.restart_delay"),
			},
		})
	end,
}

actions["players.list"] = {
	permission = "consul.open",
	execute = function()
		local list = {}
		for _, player in Players:GetPlayers() do
			table.insert(list, playerSummary(player))
		end
		table.sort(list, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		return success({ players = list })
	end,
}

actions["players.search"] = {
	permission = "censor.view",
	execute = function(_, d)
		if not Core.isText(d.text, 40) then
			return failure("invalid_text")
		end
		local text = string.gsub(d.text, "^%s*@?(.-)%s*$", "%1")
		local userId = tonumber(text)
		if not userId then
			local ok, result = pcall(Players.GetUserIdFromNameAsync, Players, text)
			if not ok then
				return failure("player_not_found")
			end
			userId = result
		end
		if not Core.isUserId(userId) then
			return failure("player_not_found")
		end
		return success({ userId = userId })
	end,
}

actions["players.record"] = {
	permission = "censor.view",
	execute = function(actor, d)
		if not Core.isUserId(d.userId) then
			return failure("player_not_found")
		end
		local userId = d.userId
		local online = Players:GetPlayerByUserId(userId)
		local name = nameOf(userId)
		local record = Censor.record(userId)
		-- A test player who left no longer has a name on Roblox, but their record still exists.
		if not online and not record and string.sub(name, 1, 1) == "#" then
			return failure("player_not_found")
		end
		local state = Praetor.state(userId)
		local rank = online and Senatus.rank(online)

		local ban = state and state.ban
		local mute = state and state.mute
		local now = os.time()
		local function ifActive(m)
			if m and (m.expiresAt == nil or m.expiresAt > now) then
				return { expiresAt = m.expiresAt, reason = m.reason, by = m.by, date = m.date }
			end
			return nil
		end

		local sanctions = {}
		if record then
			for i = #record.sanctions, 1, -1 do
				table.insert(sanctions, record.sanctions[i])
			end
		end

		return success({
			userId = userId,
			name = name,
			displayName = if online then online.DisplayName else nil,
			online = online ~= nil,
			session = if online then Censor.sessionDuration(online) else nil,
			rank = rank and rank.name,
			rankColor = rank and rank.color,
			firstSeen = record and record.firstSeen,
			lastSeen = record and record.lastSeen,
			playtime = record and record.playtime,
			usernames = record and record.usernames,
			warnings = if state then state.warnings else 0,
			ban = ifActive(ban),
			mute = ifActive(mute),
			sanctions = sanctions,
			canAct = Senatus.canActOn(actor, userId),
		})
	end,
}

actions["praetor.warn"] = {
	permission = "praetor.warn",
	execute = function(actor, d)
		local err, userId, reason = readSanction(actor, d, false)
		if err then
			return err
		end
		local ok, code = Praetor.warn(actor, userId, reason)
		return praetorResult(actor, "warning", userId :: number, reason :: string, ok, code)
	end,
}

actions["praetor.mute"] = {
	permission = "praetor.mute",
	execute = function(actor, d)
		local err, userId, reason, duration = readSanction(actor, d, true)
		if err then
			return err
		end
		local ok, code = Praetor.mute(actor, userId, duration, reason)
		return praetorResult(
			actor,
			"mute",
			userId :: number,
			`{reason} ({Core.formatDuration(duration)})`,
			ok,
			code
		)
	end,
}

actions["praetor.demute"] = {
	permission = "praetor.mute",
	execute = function(actor, d)
		local err, userId = readSanction(actor, { userId = d.userId }, false)
		if err then
			return err
		end
		local ok, code = Praetor.demute(actor, userId)
		return praetorResult(actor, "unmute", userId :: number, "—", ok, code)
	end,
}

actions["praetor.kick"] = {
	permission = "praetor.kick",
	execute = function(actor, d)
		local err, userId, reason = readSanction(actor, d, false)
		if err then
			return err
		end
		local ok, code = Praetor.kick(actor, userId, reason)
		return praetorResult(actor, "kick", userId :: number, reason :: string, ok, code)
	end,
}

actions["praetor.ban"] = {
	permission = "praetor.ban",
	execute = function(actor, d)
		local err, userId, reason, duration = readSanction(actor, d, true)
		if err then
			return err
		end
		local ok, code = Praetor.ban(actor, userId, duration, reason)
		return praetorResult(
			actor,
			"ban",
			userId :: number,
			`{reason} ({Core.formatDuration(duration)})`,
			ok,
			code
		)
	end,
}

actions["praetor.unban"] = {
	permission = "praetor.unban",
	execute = function(actor, d)
		if not Core.isUserId(d.userId) then
			return failure("player_not_found")
		end
		local ok, code = Praetor.unban(actor, d.userId)
		return praetorResult(actor, "unban", d.userId, "—", ok, code)
	end,
}

-- Staff teleport. Temporary: it will move to Viator once it exists.
actions["teleport"] = {
	permission = "consul.teleport",
	execute = function(actor, d)
		if not Core.isUserId(d.userId) or (d.direction ~= "to" and d.direction ~= "bring") then
			return failure("invalid_value")
		end
		local target = Players:GetPlayerByUserId(d.userId)
		if not target then
			return failure("offline")
		end
		if d.direction == "bring" and not Senatus.canActOn(actor, d.userId) then
			return failure("insufficient_rank")
		end
		local source = character(if d.direction == "to" then actor else target)
		local destination = character(if d.direction == "to" then target else actor)
		if not source or not destination then
			return failure("no_character")
		end
		source:PivotTo(destination:GetPivot() * CFrame.new(0, 0, 4))
		Censor.logAction(
			actor,
			if d.direction == "to" then "teleport to" else "teleport bring",
			{ name = target.Name, userId = target.UserId }
		)
		return success()
	end,
}

actions["server.state"] = {
	permission = "consul.open",
	execute = function()
		return success({ server = Praefectus.state() })
	end,
}

local KINDS = { info = true, warning = true, maintenance = true }

actions["server.announce"] = {
	permission = "praefectus.announce",
	execute = function(actor, d)
		if not Core.isText(d.text, 200) or not string.match(d.text, "%S") then
			return failure("invalid_text")
		end
		if not KINDS[d.kind] then
			return failure("invalid_value")
		end
		local text = filterText(d.text, actor)
		if not text then
			return failure("filtering_failed")
		end
		local announcement = { kind = d.kind, text = text, title = "Announcement", duration = 10 }
		if d.everywhere == true then
			Praeco.announceEverywhere(announcement)
		else
			Praeco.announce(announcement)
		end
		Censor.logAction(actor, if d.everywhere == true then "announcement (all servers)" else "announcement", nil, text)
		return success()
	end,
}

actions["server.lock"] = {
	permission = "praefectus.lock",
	execute = function(actor, d)
		if type(d.state) ~= "boolean" then
			return failure("invalid_value")
		end
		if d.everywhere == true then
			local ok, code = Praefectus.broadcastOrder("lock", { state = d.state })
			if not ok then
				return failure(code)
			end
		else
			Praefectus.lock(d.state)
		end
		local action = if d.state then "lock" else "unlock"
		Censor.logAction(actor, if d.everywhere == true then `{action} (all servers)` else action)
		return success()
	end,
}

actions["server.restart"] = {
	permission = "praefectus.restart",
	execute = function(actor, d)
		if not Core.isNumber(d.delaySeconds) or d.delaySeconds < 5 or d.delaySeconds > 600 then
			return failure("invalid_value")
		end
		local reason = "Maintenance"
		if Core.isText(d.reason, 120) and string.match(d.reason, "%S") then
			local filter = filterText(d.reason, actor)
			if not filter then
				return failure("filtering_failed")
			end
			reason = filter
		end
		local delaySeconds = math.floor(d.delaySeconds)
		local ok, code
		if d.everywhere == true then
			ok, code = Praefectus.broadcastOrder("restart", { delaySeconds = delaySeconds, reason = reason })
		else
			ok, code = Praefectus.restart(delaySeconds, reason)
		end
		if not ok then
			return failure(code)
		end
		Censor.logAction(
			actor,
			if d.everywhere == true then "restart (all servers)" else "restart",
			nil,
			`{reason}: {Core.formatCountdown(delaySeconds)}`
		)
		return success()
	end,
}

actions["server.cancel"] = {
	permission = "praefectus.restart",
	execute = function(actor, d)
		if d.everywhere == true then
			local ok, code = Praefectus.broadcastOrder("cancel", {})
			if not ok then
				return failure(code)
			end
		elseif not Praefectus.cancelRestart() then
			return failure("nothing_to_cancel")
		end
		Censor.logAction(actor, "restart cancelled")
		return success()
	end,
}

actions["lex.list"] = {
	permission = "lex.edit",
	execute = function()
		return success({ settings = Lex.list() })
	end,
}

actions["lex.edit"] = {
	permission = "lex.edit",
	execute = function(actor, d)
		if not Core.isText(d.key, 80) then
			return failure("unknown_key")
		end
		local previous = select(2, pcall(Lex.get, d.key))
		local ok, code
		if d.reset == true then
			ok, code = Lex.reset(d.key)
		else
			ok, code = Lex.set(d.key, d.value)
		end
		if not ok then
			return failure(code)
		end
		Censor.logAction(actor, "setting", nil, `{d.key}: {tostring(previous)} → {tostring(Lex.get(d.key))}`)
		return success({ value = Lex.get(d.key) })
	end,
}

actions["censor.log"] = {
	permission = "censor.log",
	execute = function()
		return success({ entries = Censor.getLog(100) })
	end,
}

-- Broadcast to open panels --------------------------------------------------

local function staffWith(permission: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if Senatus.can(player, permission) then
			table.insert(list, player)
		end
	end
	return list
end

local function push(kind: string, data: any?, permission: string?)
	Veredarius.sendTo("consul.update", staffWith(permission or "consul.open"), kind, data)
end

-- Lifecycle ---------------------------------------------------------------------------

function Consul.init(deps)
	Senatus = deps.Senatus
	Praetor = deps.Praetor
	Praefectus = deps.Praefectus
	Censor = deps.Censor
	Lex = deps.Lex
	Praeco = deps.Praeco

	Veredarius.declare("consul.update")
	Veredarius.declare("consul.access")
end

function Consul.start()
	Veredarius.serve("consul", function(actor: Player, name: any, data: any)
		if type(name) ~= "string" then
			return failure("unknown_action")
		end
		local action = actions[name]
		if not action then
			return failure("unknown_action")
		end
		if not Senatus.can(actor, "consul.open") or not Senatus.can(actor, action.permission) then
			-- Every client asks for access at startup: a refusal here is normal.
			if name == "access" then
				return failure("unauthorized")
			end
			logger.warning(`{actor.Name} tried "{name}" without permission`)
			return failure("unauthorized")
		end
		return action.execute(actor, if type(data) == "table" then data else {})
	end)

	-- The rank can arrive after the client has loaded (groups): notify it.
	Signum.on("senatus.rank", function(player: Player)
		if Senatus.can(player, "consul.open") then
			Veredarius.send("consul.access", player)
		end
	end)

	Players.PlayerAdded:Connect(function()
		push("players")
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(push, "players")
	end)
	Signum.on("praetor.sanction", function(_kind, userId)
		push("players")
		push("record", userId)
	end)
	Signum.on("praefectus.state", function(state)
		push("server", state)
	end)
	Signum.on("censor.entry", function(entry)
		push("log", entry, "censor.log")
	end)
	Signum.on("lex.change", function()
		push("settings", nil, "lex.edit")
	end)
end

return Consul
