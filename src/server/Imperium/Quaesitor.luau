--!strict
-- Quaesitor: investigations.
-- Keeps a rolling record of the last minutes on the server: the position and state of
-- each character (once per second), Lictor detections, deaths and staff actions.
-- When a player report is sent (Tribune) or a Lictor alert fires, freezes that record into
-- a case file for the players involved and stores it with Tabularius.
-- Staff replay a case from the panel (Consul): ghosts move on the viewer's screen only.
-- Case files are deleted after the number of days set in Lex.
--
-- Does not detect cheating (Lictor), decide sanctions (Praetor) or record the chat
-- (Tribune already attaches the filtered chat to its tickets).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local logger = Scriba.scoped("Quaesitor")

local SAMPLE = 1 -- seconds between two samples of every character
local MAX_CASES = 200 -- kept across all servers; the oldest go first
local LICTOR_GAP = 60 -- seconds between two Lictor cases about the same player
local SWEEP = 3600 -- seconds between two checks for expired cases
local DAY = 86400

-- Sample flags, added together.
local DEAD = 1
local SEATED = 2
local AIRBORNE = 4

-- One sample: { t, x, y, z, yaw (degrees), health, flags }.
-- In memory t is os.clock(); in a case it is seconds since the start of the case.
type Sample = { number }

type Frame = { t: number, players: { [number]: Sample } }

export type Event = {
	t: number,
	kind: string, -- "lictor" | "death" | "staff" | "left"
	userIds: { number }?, -- only in memory: who the event is about
	userId: number?, -- in a case: the involved player it is about
	text: string,
}

export type Person = { userId: number, name: string, role: string }

export type Summary = {
	id: number,
	source: string, -- "report" | "lictor"
	ticketId: number?,
	label: string,
	players: { Person },
	date: number, -- when the case was created
	startedAt: number, -- wall time of the first sample
	duration: number,
	eventCount: number,
	expiresAt: number?, -- computed when listed, never stored
}

export type Track = Person & { samples: { Sample } }

export type Case = Summary & { tracks: { Track }, events: { Event } }

type Index = { next: number, cases: { Summary } }

local Quaesitor = {
	dependencies = { "Tabularius", "Lex" },
}

local keyStore: any
local Lex: any

local frames: { Frame } = {}
local events: { Event } = {}
local lastLictorCase: { [number]: number } = {}

local function round1(n: number): number
	return math.round(n * 10) / 10
end

-- Recording ----------------------------------------------------------------------------

local function sampleOf(player: Player, now: number): Sample?
	local character = player.Character
	local root = character and character.PrimaryPart
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	local p = root.Position
	local look = root.CFrame.LookVector
	local flags = 0
	if humanoid.Health <= 0 then
		flags += DEAD
	end
	if humanoid.SeatPart ~= nil then
		flags += SEATED
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		flags += AIRBORNE
	end
	return {
		now,
		round1(p.X),
		round1(p.Y),
		round1(p.Z),
		math.round(math.deg(math.atan2(-look.X, -look.Z))),
		math.round(humanoid.Health),
		flags,
	}
end

local function trim(now: number)
	local from = now - Lex.get("quaesitor.window")
	while frames[1] and frames[1].t < from do
		table.remove(frames, 1)
	end
	while events[1] and events[1].t < from do
		table.remove(events, 1)
	end
end

local function recordFrame()
	local now = os.clock()
	local frame: Frame = { t = now, players = {} }
	for _, player in Players:GetPlayers() do
		local sample = sampleOf(player, now)
		if sample then
			frame.players[player.UserId] = sample
		end
	end
	table.insert(frames, frame)
	trim(now)
end

local function addEvent(kind: string, userIds: { number }, text: string)
	if not Lex.get("quaesitor.enabled") then
		return
	end
	table.insert(events, { t = os.clock(), kind = kind, userIds = userIds, text = text })
end

local function watchDeaths(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Connect(function()
			-- Classic convention of weapons: an ObjectValue "creator" pointing to the killer.
			local creator = humanoid:FindFirstChild("creator")
			local killer = if creator and creator:IsA("ObjectValue") then creator.Value else nil
			if killer and killer:IsA("Player") and killer ~= player then
				addEvent("death", { player.UserId, killer.UserId }, `{player.Name} killed by {killer.Name}`)
			else
				addEvent("death", { player.UserId }, `{player.Name} died`)
			end
		end)
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

-- Case files ---------------------------------------------------------------------------

-- Copies the record of the involved players, with times relative to its start.
local function freeze(involved: { Person }): ({ Track }, { Event }, number, number)
	recordFrame()
	local now = os.clock()
	local start = if frames[1] then frames[1].t else now

	local tracks: { Track } = {}
	for _, person in involved do
		local samples = {}
		for _, frame in frames do
			local sample = frame.players[person.userId]
			if sample then
				local copy = table.clone(sample)
				copy[1] = round1(sample[1] - start)
				table.insert(samples, copy)
			end
		end
		table.insert(tracks, {
			userId = person.userId,
			name = person.name,
			role = person.role,
			samples = samples,
		})
	end

	local caseEvents: { Event } = {}
	for _, event in events do
		for _, person in involved do
			if table.find(event.userIds or {}, person.userId) then
				table.insert(caseEvents, {
					t = round1(event.t - start),
					kind = event.kind,
					userId = person.userId,
					text = event.text,
				})
				break
			end
		end
	end

	return tracks, caseEvents, os.time() - math.round(now - start), round1(now - start)
end

local function removeFromIndex(ids: { number })
	keyStore:update("index", function(stored: Index?)
		if not stored then
			return nil
		end
		local kept = {}
		for _, summary in stored.cases do
			if not table.find(ids, summary.id) then
				table.insert(kept, summary)
			end
		end
		stored.cases = kept
		return stored
	end)
end

local function save(base: { [string]: any }, tracks: { Track }, caseEvents: { Event })
	local summary: Summary? = nil
	local dropped: { number } = {}
	local ok = keyStore:update("index", function(stored: Index?)
		dropped = {}
		local index = stored or { next = 1, cases = {} }
		local fresh = table.clone(base) :: any
		fresh.id = index.next
		index.next += 1
		table.insert(index.cases, fresh)
		while #index.cases > MAX_CASES do
			table.insert(dropped, table.remove(index.cases, 1).id)
		end
		summary = fresh
		return index
	end)
	if not ok or not summary then
		logger.warning(`could not save the case "{base.label}"`)
		return
	end
	local saved = summary :: Summary
	for _, id in dropped do
		keyStore:remove(`case_{id}`)
	end

	local case = table.clone(saved) :: any
	case.tracks = tracks
	case.events = caseEvents
	local written = keyStore:update(`case_{saved.id}`, function()
		return case
	end)
	if not written then
		removeFromIndex({ saved.id })
		logger.warning(`could not save case #{saved.id}`)
		return
	end
	logger.info(`case #{saved.id}: {saved.label}`)
	Signum.emit("quaesitor.case", saved)
end

local function createCase(source: string, ticketId: number?, label: string, involved: { Person })
	if not Lex.get("quaesitor.enabled") then
		return
	end
	local tracks, caseEvents, startedAt, duration = freeze(involved)
	local base = {
		source = source,
		ticketId = ticketId,
		label = label,
		players = involved,
		date = os.time(),
		startedAt = startedAt,
		duration = duration,
		eventCount = #caseEvents,
	}
	task.spawn(save, base, tracks, caseEvents)
end

-- Deletes the cases older than the Lex delay.
local function sweep()
	local limit = os.time() - Lex.get("quaesitor.retention_days") * DAY
	local expired: { number } = {}
	keyStore:update("index", function(stored: Index?)
		expired = {}
		if not stored then
			return nil
		end
		local kept = {}
		for _, summary in stored.cases do
			if summary.date < limit then
				table.insert(expired, summary.id)
			else
				table.insert(kept, summary)
			end
		end
		if #expired == 0 then
			return nil
		end
		stored.cases = kept
		return stored
	end)
	for _, id in expired do
		keyStore:remove(`case_{id}`)
	end
	if #expired > 0 then
		logger.info(`{#expired} expired case file(s) deleted`)
		Signum.emit("quaesitor.case", nil)
	end
end

-- API ---------------------------------------------------------------------------------

local function readIndex(): Index?
	local ok, index = keyStore:read("index")
	if not ok then
		return nil
	end
	return index or { next = 1, cases = {} }
end

local function withExpiry(summary: Summary): Summary
	local copy = table.clone(summary)
	copy.expiresAt = summary.date + Lex.get("quaesitor.retention_days") * DAY
	return copy
end

-- Summaries, most recent first. source: "report", "lictor" or nil for all.
function Quaesitor.list(source: string?, limit: number?): { Summary }?
	local index = readIndex()
	if not index then
		return nil
	end
	local list = {}
	for i = #index.cases, 1, -1 do
		local summary = index.cases[i]
		if source == nil or summary.source == source then
			table.insert(list, withExpiry(summary))
			if limit and #list >= limit then
				break
			end
		end
	end
	return list
end

-- The case created for a Tribune ticket, if any.
function Quaesitor.caseOfTicket(ticketId: number): Summary?
	local index = readIndex()
	if not index then
		return nil
	end
	for _, summary in index.cases do
		if summary.ticketId == ticketId then
			return withExpiry(summary)
		end
	end
	return nil
end

-- Full case, with the tracks and events. Returns (case) or (nil, error_code).
function Quaesitor.get(id: number): (Case?, string?)
	local ok, case = keyStore:read(`case_{id}`)
	if not ok then
		return nil, "save_failed"
	end
	if not case then
		return nil, "case_not_found"
	end
	return withExpiry(case) :: any
end

-- Lifecycle -----------------------------------------------------------------------------

function Quaesitor.init(deps)
	keyStore = deps.Tabularius.keyStore("Quaesitor")
	Lex = deps.Lex

	Lex.define("quaesitor.enabled", {
		default = true,
		type = "boolean",
		description = "Records the last minutes and creates case files on player reports and Lictor alerts.",
	})
	Lex.define("quaesitor.window", {
		default = 180,
		type = "number",
		description = "Seconds of recording kept in a case file.",
		min = 30,
		max = 600,
	})
	Lex.define("quaesitor.retention_days", {
		default = 14,
		type = "number",
		description = "Days a case file is kept before it is deleted.",
		min = 1,
		max = 90,
	})
end

function Quaesitor.start()
	-- Player reports: one case for the reporter and the reported player.
	Signum.on("tribune.ticket", function(ticket: any, created: boolean?)
		if created ~= true or ticket.kind ~= "player" or not ticket.targetId then
			return
		end
		createCase("report", ticket.id, `Report #{ticket.id} · {ticket.categoryLabel}`, {
			{ userId = ticket.reporterId, name = ticket.reporterName, role = "reporter" },
			{ userId = ticket.targetId, name = ticket.targetName, role = "reported" },
		})
	end)

	-- Lictor emits each detection before the alert: the case includes it.
	Signum.on("lictor.detection", function(detection: any)
		addEvent(
			"lictor",
			{ detection.userId },
			`{detection.label}: {detection.details} (score {detection.score})`
		)
	end)
	Signum.on("lictor.alert", function(detection: any)
		local last = lastLictorCase[detection.userId]
		if last and os.clock() - last < LICTOR_GAP then
			return
		end
		lastLictorCase[detection.userId] = os.clock()
		createCase("lictor", nil, `Lictor · {detection.label}`, {
			{ userId = detection.userId, name = detection.name, role = "suspect" },
		})
	end)

	Signum.on("censor.entry", function(entry: any)
		local text = `{entry.actor} · {entry.action}`
		if entry.target then
			text ..= ` · {entry.target}`
		end
		if entry.details then
			text ..= `: {entry.details}`
		end
		addEvent("staff", { entry.actorId, entry.targetId }, text)
	end)

	for _, player in Players:GetPlayers() do
		watchDeaths(player)
	end
	Players.PlayerAdded:Connect(watchDeaths)
	Players.PlayerRemoving:Connect(function(player)
		addEvent("left", { player.UserId }, `{player.Name} left the server`)
		lastLictorCase[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(SAMPLE)
			if Lex.get("quaesitor.enabled") then
				local ok, err = pcall(recordFrame)
				if not ok then
					logger.err("recording failed:", err)
				end
			elseif #frames > 0 then
				table.clear(frames)
				table.clear(events)
			end
		end
	end)

	-- Expired cases: shortly after startup, then every hour and when the delay changes.
	task.delay(30, sweep)
	task.spawn(function()
		while true do
			task.wait(SWEEP)
			sweep()
		end
	end)
	Lex.onChange("quaesitor.retention_days", function()
		task.spawn(sweep)
	end)
end

return Quaesitor
