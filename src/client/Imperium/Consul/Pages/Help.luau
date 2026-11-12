--!strict
-- Help page: what each page does and where to find it.
-- Only shows what the viewer's rank allows.

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)
local Catalog = require(Consul.Catalog)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local SECTIONS = {
	{
		page = "Players",
		title = "Players",
		path = "Curia > Praetor",
		permission = "consul.open",
		summary = "List of the players on the server, with a record for each one.",
		commands = {
			{ "censor.view", "Search offline", "Finds the record of an absent player, by username or UserId." },
			{ "praetor.warn", "Warn", "Warns the player and adds the warning to their record." },
			{ "praetor.mute", "Mute / Unmute", "Removes or restores the ability to chat." },
			{ "praetor.kick", "Kick", "Removes the player from the server. They can come back." },
			{ "praetor.ban", "Ban", "Blocks access to the game for a duration or permanently." },
			{ "praetor.unban", "Unban", "Lifts an active ban." },
			{ "consul.teleport", "Go to / Bring", "Teleports you to the player, or brings them to you." },
		},
	},
	{
		page = "Tribune",
		title = "Reports",
		path = "Forum > Tribune",
		permission = "tribune.handle",
		summary = "Reports sent by players with the Report button or /report, about a player or a bug. Each one comes with the context of the moment: server, positions, Lictor score, past warnings, and the chat of both players from the last 5 minutes. You get a notice for every new report. Open a report to see the record and log of both players side by side.",
		commands = {
			{ "tribune.handle", "Claim / Release", "Takes a report so nobody else handles it at the same time, or gives it back." },
			{ "tribune.handle", "Close / Dismiss", "Closes the report with an optional comment, kept in the ticket and sent to the webhook. The reporter is told, without your name, the sanction or the comment." },
			{ "consul.teleport", "Teleport", "From an open report: go to either player, bring one or both, or send them to the staff point (a part named ImperiumStaffPoint)." },
			{ "tribune.manage", "Override", "Closes or releases a report claimed by someone else." },
		},
	},
	{
		page = "Lictor",
		title = "Anticheat",
		path = "Curia > Lictor",
		permission = "lictor.view",
		summary = "Players whose movements look impossible, with a suspicion score that drops over time. Above the alert threshold, staff get a notice; above the kick threshold, Praetor kicks the player.",
		commands = {
			{ "lictor.clear", "Clear", "Resets the score and history of a player, after a false alarm." },
		},
	},
	{
		page = "Quaesitor",
		title = "Case files",
		path = "Curia > Quaesitor",
		permission = "quaesitor.view",
		summary = "The server keeps the last minutes of every character's position, Lictor detections, deaths and staff actions. A report (player or bug) or a Lictor alert freezes them into a case file for the players involved, with the minutes before and a few seconds after (quaesitor.after), linked from the report and the Anticheat page. Case files are deleted after the number of days in Settings (quaesitor.retention_days).",
		commands = {
			{ "quaesitor.view", "Replay", "Hides the panel and plays the case: the players appear as ghosts in the world, on your screen only. Pause, scrub the timeline, change the speed and follow any of them with the camera." },
		},
	},
	{
		page = "Server",
		title = "Server",
		path = "Curia > Praefectus",
		permission = "consul.open",
		summary = "Server state: players, uptime, version.",
		commands = {
			{ "praefectus.announce", "Announcement", "Shows a banner to all players." },
			{ "praefectus.lock", "Lock", "Refuses new players who are not staff." },
			{ "praefectus.restart", "Restart", "Starts a countdown, then empties the server." },
		},
	},
	{
		page = "Log",
		title = "Log",
		path = "Curia > Censor",
		permission = "censor.log",
		summary = "History of staff actions. A click opens the record of the targeted player.",
		commands = {},
	},
	{
		page = "Settings",
		title = "Settings",
		path = "Core > Lex",
		permission = "lex.edit",
		summary = "Game settings, editable live on this server until it closes.",
		commands = {},
	},
}

local STATUSES = {
	{ "Available", "the system has a page in this panel." },
	{ "Active", "the system runs in the background, without a page." },
	{ "Coming soon", "the system has not been built yet." },
}

return function(ctx: any, frame: Frame)
	local scroller = Components.scroller({ Parent = frame }, 10)
	local order = 0

	local function card(title: string): Frame
		order += 1
		local c = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 6) })
		Components.section(title, 0).Parent = c
		return c
	end

	local function row(parent: Instance, rowOrder: number, bold: string, text: string)
		Components.paragraph(`<b>{bold}</b>: {text}`, {
			RichText = true,
			TextSize = Theme.sizes.small + 1,
			LayoutOrder = rowOrder,
			Parent = parent,
		})
	end

	-- Welcome
	local welcome = card(`Your rank: {ctx.access.rank}`)
	Components.paragraph(
		"This help only shows what your rank allows. F2 opens and closes the panel. At the top right, choose your view: the simple view goes straight to the tasks, the Families view shows every Imperium system.",
		{ TextColor3 = C.textMuted, TextSize = Theme.sizes.small + 1, LayoutOrder = 1, Parent = welcome }
	)

	-- What the viewer has access to
	for _, section in SECTIONS do
		if not ctx.can(section.permission) then
			continue
		end
		local c = card(section.title)
		Components.paragraph(section.summary, {
			TextColor3 = C.textMuted,
			TextSize = Theme.sizes.small + 1,
			LayoutOrder = 1,
			Parent = c,
		})
		local n = 1
		for _, command in section.commands do
			if ctx.can(command[1]) then
				n += 1
				row(c, n, command[2], command[3])
			end
		end
		Components.paragraph(`In the Families view: {section.path}`, {
			TextColor3 = C.textFaint,
			TextSize = Theme.sizes.small,
			LayoutOrder = n + 1,
			Parent = c,
		})
		Components.button(`Open {section.title}`, "secondary", function()
			ctx.open(section.page)
		end, { LayoutOrder = n + 2, TextSize = Theme.sizes.small + 1, Parent = c })
	end

	-- Rules shared by all sanctions
	if ctx.can("praetor.mute") or ctx.can("praetor.ban") then
		local c = card("Sanctions")
		row(c, 1, "Durations", "30s, 10m, 2h, 7d, or perm for permanent.")
		row(c, 2, "Hierarchy", "you can only act on a rank below yours.")
		row(c, 3, "Reason", "it is shown to the player and goes through the Roblox filter.")
	end

	-- Statuses and families
	local legend = card("System statuses")
	for i, status in STATUSES do
		row(legend, i, status[1], status[2])
	end

	local families = card("The families")
	for i, family in Catalog do
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = i,
			Parent = families,
		})
		local insignia = Components.insignia(family.name, 24, family.color)
		if insignia then
			insignia.Parent = rowFrame
		else
			create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(3, 16),
				BackgroundColor3 = family.color,
				BorderSizePixel = 0,
				Parent = rowFrame,
			})
		end
		Components.text({
			Text = string.upper(family.name),
			FontFace = P.medium,
			TextSize = Theme.sizes.small + 1,
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(0, 90, 1, 0),
			Parent = rowFrame,
		})
		Components.text({
			Text = family.theme,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			Position = UDim2.fromOffset(126, 0),
			Size = UDim2.new(1, -126, 1, 0),
			Parent = rowFrame,
		})
	end

	return {
		show = function() end,
		update = function() end,
	}
end
