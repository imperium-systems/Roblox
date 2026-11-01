--!strict
-- Praefectus: operations on running servers.
-- Maintenance announcements, access locking, restart with a countdown,
-- on this server or on all of them.
-- Does not create servers or place players (Hospes, Lanista).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local logger = Scriba.scoped("Praefectus")

local TOPIC = "Imperium_Praefectus"
-- The last seconds are covered by the permanent Praeco reminder.
local THRESHOLDS = { 300, 120, 60, 30, 15, 10 }

local Praefectus = {
	dependencies = { "Senatus", "Praeco", "Lex" },
}

local Senatus: any
local Praeco: any
local Lex: any

local locked = false
local startedAt = os.time()
local countdown: { expiresAt: number, reason: string, token: {} }? = nil

local function notifyChanged()
	Signum.emit("praefectus.state", Praefectus.state())
end

-- API ---------------------------------------------------------------------------

function Praefectus.state()
	return {
		locked = locked,
		players = #Players:GetPlayers(),
		max = Players.MaxPlayers,
		jobId = if game.JobId == "" then "studio" else game.JobId,
		version = game.PlaceVersion,
		startedAt = startedAt,
		restart = countdown and { expiresAt = countdown.expiresAt, reason = countdown.reason },
	}
end

function Praefectus.lock(state: boolean)
	locked = state
	logger.info(if state then "server locked" else "server unlocked")
	notifyChanged()
end

function Praefectus.isLocked(): boolean
	return locked
end

-- Starts a countdown, then empties the server. The server closes once empty.
function Praefectus.restart(delaySeconds: number, reason: string): (boolean, string?)
	if countdown then
		return false, "already_running"
	end
	local token = {}
	countdown = { expiresAt = os.time() + delaySeconds, reason = reason, token = token }
	Praeco.reminder({ text = "Server restarting in", expiresAt = countdown.expiresAt })
	notifyChanged()

	local function running()
		return countdown ~= nil and countdown.token == token
	end

	task.spawn(function()
		local announced: { [number]: boolean } = {}
		local first = true
		while running() do
			local remaining = (countdown :: any).expiresAt - os.time()
			if remaining <= 0 then
				break
			end
			-- Announces at the start, then at each threshold crossed.
			local crossed = false
			for _, threshold in THRESHOLDS do
				if remaining <= threshold and not announced[threshold] then
					announced[threshold] = true
					crossed = true
				end
			end
			if first or crossed then
				first = false
				Praeco.announce({
					kind = "maintenance",
					title = "Server restart",
					text = `{reason} in {Core.formatCountdown(remaining)}`,
					duration = math.min(8, remaining),
				})
			end
			task.wait(1)
		end
		if not running() then
			return
		end
		locked = true
		for _, player in Players:GetPlayers() do
			player:Kick(`The server is restarting: {reason}\nReconnect in a moment.`)
		end
	end)
	return true
end

function Praefectus.cancelRestart(): boolean
	if not countdown then
		return false
	end
	countdown = nil
	Praeco.removeReminder()
	Praeco.announce({ kind = "success", title = "Restart cancelled", text = "The server stays online.", duration = 6 })
	notifyChanged()
	return true
end

-- Sends an order to every server, including this one.
function Praefectus.broadcastOrder(order: string, data: { [string]: any }): (boolean, string?)
	local message = table.clone(data)
	message.order = order
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, message)
	if not ok then
		logger.warning("cross-server order failed:", err)
		return false, "cross_server"
	end
	return true
end

local function executeOrder(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.order == "restart" and type(message.delaySeconds) == "number" and type(message.reason) == "string" then
		Praefectus.restart(math.clamp(message.delaySeconds, 5, 600), message.reason)
	elseif message.order == "cancel" then
		Praefectus.cancelRestart()
	elseif message.order == "lock" and type(message.state) == "boolean" then
		Praefectus.lock(message.state)
	end
end

-- Lifecycle --------------------------------------------------------------------

function Praefectus.init(deps)
	Senatus = deps.Senatus
	Praeco = deps.Praeco
	Lex = deps.Lex

	Lex.define("praefectus.restart_delay", {
		default = 60,
		type = "number",
		description = "Default delay offered before a restart, in seconds.",
		min = 5,
		max = 600,
	})
	Lex.define("praefectus.locked_message", {
		default = "This server is under maintenance. Try again in a few minutes.",
		type = "string",
		description = "Message shown to players refused while the server is locked.",
	})
end

function Praefectus.start()
	-- Senatus computes the rank on arrival; wait for its verdict.
	Signum.on("senatus.rank", function(player: Player)
		if locked and not Senatus.isStaff(player) then
			player:Kick(Lex.get("praefectus.locked_message"))
		end
	end)
	Players.PlayerAdded:Connect(notifyChanged)
	Players.PlayerRemoving:Connect(function()
		task.defer(notifyChanged)
	end)

	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		executeOrder(message.Data)
	end)
	if not ok then
		logger.warning("cross-server subscription failed:", err)
	end
end

return Praefectus
