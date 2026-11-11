--!strict
-- Nuntius: outside notifications.
-- Sends messages to webhooks (Discord or any other service) through named channels,
-- configured in Config > Nuntius. Each channel has its own queue: messages leave one
-- by one, and a refusal for too many requests waits and retries.
-- Does not decide what to send: the calling system builds the message.
-- Text must already be filtered by the caller.

local HttpService = game:GetService("HttpService")

local Scriba = require(game:GetService("ReplicatedStorage").ImperiumShared.Imperium.Scriba)

local logger = Scriba.scoped("Nuntius")

local SPACING = 2 -- seconds between two messages of one channel
local RETRIES = 3

export type Field = { name: string, value: string, inline: boolean? }

export type Message = {
	title: string,
	description: string?,
	color: Color3?,
	fields: { Field }?,
	footer: string?,
}

type Channel = {
	target: any?, -- URL string or Roblox Secret
	queue: { Message },
	running: boolean,
}

local Nuntius = {}

local format = "discord"
local channels: { [string]: Channel } = {}

local function cut(text: string, limit: number): string
	if utf8.len(text) and (utf8.len(text) :: number) > limit then
		local stop = utf8.offset(text, limit) or (#text + 1)
		return string.sub(text, 1, stop - 1) .. "…"
	end
	return text
end

local function hex(color: Color3?): number?
	if not color then
		return nil
	end
	return tonumber(color:ToHex(), 16)
end

-- Discord limits: title 256, description 4096, field value 1024, 25 fields.
local function body(message: Message): string
	if format == "json" then
		return HttpService:JSONEncode({
			source = "Imperium",
			title = message.title,
			description = message.description,
			fields = message.fields,
			footer = message.footer,
			date = os.time(),
		})
	end
	local fields = {}
	for i, field in message.fields or {} do
		if i > 25 then
			break
		end
		table.insert(fields, {
			name = cut(field.name, 256),
			value = cut(if field.value == "" then "-" else field.value, 1024),
			inline = field.inline == true,
		})
	end
	return HttpService:JSONEncode({
		username = "Imperium",
		-- Player text must never ping anyone (@everyone, roles).
		allowed_mentions = { parse = {} },
		embeds = {
			{
				title = cut(message.title, 256),
				description = if message.description then cut(message.description, 4000) else nil,
				color = hex(message.color),
				fields = fields,
				footer = if message.footer then { text = cut(message.footer, 2048) } else nil,
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	})
end

-- Sends one message. Returns the number of seconds to wait before retrying, or nil.
local function post(channel: Channel, message: Message): (boolean, number?)
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = channel.target,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = body(message),
	})
	if not ok then
		logger.warning("webhook unreachable:", response)
		return false, nil
	end
	if response.StatusCode == 429 then
		local retry = tonumber(response.Headers["retry-after"]) or 5
		return false, math.clamp(retry, 1, 60)
	end
	if not response.Success then
		logger.warning(`webhook refused the message ({response.StatusCode}):`, cut(response.Body or "", 200))
		return false, nil
	end
	return true, nil
end

local function drain(channel: Channel)
	if channel.running then
		return
	end
	channel.running = true
	while #channel.queue > 0 do
		local message = table.remove(channel.queue, 1) :: Message
		for _ = 1, RETRIES do
			local sent, wait = post(channel, message)
			if sent or not wait then
				break
			end
			task.wait(wait)
		end
		task.wait(SPACING)
	end
	channel.running = false
end

-- Queues a message on a channel. Does nothing when the channel is off.
function Nuntius.send(name: string, message: Message)
	local channel = channels[name]
	if not channel or not channel.target then
		return
	end
	table.insert(channel.queue, message)
	task.spawn(drain, channel)
end

-- Channels that will really send something, for the panel.
function Nuntius.channels(): { [string]: boolean }
	local list = {}
	for name, channel in channels do
		list[name] = channel.target ~= nil
	end
	return list
end

function Nuntius.init()
	local config = require(script.Parent.Parent.Config.Nuntius) :: any
	format = if config.format == "json" then "json" else "discord"

	local active = 0
	for name, entry in config.channels or {} do
		local target: any = nil
		if type(entry.secret) == "string" and entry.secret ~= "" then
			local ok, secret = pcall(HttpService.GetSecret, HttpService, entry.secret)
			if ok then
				target = secret
			else
				logger.warning(`secret "{entry.secret}" for channel {name} is unavailable:`, secret)
			end
		end
		if not target and type(entry.url) == "string" and entry.url ~= "" then
			target = entry.url
		end
		channels[name] = { target = target, queue = {}, running = false }
		if target then
			active += 1
		end
	end

	if active > 0 and not HttpService.HttpEnabled then
		logger.warning("webhooks are configured but HTTP requests are off: Game Settings > Security > Allow HTTP Requests.")
	end
end

return Nuntius
