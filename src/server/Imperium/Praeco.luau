--!strict
-- Praeco: official in-game announcements.
-- Banners for all players (this server or all servers) and individual notices.
-- Does not send out-of-game notifications (Nuntius).
-- Received text must already be filtered by the caller.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Scriba = require(Imperium.Scriba)
local Veredarius = require(Imperium.Veredarius)

local logger = Scriba.scoped("Praeco")

local CHANNEL = "praeco"
local REMINDER_CHANNEL = "praeco.reminder"
local TOPIC = "Imperium_Praeco"

export type Kind = "info" | "warning" | "maintenance" | "success"

export type Annonce = {
	text: string,
	kind: Kind,
	duration: number?,
	title: string?,
}

-- Permanent message with a timer, shown until it is removed.
export type Reminder = {
	text: string,
	expiresAt: number,
}

local Praeco = {}

local activeReminder: Reminder? = nil

function Praeco.reminder(reminder: Reminder)
	activeReminder = reminder
	Veredarius.sendToAll(REMINDER_CHANNEL, reminder)
end

function Praeco.removeReminder()
	activeReminder = nil
	Veredarius.sendToAll(REMINDER_CHANNEL, nil)
end

function Praeco.announce(announcement: Annonce)
	Veredarius.sendToAll(CHANNEL, announcement)
end

-- Broadcasts to every server of the game, including this one.
function Praeco.announceEverywhere(announcement: Annonce)
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, announcement)
	if not ok then
		logger.warning("cross-server broadcast failed, announcing locally only:", err)
		Praeco.announce(announcement)
	end
end

function Praeco.notify(player: Player, announcement: Annonce)
	Veredarius.send(CHANNEL, player, announcement)
end

function Praeco.init()
	Veredarius.declare(CHANNEL)
	Veredarius.declare(REMINDER_CHANNEL)
end

function Praeco.start()
	-- A player joining during a countdown must see it too.
	Players.PlayerAdded:Connect(function(player)
		if activeReminder then
			Veredarius.send(REMINDER_CHANNEL, player, activeReminder)
		end
	end)

	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		Praeco.announce(message.Data)
	end)
	if not ok then
		logger.warning("cross-server subscription failed:", err)
	end
end

return Praeco
