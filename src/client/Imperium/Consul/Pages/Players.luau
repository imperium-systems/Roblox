--!strict
-- Players page: server list, offline search, player record, sanctions and teleport.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local SANCTION_LABELS: { [string]: string } = {
	warning = "Warning",
	mute = "Mute",
	kick = "Kick",
	ban = "Ban",
	unban = "Unban",
}

local function avatar(userId: number, size: number): ImageLabel
	return create("ImageLabel", {
		Image = if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else "",
		BackgroundColor3 = C.field,
		Size = UDim2.new(0, size, 0, size),
	}, { Components.corners(UDim.new(1, 0)) })
end

return function(ctx: any, frame: Frame)
	local players: { any } = {}
	local selection: number? = nil
	local filter = ""

	-- Left column: search + list -------------------------------------------------

	local left = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.36, -8, 1, 0),
		Parent = frame,
	})
	local search = Components.field("Filter or search a username…", { Parent = left })
	local listOffset = 42
	if ctx.can("censor.view") then
		listOffset = 84
	end
	local list = Components.scroller({
		Position = UDim2.new(0, 0, 0, listOffset),
		Size = UDim2.new(1, 0, 1, -listOffset),
		Parent = left,
	}, 4)

	-- Right column: player record ---------------------------------------------------------------

	local right = Components.scroller({
		Position = UDim2.new(0.36, 8, 0, 0),
		Size = UDim2.new(0.64, -8, 1, 0),
		Parent = frame,
	}, 10)

	local function showEmpty(message: string)
		Components.clear(right)
		Components.paragraph(message, {
			TextColor3 = C.textFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = right,
		})
	end

	local displayRecord: (any) -> ()
	local loadRecord: (number) -> ()

	-- List ----------------------------------------------------------------------------------

	local function drawList()
		Components.clear(list)
		local query = string.lower(filter)
		local n = 0
		for _, j in players do
			if
				query ~= ""
				and not string.find(string.lower(j.name), query, 1, true)
				and not string.find(string.lower(j.displayName), query, 1, true)
			then
				continue
			end
			n += 1
			local selected = j.userId == selection
			local row = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if selected then C.cardHover else C.card,
				Size = UDim2.new(1, 0, 0, 52),
				LayoutOrder = n,
				Parent = list,
			}, {
				Components.corners(Theme.radiusSmall),
				Components.padding(8),
			})
			if selected then
				Components.stroke(C.accentHover).Parent = row
			end
			local image = avatar(j.userId, 36)
			image.Position = UDim2.new(0, 0, 0.5, -18)
			image.Parent = row
			Components.text({
				Text = j.displayName,
				FontFace = P.medium,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.new(0, 46, 0, 0),
				Size = UDim2.new(1, -46, 0, 18),
				Parent = row,
			})
			local subtitle = `@{j.name}`
			if j.muted then
				subtitle ..= "  ·  muted"
			end
			Components.text({
				Text = subtitle,
				TextSize = Theme.sizes.small,
				TextColor3 = if j.muted then C.warning else C.textMuted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.new(0, 46, 0, 18),
				Size = UDim2.new(1, -46, 0, 16),
				Parent = row,
			})
			if j.rank then
				local tag = Components.text({
					Text = j.rank,
					FontFace = P.bold,
					TextSize = 11,
					TextColor3 = j.rankColor or C.aurum,
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0, 90, 0, 18),
					Parent = row,
				})
				tag.ZIndex = 2
			end
			row.Activated:Connect(function()
				selection = j.userId
				drawList()
				loadRecord(j.userId)
			end)
		end
		if n == 0 then
			Components.paragraph(if filter == "" then "No players." else "Nobody on this server.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small,
				Parent = list,
			})
		end
	end

	local function loadList()
		local response = ctx.request("players.list")
		if response.ok then
			players = response.players
			drawList()
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		filter = search.Text
		drawList()
	end)

	local function searchOffline()
		local text = search.Text
		if not string.match(text, "%S") then
			return
		end
		local response = ctx.execute("players.search", { text = text })
		if response then
			selection = response.userId
			drawList()
			loadRecord(response.userId)
		end
	end

	if ctx.can("censor.view") then
		Components.button("Search offline", "secondary", searchOffline, {
			Position = UDim2.new(0, 0, 0, 42),
			Size = UDim2.new(1, 0, 0, 34),
			AutomaticSize = Enum.AutomaticSize.None,
			TextSize = Theme.sizes.small + 1,
			Parent = left,
		})
		search.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				-- Enter on a name that is not on this server: search offline.
				local query = string.lower(search.Text)
				for _, j in players do
					if string.lower(j.name) == query then
						selection = j.userId
						drawList()
						loadRecord(j.userId)
						return
					end
				end
				searchOffline()
			end
		end)
	end

	-- Player record ------------------------------------------------------------------------------------

	local function infoRow(parent: Instance, order: number, key: string, value: string)
		local row = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = parent,
		})
		Components.text({
			Text = key,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			Size = UDim2.new(0.42, 0, 0, 20),
			Parent = row,
		})
		Components.text({
			Text = value,
			TextSize = Theme.sizes.small + 1,
			Position = UDim2.new(0.42, 0, 0, 0),
			Size = UDim2.new(0.58, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = row,
		})
	end

	displayRecord = function(f: any)
		Components.clear(right)

		-- Header
		local header = Components.card({ LayoutOrder = 1, Parent = right })
		local image = avatar(f.userId, 64)
		image.Parent = header
		local block = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 78, 0, 0),
			Size = UDim2.new(1, -78, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = header,
		}, { Components.stack("V", 4) })
		Components.text({
			Text = f.displayName or f.name,
			FontFace = P.title,
			TextSize = Theme.sizes.large,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = block,
		})
		Components.text({
			Text = `@{f.name}  ·  #{f.userId}`,
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 16),
			Parent = block,
		})
		local badges = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = block,
		}, { Components.stack("H", 6) })
		Components.badge(if f.online then "Online" else "Offline", if f.online then C.success else C.textFaint).Parent =
			badges
		if f.rank then
			Components.badge(f.rank, f.rankColor or C.aurum).Parent = badges
		end
		if f.mute then
			Components.badge("Muted", C.warning).Parent = badges
		end
		if f.ban then
			Components.badge("Banned", C.danger).Parent = badges
		end

		-- Information
		if f.firstSeen ~= nil or f.online then
			local info = Components.card({ LayoutOrder = 2, Parent = right }, { Components.stack("V", 4) })
			Components.section("Registry", 0).Parent = info
			infoRow(info, 1, "First join", Core.formatDate(f.firstSeen))
			infoRow(info, 2, "Last join", Core.formatDate(f.lastSeen))
			infoRow(info, 3, "Playtime", Core.formatDuration((f.playtime or 0) + (f.session or 0)))
			if f.session then
				infoRow(info, 4, "Current session", Core.formatDuration(f.session))
			end
			infoRow(info, 5, "Warnings", tostring(f.warnings or 0))
			if f.usernames and #f.usernames > 1 then
				infoRow(info, 6, "Previous usernames", table.concat(f.usernames, ", "))
			end
		end

		-- Active measures
		local function measure(order: number, title: string, m: any, color: Color3)
			local card = Components.card({ LayoutOrder = order, Parent = right }, {
				Components.stack("V", 4),
				Components.stroke(color),
			})
			local heading = Components.section(title, 0)
			heading.TextColor3 = color
			heading.Parent = card
			infoRow(card, 1, "Reason", m.reason)
			infoRow(card, 2, "By", m.by)
			infoRow(card, 3, "Since", Core.formatDate(m.date))
			infoRow(card, 4, "Ends", if m.expiresAt then Core.formatDate(m.expiresAt) else "Permanent")
		end
		if f.ban then
			measure(3, "Active ban", f.ban, C.danger)
		end
		if f.mute then
			measure(4, "Active mute", f.mute, C.warning)
		end

		-- Actions
		local actions = Components.card({ LayoutOrder = 5, Parent = right }, { Components.stack("V", 8) })
		Components.section("Actions", 0).Parent = actions

		if not f.canAct then
			Components.paragraph(
				if f.userId == ctx.me
					then "This is you."
					else "Rank equal to or above yours: sanctions unavailable.",
				{ TextColor3 = C.textMuted, TextSize = Theme.sizes.small + 1, LayoutOrder = 1, Parent = actions }
			)
		end

		local fields = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Visible = f.canAct,
			Parent = actions,
		})
		local reasonField = Components.field("Reason (shown to the player)", {
			Size = UDim2.new(0.68, -4, 1, 0),
			Parent = fields,
		})
		local settings = ctx.access.settings
		local duration = Components.field("Duration", {
			Size = UDim2.new(0.32, -4, 1, 0),
			Position = UDim2.new(0.68, 4, 0, 0),
			Parent = fields,
		})
		-- Empty field: Lex default duration, which differs for a mute and a ban.
		local function durationOr(default: string): string
			return if string.match(duration.Text, "%S") then duration.Text else default
		end
		Components.paragraph(
			`Duration: 30s, 10m, 2h, 7d or perm. Empty = {settings.muteDuration} (mute), {settings.banDuration} (ban). The reason goes through the Roblox filter.`,
			{
			TextColor3 = C.textFaint,
			TextSize = 12,
				LayoutOrder = 3,
				Visible = f.canAct,
				Parent = actions,
			}
		)

		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			Parent = actions,
		}, { Components.stack("H", 6) })

		local function run(action: string, data: { [string]: any }, message: string)
			data.userId = f.userId
			task.spawn(function()
				if ctx.execute(action, data, message) then
					loadRecord(f.userId)
				end
			end)
		end

		local function button(label: string, style: any, permission: string, condition: boolean, fn: () -> ())
			if condition and ctx.can(permission) then
				Components.button(label, style, fn, { Parent = rowFrame })
			end
		end

		local canSanction = f.canAct == true
		button("Warn", "secondary", "praetor.warn", canSanction, function()
			run("praetor.warn", { reason = reasonField.Text }, `{f.name} was warned.`)
		end)
		button("Mute", "secondary", "praetor.mute", canSanction and not f.mute, function()
			run("praetor.mute", { reason = reasonField.Text, duration = durationOr(settings.muteDuration) }, `{f.name} is muted.`)
		end)
		button("Unmute", "secondary", "praetor.mute", canSanction and f.mute ~= nil, function()
			run("praetor.demute", {}, `{f.name} can speak again.`)
		end)
		button("Kick", "danger", "praetor.kick", canSanction and f.online, function()
			ctx.confirm("Kick", `Kick {f.name} from the server?`, "Kick", function()
				run("praetor.kick", { reason = reasonField.Text }, `{f.name} was kicked.`)
			end)
		end)
		button("Ban", "danger", "praetor.ban", canSanction and not f.ban, function()
			local durationText = durationOr(settings.banDuration)
			local ok, seconds = Core.parseDuration(durationText)
			if not ok then
				ctx.notify(ctx.errorMessage("invalid_duration"), "error")
				return
			end
			ctx.confirm("Ban", `Ban {f.name} for {Core.formatDuration(seconds)}?`, "Ban", function()
				run("praetor.ban", { reason = reasonField.Text, duration = durationText }, `{f.name} was banned.`)
			end)
		end)
		button("Unban", "secondary", "praetor.unban", f.ban ~= nil, function()
			run("praetor.unban", {}, `{f.name} was unbanned.`)
		end)
		button("Go to", "ghost", "consul.teleport", f.online and f.userId ~= ctx.me, function()
			run("teleport", { direction = "to" }, `Teleported to {f.name}.`)
		end)
		button("Bring", "ghost", "consul.teleport", canSanction and f.online, function()
			run("teleport", { direction = "bring" }, `{f.name} was brought.`)
		end)

		-- History
		local history = Components.card({ LayoutOrder = 6, Parent = right }, { Components.stack("V", 6) })
		Components.section("Sanction history", 0).Parent = history
		if not f.sanctions or #f.sanctions == 0 then
			Components.paragraph("No sanctions.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = 1,
				Parent = history,
			})
		else
			for i, s in f.sanctions do
				local entry = create("Frame", {
					BackgroundColor3 = C.field,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = i,
					Parent = history,
				}, { Components.corners(Theme.radiusSmall), Components.padding(8, 10), Components.stack("V", 2) })
				local title = SANCTION_LABELS[s.type] or s.type
				if s.duration or s.type == "ban" or s.type == "mute" then
					title ..= ` · {Core.formatDuration(s.duration)}`
				end
				Components.text({
					Text = title,
					FontFace = P.bold,
					TextSize = Theme.sizes.small + 1,
					LayoutOrder = 1,
					Parent = entry,
				})
				Components.paragraph(`{s.reason}  —  by {s.by}, on {Core.formatDate(s.date)}`, {
					TextSize = Theme.sizes.small,
					TextColor3 = C.textMuted,
					LayoutOrder = 2,
					Parent = entry,
				})
			end
		end
	end

	loadRecord = function(userId: number)
		if not ctx.can("censor.view") then
			-- Without registry access: reduced record built from the list.
			for _, j in players do
				if j.userId == userId then
					displayRecord({
						userId = j.userId,
						name = j.name,
						displayName = j.displayName,
						online = true,
						rank = j.rank,
						rankColor = j.rankColor,
						mute = if j.muted then { reason = "—", by = "—" } else nil,
						canAct = j.level < ctx.access.level and j.userId ~= ctx.me,
						sanctions = {},
					})
				end
			end
			return
		end
		local response = ctx.request("players.record", { userId = userId })
		if selection ~= userId then
			return
		end
		if not response.ok then
			showEmpty(ctx.errorMessage(response.err))
			return
		end
		displayRecord(response)
	end

	showEmpty("Choose a player from the list.")

	return {
		show = function(userId: number?)
			task.spawn(loadList)
			if userId then
				selection = userId
				task.spawn(loadRecord, userId)
			end
		end,
		update = function(kind: string, data: any)
			if not frame.Visible then
				return
			end
			if kind == "players" then
				task.spawn(loadList)
			elseif kind == "record" and data == selection then
				task.spawn(loadRecord, data)
			end
		end,
	}
end
