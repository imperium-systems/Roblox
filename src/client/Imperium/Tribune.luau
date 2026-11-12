--!strict
-- Tribune: report form for every player.
-- Opened by the Report button at the bottom left, or "/report [name]" in chat.
-- Two tabs: a new report (a player or a bug), and the follow-up of your own reports.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Imperium = ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium")
local Core = require(Imperium:WaitForChild("Core"))
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Consul = script.Parent:WaitForChild("Consul")
local Theme = require(Consul:WaitForChild("Theme"))
local Components = require(Consul:WaitForChild("Components"))

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local MIN_LENGTH = 10

local MESSAGES: { [string]: string } = {
	disabled = "Reports are turned off in this game.",
	too_short = "Please describe what happened (10 characters minimum).",
	self_report = "You cannot report yourself.",
	offline = "One of these players has left the server.",
	player_not_found = "Choose at least one player first.",
	already_reported = "You already have an open report about one of these players.",
	too_many_targets = "Too many players in one report.",
	too_many_open = "You already have several reports waiting. Staff will look at them soon.",
	invalid_text = "The description is empty or too long.",
	invalid_value = "Choose a category first.",
	filtering_failed = "The Roblox text filter did not respond, try again.",
	save_failed = "Your report could not be saved, try again.",
	rate_limited = "Too many requests, slow down a little.",
	network = "The server is not responding.",
}

-- Status shown to the reporter, without staff names.
local function statusOf(ticket: any): (string, Color3)
	if ticket.status == "open" then
		return "Waiting", C.info
	elseif ticket.status == "claimed" then
		return "In progress", C.warning
	elseif ticket.outcome == "resolved" then
		return "Handled", C.success
	end
	return "Reviewed", C.textMuted
end

local Tribune = {}

local function request(action: string, data: { [string]: any }?): { [string]: any }
	local response = Veredarius.request("tribune", action, data or {})
	if type(response) ~= "table" then
		return { ok = false, err = "network" }
	end
	return response
end

-- Choices that wrap onto several lines. Returns the frame and a function to change the choice.
local function chips(
	options: { { value: string, label: string } },
	onChange: (string) -> ()
): (Frame, (string?) -> ())
	local layout = Components.stack("H", 6)
	layout.Wraps = true
	local frame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { layout })
	local buttons: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	local function choose(value: string?)
		for key, b in buttons do
			local selected = key == value
			b.button.BackgroundColor3 = if selected then C.accent else C.field
			b.button.TextColor3 = if selected then C.onAccent else C.textMuted
			b.stroke.Color = if selected then C.accent else C.border
		end
	end
	for i, option in options do
		local stroke = Components.stroke()
		local button = create("TextButton", {
			Text = option.label,
			FontFace = P.medium,
			TextSize = Theme.sizes.small + 1,
			AutoButtonColor = false,
			Size = UDim2.new(0, 0, 0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = frame,
		}, { Components.corners(Theme.radiusSmall), Components.padding(0, 12), stroke }) :: TextButton
		buttons[option.value] = { button = button, stroke = stroke }
		button.Activated:Connect(function()
			choose(option.value)
			onChange(option.value)
		end)
	end
	choose(nil)
	return frame, choose
end

local function build()
	local me = Players.LocalPlayer
	local settings = request("settings")
	if not settings.ok then
		-- The server may still be starting: retry once.
		task.wait(3)
		settings = request("settings")
		if not settings.ok then
			return
		end
	end

	local screen = create("ScreenGui", {
		Name = "ImperiumTribune",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 45,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = me:WaitForChild("PlayerGui"),
	})

	-- Window ------------------------------------------------------------------------------

	local window = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.86),
		BackgroundColor3 = C.background,
		Visible = false,
		Parent = screen,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(480, 580), MinSize = Vector2.new(300, 320) }),
		Components.corners(),
		Components.stroke(C.border),
	})
	local scale = create("UIScale", { Scale = 1, Parent = window })

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.panel,
		Parent = window,
	}, {
		Components.corners(),
		create("Frame", {
			Size = UDim2.new(1, 0, 0, 12),
			Position = UDim2.new(0, 0, 1, -12),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}),
		create("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = C.border,
			BorderSizePixel = 0,
		}),
		-- Forum color: Tribune belongs to the Forum.
		create("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.fromHex("#66D2CE"),
			BorderSizePixel = 0,
		}),
	})
	Components.text({
		Text = "REPORT",
		FontFace = P.title,
		TextSize = Theme.sizes.large + 2,
		TextColor3 = C.aurum,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 24),
		Parent = header,
	})

	local function toggle(visible: boolean)
		window.Visible = visible
		if visible then
			scale.Scale = 0.96
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end
	end

	Components.button("Close", "ghost", function()
		toggle(false)
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 32),
		Parent = header,
	})

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 53),
		Size = UDim2.new(1, 0, 1, -53),
		Parent = window,
	}, { Components.padding(12, 14, 14, 16) })

	local formPage = Components.scroller({
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		Parent = body,
	}, 8)
	local minePage = Components.scroller({
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		Visible = false,
		Parent = body,
	}, 8)

	-- New report ---------------------------------------------------------------------------

	local kind = "player"
	local category: string? = nil
	local targets: { number } = {} -- UserIds of the chosen players
	local maxTargets = settings.maxTargets or 1
	local sending = false

	local playerSection = Components.section(if maxTargets > 1 then `Players (up to {maxTargets})` else "Player", 3)
	playerSection.Parent = formPage
	local search = Components.field("Search a player…", { LayoutOrder = 4, Parent = formPage })
	local playerList = Components.scroller({
		Size = UDim2.new(1, 0, 0, 132),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.field,
		LayoutOrder = 5,
		Parent = formPage,
	}, 2)
	Components.corners(Theme.radiusSmall).Parent = playerList

	Components.section("Category", 6).Parent = formPage
	local categoryHolder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 7,
		Parent = formPage,
	})

	Components.section("What happened?", 8).Parent = formPage
	local description = Components.field("Describe what you saw, where and when.", {
		MultiLine = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 96),
		LayoutOrder = 9,
		Parent = formPage,
	})
	local descriptionPadding = description:FindFirstChildOfClass("UIPadding")
	if descriptionPadding then
		descriptionPadding.PaddingTop = UDim.new(0, 8)
		descriptionPadding.PaddingBottom = UDim.new(0, 8)
	end
	local counter = Components.text({
		Text = `0/{settings.maxLength}`,
		TextSize = 12,
		TextColor3 = C.textFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 10,
		Parent = formPage,
	})

	Components.paragraph(
		"Staff receive your report with details about the server and the players involved. Abusive reports can be sanctioned.",
		{ TextSize = Theme.sizes.small, TextColor3 = C.textFaint, LayoutOrder = 11, Parent = formPage }
	)
	local feedback = Components.paragraph("", {
		TextSize = Theme.sizes.small + 1,
		Visible = false,
		LayoutOrder = 12,
		Parent = formPage,
	})
	local submit: TextButton

	local function say(text: string?, color: Color3?)
		feedback.Visible = text ~= nil
		feedback.Text = text or ""
		feedback.TextColor3 = color or C.textMuted
	end

	local function refreshSubmit()
		local length = #description.Text
		local ready = not sending
			and category ~= nil
			and length >= MIN_LENGTH
			and (kind == "bug" or #targets > 0)
		Components.setEnabled(submit, ready)
	end

	local function drawPlayers()
		Components.clear(playerList)
		local filter = string.lower(search.Text)
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		local shown = 0
		for _, player in list do
			if player == me then
				continue
			end
			local matches = filter == ""
				or string.find(string.lower(player.Name), filter, 1, true) ~= nil
				or string.find(string.lower(player.DisplayName), filter, 1, true) ~= nil
			if not matches then
				continue
			end
			shown += 1
			local selected = table.find(targets, player.UserId) ~= nil
			local row = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if selected then C.card else C.field,
				Size = UDim2.new(1, 0, 0, 38),
				LayoutOrder = shown,
				Parent = playerList,
			}, { Components.corners(Theme.radiusSmall), Components.padding(0, 10) })
			if selected then
				Components.stroke(C.accent, 1.5).Parent = row
			end
			Components.text({
				Text = player.DisplayName,
				FontFace = P.medium,
				TextColor3 = if selected then C.accent else C.text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(0.5, 0, 1, 0),
				Parent = row,
			})
			Components.text({
				Text = `@{player.Name}`,
				TextSize = Theme.sizes.small,
				TextColor3 = C.textFaint,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0.5, -8, 1, 0),
				Parent = row,
			})
			-- A click adds or removes the player; one player only when the limit is 1.
			row.Activated:Connect(function()
				local index = table.find(targets, player.UserId)
				if index then
					table.remove(targets, index)
				elseif maxTargets <= 1 then
					targets = { player.UserId }
				elseif #targets >= maxTargets then
					say(`You can report up to {maxTargets} players at once.`, C.danger)
					return
				else
					table.insert(targets, player.UserId)
				end
				drawPlayers()
				refreshSubmit()
			end)
		end
		if shown == 0 then
			Components.paragraph(if filter == "" then "No other player on this server." else "No player found.", {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.textFaint,
				Size = UDim2.new(1, 0, 0, 38),
				Parent = playerList,
			}).TextYAlignment = Enum.TextYAlignment.Center
		end
	end

	local function drawCategories()
		Components.clear(categoryHolder)
		category = nil
		local frame = chips(settings.categories[kind], function(value)
			category = value
			refreshSubmit()
		end)
		frame.Parent = categoryHolder
	end

	local function setKind(fresh: string)
		kind = fresh
		playerSection.Visible = kind == "player"
		search.Visible = kind == "player"
		playerList.Visible = kind == "player"
		drawCategories()
		refreshSubmit()
	end

	Components.section("What do you want to report?", 1).Parent = formPage
	local kindSelector = Components.selector({
		{ value = "player", label = "A player" },
		{ value = "bug", label = "A bug" },
	}, kind, setKind)
	kindSelector.LayoutOrder = 2
	kindSelector.Parent = formPage

	submit = Components.button("Send report", "primary", function()
		if sending then
			return
		end
		sending = true
		refreshSubmit()
		say("Sending…", C.textMuted)
		task.spawn(function()
			local response = request("submit", {
				kind = kind,
				category = category,
				userIds = if kind == "player" then targets else nil,
				description = description.Text,
			})
			sending = false
			if response.ok then
				say(`Report #{response.id} sent. You can follow it in My reports.`, C.success)
				description.Text = ""
				table.clear(targets)
				drawPlayers()
				drawCategories()
			elseif response.err == "cooldown" then
				say(`Please wait {Core.formatCountdown(response.wait or 0)} before sending another report.`, C.danger)
			else
				say(MESSAGES[response.err or ""] or `Failed ({response.err or "unknown"}).`, C.danger)
			end
			refreshSubmit()
		end)
	end, { LayoutOrder = 13, Parent = formPage })

	description:GetPropertyChangedSignal("Text"):Connect(function()
		if #description.Text > settings.maxLength then
			description.Text = string.sub(description.Text, 1, settings.maxLength)
			return
		end
		counter.Text = `{#description.Text}/{settings.maxLength}`
		refreshSubmit()
	end)
	search:GetPropertyChangedSignal("Text"):Connect(drawPlayers)
	Players.PlayerAdded:Connect(function()
		if window.Visible then
			drawPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local index = table.find(targets, player.UserId)
		if index then
			table.remove(targets, index)
		end
		task.defer(function()
			if window.Visible then
				drawPlayers()
				refreshSubmit()
			end
		end)
	end)

	-- My reports ------------------------------------------------------------------------------

	local function drawMine()
		Components.clear(minePage)
		local loading = Components.paragraph("Loading…", { TextColor3 = C.textFaint, Parent = minePage })
		local response = request("mine")
		loading:Destroy()
		if not response.ok then
			Components.paragraph(MESSAGES[response.err or ""] or "Could not load your reports.", {
				TextColor3 = C.danger,
				Parent = minePage,
			})
			return
		end
		if #response.tickets == 0 then
			Components.paragraph("You have not sent any report yet.", { TextColor3 = C.textFaint, Parent = minePage })
			return
		end
		for i, ticket in response.tickets do
			local card = Components.card({ LayoutOrder = i, Parent = minePage }, { Components.stack("V", 6) })
			local top = create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 1,
				Parent = card,
			})
			local about = if ticket.targetName then ` · {ticket.targetName}` else " · Bug"
			Components.text({
				Text = `#{ticket.id}  {ticket.categoryLabel}{about}`,
				FontFace = P.medium,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -120, 1, 0),
				Parent = top,
			})
			local label, color = statusOf(ticket)
			local badge = Components.badge(label, color)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.fromScale(1, 0)
			badge.Parent = top
			Components.paragraph(ticket.description, {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.textMuted,
				LayoutOrder = 2,
				Parent = card,
			})
			Components.text({
				Text = Core.formatDate(ticket.date),
				TextSize = 12,
				TextColor3 = C.textFaint,
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 3,
				Parent = card,
			})
		end
	end

	local tab = "form"
	local tabSelector: Frame? = nil
	local function setTab(fresh: string)
		tab = fresh
		formPage.Visible = tab == "form"
		minePage.Visible = tab == "mine"
		if tab == "mine" then
			task.spawn(drawMine)
		end
	end
	local function buildTabs()
		if tabSelector then
			tabSelector:Destroy()
		end
		tabSelector = Components.selector({
			{ value = "form", label = "New report" },
			{ value = "mine", label = "My reports" },
		}, tab, setTab)
		tabSelector.Parent = body
	end
	buildTabs()

	-- Opening ------------------------------------------------------------------------------------

	local function open(userId: number?)
		if userId then
			-- From "/report name": straight to that player.
			if tab ~= "form" then
				tab = "form"
				buildTabs()
				setTab("form")
			end
			kindSelector:Destroy()
			kindSelector = Components.selector({
				{ value = "player", label = "A player" },
				{ value = "bug", label = "A bug" },
			}, "player", setKind)
			kindSelector.LayoutOrder = 2
			kindSelector.Parent = formPage
			setKind("player")
			targets = { userId }
		end
		if not settings.enabled then
			say(MESSAGES.disabled, C.danger)
		elseif not sending and feedback.TextColor3 ~= C.success then
			say(nil)
		end
		drawPlayers()
		refreshSubmit()
		toggle(true)
		if tab == "mine" then
			task.spawn(drawMine)
		end
	end

	-- On mobile, the thumbstick takes the bottom left corner.
	local touch = UserInputService.TouchEnabled
	local reportButton = Components.button("Report", "secondary", function()
		if window.Visible then
			toggle(false)
		else
			open(nil)
		end
	end, {
		AnchorPoint = if touch then Vector2.new(0, 0.5) else Vector2.new(0, 1),
		Position = if touch then UDim2.new(0, 16, 0.5, 0) else UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(0, 0, 0, 32),
		Visible = settings.enabled and settings.button,
		Parent = screen,
	})

	Veredarius.onReceive("tribune.open", function(userId: any)
		open(if type(userId) == "number" then userId else nil)
	end)
	Veredarius.onReceive("tribune.settings", function(fresh: any)
		if type(fresh) ~= "table" then
			return
		end
		settings.enabled = fresh.enabled
		settings.button = fresh.button
		reportButton.Visible = fresh.enabled and fresh.button
	end)

	setKind("player")
end

-- Waits for the server settings: runs apart so the other systems start right away.
function Tribune.start()
	task.spawn(build)
end

return Tribune
