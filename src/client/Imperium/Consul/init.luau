--!strict
-- Consul: admin panel, client side.
-- Only built for staff (the server decides). The interface only shows permitted tabs
-- and buttons, but the server checks every action again.
-- Shortcut: F2, or the "Imperium" button at the bottom right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Imperium = ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium")
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Theme = require(script.Theme)
local Components = require(script.Components)
local Logos = require(script.Logos)
local Catalog = require(script.Catalog)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local SHORTCUT = Enum.KeyCode.F2

local MESSAGES: { [string]: string } = {
	unauthorized = "You do not have permission to do that.",
	insufficient_rank = "This player has a rank equal to or above yours.",
	player_not_found = "Player not found.",
	offline = "This player is not on this server.",
	no_character = "Character not found (dead or loading?).",
	invalid_duration = "Unreadable duration. Examples: 30s, 10m, 2h, 7d, perm.",
	invalid_text = "Invalid or too long text.",
	invalid_value = "Invalid value.",
	out_of_range = "Value outside the allowed limits.",
	unknown_key = "Unknown setting.",
	filtering_failed = "The Roblox text filter did not respond, try again.",
	already_running = "A restart is already running.",
	nothing_to_cancel = "No restart is running.",
	not_banned = "This player is not banned.",
	cross_server = "Could not reach the other servers.",
	save_failed = "Saving did not respond, try again.",
	rate_limited = "Too many requests, slow down a little.",
	network = "The server is not responding.",
	internal_error = "Internal server error.",
	unknown_action = "Unknown action.",
	ticket_not_found = "This report no longer exists.",
	ticket_closed = "This report is already closed.",
	already_claimed = "Another staff member is handling this report.",
	not_claimed = "Nobody has claimed this report.",
	case_not_found = "This case file no longer exists, or is still being saved.",
	no_staff_point = "No staff point: add a part named ImperiumStaffPoint in Workspace (or change consul.staff_point in Settings)."
}


-- Simple view: what you came to do, without knowing the system names.
local SIMPLE_VIEW = {
	{ page = "Players", name = "Players", description = "Sanctions and records" },
	{ page = "Tribune", name = "Reports", description = "Sent by players" },
	{ page = "Lictor", name = "Anticheat", description = "Suspicious players" },
	{ page = "Quaesitor", name = "Case files", description = "Replays of incidents" },
	{ page = "Server", name = "Server", description = "Announcements, restart" },
	{ page = "Log", name = "Log", description = "Staff actions" },
	{ page = "Settings", name = "Settings", description = "Game values" },
	{ page = "Help", name = "Help", description = "How it works" },
}

local Consul = {}

local built = false

export type Context = {
	access: { [string]: any },
	me: number,
	can: (permission: string) -> boolean,
	request: (action: string, data: { [string]: any }?) -> { [string]: any },
	execute: (action: string, data: { [string]: any }?, success: string?) -> { [string]: any }?,
	notify: (message: string, kind: ("success" | "error" | "info")?) -> (),
	confirm: (title: string, message: string, label: string, onConfirm: () -> ()) -> (),
	open: (tab: string, argument: any?) -> (),
	errorMessage: (code: string?) -> string,
	screen: ScreenGui,
	setVisible: (visible: boolean) -> (),
}

local function build(access: { [string]: any })
	built = true
	local me = Players.LocalPlayer

	local screen = create("ScreenGui", {
		Name = "ImperiumConsul",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = me:WaitForChild("PlayerGui"),
	})

	-- Notifications ------------------------------------------------------------------

	local notificationArea = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 20,
		Parent = screen,
	}, {
		Components.stack("V", 6, Enum.HorizontalAlignment.Center),
		create("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
	})

	local function notify(message: string, kind: ("success" | "error" | "info")?)
		local color = if kind == "error" then C.danger elseif kind == "success" then C.success else C.info
		local bubble = create("Frame", {
			BackgroundColor3 = C.panel,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 20,
			Parent = notificationArea,
		}, {
			Components.corners(),
			Components.stroke(color, 1.5),
			Components.padding(10, 14),
			Components.paragraph(message, { ZIndex = 21, TextSize = Theme.sizes.small + 1 }),
		})
		task.delay(4, function()
			bubble:Destroy()
		end)
	end

	local function errorMessage(code: string?): string
		return MESSAGES[code or ""] or `Failed ({code or "unknown"}).`
	end

	local function request(action: string, data: { [string]: any }?): { [string]: any }
		local response = Veredarius.request("consul", action, data or {})
		if type(response) ~= "table" then
			return { ok = false, err = "network" }
		end
		return response
	end

	-- Like request, but shows the result. Returns the response when it succeeded.
	local function execute(action: string, data: { [string]: any }?, success: string?): { [string]: any }?
		local response = request(action, data)
		if not response.ok then
			notify(errorMessage(response.err), "error")
			return nil
		end
		if success then
			notify(success, "success")
		end
		return response
	end

	local function can(permission: string): boolean
		return access.permissions[permission] == true
	end

	-- Window --------------------------------------------------------------------------

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.88),
		BackgroundColor3 = C.background,
		Visible = false,
		Parent = screen,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(940, 600), MinSize = Vector2.new(320, 300) }),
		Components.corners(),
		Components.stroke(C.border),
	})
	local scale = create("UIScale", { Scale = 1, Parent = window })

	-- Header
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = C.panel,
		Parent = window,
	}, {
		Components.corners(),
		-- Hides the rounded bottom of the header.
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
	})
	-- Line in the current family's color, like the top of a design system panel.
	local topLine = create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Parent = header,
	})
	local subtitle = `Version {access.version}  ·  {access.rank}`
	if Logos.horizontal ~= 0 then
		create("ImageLabel", {
			Image = `rbxassetid://{Logos.horizontal}`,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0.5, -18),
			Size = UDim2.fromOffset(166, 36),
			Parent = header,
		})
		Components.text({
			Text = subtitle,
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			Position = UDim2.new(0, 194, 0.5, -8),
			Size = UDim2.new(0, 220, 0, 16),
			Parent = header,
		})
	else
		Components.text({
			Text = "IMPERIUM",
			FontFace = P.title,
			TextSize = Theme.sizes.title,
			TextColor3 = C.aurum,
			Position = UDim2.new(0, 16, 0, 8),
			Size = UDim2.new(0.6, 0, 0, 24),
			Parent = header,
		})
		Components.text({
			Text = subtitle,
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			Position = UDim2.new(0, 16, 0, 31),
			Size = UDim2.new(0.6, 0, 0, 16),
			Parent = header,
		})
	end

	local function toggle(visible: boolean?)
		local target = if visible == nil then not window.Visible else visible
		if target then
			window.Visible = true
			scale.Scale = 0.96
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		else
			window.Visible = false
		end
	end

	Components.button("Close", "ghost", function()
		toggle(false)
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = header,
	})

	-- Dragging by the header.
	do
		local source: Vector3? = nil
		local startPosition: UDim2? = nil
		header.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				source = input.Position
				startPosition = window.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if
				source
				and startPosition
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local delta = input.Position - source
				window.Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				source = nil
			end
		end)
	end

	-- Body: families on the left, sub-families on top, content below
	local sidebarWidth = 150
	local sidebar = Components.scroller({
		Position = UDim2.new(0, 8, 0, 69),
		Size = UDim2.new(0, sidebarWidth - 8, 1, -77),
		ScrollBarThickness = 2,
		Parent = window,
	}, 3)
	local content = create("Frame", {
		Position = UDim2.new(0, sidebarWidth, 0, 57),
		Size = UDim2.new(1, -sidebarWidth, 1, -57),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = window,
	}, {
		Components.padding(12, 16, 14, 8),
	})
	local tabLayout = Components.stack("H", 4)
	tabLayout.Wraps = false
	local tabBar = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 38),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.border,
		Parent = content,
	}, { tabLayout })
	local pageArea = create("Frame", {
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		Parent = content,
	})

	-- Confirmation ---------------------------------------------------------------------

	local function confirm(title: string, message: string, label: string, onConfirm: () -> ())
		local overlay = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = window,
		}, { Components.corners() })
		local box = Components.card({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 380, 0, 0),
			BackgroundColor3 = C.panel,
			ZIndex = 11,
			Parent = overlay,
		}, {
			Components.stroke(C.border),
			Components.stack("V", 10),
			create("UISizeConstraint", { MaxSize = Vector2.new(380, math.huge) }),
		})
		box.Size = UDim2.new(0.9, 0, 0, 0)
		Components.text({
			Text = title,
			FontFace = P.title,
			TextSize = Theme.sizes.large,
			TextColor3 = C.aurum,
			LayoutOrder = 1,
			ZIndex = 12,
			Parent = box,
		})
		Components.paragraph(message, { LayoutOrder = 2, ZIndex = 12, TextColor3 = C.textMuted, Parent = box })
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 3,
			Parent = box,
		}, { Components.stack("H", 8, Enum.HorizontalAlignment.Right) })
		Components.button("Cancel", "secondary", function()
			overlay:Destroy()
		end, { ZIndex = 12, LayoutOrder = 1, Parent = rowFrame })
		Components.button(label, "danger", function()
			overlay:Destroy()
			onConfirm()
		end, { ZIndex = 12, LayoutOrder = 2, Parent = rowFrame })
	end

	-- Navigation ---------------------------------------------------------------------------

	local pages: { [string]: { frame: Frame, show: (any?) -> (), update: (string, any?) -> () } } = {}
	local familyButtons: { [any]: TextButton } = {}
	local activeFamily: any = nil
	local activeSystem: any = nil
	local display: (any, any?, any?) -> ()

	-- Help is not a system: it has its own entry below the families.
	local help: any = {
		name = "Help",
		color = C.aurum,
		noTabs = true,
		systems = { { name = "Help", page = "Help", permission = "consul.open" } },
	}
	local entries: { any } = table.clone(Catalog) :: any
	table.insert(entries, help)

	-- Two views of the same pages: the task list, or the families and their systems.
	local mode = "simple"
	local entriesByMode: { [string]: { any } } = { simple = {}, families = entries }

	local function open(id: string, argument: any?)
		for _, family in entriesByMode[mode] do
			for _, system in family.systems do
				if system.page == id and pages[id] then
					display(family, system, argument)
					return
				end
			end
		end
	end

	local ctx: Context = {
		access = access,
		me = me.UserId,
		can = can,
		request = request,
		execute = execute,
		notify = notify,
		confirm = confirm,
		open = open,
		errorMessage = errorMessage,
		screen = screen,
		setVisible = function(visible: boolean)
			toggle(visible)
		end,
	}

	-- A page is only built when the rank grants access to it.
	for _, family in entries do
		for _, system in family.systems do
			if system.page and can(system.permission) then
				local frame = create("Frame", {
					Name = system.page,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Visible = false,
					Parent = pageArea,
				})
				local factory = require(script.Pages:WaitForChild(system.page)) :: any
				local page = factory(ctx, frame)
				page.frame = frame
				pages[system.page] = page
			end
		end
	end

	for _, taskEntry in SIMPLE_VIEW do
		if pages[taskEntry.page] then
			table.insert(entriesByMode.simple, {
				name = taskEntry.name,
				description = taskEntry.description,
				color = C.aurum,
				noTabs = true,
				systems = { { name = taskEntry.name, page = taskEntry.page } },
			})
		end
	end

	-- Only systems the rank can reach are shown: a refused page appears nowhere.
	local function visibleSystems(family: any): { any }
		local list = {}
		for _, system in family.systems do
			if not system.page or pages[system.page] then
				table.insert(list, system)
			end
		end
		return list
	end

	local function status(family: any, system: any): (string, Color3)
		if system.page then
			return "Available", C.success
		end
		if system.active then
			return "Active", family.color
		end
		return "Coming soon", C.textFaint
	end

	-- Overview: the family's systems, in a 3-column table.
	local overview = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.border,
		Visible = false,
		Parent = pageArea,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -8, 0, 96),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local detailView = Components.scroller({ Visible = false, Parent = pageArea }, 10)

	local function fillOverview(family: any)
		Components.clear(overview)
		for i, system in visibleSystems(family) do
			local label, color = status(family, system)
			local card = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.card,
				LayoutOrder = i,
				Parent = overview,
			}, { Components.corners(), Components.padding(10, 12) })
			if system.active then
				Components.stroke(family.color).Parent = card
			end
			Components.text({
				Text = string.upper(system.name),
				FontFace = P.bold,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, 0, 0, 18),
				Parent = card,
			})
			Components.text({
				Text = system.role,
				TextSize = Theme.sizes.small,
				TextColor3 = C.textMuted,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0, 0, 0, 20),
				Size = UDim2.new(1, 0, 0, 34),
				Parent = card,
			})
			Components.text({
				Text = label,
				FontFace = P.bold,
				TextSize = 12,
				TextColor3 = color,
				Position = UDim2.new(0, 0, 0, 58),
				Size = UDim2.new(1, 0, 0, 16),
				Parent = card,
			})
			card.Activated:Connect(function()
				display(family, system)
			end)
		end
	end

	local function fillDetail(family: any, system: any)
		Components.clear(detailView)
		local card = Components.card({ Parent = detailView }, { Components.stack("V", 8) })
		local insignia = Components.insignia(family.name, 64, family.color)
		if insignia then
			insignia.Parent = card
		end
		Components.text({
			Text = string.upper(system.name),
			FontFace = P.title,
			TextSize = Theme.sizes.large,
			TextColor3 = family.color,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 1,
			Parent = card,
		})
		Components.paragraph(`{system.role}  ·  {family.name}`, {
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Parent = card,
		})
		local label, color = status(family, system)
		local badge = Components.badge(label, color)
		badge.LayoutOrder = 3
		badge.Parent = card
		local explanation = "This system has not been built yet."
		if system.active then
			explanation = "This system runs in the background: it has no page in the panel."
		end
		Components.paragraph(explanation, {
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			LayoutOrder = 4,
			Parent = card,
		})
	end

	-- Sub-families: the overview, then each system of the family.
	local function drawTabs()
		Components.clear(tabBar)
		local family = activeFamily
		local selectedButton: TextButton? = nil

		local function addTab(label: string, order: number, system: any)
			local selected = system == activeSystem
			local button = create("TextButton", {
				Text = label,
				FontFace = P.medium,
				TextSize = Theme.sizes.small + 1,
				TextColor3 = if selected
					then family.color
					elseif system == nil or system.active then C.text
					else C.textFaint,
				BackgroundColor3 = if selected then C.card else C.background,
				AutoButtonColor = false,
				Size = UDim2.new(0, 0, 0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = order,
				Parent = tabBar,
			}, { Components.corners(Theme.radiusSmall), Components.padding(0, 12) })
			button.Activated:Connect(function()
				display(family, system)
			end)
			if selected then
				selectedButton = button
			end
		end

		addTab("Overview", 0, nil)
		for i, system in visibleSystems(family) do
			addTab(string.upper(system.name), i, system)
		end

		-- Brings the selected tab into view once the layout has been computed.
		task.defer(function()
			local button = selectedButton
			if button and button.Parent then
				local x = button.AbsolutePosition.X - tabBar.AbsolutePosition.X + tabBar.CanvasPosition.X
				tabBar.CanvasPosition = Vector2.new(math.max(0, x - 8), 0)
			end
		end)
	end

	display = function(family: any, system: any?, argument: any?)
		activeFamily = family
		activeSystem = system
		topLine.BackgroundColor3 = family.color
		for f, button in familyButtons do
			button.BackgroundColor3 = if f == family then C.card else C.background
			button.TextColor3 = if f == family then C.text else C.textMuted
		end
		drawTabs()
		local pageTop = if family.noTabs then 0 else 46
		tabBar.Visible = not family.noTabs
		pageArea.Position = UDim2.new(0, 0, 0, pageTop)
		pageArea.Size = UDim2.new(1, 0, 1, -pageTop)

		for _, page in pages do
			page.frame.Visible = false
		end
		overview.Visible = false
		detailView.Visible = false

		local page = system and system.page and pages[system.page]
		if page then
			page.frame.Visible = true
			page.show(argument)
		elseif system then
			fillDetail(family, system)
			detailView.Visible = true
		else
			fillOverview(family)
			overview.Visible = true
		end
	end

	-- Left column, depending on the selected view.
	local function drawSidebar()
		Components.clear(sidebar)
		table.clear(familyButtons)
		for i, family in entriesByMode[mode] do
			local list = visibleSystems(family)
			local activeCount = 0
			for _, system in list do
				if system.active then
					activeCount += 1
				end
			end
			local detail = family.description
			local insignia = if family.noTabs then nil else Components.insignia(family.name, 24, family.color)
			local leftMargin = if insignia then 38 else 14
			local button = create("TextButton", {
				Text = if family.noTabs then family.name else string.upper(family.name),
				FontFace = P.medium,
				TextSize = if family.noTabs then Theme.sizes.normal else Theme.sizes.small + 1,
				TextColor3 = C.textMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = if detail then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
				BackgroundColor3 = C.background,
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, if detail then 54 else 36),
				LayoutOrder = i,
				Parent = sidebar,
			}, {
				Components.corners(Theme.radiusSmall),
				if detail then Components.padding(8, 10, 8, 14) else Components.padding(0, 10, 0, leftMargin),
				create("Frame", {
					Size = UDim2.new(0, 3, 0, 18),
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, -8, 0.5, 0),
					BackgroundColor3 = family.color,
					BorderSizePixel = 0,
					Visible = insignia == nil,
				}),
				if detail
					then Components.text({
						Text = detail,
						TextSize = 12,
						TextColor3 = C.textFaint,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextWrapped = false,
						Position = UDim2.fromOffset(0, 20),
						Size = UDim2.new(1, 0, 0, 16),
					})
					else Components.text({
						Text = if family.noTabs then "" else `{activeCount}/{#list}`,
						TextSize = 12,
						TextColor3 = C.textFaint,
						TextXAlignment = Enum.TextXAlignment.Right,
						Size = UDim2.fromScale(1, 1),
					}),
			})
			if insignia then
				insignia.AnchorPoint = Vector2.new(0, 0.5)
				insignia.Position = UDim2.new(0, -30, 0.5, 0)
				insignia.Parent = button
			end
			familyButtons[family] = button
			button.Activated:Connect(function()
				display(family, if family.noTabs then list[1] else nil)
			end)
		end
	end
	drawSidebar()

	-- Switches view and stays on the current page when it exists on both sides.
	local function setMode(fresh: string)
		if fresh == mode then
			return
		end
		local page = activeSystem and activeSystem.page
		mode = fresh
		drawSidebar()
		if activeFamily then
			open(if page then page else "Players")
		end
	end

	local viewSelector = Components.selector({
		{ value = "simple", label = "Simple view" },
		{ value = "families", label = "Families" },
	}, mode, setMode)
	viewSelector.AnchorPoint = Vector2.new(1, 0.5)
	viewSelector.Position = UDim2.new(1, -106, 0.5, 0)
	viewSelector.Parent = header

	-- Updates pushed by the server.
	Veredarius.onReceive("consul.update", function(kind: string, data: any)
		for _, page in pages do
			page.update(kind, data)
		end
	end)

	-- Opening -----------------------------------------------------------------------------

	local function togglePanel()
		toggle()
		if window.Visible and not activeFamily then
			open("Players")
		end
	end

	-- On mobile, the jump button already occupies the bottom right corner.
	local bottomMargin = if UserInputService.TouchEnabled then 180 else 16
	Components.button("Imperium", "brand", togglePanel, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -bottomMargin),
		Parent = screen,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= SHORTCUT then
			return
		end
		togglePanel()
	end)

	notify(`Imperium ready: press F2 to open the panel ({access.rank}).`, "info")
end

local function tryAccess()
	if built then
		return
	end
	local response = Veredarius.request("consul", "access", {})
	if type(response) == "table" and response.ok and not built then
		build(response)
	end
end

function Consul.start()
	-- The server signals as soon as the rank is known; we also try right away.
	Veredarius.onReceive("consul.access", function()
		task.spawn(tryAccess)
	end)
	task.spawn(tryAccess)
end

return Consul
