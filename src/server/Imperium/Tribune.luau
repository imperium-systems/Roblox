--!strict
-- Tribune: reports and support.
-- Lets a player report one or several players (up to tribune.max_targets) or a bug, attaches the
-- context automatically (server, positions, Lictor score, past warnings, the recent chat
-- of everyone involved) and
-- follows the ticket until staff close it, with a short comment. The reporter is told
-- when their ticket is handled, even on a later visit.
-- Bug reports, player reports and closed tickets also leave through Nuntius (webhooks).
-- Does not sanction anyone (Praetor): staff decide, Tribune only carries the ticket.
--
-- Players open the form with the button at the bottom left, or "/report [name]" in chat.
-- Staff handle tickets in the panel (Consul), through the functions below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)
local Veredarius = require(Imperium.Veredarius)

local logger = Scriba.scoped("Tribune")

local CHANNEL = "tribune"
local OPEN_CHANNEL = "tribune.open"
local MAX_TICKETS = 200 -- kept across all servers; the oldest closed ones go first
local MAX_LENGTH = 300
local COMMAND = "/report"
local MAX_COMMENT = 300
local CHAT_KEEP = 10 -- messages kept per player
local CHAT_WINDOW = 300 -- seconds of chat attached to a report
local FORUM = Color3.fromHex("#66D2CE")

-- Categories a player can choose, by kind of report.
local CATEGORIES: { [string]: { [string]: string } } = {
	player = {
		cheating = "Cheating",
		harassment = "Harassment",
		language = "Inappropriate language",
		griefing = "Griefing",
		other = "Other",
	},
	bug = {
		gameplay = "Gameplay",
		interface = "Interface",
		map = "Map",
		other = "Other",
	},
}

export type Status = "open" | "claimed" | "closed"
export type Outcome = "resolved" | "dismissed"

export type Ticket = {
	id: number,
	kind: string,
	category: string,
	categoryLabel: string,
	description: string,
	reporterId: number,
	reporterName: string,
	-- First reported player, kept for the Log and older tickets; targets lists them all.
	targetId: number?,
	targetName: string?,
	targets: { Target }?,
	context: { { string } }, -- { label, value } pairs, already formatted
	status: Status,
	date: number,
	updated: number,
	claimedBy: string?,
	claimedById: number?,
	closedBy: string?,
	outcome: Outcome?,
	notified: boolean?, -- the reporter has been told about the outcome
	comment: string?, -- written by staff when closing, filtered
	-- Chat written shortly before the report, filtered. Missing while being filtered.
	-- target is the chat of the first reported player, targets the chat of each of them.
	chat: { reporter: { ChatLine }, target: { ChatLine }?, targets: { TargetChat }? }?,
}

export type Target = { userId: number, name: string }
export type ChatLine = { date: number, text: string }
export type TargetChat = { userId: number, lines: { ChatLine } }

type Book = { next: number, tickets: { Ticket } }

local Tribune = {
	dependencies = { "Tabularius", "Lex", "Praeco", "Lictor", "Praetor", "Praefectus", "Nuntius" },
}

local keyStore: any
local Lex: any
local Praeco: any
local Lictor: any
local Praetor: any
local Praefectus: any
local Nuntius: any

local lastReport: { [Player]: number } = {}
-- Raw chat, never shown as is: it is filtered when attached to a report.
local chatLog: { [Player]: { ChatLine } } = {}

local function failure(code: string): { [string]: any }
	return { ok = false, err = code }
end

-- Player text goes through the Roblox filter before staff read it.
local function filterText(text: string, authorId: number, context: Enum.TextFilterContext?): string?
	local ok, result = pcall(function()
		local filter = TextService:FilterStringAsync(text, authorId, context or Enum.TextFilterContext.PublicChat)
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

-- The reported players of a ticket (older tickets only have targetId).
function Tribune.targetsOf(ticket: Ticket): { Target }
	if ticket.targets then
		return ticket.targets
	end
	if ticket.targetId then
		return { { userId = ticket.targetId, name = ticket.targetName or tostring(ticket.targetId) } }
	end
	return {}
end

-- "Name1, Name2" for the reported players, or nil for a bug report.
function Tribune.targetNames(ticket: Ticket): string?
	local names = {}
	for _, target in Tribune.targetsOf(ticket) do
		table.insert(names, target.name)
	end
	return if #names > 0 then table.concat(names, ", ") else nil
end

local function readBook(): Book?
	local ok, book = keyStore:read("tickets")
	if not ok then
		return nil
	end
	return book or { next = 1, tickets = {} }
end

-- Changes one ticket. fn returns false to leave the book untouched.
local function editTicket(id: number, fn: (Ticket) -> boolean): (boolean, Ticket?)
	local changed: Ticket? = nil
	local ok = keyStore:update("tickets", function(book: Book?)
		changed = nil
		if not book then
			return nil
		end
		for _, ticket in book.tickets do
			if ticket.id == id then
				if not fn(ticket) then
					return nil
				end
				ticket.updated = os.time()
				changed = ticket
				return book
			end
		end
		return nil
	end)
	return ok and changed ~= nil, changed
end

local function position(player: Player): Vector3?
	local character = player.Character
	local root = character and character.PrimaryPart
	return root and root.Position
end

local function formatPosition(p: Vector3): string
	return `{math.round(p.X)}, {math.round(p.Y)}, {math.round(p.Z)}`
end

-- What staff need to judge the report without asking the reporter.
local function gatherContext(reporter: Player, targets: { Player }): { { string } }
	local server = Praefectus.state()
	local context: { { string } } = {
		{ "Server", `{string.sub(server.jobId, 1, 8)} · version {server.version}` },
		{ "Players", `{server.players}/{server.max}` },
		{ "Server uptime", Core.formatDuration(os.time() - server.startedAt) },
		{ "Reporter account", `{reporter.AccountAge} days old` },
	}
	local reporterPosition = position(reporter)
	if reporterPosition then
		table.insert(context, { "Reporter position", formatPosition(reporterPosition) })
	end
	for _, target in targets do
		-- One target keeps the short labels; several are told apart by name.
		local prefix = if #targets == 1 then "Target" else target.Name
		local targetPosition = position(target)
		if targetPosition then
			table.insert(context, { `{prefix} position`, formatPosition(targetPosition) })
			if reporterPosition then
				table.insert(context, {
					if #targets == 1 then "Distance" else `{prefix} distance`,
					`{math.round((targetPosition - reporterPosition).Magnitude)} studs`,
				})
			end
		end
		table.insert(context, { `{prefix} account`, `{target.AccountAge} days old` })
		table.insert(context, {
			if #targets == 1 then "Lictor score" else `{prefix} Lictor score`,
			tostring(Lictor.scoreOf(target)),
		})
		local state = Praetor.state(target.UserId)
		table.insert(context, {
			if #targets == 1 then "Past warnings" else `{prefix} warnings`,
			tostring(if state then state.warnings else 0),
		})
	end
	return context
end

-- Tells the reporter how their ticket ended, if they are on this server.
local function tellReporter(ticket: Ticket): boolean
	local reporter = Players:GetPlayerByUserId(ticket.reporterId)
	if not reporter then
		return false
	end
	local names = Tribune.targetNames(ticket)
	local about = if names then `your report about {names}` else "your bug report"
	Praeco.notify(reporter, {
		kind = "success",
		title = "REPORT",
		text = if ticket.outcome == "resolved"
			then `Staff have handled {about} (#{ticket.id}). Thank you.`
			else `Staff have reviewed {about} (#{ticket.id}). No action was needed this time.`,
		duration = 8,
	})
	return true
end

-- Chat ---------------------------------------------------------------------------------

local function recordChat(player: Player, text: string)
	-- Commands (/report, /e dance…) are not conversation.
	if string.sub(text, 1, 1) == "/" then
		return
	end
	local list = chatLog[player]
	if not list then
		list = {}
		chatLog[player] = list
	end
	table.insert(list, { date = os.time(), text = string.sub(text, 1, 200) })
	while #list > CHAT_KEEP do
		table.remove(list, 1)
	end
end

local function recentChat(player: Player?): { ChatLine }
	local list = {}
	local since = os.time() - CHAT_WINDOW
	for _, line in (player and chatLog[player]) or {} do
		if line.date >= since then
			table.insert(list, { date = line.date, text = line.text })
		end
	end
	return list
end

local function filterChat(lines: { ChatLine }, authorId: number): { ChatLine }
	local result = {}
	for _, line in lines do
		local text = filterText(line.text, authorId, Enum.TextFilterContext.PublicChat)
		table.insert(result, { date = line.date, text = text or "[could not be filtered]" })
	end
	return result
end

-- Webhooks -------------------------------------------------------------------------------

local function contextFields(ticket: Ticket): { any }
	local fields = {}
	for _, pair in ticket.context do
		table.insert(fields, { name = pair[1], value = pair[2], inline = true })
	end
	return fields
end

local function reportedField(ticket: Ticket): { [string]: any }?
	local targets = Tribune.targetsOf(ticket)
	if #targets == 0 then
		return nil
	end
	local lines = {}
	for _, target in targets do
		table.insert(lines, `{target.name} ({target.userId})`)
	end
	return {
		name = if #targets == 1 then "Reported player" else "Reported players",
		value = table.concat(lines, "\n"),
		inline = true,
	}
end

local function announceTicket(ticket: Ticket)
	local fields = {
		{ name = "Reporter", value = `{ticket.reporterName} ({ticket.reporterId})`, inline = true },
	}
	local reported = reportedField(ticket)
	if reported then
		table.insert(fields, reported)
	end
	for _, field in contextFields(ticket) do
		table.insert(fields, field)
	end
	Nuntius.send(if ticket.kind == "bug" then "bugs" else "reports", {
		title = `{if ticket.kind == "bug" then "Bug" else "Report"} #{ticket.id} · {ticket.categoryLabel}`,
		description = ticket.description,
		color = FORUM,
		fields = fields,
		footer = "Imperium · Tribune",
	})
end

local function announceClosing(ticket: Ticket)
	local fields = {
		{ name = "Outcome", value = if ticket.outcome == "resolved" then "Resolved" else "Dismissed", inline = true },
		{ name = "Closed by", value = ticket.closedBy or "-", inline = true },
		{ name = "Reporter", value = ticket.reporterName, inline = true },
	}
	local reported = reportedField(ticket)
	if reported then
		table.insert(fields, reported)
	end
	table.insert(fields, { name = "Report", value = ticket.description })
	table.insert(fields, { name = "Staff comment", value = ticket.comment or "No comment." })
	Nuntius.send("closed", {
		title = `{if ticket.kind == "bug" then "Bug" else "Report"} #{ticket.id} closed · {ticket.categoryLabel}`,
		color = if ticket.outcome == "resolved" then Color3.fromHex("#74C67A") else Color3.fromHex("#8A8071"),
		fields = fields,
		footer = "Imperium · Tribune",
	})
end

-- Player side ----------------------------------------------------------------------

local function categoriesFor(kind: string): { { value: string, label: string } }
	local list = {}
	for value, label in CATEGORIES[kind] do
		table.insert(list, { value = value, label = label })
	end
	table.sort(list, function(a, b)
		-- "Other" always last.
		if a.value == "other" or b.value == "other" then
			return b.value == "other" and a.value ~= "other"
		end
		return a.label < b.label
	end)
	return list
end

local function cooldownLeft(player: Player): number
	local last = lastReport[player]
	if not last then
		return 0
	end
	return math.max(0, math.ceil(last + Lex.get("tribune.cooldown") - os.clock()))
end

-- What the reporter sees of a ticket: never the staff names or the context.
local function publicView(ticket: Ticket): { [string]: any }
	return {
		id = ticket.id,
		kind = ticket.kind,
		categoryLabel = ticket.categoryLabel,
		targetName = Tribune.targetNames(ticket),
		description = ticket.description,
		status = ticket.status,
		outcome = ticket.outcome,
		date = ticket.date,
	}
end

function Tribune.submit(reporter: Player, data: { [string]: any }): { [string]: any }
	if not Lex.get("tribune.enabled") then
		return failure("disabled")
	end
	local kind = data.kind
	if type(kind) ~= "string" or not CATEGORIES[kind] then
		return failure("invalid_value")
	end
	if type(data.category) ~= "string" or not CATEGORIES[kind][data.category] then
		return failure("invalid_value")
	end
	if not Core.isText(data.description, MAX_LENGTH) then
		return failure("invalid_text")
	end
	local raw = string.gsub(data.description, "^%s*(.-)%s*$", "%1")
	if #raw < 10 then
		return failure("too_short")
	end

	-- One or several players: userIds (a list), or userId for a single one.
	local targets: { Player } = {}
	if kind == "player" then
		local ids = if type(data.userIds) == "table" then data.userIds else { data.userId }
		if #ids == 0 then
			return failure("player_not_found")
		end
		if #ids > Lex.get("tribune.max_targets") then
			return failure("too_many_targets")
		end
		for _, userId in ids do
			if not Core.isUserId(userId) then
				return failure("player_not_found")
			end
			if userId == reporter.UserId then
				return failure("self_report")
			end
			local target = Players:GetPlayerByUserId(userId)
			if not target then
				return failure("offline")
			end
			if not table.find(targets, target) then
				table.insert(targets, target)
			end
		end
	end
	local target: Player? = targets[1]
	local targetList: { Target } = {}
	for _, player in targets do
		table.insert(targetList, { userId = player.UserId, name = player.Name })
	end

	local wait = cooldownLeft(reporter)
	if wait > 0 then
		return { ok = false, err = "cooldown", wait = wait }
	end

	local description = filterText(raw, reporter.UserId)
	if not description then
		return failure("filtering_failed")
	end
	-- Counted before the save: a failed save must not let someone spam retries.
	lastReport[reporter] = os.clock()

	local context = gatherContext(reporter, targets)
	-- Taken now: the targets may leave before the filter has finished.
	local reporterChat = if target then recentChat(reporter) else {}
	local targetChats = {}
	for _, player in targets do
		table.insert(targetChats, { userId = player.UserId, lines = recentChat(player) })
	end
	local maxOpen = Lex.get("tribune.max_open")
	local refusal: string? = nil
	local created: Ticket? = nil
	local ok = keyStore:update("tickets", function(stored: Book?)
		refusal = nil
		created = nil
		local book = stored or { next = 1, tickets = {} }
		local open = 0
		for _, ticket in book.tickets do
			if ticket.reporterId == reporter.UserId and ticket.status ~= "closed" then
				open += 1
				-- One open report per reported player.
				for _, reported in Tribune.targetsOf(ticket) do
					for _, wanted in targetList do
						if wanted.userId == reported.userId then
							refusal = "already_reported"
							return nil
						end
					end
				end
			end
		end
		if open >= maxOpen then
			refusal = "too_many_open"
			return nil
		end
		local now = os.time()
		local ticket: Ticket = {
			id = book.next,
			kind = kind,
			category = data.category,
			categoryLabel = CATEGORIES[kind][data.category],
			description = description :: string,
			reporterId = reporter.UserId,
			reporterName = reporter.Name,
			targetId = target and target.UserId,
			targetName = target and target.Name,
			targets = if #targetList > 0 then targetList else nil,
			context = context,
			status = "open",
			date = now,
			updated = now,
		}
		book.next += 1
		table.insert(book.tickets, ticket)
		-- Too many tickets: drop the oldest closed one, or the oldest one at all.
		while #book.tickets > MAX_TICKETS do
			local removed = false
			for i, old in book.tickets do
				if old.status == "closed" then
					table.remove(book.tickets, i)
					removed = true
					break
				end
			end
			if not removed then
				table.remove(book.tickets, 1)
			end
		end
		created = ticket
		return book
	end)

	if refusal then
		lastReport[reporter] = nil
		return failure(refusal)
	end
	if not ok or not created then
		return failure("save_failed")
	end
	local ticket = created :: Ticket
	logger.info(`ticket #{ticket.id} from {reporter.Name}: {ticket.categoryLabel}`)
	Signum.emit("tribune.ticket", ticket, true)
	announceTicket(ticket)
	if target then
		task.spawn(function()
			local filtered: { TargetChat } = {}
			for _, entry in targetChats do
				table.insert(filtered, { userId = entry.userId, lines = filterChat(entry.lines, entry.userId) })
			end
			local chat = {
				reporter = filterChat(reporterChat, reporter.UserId),
				target = filtered[1] and filtered[1].lines,
				targets = filtered,
			}
			editTicket(ticket.id, function(t)
				t.chat = chat
				return true
			end)
			Signum.emit("tribune.ticket", ticket, false)
		end)
	end
	return { ok = true, id = ticket.id }
end

-- Tickets of one reporter, most recent first.
function Tribune.ticketsOf(userId: number): { { [string]: any } }?
	local book = readBook()
	if not book then
		return nil
	end
	local list = {}
	for i = #book.tickets, 1, -1 do
		local ticket = book.tickets[i]
		if ticket.reporterId == userId then
			table.insert(list, publicView(ticket))
		end
	end
	return list
end

-- Staff side -----------------------------------------------------------------------

-- filter: "open" (open and claimed), "closed" or "all". Most recent first.
function Tribune.list(filter: string, limit: number?): { Ticket }?
	local book = readBook()
	if not book then
		return nil
	end
	local list = {}
	for i = #book.tickets, 1, -1 do
		local ticket = book.tickets[i]
		local closed = ticket.status == "closed"
		if filter == "all" or (filter == "closed") == closed then
			table.insert(list, ticket)
			if limit and #list >= limit then
				break
			end
		end
	end
	return list
end

function Tribune.get(id: number): Ticket?
	local book = readBook()
	if not book then
		return nil
	end
	for _, ticket in book.tickets do
		if ticket.id == id then
			return ticket
		end
	end
	return nil
end

Tribune.MAX_COMMENT = MAX_COMMENT

-- Webhook channels that will really send, for the panel.
function Tribune.webhooks(): { [string]: boolean }
	return Nuntius.channels()
end

function Tribune.openCount(): number
	local book = readBook()
	if not book then
		return 0
	end
	local count = 0
	for _, ticket in book.tickets do
		if ticket.status ~= "closed" then
			count += 1
		end
	end
	return count
end

-- Takes a ticket so that two staff members do not handle the same one.
function Tribune.claim(actor: Player, id: number): (boolean, string?, Ticket?)
	local refusal = "ticket_not_found"
	local ok, ticket = editTicket(id, function(t)
		if t.status == "closed" then
			refusal = "ticket_closed"
			return false
		end
		if t.status == "claimed" and t.claimedById ~= actor.UserId then
			refusal = "already_claimed"
			return false
		end
		t.status = "claimed"
		t.claimedBy = actor.Name
		t.claimedById = actor.UserId
		return true
	end)
	if not ok then
		return false, refusal
	end
	Signum.emit("tribune.ticket", ticket)
	return true, nil, ticket
end

-- Gives a claimed ticket back to the queue.
function Tribune.release(actor: Player, id: number, force: boolean): (boolean, string?, Ticket?)
	local refusal = "ticket_not_found"
	local ok, ticket = editTicket(id, function(t)
		if t.status ~= "claimed" then
			refusal = "not_claimed"
			return false
		end
		if t.claimedById ~= actor.UserId and not force then
			refusal = "already_claimed"
			return false
		end
		t.status = "open"
		t.claimedBy = nil
		t.claimedById = nil
		return true
	end)
	if not ok then
		return false, refusal
	end
	Signum.emit("tribune.ticket", ticket)
	return true, nil, ticket
end

-- Closes a ticket. Someone else's claim can only be overridden with force.
-- comment: optional, already filtered by the caller.
function Tribune.close(
	actor: Player,
	id: number,
	outcome: Outcome,
	force: boolean,
	comment: string?
): (boolean, string?, Ticket?)
	local refusal = "ticket_not_found"
	local ok, ticket = editTicket(id, function(t)
		if t.status == "closed" then
			refusal = "ticket_closed"
			return false
		end
		if t.status == "claimed" and t.claimedById ~= actor.UserId and not force then
			refusal = "already_claimed"
			return false
		end
		t.status = "closed"
		t.outcome = outcome
		t.comment = comment
		t.closedBy = actor.Name
		t.claimedBy = t.claimedBy or actor.Name
		t.claimedById = t.claimedById or actor.UserId
		return true
	end)
	if not ok or not ticket then
		return false, refusal
	end
	if tellReporter(ticket) then
		editTicket(id, function(t)
			t.notified = true
			return true
		end)
	end
	announceClosing(ticket)
	Signum.emit("tribune.ticket", ticket)
	return true, nil, ticket
end

-- Lifecycle ---------------------------------------------------------------

-- A reporter who was away when their ticket closed hears about it on their next visit.
local function catchUp(player: Player)
	local book = readBook()
	if not book then
		return
	end
	for _, ticket in book.tickets do
		if ticket.reporterId == player.UserId and ticket.status == "closed" and not ticket.notified then
			if tellReporter(ticket) then
				editTicket(ticket.id, function(t)
					t.notified = true
					return true
				end)
			end
		end
	end
end

local function playerFromName(text: string): Player?
	local wanted = string.lower((string.gsub(text, "^%s*@?(.-)%s*$", "%1")))
	if wanted == "" then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if string.lower(player.Name) == wanted or string.lower(player.DisplayName) == wanted then
			return player
		end
	end
	for _, player in Players:GetPlayers() do
		if string.sub(string.lower(player.Name), 1, #wanted) == wanted then
			return player
		end
	end
	return nil
end

-- "/report" opens the form; "/report name" picks the player too.
local function createCommand()
	local ok, err = pcall(function()
		local command = Instance.new("TextChatCommand")
		command.Name = "ImperiumReport"
		command.PrimaryAlias = COMMAND
		command.Parent = TextChatService
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if not player then
				return
			end
			local target = playerFromName(string.sub(text, #COMMAND + 1))
			Veredarius.send(OPEN_CHANNEL, player, if target and target ~= player then target.UserId else nil)
		end)
	end)
	if not ok then
		logger.warning(`the {COMMAND} chat command is unavailable:`, err)
	end
end

function Tribune.init(deps)
	keyStore = deps.Tabularius.keyStore("Tribune")
	Lex = deps.Lex
	Praeco = deps.Praeco
	Lictor = deps.Lictor
	Praetor = deps.Praetor
	Praefectus = deps.Praefectus
	Nuntius = deps.Nuntius

	Lex.define("tribune.enabled", {
		default = true,
		type = "boolean",
		description = "Lets players send reports.",
	})
	Lex.define("tribune.show_button", {
		default = true,
		type = "boolean",
		description = "Shows the Report button at the bottom left (the /report command always works).",
	})
	Lex.define("tribune.cooldown", {
		default = 60,
		type = "number",
		description = "Seconds a player must wait between two reports.",
		min = 0,
		max = 3600,
	})
	Lex.define("tribune.max_targets", {
		default = 5,
		type = "number",
		description = "Players a player can name in one report (1 for one player only).",
		min = 1,
		max = 10,
	})
	Lex.define("tribune.max_open", {
		default = 3,
		type = "number",
		description = "Unhandled reports a player can have at once.",
		min = 1,
		max = 20,
	})

	Veredarius.declare(OPEN_CHANNEL)
	Veredarius.declare("tribune.settings")
end

function Tribune.start()
	Veredarius.serve(CHANNEL, function(player: Player, action: any, data: any)
		local d = if type(data) == "table" then data else {}
		if action == "settings" then
			return {
				ok = true,
				enabled = Lex.get("tribune.enabled"),
				button = Lex.get("tribune.show_button"),
				maxLength = MAX_LENGTH,
				maxTargets = Lex.get("tribune.max_targets"),
				categories = { player = categoriesFor("player"), bug = categoriesFor("bug") },
				wait = cooldownLeft(player),
			}
		elseif action == "submit" then
			return Tribune.submit(player, d)
		elseif action == "mine" then
			local list = Tribune.ticketsOf(player.UserId)
			if not list then
				return failure("save_failed")
			end
			return { ok = true, tickets = list }
		end
		return failure("unknown_action")
	end)

	-- The button and the player limit follow the settings live.
	local function broadcastSettings()
		Veredarius.sendToAll("tribune.settings", {
			enabled = Lex.get("tribune.enabled"),
			button = Lex.get("tribune.show_button"),
			maxTargets = Lex.get("tribune.max_targets"),
		})
	end
	Lex.onChange("tribune.enabled", broadcastSettings)
	Lex.onChange("tribune.show_button", broadcastSettings)
	Lex.onChange("tribune.max_targets", broadcastSettings)

	createCommand()

	local function watchChat(player: Player)
		player.Chatted:Connect(function(text)
			recordChat(player, text)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchChat(player)
	end
	Players.PlayerAdded:Connect(function(player)
		watchChat(player)
		task.delay(5, catchUp, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastReport[player] = nil
		chatLog[player] = nil
	end)
end

return Tribune
