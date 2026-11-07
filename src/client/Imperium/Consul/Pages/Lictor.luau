--!strict
-- Lictor page: suspicious players with their score, and the latest detections, live.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

-- Detections can arrive several times per second: redraw at most this often.
local REFRESH = 1

return function(ctx: any, frame: Frame)
	local scroller = Components.scroller({ Parent = frame }, 10)

	local state: any = nil
	local pending = false
	local load: () -> ()

	local function scoreBar(parent: Instance, score: number, thresholds: any)
		local scale = math.max(thresholds.ban, thresholds.kick, thresholds.alert, 1)
		local color = if score >= thresholds.alert then C.danger else C.warning
		local track = create("Frame", {
			BackgroundColor3 = C.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 4),
			Parent = parent,
		}, { Components.corners(Theme.radiusSmall) })
		create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.new(math.clamp(score / scale, 0, 1), 0, 1, 0),
			Parent = track,
		}, { Components.corners(Theme.radiusSmall) })
	end

	local function suspectRow(order: number, s: any, thresholds: any)
		local row = create("Frame", {
			BackgroundColor3 = C.card,
			Size = UDim2.new(1, 0, 0, 64),
			LayoutOrder = order,
			Parent = scroller,
		}, { Components.corners(Theme.radiusSmall), Components.padding(10, 12) })
		if s.score >= thresholds.alert then
			Components.stroke(C.danger).Parent = row
		end

		Components.text({
			Text = s.displayName,
			FontFace = P.medium,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(0.45, 0, 0, 18),
			Parent = row,
		})
		local summary = `@{s.name}  ·  {s.count} detection{if s.count == 1 then "" else "s"}`
		if s.lastLabel then
			summary ..= `  ·  last: {s.lastLabel}, {Core.formatDate(s.lastDate)}`
		end
		Components.text({
			Text = summary,
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, -300, 0, 16),
			Parent = row,
		})
		Components.text({
			Text = `Score {s.score}`,
			FontFace = P.bold,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = if s.score >= thresholds.alert then C.danger else C.text,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 90, 0, 18),
			Parent = row,
		})
		scoreBar(row, s.score, thresholds)

		local buttons = create("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -96, 0, 0),
			Size = UDim2.new(0, 200, 0, 30),
			Parent = row,
		}, { Components.stack("H", 6, Enum.HorizontalAlignment.Right) })
		Components.button("Record", "ghost", function()
			ctx.open("Players", s.userId)
		end, { Size = UDim2.new(0, 0, 0, 28), LayoutOrder = 1, Parent = buttons })
		if ctx.can("lictor.clear") then
			Components.button("Clear", "secondary", function()
				task.spawn(function()
					if ctx.execute("lictor.clear", { userId = s.userId }, `Score of {s.name} cleared.`) then
						load()
					end
				end)
			end, { Size = UDim2.new(0, 0, 0, 28), LayoutOrder = 2, Parent = buttons })
		end
	end

	local function detectionRow(order: number, d: any)
		local row = create("Frame", {
			BackgroundColor3 = C.card,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = scroller,
		}, { Components.corners(Theme.radiusSmall), Components.padding(8, 12), Components.stack("V", 2) })
		local top = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			Parent = row,
		})
		Components.text({
			Text = `{d.label}  ·  {d.name}`,
			FontFace = P.medium,
			TextSize = Theme.sizes.small + 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -130, 1, 0),
			Parent = top,
		})
		Components.text({
			Text = Core.formatDate(d.date),
			TextSize = 12,
			TextColor3 = C.textFaint,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 125, 1, 0),
			Parent = top,
		})
		Components.paragraph(`{d.details}  ·  score {d.score}`, {
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Parent = row,
		})
	end

	local function draw()
		Components.clear(scroller)
		if not state then
			return
		end
		local t = state.thresholds
		local limits = `Alert at {t.alert}`
		limits ..= if t.kick > 0 then `, kick at {t.kick}` else ", automatic kick off"
		limits ..= if t.ban > 0 then `, ban at {t.ban}.` else ", automatic ban off."
		Components.paragraph(`{limits} Scores drop over time; thresholds are in Settings.`, {
			TextColor3 = C.textFaint,
			TextSize = Theme.sizes.small,
			LayoutOrder = 0,
			Parent = scroller,
		})

		Components.section("Suspicious players", 1).Parent = scroller
		if #state.suspects == 0 then
			Components.paragraph("Nobody looks suspicious on this server.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = 2,
				Parent = scroller,
			})
		end
		for i, s in state.suspects do
			suspectRow(1 + i, s, t)
		end

		local base = 2 + #state.suspects
		Components.section("Latest detections", base).Parent = scroller
		if #state.recent == 0 then
			Components.paragraph("No detections yet.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = base + 1,
				Parent = scroller,
			})
		end
		for i, d in state.recent do
			detectionRow(base + i, d)
		end
	end

	load = function()
		local response = ctx.request("lictor.list")
		if response.ok then
			state = response
			draw()
		end
	end

	return {
		show = function()
			task.spawn(load)
		end,
		update = function(kind: string)
			if kind ~= "lictor" or not frame.Visible or pending then
				return
			end
			pending = true
			task.delay(REFRESH, function()
				pending = false
				if frame.Visible then
					load()
				end
			end)
		end,
	}
end
