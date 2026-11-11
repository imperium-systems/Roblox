--!strict
-- Lictor: anticheat.
-- Detects impossible behavior on the server (speed, teleport, flight, network abuse),
-- keeps a suspicion score per player that decays over time, puts the character back
-- in place, and hands over to Praetor above a threshold.
-- Does not ban by itself and does not moderate chat.
--
-- Other systems report what they see with Lictor.report (Pugna for damage, fire rate…)
-- and declare legitimate moves with Lictor.exempt (teleports, cutscenes…).
-- A game script can also set the attribute ImperiumLictorExempt on a player or character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local logger = Scriba.scoped("Lictor")

local SAMPLE = 0.25 -- seconds between two position samples
local SLACK = 4 -- studs allowed on top of the computed limit (latency, physics)
local TELEPORT_DISTANCE = 40 -- studs in one sample beyond the limit: a teleport
local MAX_DETECTIONS = 20 -- kept per player
local MAX_RECENT = 50 -- kept for the whole server
local NETWORK_COOLDOWN = 5 -- seconds between two network reports for the same remote
local EXEMPT_ATTRIBUTE = "ImperiumLictorExempt"

local WEIGHTS = {
	speed = 1,
	teleport = 3,
	flight = 2,
	network = 0.5,
}

local LABELS = {
	speed = "Abnormal speed",
	teleport = "Teleport",
	flight = "Flight",
	network = "Request flood",
}

export type Detection = {
	userId: number,
	name: string,
	kind: string,
	label: string,
	details: string,
	date: number,
	score: number,
}

type Tracker = {
	score: number,
	scoreTime: number,
	alerted: boolean,
	detections: { Detection },
	exemptUntil: number,
	lastPosition: Vector3?,
	lastValid: CFrame?,
	airTime: number,
	speedStrikes: number,
	networkTimes: { [string]: number },
}

local Lictor = {
	dependencies = { "Lex", "Praetor" },
}

local Lex: any
local Praetor: any

local trackers: { [Player]: Tracker } = {}
local recent: { Detection } = {}

local function tracker(player: Player): Tracker
	local t = trackers[player]
	if not t then
		t = {
			score = 0,
			scoreTime = os.clock(),
			alerted = false,
			detections = {},
			exemptUntil = 0,
			airTime = 0,
			speedStrikes = 0,
			networkTimes = {},
		}
		trackers[player] = t
	end
	return t
end

-- Brings the score up to date with its decay.
local function decay(t: Tracker): number
	local now = os.clock()
	local perMinute = Lex.get("lictor.decay_per_minute")
	t.score = math.max(0, t.score - perMinute * (now - t.scoreTime) / 60)
	t.scoreTime = now
	if t.score < Lex.get("lictor.alert_threshold") / 2 then
		t.alerted = false
	end
	return t.score
end

local function resetMovement(t: Tracker)
	t.lastPosition = nil
	t.lastValid = nil
	t.airTime = 0
	t.speedStrikes = 0
end

local function isExempt(player: Player, t: Tracker): boolean
	if os.clock() < t.exemptUntil then
		return true
	end
	local character = player.Character
	return player:GetAttribute(EXEMPT_ATTRIBUTE) == true
		or (character ~= nil and character:GetAttribute(EXEMPT_ATTRIBUTE) == true)
end

-- API ---------------------------------------------------------------------------

-- Records a suspicious behavior. weight is optional (default per kind, else 1).
function Lictor.report(player: Player, kind: string, details: string, weight: number?)
	if not Lex.get("lictor.enabled") or not player.Parent then
		return
	end
	local t = tracker(player)
	decay(t)
	t.score += weight or (WEIGHTS :: any)[kind] or 1

	local detection: Detection = {
		userId = player.UserId,
		name = player.Name,
		kind = kind,
		label = (LABELS :: any)[kind] or kind,
		details = details,
		date = os.time(),
		score = math.round(t.score * 10) / 10,
	}
	table.insert(t.detections, 1, detection)
	if #t.detections > MAX_DETECTIONS then
		table.remove(t.detections)
	end
	table.insert(recent, 1, detection)
	if #recent > MAX_RECENT then
		table.remove(recent)
	end
	Signum.emit("lictor.detection", detection)

	if not t.alerted and t.score >= Lex.get("lictor.alert_threshold") then
		t.alerted = true
		logger.warning(`{player.Name}: {detection.label} ({details}), score {detection.score}`)
		Signum.emit("lictor.alert", detection)
	end

	-- Above a threshold, the decision goes to Praetor.
	local banThreshold = Lex.get("lictor.ban_threshold")
	local kickThreshold = Lex.get("lictor.kick_threshold")
	local reason = `Lictor: {string.lower(detection.label)} detected`
	if banThreshold > 0 and t.score >= banThreshold then
		local ok, duration = Core.parseDuration(Lex.get("lictor.ban_duration"))
		Praetor.ban(nil, player.UserId, if ok then duration else 86400, reason)
		t.score = 0
	elseif kickThreshold > 0 and t.score >= kickThreshold then
		Praetor.kick(nil, player.UserId, reason)
		t.score = 0
	end
end

-- Lets a player move freely for a few seconds (legitimate teleport, cutscene…).
function Lictor.exempt(player: Player, seconds: number)
	local t = tracker(player)
	t.exemptUntil = math.max(t.exemptUntil, os.clock() + seconds)
	resetMovement(t)
end

-- Clears the score and history of an online player.
function Lictor.clear(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	if not player or not trackers[player] then
		return false
	end
	local t = trackers[player]
	t.score = 0
	t.alerted = false
	table.clear(t.detections)
	return true
end

-- Online players with a score or a detection, most suspicious first.
function Lictor.suspects(): { { [string]: any } }
	local list = {}
	for player, t in trackers do
		local score = decay(t)
		if score > 0 or #t.detections > 0 then
			local last = t.detections[1]
			table.insert(list, {
				userId = player.UserId,
				name = player.Name,
				displayName = player.DisplayName,
				score = math.round(score * 10) / 10,
				count = #t.detections,
				lastLabel = last and last.label,
				lastDate = last and last.date,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	return list
end

-- Current score of an online player (0 when nothing was detected).
function Lictor.scoreOf(player: Player): number
	local t = trackers[player]
	return if t then math.round(decay(t) * 10) / 10 else 0
end

function Lictor.recent(limit: number?): { Detection }
	local list = {}
	for i = 1, math.min(limit or MAX_RECENT, #recent) do
		table.insert(list, recent[i])
	end
	return list
end

function Lictor.thresholds(): { [string]: number }
	return {
		alert = Lex.get("lictor.alert_threshold"),
		kick = Lex.get("lictor.kick_threshold"),
		ban = Lex.get("lictor.ban_threshold"),
	}
end

-- Movement checks ------------------------------------------------------------------

local function putBack(character: Model, t: Tracker)
	if Lex.get("lictor.correct_position") and t.lastValid then
		character:PivotTo(t.lastValid)
		local root = character.PrimaryPart
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		t.lastPosition = t.lastValid.Position
	end
end

local function check(player: Player, t: Tracker, dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character.PrimaryPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		resetMovement(t)
		return
	end
	if isExempt(player, t) or humanoid.SeatPart ~= nil or root.Anchored then
		resetMovement(t)
		return
	end

	local position = root.Position
	local previous = t.lastPosition
	t.lastPosition = position
	if not previous then
		t.lastValid = root.CFrame
		return
	end

	local delta = position - previous
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local allowed = math.max(humanoid.WalkSpeed, 16) * Lex.get("lictor.speed_tolerance") * dt + SLACK
	local suspicious = false

	-- Teleport and speed: only what the character covers horizontally, or by going up.
	local travelled = Vector3.new(delta.X, math.max(delta.Y, 0), delta.Z).Magnitude
	if travelled > allowed + TELEPORT_DISTANCE then
		suspicious = true
		Lictor.report(player, "teleport", `{math.round(travelled)} studs in {math.round(dt * 100) / 100} s`)
	elseif horizontal > allowed then
		t.speedStrikes += 1
		-- Two samples in a row, so a single lag spike is not enough.
		if t.speedStrikes >= 2 then
			suspicious = true
			local speed = math.round(horizontal / dt)
			local max = math.round((allowed - SLACK) / dt)
			Lictor.report(player, "speed", `{speed} studs/s (max {max})`)
		end
	else
		t.speedStrikes = 0
	end

	-- Flight: time in the air without falling.
	local state = humanoid:GetState()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Climbing
	if grounded then
		t.airTime = 0
	elseif root.AssemblyLinearVelocity.Y > -10 then
		t.airTime += dt
		if t.airTime > Lex.get("lictor.max_air_time") then
			suspicious = true
			Lictor.report(player, "flight", `{math.round(t.airTime * 10) / 10} s in the air`)
			t.airTime = 0
		end
	end

	if suspicious then
		putBack(character, t)
	elseif grounded then
		t.lastValid = root.CFrame
	end
end

-- Lifecycle ---------------------------------------------------------------------

function Lictor.init(deps)
	Lex = deps.Lex
	Praetor = deps.Praetor

	Lex.define("lictor.enabled", {
		default = true,
		type = "boolean",
		description = "Turns all Lictor checks on or off.",
	})
	Lex.define("lictor.correct_position", {
		default = true,
		type = "boolean",
		description = "Puts a character back at its last valid position after a suspicious move.",
	})
	Lex.define("lictor.speed_tolerance", {
		default = 1.5,
		type = "number",
		description = "Multiplier applied to the walk speed before a move counts as too fast.",
		min = 1,
		max = 5,
	})
	Lex.define("lictor.max_air_time", {
		default = 3,
		type = "number",
		description = "Seconds a character can stay in the air without falling.",
		min = 1,
		max = 60,
	})
	Lex.define("lictor.decay_per_minute", {
		default = 6,
		type = "number",
		description = "Suspicion points removed per minute.",
		min = 0,
		max = 100,
	})
	Lex.define("lictor.alert_threshold", {
		default = 5,
		type = "number",
		description = "Score at which staff receive an alert.",
		min = 1,
		max = 1000,
	})
	Lex.define("lictor.kick_threshold", {
		default = 15,
		type = "number",
		description = "Score at which Praetor kicks the player (0 to disable).",
		min = 0,
		max = 1000,
	})
	Lex.define("lictor.ban_threshold", {
		default = 0,
		type = "number",
		description = "Score at which Praetor bans the player (0 to disable).",
		min = 0,
		max = 1000,
	})
	Lex.define("lictor.ban_duration", {
		default = "1d",
		type = "string",
		description = "Duration of an automatic ban (e.g. 1d, 7d, perm).",
	})
end

function Lictor.start()
	Players.PlayerAdded:Connect(function(player)
		local t = tracker(player)
		player.CharacterAdded:Connect(function()
			resetMovement(t)
		end)
	end)
	for _, player in Players:GetPlayers() do
		local t = tracker(player)
		player.CharacterAdded:Connect(function()
			resetMovement(t)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		trackers[player] = nil
	end)

	-- Veredarius signals players who flood a remote.
	Signum.on("veredarius.abuse", function(player: Player, name: string)
		local t = tracker(player)
		local now = os.clock()
		if now - (t.networkTimes[name] or 0) >= NETWORK_COOLDOWN then
			t.networkTimes[name] = now
			Lictor.report(player, "network", `rate limit hit on "{name}"`)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(SAMPLE)
			local now = os.clock()
			local dt = now - last
			last = now
			if Lex.get("lictor.enabled") then
				for player, t in trackers do
					local ok, err = pcall(check, player, t, dt)
					if not ok then
						logger.err(`check failed for {player.Name}:`, err)
					end
				end
			end
		end
	end)
end

return Lictor
