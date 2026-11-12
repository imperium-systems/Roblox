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
	dependencies = {
		"Senatus",
		"Praetor",
		"Praefectus",
		"Censor",
		"Lex",
		"Praeco",
		"Lictor",
		"Tribune",
		"Quaesitor",
	},
}

local Senatus: any
local Lictor: any
local Quaesitor: any
local Tribune: any
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

-- A ban or mute that is still running, or nil.
local function activeMeasure(m: any): Response?
	if m and (m.expiresAt == nil or m.expiresAt > os.time()) then
		return { expiresAt = m.expiresAt, reason = m.reason, by = m.by, date = m.date }
	end
	return nil
end

-- Part where staff send players with "Send to point".
local function staffPoint(): BasePart?
	local found = workspace:FindFirstChild(Lex.get("consul.staff_point"), true)
	if found and found:IsA("BasePart") then
		return found
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
			ban = activeMeasure(state and state.ban),
			mute = activeMeasure(state and state.mute),
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
--   to     the staff member goes to the player
--   bring  the player comes to the staff member
--   point  the player goes to the staff point (Lex consul.staff_point)
-- slot 1 or 2 shifts the arrival sideways, so two players sent together do not overlap.
local SLOTS = { [0] = CFrame.new(0, 0, 4), [1] = CFrame.new(4, 0, 4), [2] = CFrame.new(-4, 0, 4) }
local MOVES = { to = "teleport to", bring = "teleport bring", point = "teleport to staff point" }

actions["teleport"] = {
	permission = "consul.teleport",
	execute = function(actor, d)
		local direction = d.direction
		if not Core.isUserId(d.userId) or type(direction) ~= "string" or not MOVES[direction] then
			return failure("invalid_value")
		end
		local target = Players:GetPlayerByUserId(d.userId)
		if not target then
			return failure("offline")
		end
		if direction ~= "to" and not Senatus.canActOn(actor, d.userId) then
			return failure("insufficient_rank")
		end
		local mover = if direction == "to" then actor else target
		local model = character(mover)
		if not model then
			return failure("no_character")
		end
		local destination: CFrame
		if direction == "point" then
			local point = staffPoint()
			if not point then
				return failure("no_staff_point")
			end
			destination = point.CFrame + Vector3.new(0, point.Size.Y / 2 + 3, 0)
		else
			local other = character(if direction == "to" then target else actor)
			if not other then
				return failure("no_character")
			end
			destination = other:GetPivot()
		end
		local slot = if d.slot == 1 or d.slot == 2 then d.slot else 0
		-- A staff teleport is legitimate: Lictor must not flag it.
		Lictor.exempt(mover, 2)
		model:PivotTo(destination * SLOTS[slot])
		Censor.logAction(actor, MOVES[direction], { name = target.Name, userId = target.UserId })
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

actions["lictor.list"] = {
	permission = "lictor.view",
	execute = function(actor)
		return success({
			suspects = Lictor.suspects(),
			recent = Lictor.recent(30),
			thresholds = Lictor.thresholds(),
			cases = if Senatus.can(actor, "quaesitor.view") then Quaesitor.list("lictor", 8) else nil,
		})
	end,
}

actions["lictor.clear"] = {
	permission = "lictor.clear",
	execute = function(actor, d)
		if not Core.isUserId(d.userId) then
			return failure("player_not_found")
		end
		if not Lictor.clear(d.userId) then
			return failure("offline")
		end
		Censor.logAction(actor, "suspicion cleared", { name = nameOf(d.userId), userId = d.userId })
		return success()
	end,
}

local FILTERS = { open = true, closed = true, all = true }
local OUTCOMES = { resolved = true, dismissed = true }

actions["tribune.list"] = {
	permission = "tribune.handle",
	execute = function(_, d)
		local filter = if FILTERS[d.filter] then d.filter else "open"
		local tickets = Tribune.list(filter, 60)
		if not tickets then
			return failure("save_failed")
		end
		return success({ tickets = tickets, openCount = Tribune.openCount(), webhooks = Tribune.webhooks() })
	end,
}

-- One side of a ticket: record, sanctions, and the log entries about that player.
local function personOf(actor: Player, userId: number, name: string, log: { any }): Response
	local online = Players:GetPlayerByUserId(userId)
	local record = Censor.record(userId)
	local state = Praetor.state(userId)
	local rank = online and Senatus.rank(online)
	local sanctions = {}
	if record then
		for i = #record.sanctions, math.max(1, #record.sanctions - 4), -1 do
			table.insert(sanctions, record.sanctions[i])
		end
	end
	local entries = {}
	for _, entry in log do
		if entry.targetId == userId or entry.actorId == userId then
			table.insert(entries, entry)
			if #entries >= 8 then
				break
			end
		end
	end
	return {
		userId = userId,
		name = name,
		displayName = if online then online.DisplayName else nil,
		online = online ~= nil,
		rank = rank and rank.name,
		rankColor = rank and rank.color,
		firstSeen = record and record.firstSeen,
		playtime = record and record.playtime,
		warnings = if state then state.warnings else 0,
		ban = activeMeasure(state and state.ban),
		mute = activeMeasure(state and state.mute),
		sanctionCount = if record then #record.sanctions else 0,
		sanctions = sanctions,
		lictor = if online then Lictor.scoreOf(online) else nil,
		log = entries,
		canAct = Senatus.canActOn(actor, userId),
	}
end

actions["tribune.detail"] = {
	permission = "tribune.handle",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("ticket_not_found")
		end
		local ticket = Tribune.get(d.id)
		if not ticket then
			return failure("ticket_not_found")
		end
		local log = Censor.getLog(200)
		return success({
			ticket = ticket,
			reporter = personOf(actor, ticket.reporterId, ticket.reporterName, log),
			target = if ticket.targetId then personOf(actor, ticket.targetId, ticket.targetName, log) else nil,
			maxComment = Tribune.MAX_COMMENT,
			staffPoint = staffPoint() ~= nil,
			case = if Senatus.can(actor, "quaesitor.view") then Quaesitor.caseOfTicket(ticket.id) else nil,
		})
	end,
}

-- Result of a ticket operation, logged with its target.
local function ticketResult(actor: Player, action: string, ok: boolean, code: string?, ticket: any?): Response
	if not ok or not ticket then
		return failure(code or "internal_error")
	end
	local target = if ticket.targetId then { name = ticket.targetName, userId = ticket.targetId } else nil
	Censor.logAction(actor, action, target, `#{ticket.id} {ticket.categoryLabel}`)
	return success()
end

actions["tribune.claim"] = {
	permission = "tribune.handle",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("ticket_not_found")
		end
		local ok, code, ticket = Tribune.claim(actor, d.id)
		return ticketResult(actor, "report claimed", ok, code, ticket)
	end,
}

actions["tribune.release"] = {
	permission = "tribune.handle",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("ticket_not_found")
		end
		local ok, code, ticket = Tribune.release(actor, d.id, Senatus.can(actor, "tribune.manage"))
		return ticketResult(actor, "report released", ok, code, ticket)
	end,
}

actions["tribune.close"] = {
	permission = "tribune.handle",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("ticket_not_found")
		end
		if not OUTCOMES[d.outcome] then
			return failure("invalid_value")
		end
		local comment: string? = nil
		if d.comment ~= nil then
			if not Core.isText(d.comment, Tribune.MAX_COMMENT) then
				return failure("invalid_text")
			end
			if string.match(d.comment, "%S") then
				comment = filterText(d.comment, actor)
				if not comment then
					return failure("filtering_failed")
				end
			end
		end
		local force = Senatus.can(actor, "tribune.manage")
		local ok, code, ticket = Tribune.close(actor, d.id, d.outcome, force, comment)
		local action = if d.outcome == "resolved" then "report resolved" else "report dismissed"
		return ticketResult(actor, action, ok, code, ticket)
	end,
}

local SOURCES = { report = true, lictor = true }

actions["quaesitor.list"] = {
	permission = "quaesitor.view",
	execute = function(_, d)
		local cases = Quaesitor.list(if SOURCES[d.source] then d.source else nil, 60)
		if not cases then
			return failure("save_failed")
		end
		return success({
			cases = cases,
			enabled = Lex.get("quaesitor.enabled"),
			window = Lex.get("quaesitor.window"),
			after = Lex.get("quaesitor.after"),
			interval = Lex.get("quaesitor.interval"),
			others = Lex.get("quaesitor.others"),
			radius = Lex.get("quaesitor.nearby_radius"),
			retention = Lex.get("quaesitor.retention_days"),
		})
	end,
}

-- The full case: positions and events. Opening one is logged, like any look at a record.
actions["quaesitor.get"] = {
	permission = "quaesitor.view",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("case_not_found")
		end
		local case, code = Quaesitor.get(d.id)
		if not case then
			return failure(code or "case_not_found")
		end
		local target = nil
		for _, person in case.players do
			if person.role ~= "reporter" then
				target = { name = person.name, userId = person.userId }
				break
			end
		end
		Censor.logAction(actor, "case opened", target, `#{case.id} {case.label}`)
		return success({
			case = case,
			ticketAccess = Senatus.can(actor, "tribune.handle"),
		})
	end,
}

-- Avatars of a replay, handed to the viewer alone.
actions["quaesitor.ghosts"] = {
	permission = "quaesitor.view",
	execute = function(actor, d)
		if not Core.isPositiveInteger(d.id) then
			return failure("case_not_found")
		end
		local folder, result = Quaesitor.ghosts(actor, d.id)
		if not folder then
			return failure(result :: string)
		end
		return success({ folder = folder, count = result })
	end,
}

-- Streams the map around what the viewer watches during a replay.
actions["quaesitor.focus"] = {
	permission = "quaesitor.view",
	execute = function(actor, d)
		if not (Core.isNumber(d.x) and Core.isNumber(d.y) and Core.isNumber(d.z)) then
			return failure("invalid_value")
		end
		local position = Vector3.new(d.x, d.y, d.z)
		if position.Magnitude > 1e6 then
			return failure("invalid_value")
		end
		Quaesitor.focus(actor, position)
		return success()
	end,
}

actions["quaesitor.end"] = {
	permission = "quaesitor.view",
	execute = function(actor)
		Quaesitor.endReplay(actor)
		return success()
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
	Lictor = deps.Lictor
	Tribune = deps.Tribune
	Quaesitor = deps.Quaesitor

	Lex.define("consul.staff_point", {
		default = "ImperiumStaffPoint",
		type = "string",
		description = "Name of the part in Workspace where staff send players (Send to point).",
	})

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
	Signum.on("lictor.detection", function(detection)
		push("lictor", detection, "lictor.view")
	end)
	-- Over the alert threshold, staff who can see Lictor get a notice wherever they are.
	Signum.on("lictor.alert", function(detection)
		for _, player in staffWith("lictor.view") do
			Praeco.notify(player, {
				kind = "warning",
				title = "LICTOR",
				text = `{detection.label} · {detection.name}`,
				duration = 8,
			})
		end
	end)
	-- A new or deleted case refreshes the case list, and the ticket or Lictor page that links to it.
	Signum.on("quaesitor.case", function(summary)
		push("quaesitor", summary and summary.id, "quaesitor.view")
		if summary and summary.ticketId then
			push("tribune", summary.ticketId, "tribune.handle")
		elseif summary and summary.source == "lictor" then
			push("lictor", nil, "lictor.view")
		end
	end)
	-- Every change refreshes the page; a new ticket also alerts staff wherever they are.
	Signum.on("tribune.ticket", function(ticket, created)
		push("tribune", ticket.id, "tribune.handle")
		if not created then
			return
		end
		local about = if ticket.targetName then ` · {ticket.targetName}` else ""
		for _, player in staffWith("tribune.handle") do
			if player.UserId ~= ticket.reporterId then
				Praeco.notify(player, {
					kind = "info",
					title = "TRIBUNE",
					text = `Report #{ticket.id}: {ticket.categoryLabel}{about}`,
					duration = 8,
				})
			end
		end
	end)
end

return Consul
