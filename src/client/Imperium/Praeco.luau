--!strict
-- Praeco: displays official announcements for all players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Imperium = ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium")
local Core = require(Imperium:WaitForChild("Core"))
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Consul = script.Parent:WaitForChild("Consul")
local Theme = require(Consul:WaitForChild("Theme"))
local Components = require(Consul:WaitForChild("Components"))

local C = Theme.colors
local create = Components.create

local COLORS: { [string]: Color3 } = {
	info = C.info,
	warning = C.danger,
	maintenance = C.aurum,
	success = C.success,
}

local WARNING_BACKGROUND = C.dangerSoft

local BANNER_TOP = 12
local REMINDER_HEIGHT = 44
local URGENT_SECONDS = 10 -- seconds left at which the reminder turns red

local Praeco = {}

local queue: { any } = {}
local running = false
local container: Frame

-- Icon stroke, centered on (x, y) in a 28 px badge.
local function line(parent: Instance, color: Color3, x: number, y: number, l: number, h: number, rotation: number?)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(l, h),
		Rotation = rotation or 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

-- Icons drawn with frames: no image to host, sharp at any resolution.
local function icon(kind: string, color: Color3, background: Color3): Frame
	local badge = create("Frame", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.8,
	}, {
		Components.corners(Theme.radiusSmall),
		Components.stroke(color, 1.5),
	})
	if kind == "warning" then
		line(badge, color, 14, 11, 3, 10)
		line(badge, color, 14, 20, 3, 3)
	elseif kind == "success" then
		line(badge, color, 10, 16, 3, 7, -45)
		line(badge, color, 16, 14, 3, 13, 45)
	elseif kind == "maintenance" then
		-- Gear: three crossed bars, a disc, a hole.
		for _, rotation in { 0, 60, 120 } do
			line(badge, color, 14, 14, 4, 18, rotation)
		end
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = color,
			Parent = badge,
		}, { Components.corners(UDim.new(1, 0)) })
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = background,
			Parent = badge,
		}, { Components.corners(UDim.new(1, 0)) })
	else
		line(badge, color, 14, 8, 3, 3)
		line(badge, color, 14, 16, 3, 9)
	end
	return badge
end

local function display(announcement: any)
	local color = COLORS[announcement.kind] or C.info
	local background = if announcement.kind == "warning" then WARNING_BACKGROUND else C.panel
	local banner = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = background,
		BackgroundTransparency = 0.05,
		Parent = container,
	}, {
		Components.corners(),
		Components.stroke(color, 1.5),
		Components.padding(10, 16),
	})
	icon(announcement.kind, color, background).Parent = banner
	local block = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = banner,
	}, { Components.stack("V", 2) })
	if announcement.title then
		Components.text({
			Text = announcement.title,
			FontFace = Theme.fonts.bold,
			TextColor3 = color,
			TextSize = Theme.sizes.small,
			LayoutOrder = 1,
			Parent = block,
		})
	end
	Components.paragraph(tostring(announcement.text), { LayoutOrder = 2, Parent = block })

	local enterTween = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(banner, enterTween, { Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	task.wait(math.clamp(tonumber(announcement.duration) or 8, 2, 30))
	local exitTween = TweenService:Create(banner, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) })
	exitTween:Play()
	exitTween.Completed:Wait()
	banner:Destroy()
end

local function processQueue()
	if running then
		return
	end
	running = true
	while #queue > 0 do
		display(table.remove(queue, 1))
	end
	running = false
end

-- Permanent reminder at the top of the screen; banners shift below it.
local function createReminder(screen: ScreenGui): (any) -> ()
	local stroke = Components.stroke(C.aurum, 1.5)
	local frame = create("Frame", {
		Name = "Reminder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_TOP),
		Size = UDim2.fromOffset(0, REMINDER_HEIGHT - 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	}, {
		Components.corners(Theme.radiusSmall),
		stroke,
		Components.padding(0, 14, 0, 6),
		Components.stack("H", 8),
	})
	icon("maintenance", C.aurum, C.panel).Parent = frame
	local text = Components.text({
		FontFace = Theme.fonts.bold,
		TextColor3 = C.aurum,
		TextWrapped = false,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = frame,
	})

	local function placeBanners(height: number)
		TweenService:Create(container, TweenInfo.new(0.2), {
			Position = UDim2.new(0.5, 0, 0, BANNER_TOP + height),
		}):Play()
	end

	local currentToken = 0

	return function(reminder: any)
		currentToken += 1
		local token = currentToken
		if type(reminder) ~= "table" then
			frame.Visible = false
			placeBanners(0)
			return
		end
		frame.Visible = true
		placeBanners(REMINDER_HEIGHT)
		task.spawn(function()
			while token == currentToken do
				local remaining = reminder.expiresAt - workspace:GetServerTimeNow()
				local color = if remaining <= URGENT_SECONDS then C.danger else C.aurum
				text.Text = `{reminder.text} {Core.formatCountdown(remaining)}`
				text.TextColor3 = color
				stroke.Color = color
				task.wait(0.2)
			end
		end)
	end
end

function Praeco.start()
	local screen = create("ScreenGui", {
		Name = "ImperiumPraeco",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	container = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_TOP),
		Size = UDim2.new(0.9, 0, 0, 0),
		ClipsDescendants = false,
		Parent = screen,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) }),
	})

	Veredarius.onReceive("praeco", function(announcement)
		if type(announcement) ~= "table" then
			return
		end
		table.insert(queue, announcement)
		task.spawn(processQueue)
	end)

	Veredarius.onReceive("praeco.reminder", createReminder(screen))
end

return Praeco
