--!strict
-- Server page: state, announcements, locking and restart (through Praefectus and Praeco).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local function now(): number
	return workspace:GetServerTimeNow()
end

return function(ctx: any, frame: Frame)
	local state: any = nil

	local scroller = Components.scroller({ Parent = frame }, 12)

	-- State ------------------------------------------------------------------------------

	local grid = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroller,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -6, 0, 72),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local values: { [string]: TextLabel } = {}
	local function tile(order: number, key: string, label: string)
		local t = Components.card({ LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.None, Parent = grid })
		Components.text({
			Text = label,
			TextSize = 12,
			TextColor3 = C.textMuted,
			Size = UDim2.new(1, 0, 0, 16),
			Parent = t,
		})
		values[key] = Components.text({
			Text = "—",
			FontFace = P.title,
			TextSize = Theme.sizes.large,
			TextColor3 = C.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = t,
		})
	end
	tile(1, "players", "Players")
	tile(2, "duration", "Uptime")
	tile(3, "status", "Access")
	tile(4, "version", "Place version")

	local serverIdLabel = Components.text({
		Text = "",
		FontFace = P.code,
		TextSize = 12,
		TextColor3 = C.textFaint,
		LayoutOrder = 2,
		Parent = scroller,
	})

	local banner = Components.card({ LayoutOrder = 3, Visible = false, Parent = scroller }, {
		Components.stroke(C.aurum),
	})
	local bannerText = Components.paragraph("", { TextColor3 = C.aurum, FontFace = P.medium, Parent = banner })

	local showLock: ((boolean) -> ())? = nil

	local function drawState()
		if not state then
			return
		end
		values.players.Text = `{state.players} / {state.max}`
		values.duration.Text = Core.formatDuration(now() - state.startedAt)
		values.status.Text = if state.locked then "Locked" else "Open"
		values.status.TextColor3 = if state.locked then C.warning else C.success
		values.version.Text = tostring(state.version)
		serverIdLabel.Text = `Server {state.jobId}`
		if state.restart then
			local remaining = math.max(0, math.floor(state.restart.expiresAt - now()))
			banner.Visible = true
			bannerText.Text = `Restarting in {Core.formatCountdown(remaining)}: {state.restart.reason}`
		else
			banner.Visible = false
		end
		if showLock then
			showLock(state.locked)
		end
	end

	local function load()
		local response = ctx.request("server.state")
		if response.ok then
			state = response.server
			drawState()
		end
	end

	-- Announcement ---------------------------------------------------------------------------

	if ctx.can("praefectus.announce") then
		local card = Components.card({ LayoutOrder = 10, Parent = scroller }, { Components.stack("V", 8) })
		Components.section("Announcement", 0).Parent = card
		local message = Components.field("Message shown to all players…", {
			LayoutOrder = 1,
			Parent = card,
		})
		local kind = "info"
		local everywhere = false
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = card,
		}, { Components.stack("H", 10) })
		Components.selector({
			{ value = "info", label = "Info" },
			{ value = "warning", label = "Alert" },
			{ value = "maintenance", label = "Maintenance" },
		}, kind, function(v)
			kind = v
		end).Parent =
			rowFrame
		local toggle = Components.toggle(false, function(v)
			everywhere = v
		end)
		toggle.LayoutOrder = 2
		toggle.Parent = rowFrame
		Components.text({
			Text = "All servers",
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 3,
			Parent = rowFrame,
		})
		Components.button("Send", "primary", function()
			local text = message.Text
			task.spawn(function()
				if ctx.execute("server.announce", { text = text, kind = kind, everywhere = everywhere }, "Announcement sent.") then
					message.Text = ""
				end
			end)
		end, { LayoutOrder = 4, Parent = rowFrame })
	end

	-- Locking ----------------------------------------------------------------------

	if ctx.can("praefectus.lock") then
		local card = Components.card({ LayoutOrder = 20, Parent = scroller }, { Components.stack("V", 8) })
		Components.section("Server access", 0).Parent = card
		Components.paragraph(
			"When locked, the server refuses new players who are not staff. Players already here stay.",
			{ TextColor3 = C.textMuted, TextSize = Theme.sizes.small + 1, LayoutOrder = 1, Parent = card }
		)
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Parent = card,
		}, { Components.stack("H", 10) })
		local everywhere = false
		local button, display = Components.toggle(false, function(v)
			task.spawn(function()
				local message = if v then "Server locked." else "Server open."
				if not ctx.execute("server.lock", { state = v, everywhere = everywhere }, message) then
					load()
				end
			end)
		end)
		showLock = display
		button.Parent = rowFrame
		Components.text({
			Text = "Lock",
			FontFace = P.medium,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = rowFrame,
		})
		local everywhereToggle = Components.toggle(false, function(v)
			everywhere = v
		end)
		everywhereToggle.LayoutOrder = 3
		everywhereToggle.Parent = rowFrame
		Components.text({
			Text = "All servers",
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 4,
			Parent = rowFrame,
		})
	end

	-- Restart -----------------------------------------------------------------------

	if ctx.can("praefectus.restart") then
		local card = Components.card({ LayoutOrder = 30, Parent = scroller }, { Components.stack("V", 8) })
		Components.section("Restart", 0).Parent = card
		Components.paragraph(
			"Announces a countdown, then kicks everyone with a reconnect message. The server closes once empty.",
			{ TextColor3 = C.textMuted, TextSize = Theme.sizes.small + 1, LayoutOrder = 1, Parent = card }
		)
		local fields = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Parent = card,
		})
		local reason = Components.field("Reason (e.g. Update)", {
			Size = UDim2.new(0.7, -4, 1, 0),
			Parent = fields,
		})
		local delaySeconds = Components.field("Delay (s)", {
			Text = tostring(ctx.access.settings.restartDelay),
			Size = UDim2.new(0.3, -4, 1, 0),
			Position = UDim2.new(0.7, 4, 0, 0),
			Parent = fields,
		})
		local rowFrame = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 3,
			Parent = card,
		}, { Components.stack("H", 10) })
		local everywhere = false
		local everywhereToggle = Components.toggle(false, function(v)
			everywhere = v
		end)
		everywhereToggle.Parent = rowFrame
		Components.text({
			Text = "All servers",
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = rowFrame,
		})
		Components.button("Restart", "danger", function()
			local seconds = tonumber(delaySeconds.Text)
			if not seconds or seconds < 5 or seconds > 600 then
				ctx.notify("Delay between 5 and 600 seconds.", "error")
				return
			end
			local scope = if everywhere then "ALL servers" else "this server"
			ctx.confirm("Restart", `Restart {scope} in {Core.formatCountdown(seconds)}?`, "Restart", function()
				task.spawn(
					ctx.execute,
					"server.restart",
					{ delaySeconds = seconds, reason = reason.Text, everywhere = everywhere },
					"Countdown started."
				)
			end)
		end, { LayoutOrder = 3, Parent = rowFrame })
		Components.button("Cancel", "secondary", function()
			task.spawn(ctx.execute, "server.cancel", { everywhere = everywhere }, "Restart cancelled.")
		end, { LayoutOrder = 4, Parent = rowFrame })
	end

	-- Refreshes the duration and countdown while the page is visible.
	task.spawn(function()
		while true do
			task.wait(1)
			if frame.Visible and frame.Parent then
				drawState()
			end
		end
	end)

	return {
		show = function()
			task.spawn(load)
		end,
		update = function(kind: string, data: any)
			if kind == "server" and type(data) == "table" then
				state = data
				drawState()
			end
		end,
	}
end
