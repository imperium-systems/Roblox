--!strict
-- Quaesitor: investigations.
-- Keeps a rolling record of the last minutes on the server: the position, state, worn
-- accessories and tool in hand of each character (every quaesitor.interval seconds),
-- Lictor detections, deaths and staff actions.
-- When a report is sent (Tribune, player or bug) or a Lictor alert fires, keeps recording a
-- few more seconds, then freezes the minutes before and the seconds after into a case file
-- for the players involved (and the players around them, or everyone, per Lex) and stores
-- it with Tabularius.
-- Staff replay a case from the panel (Consul): avatars move on the viewer's screen only.
-- During a replay the server streams the map around what the viewer watches.
-- Case files are deleted after the number of days set in Lex.
--
-- Does not detect cheating (Lictor), decide sanctions (Praetor) or record the chat
-- (Tribune already attaches the filtered chat to its tickets).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local Appearance = require(script.Appearance)

local logger = Scriba.scoped("Quaesitor")

local MAX_CASES = 200 -- kept across all servers; the oldest go first
local MAX_SIZE = 3_800_000 -- characters of a saved case; a DataStore key holds 4 MB
local LICTOR_GAP = 60 -- seconds between two Lictor cases about the same player
local SWEEP = 3600 -- seconds between two checks for expired cases
local DAY = 86400
local GHOSTS_KEPT = 60 -- seconds the avatars of a replay wait for the viewer to copy them
local FOCUS_GAP = 0.5 -- seconds between two streaming requests of a viewer

-- Sample flags, added together.
local DEAD = 1
local SEATED = 2
local AIRBORNE = 4

-- Who else goes into a case, besides the players involved.
local OTHERS = { none = true, nearby = true, all = true }

-- One sample: { t, x, y, z, yaw (degrees), health, flags, tool, outfit }.
-- In memory t is os.clock(), tool the name of the tool in hand and outfit the names of the
-- accessories worn. In a case t is seconds since the start of the case, tool an index in
-- track.tools (0 for none) and outfit an index in track.outfits.
type Sample = { any }

type Frame = { t: number, players: { [number]: Sample } }

export type Event = {
	t: number,
	kind: string, -- "trigger" | "lictor" | "death" | "staff" | "left"
	userIds: { number }?, -- only in memory: who the event is about
	userId: number?, -- in a case: the recorded player it is about
	text: string,
}

-- role: "reporter" | "reported" | "suspect" for the players involved,
-- "nearby" | "other" for the players recorded with them.
export type Person = { userId: number, name: string, role: string }

export type Summary = {
	id: number,
	source: string, -- "report" | "lictor"
	ticketId: number?,
	label: string,
	players: { Person }, -- the players involved only
	others: number?, -- players recorded with them
	date: number, -- when the case was created
	startedAt: number, -- wall time of the first sample
	duration: number,
	triggerAt: number?, -- seconds from the start of the case to the report or alert
	interval: number?, -- seconds between two samples
	eventCount: number,
	expiresAt: number?, -- computed when listed, never stored
}

export type Track = Person & {
	samples: { Sample },
	look: Appearance.Look?,
	accessories: { string },
	tools: { string },
	outfits: { { number } },
}

export type Case = Summary & { tracks: { Track }, events: { Event } }

type Index = { next: number, cases: { Summary } }

local Quaesitor = {
	dependencies = { "Tabularius", "Lex" },
}

local keyStore: any
local Lex: any

local frames: { Frame } = {}
local events: { Event } = {}
local names: { [number]: string } = {}
-- Last known avatar of each player, kept a while after they leave.
local looks: { [number]: Appearance.Look } = {}
local lastLictorCase: { [number]: number } = {}

-- Cases waiting for the seconds after their trigger; saved at once if the server closes.
type Pending = { finish: () -> () }
local pending: { Pending } = {}

-- Replays in progress: avatars waiting to be copied, and the streaming focus.
type Viewer = { ghosts: Instance?, focus: BasePart?, lastFocus: number }
local viewers: { [Player]: Viewer } = {}
local focusFolder: Folder? = nil

local function round1(n: number): number
	return math.round(n * 10) / 10
end

-- Recording ----------------------------------------------------------------------------

local function sampleOf(player: Player, now: number): Sample?
	local character = player.Character
	local root = character and character.PrimaryPart
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
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
	local outfit, tool = Appearance.itemsOf(character)
	return {
		now,
		round1(p.X),
		round1(p.Y),
		round1(p.Z),
		math.round(math.deg(math.atan2(-look.X, -look.Z))),
		math.round(humanoid.Health),
		flags,
		tool,
		outfit,
	}
end

local function trim(now: number)
	-- A pending case still needs its window before the trigger.
	local from = now - Lex.get("quaesitor.window") - Lex.get("quaesitor.after")
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
		names[player.UserId] = player.Name
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

-- Keeps the avatar of a player; a failed read keeps the previous one.
local function rememberLook(player: Player)
	local ok, look = pcall(Appearance.lookOf, player)
	if ok and look and (look.description or not looks[player.UserId]) then
		looks[player.UserId] = look
	end
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

-- The players recorded with the involved ones: those who came within the Lex radius of
-- one of them, or everyone on the server.
local function othersOf(involved: { Person }, inRange: { Frame }): { Person }
	local mode = Lex.get("quaesitor.others")
	if not OTHERS[mode] then
		mode = "nearby"
	end
	if mode == "none" then
		return {}
	end
	local isInvolved = {}
	for _, person in involved do
		isInvolved[person.userId] = true
	end
	local radius = Lex.get("quaesitor.nearby_radius")
	local found: { [number]: boolean } = {}
	for _, frame in inRange do
		for userId, sample in frame.players do
			if isInvolved[userId] or found[userId] then
				continue
			end
			if mode == "all" then
				found[userId] = true
				continue
			end
			local position = Vector3.new(sample[2], sample[3], sample[4])
			for _, person in involved do
				local other = frame.players[person.userId]
				if other and (Vector3.new(other[2], other[3], other[4]) - position).Magnitude <= radius then
					found[userId] = true
					break
				end
			end
		end
	end
	local list = {}
	for userId in found do
		table.insert(list, {
			userId = userId,
			name = names[userId] or tostring(userId),
			role = if mode == "all" then "other" else "nearby",
		})
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Turns the samples of one player into a track: relative times, tools and outfits as indices.
local function trackOf(person: Person, inRange: { Frame }, start: number): Track
	local track: Track = {
		userId = person.userId,
		name = person.name,
		role = person.role,
		samples = {},
		accessories = {},
		tools = {},
		outfits = {},
	}
	local toolIndex: { [string]: number } = {}
	local accessoryIndex: { [string]: number } = {}
	local outfitIndex: { [string]: number } = {}
	for _, frame in inRange do
		local sample = frame.players[person.userId]
		if not sample then
			continue
		end
		local tool = 0
		if sample[8] ~= "" then
			tool = toolIndex[sample[8]]
			if not tool then
				table.insert(track.tools, sample[8])
				tool = #track.tools
				toolIndex[sample[8]] = tool
			end
		end
		local outfit = outfitIndex[sample[9]]
		if not outfit then
			local worn = {}
			if sample[9] ~= "" then
				for _, name in string.split(sample[9], "\n") do
					local i = accessoryIndex[name]
					if not i then
						table.insert(track.accessories, name)
						i = #track.accessories
						accessoryIndex[name] = i
					end
					table.insert(worn, i)
				end
			end
			table.insert(track.outfits, worn)
			outfit = #track.outfits
			outfitIndex[sample[9]] = outfit
		end
		table.insert(track.samples, {
			round1(sample[1] - start),
			sample[2],
			sample[3],
			sample[4],
			sample[5],
			sample[6],
			sample[7],
			tool,
			outfit,
		})
	end
	local player = Players:GetPlayerByUserId(person.userId)
	if player then
		rememberLook(player)
	end
	-- Kept after a player leaves: their avatar stays right in the replay.
	track.look = looks[person.userId]
	return track
end

-- Copies the record from the window before the trigger until now, with times relative to
-- its start. Returns the tracks, events, wall time of the start, duration and trigger time.
local function freeze(involved: { Person }, trigger: number, label: string): ({ Track }, { Event }, number, number, number)
	recordFrame()
	local now = os.clock()
	local from = trigger - Lex.get("quaesitor.window")
	local inRange: { Frame } = {}
	for _, frame in frames do
		if frame.t >= from then
			table.insert(inRange, frame)
		end
	end
	local start = if inRange[1] then inRange[1].t else now

	local recorded = table.clone(involved)
	for _, other in othersOf(involved, inRange) do
		table.insert(recorded, other)
	end

	local tracks: { Track } = {}
	local isRecorded: { [number]: boolean } = {}
	for _, person in recorded do
		table.insert(tracks, trackOf(person, inRange, start))
		isRecorded[person.userId] = true
	end

	local triggerAt = round1(math.max(trigger - start, 0))
	local caseEvents: { Event } = {}
	local triggerAdded = false
	for _, event in events do
		if event.t < start then
			continue
		end
		if not triggerAdded and event.t > trigger then
			table.insert(caseEvents, { t = triggerAt, kind = "trigger", text = label })
			triggerAdded = true
		end
		for _, userId in event.userIds or {} do
			if isRecorded[userId] then
				table.insert(caseEvents, {
					t = round1(event.t - start),
					kind = event.kind,
					userId = userId,
					text = event.text,
				})
				break
			end
		end
	end
	if not triggerAdded then
		table.insert(caseEvents, { t = triggerAt, kind = "trigger", text = label })
	end

	return tracks, caseEvents, os.time() - math.round(now - start), round1(now - start), triggerAt
end

-- Keeps one sample out of two until the case fits in a key: the players recorded with the
-- involved ones first, then everyone.
local function fit(case: any)
	local function thin(onlyOthers: boolean): boolean
		local changed = false
		for _, track in case.tracks do
			if onlyOthers and (track.role ~= "nearby" and track.role ~= "other") then
				continue
			end
			local samples = track.samples
			if #samples > 2 then
				local kept = {}
				for i, sample in samples do
					if i % 2 == 1 or i == #samples then
						table.insert(kept, sample)
					end
				end
				track.samples = kept
				changed = true
			end
		end
		return changed
	end
	for _ = 1, 12 do
		if #HttpService:JSONEncode(case) <= MAX_SIZE then
			return
		end
		if not thin(true) and not thin(false) then
			return
		end
		logger.info(`case "{case.label}" too large, fewer samples kept`)
	end
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
	fit(case)
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
	local trigger = os.clock()
	local date = os.time()
	local entry: Pending
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		local i = table.find(pending, entry)
		if i then
			table.remove(pending, i)
		end
		local tracks, caseEvents, startedAt, duration, triggerAt = freeze(involved, trigger, label)
		local base = {
			source = source,
			ticketId = ticketId,
			label = label,
			players = involved,
			others = #tracks - #involved,
			date = date,
			startedAt = startedAt,
			duration = duration,
			triggerAt = triggerAt,
			interval = Lex.get("quaesitor.interval"),
			eventCount = #caseEvents - 1, -- the trigger itself is not counted
		}
		save(base, tracks, caseEvents)
	end
	entry = { finish = finish }
	table.insert(pending, entry)
	-- Keep recording what follows the trigger before freezing the case.
	task.delay(Lex.get("quaesitor.after"), finish)
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

-- Replays -------------------------------------------------------------------------------

local function viewerOf(player: Player): Viewer
	local viewer = viewers[player]
	if not viewer then
		viewer = { lastFocus = 0 }
		viewers[player] = viewer
	end
	return viewer
end

local function dropGhosts(viewer: Viewer)
	if viewer.ghosts then
		viewer.ghosts:Destroy()
		viewer.ghosts = nil
	end
end

-- Builds the avatars of a case and hands them to the viewer alone (PlayerGui replicates
-- to its owner only); the client copies them into its own replay.
-- Returns (folder name, avatar count) or (nil, error_code).
function Quaesitor.ghosts(player: Player, id: number): (string?, number | string)
	local case, code = Quaesitor.get(id)
	if not case then
		return nil, code or "case_not_found"
	end
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil, "case_not_found"
	end
	local viewer = viewerOf(player)
	dropGhosts(viewer)
	local folder = Appearance.build(case)
	local count = #folder:GetChildren()
	folder.Name = `ImperiumQuaesitorGhosts{HttpService:GenerateGUID(false)}`
	folder.Parent = gui
	viewer.ghosts = folder
	task.delay(GHOSTS_KEPT, function()
		if viewer.ghosts == folder then
			dropGhosts(viewer)
		end
	end)
	return folder.Name, count
end

-- Streams the map around a point of the replay for its viewer, or back around their
-- character when position is nil.
function Quaesitor.focus(player: Player, position: Vector3?)
	local viewer = viewerOf(player)
	if not position then
		if viewer.focus then
			viewer.focus:Destroy()
			viewer.focus = nil
		end
		player.ReplicationFocus = nil
		return
	end
	if os.clock() - viewer.lastFocus < FOCUS_GAP then
		return
	end
	viewer.lastFocus = os.clock()
	if not focusFolder or not focusFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "ImperiumQuaesitorFocus"
		folder.Parent = workspace
		focusFolder = folder
	end
	local part = viewer.focus
	if not part then
		local created = Instance.new("Part")
		created.Name = player.Name
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.Transparency = 1
		created.Size = Vector3.one
		created.Parent = focusFolder
		viewer.focus = created
		part = created
	end
	(part :: BasePart).Position = position
	player.ReplicationFocus = part
	if workspace.StreamingEnabled then
		task.spawn(pcall, player.RequestStreamAroundAsync, player, position, 5)
	end
end

-- The viewer closed the replay.
function Quaesitor.endReplay(player: Player)
	local viewer = viewers[player]
	if not viewer then
		return
	end
	dropGhosts(viewer)
	Quaesitor.focus(player, nil)
	viewers[player] = nil
end

-- Lifecycle -----------------------------------------------------------------------------

function Quaesitor.init(deps)
	keyStore = deps.Tabularius.keyStore("Quaesitor")
	Lex = deps.Lex

	Lex.define("quaesitor.enabled", {
		default = true,
		type = "boolean",
		description = "Records the last minutes and creates case files on reports and Lictor alerts.",
	})
	Lex.define("quaesitor.interval", {
		default = 0.5,
		type = "number",
		description = "Seconds between two recorded positions. Lower is smoother but makes bigger case files.",
		min = 0.1,
		max = 2,
	})
	Lex.define("quaesitor.window", {
		default = 180,
		type = "number",
		description = "Seconds recorded before the report or alert in a case file.",
		min = 30,
		max = 600,
	})
	Lex.define("quaesitor.after", {
		default = 30,
		type = "number",
		description = "Seconds still recorded after the report or alert before the case file is saved.",
		min = 0,
		max = 120,
	})
	Lex.define("quaesitor.others", {
		default = "nearby",
		type = "string",
		description = 'Other players recorded in a case file: "nearby" (within quaesitor.nearby_radius of a player involved), "all" or "none".',
	})
	Lex.define("quaesitor.nearby_radius", {
		default = 100,
		type = "number",
		description = "Studs around a player involved within which other players are recorded.",
		min = 10,
		max = 5000,
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
	-- Player reports: one case for the reporter and the reported players.
	-- Bug reports: one case for the reporter, to see where and how the bug happened.
	Signum.on("tribune.ticket", function(ticket: any, created: boolean?)
		if created ~= true then
			return
		end
		local reporter = { userId = ticket.reporterId, name = ticket.reporterName, role = "reporter" }
		if ticket.kind == "player" and ticket.targetId then
			-- Every reported player (older tickets only have targetId).
			local involved = { reporter }
			for _, target in ticket.targets or { { userId = ticket.targetId, name = ticket.targetName } } do
				table.insert(involved, { userId = target.userId, name = target.name, role = "reported" })
			end
			createCase("report", ticket.id, `Report #{ticket.id} · {ticket.categoryLabel}`, involved)
		elseif ticket.kind == "bug" then
			createCase("report", ticket.id, `Bug #{ticket.id} · {ticket.categoryLabel}`, { reporter })
		end
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

	local function watchPlayer(player: Player)
		watchDeaths(player)
		player.CharacterAppearanceLoaded:Connect(function()
			rememberLook(player)
		end)
		if player.Character then
			task.spawn(rememberLook, player)
		end
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		-- The character still exists here: last chance to read the avatar.
		rememberLook(player)
		local userId = player.UserId
		task.delay(Lex.get("quaesitor.window") + Lex.get("quaesitor.after") + 60, function()
			if not Players:GetPlayerByUserId(userId) then
				looks[userId] = nil
			end
		end)
		addEvent("left", { player.UserId }, `{player.Name} left the server`)
		lastLictorCase[player.UserId] = nil
		Quaesitor.endReplay(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Lex.get("quaesitor.interval"))
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

	-- Closing server: save the pending cases with what was recorded so far.
	game:BindToClose(function()
		for _, entry in table.clone(pending) do
			local ok, err = pcall(entry.finish)
			if not ok then
				logger.err("could not save a pending case:", err)
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
