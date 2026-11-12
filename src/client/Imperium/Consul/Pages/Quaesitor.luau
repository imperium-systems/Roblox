--!strict
-- Quaesitor page: case files created by reports (player or bug) and Lictor alerts.
-- Opening a case shows who is in it and what happened; Replay plays the positions as
-- ghosts in the world, on this screen only.
-- Other pages open a case with ctx.open("Quaesitor", id) or { id = id, replay = true }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)
local Replay = require(Consul.Replay)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local REFRESH = 1

local ROLES: { [string]: string } = {
	reporter = "Reporter",
	reported = "Reported",
	suspect = "Suspect",
	nearby = "Nearby",
	other = "On server",
}

local KINDS: { [string]: { label: string, color: Color3 } } = {
	lictor = { label = "Lictor", color = C.danger },
	death = { label = "Death", color = C.warning },
	staff = { label = "Staff", color = C.accent },
	left = { label = "Left", color = C.textFaint },
	trigger = { label = "Trigger", color = C.info },
}

local function minutes(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function peopleLine(players: { any }): string
	local parts = {}
	for _, person in players do
		table.insert(parts, `{ROLES[person.role] or person.role}: <b>{person.name}</b>`)
	end
	return table.concat(parts, "   ·   ")
end

return function(ctx: any, frame: Frame)
	local source = "all"
	local state: any = nil
	local detail: any = nil
	local openId: number? = nil
	local pending = false
	local load: () -> ()

	local top = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = frame,
	})
	local selector = Components.selector({
		{ value = "all", label = "All" },
		{ value = "report", label = "Reports" },
		{ value = "lictor", label = "Lictor" },
	}, source, function(value)
		source = value
		task.spawn(load)
	end)
	selector.Parent = top
	local backButton = Components.button("Back to the list", "ghost", function()
		openId = nil
		detail = nil
		task.spawn(load)
	end, { Size = UDim2.new(0, 0, 0, 32), Visible = false, Parent = top })
	local topLabel = Components.text({
		Text = "",
		TextSize = Theme.sizes.small + 1,
		TextColor3 = C.textMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = top,
	})

	local scroller = Components.scroller({
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		Parent = frame,
	}, 10)

	local function buttonRow(parent: Instance, order: number): Frame
		local row = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = parent,
		})
		Components.stack("H", 6).Parent = row
		return row
	end

	local function smallButton(row: Instance, text: string, style: string, onClick: () -> (), order: number)
		return Components.button(text, style :: any, onClick, {
			Size = UDim2.new(0, 0, 0, 28),
			LayoutOrder = order,
			Parent = row,
		})
	end

	-- Hides the panel and plays the case; Stop brings the panel back on the case.
	local function replay(case: any)
		if #case.tracks == 0 then
			ctx.notify("This case has no recorded position.", "error")
			return
		end
		ctx.setVisible(false)
		Replay.start(ctx.screen, case, function()
			openId = case.id
			detail = { case = case, ticketAccess = ctx.can("tribune.handle") }
			ctx.setVisible(true)
			ctx.open("Quaesitor")
		end, ctx.request)
	end

	local function caseHead(parent: Instance, case: any)
		local head = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = parent,
		})
		Components.text({
			Text = `#{case.id}  {case.label}`,
			FontFace = P.bold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -110, 1, 0),
			Parent = head,
		})
		local badge = if case.source == "lictor"
			then Components.badge("Lictor alert", C.danger)
			else Components.badge("Report", C.info)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.fromScale(1, 0)
		badge.Parent = head

		-- Names come from Roblox, but they are still never trusted as rich text.
		local safe = table.clone(case.players)
		for i, person in safe do
			safe[i] = table.clone(person)
			safe[i].name = string.gsub(person.name, "[<>&]", "")
		end
		Components.paragraph(peopleLine(safe), {
			RichText = true,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Parent = parent,
		})
		local events = if case.eventCount == 1 then "1 event" else `{case.eventCount} events`
		Components.paragraph(
			`{Core.formatDate(case.date)}  ·  {minutes(case.duration)} recorded  ·  {events}{if (case.others or 0) > 0 then `  ·  {case.others} other player{if case.others == 1 then "" else "s"}` else ""}  ·  deleted on {Core.formatDate(case.expiresAt)}`,
			{
				TextSize = 12,
				TextColor3 = C.textFaint,
				LayoutOrder = 3,
				Parent = parent,
			}
		)
	end

	local function openCase(id: number, andReplay: boolean?)
		task.spawn(function()
			local response = ctx.request("quaesitor.get", { id = id })
			if not response.ok then
				ctx.notify(ctx.errorMessage(response.err), "error")
				openId = nil
				detail = nil
				load()
				return
			end
			if andReplay then
				replay(response.case)
				return
			end
			openId = id
			detail = response
			load()
		end)
	end

	-- List ---------------------------------------------------------------------------------

	local function caseCard(order: number, case: any)
		local card = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 6) })
		caseHead(card, case)
		local row = buttonRow(card, 5)
		smallButton(row, "Open", "secondary", function()
			openCase(case.id)
		end, 1)
		smallButton(row, "Replay", "primary", function()
			openCase(case.id, true)
		end, 2)
		if case.ticketId and ctx.can("tribune.handle") then
			smallButton(row, `Ticket #{case.ticketId}`, "ghost", function()
				ctx.open("Tribune", case.ticketId)
			end, 3)
		end
	end

	local function drawList()
		local count = #state.cases
		topLabel.Text = if count == 1 then "1 case file" else `{count} case files`
		local others = if state.others == "all"
			then " and of every other player on the server"
			elseif state.others == "none" then ""
			else ` and of the players within {state.radius} studs of them`
		local intro = `A case keeps the positions (every {state.interval} s), outfits, tools, Lictor detections, deaths and staff actions of the players involved{others}, from {state.window} s before a report (player or bug) or a Lictor alert until {state.after} s after it. It is saved once those seconds have passed, and deleted after {state.retention} days.`
		if not state.enabled then
			intro ..= " Recording is off (quaesitor.enabled in Settings)."
		end
		Components.paragraph(intro, {
			TextColor3 = if state.enabled then C.textFaint else C.warning,
			TextSize = Theme.sizes.small,
			LayoutOrder = 0,
			Parent = scroller,
		})
		if count == 0 then
			Components.paragraph("No case files.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = 1,
				Parent = scroller,
			})
		end
		for i, case in state.cases do
			caseCard(i, case)
		end
	end

	-- Case ----------------------------------------------------------------------------------

	local function drawDetail()
		local case = detail.case
		topLabel.Text = `Case #{case.id}`

		local card = Components.card({ LayoutOrder = 1, Parent = scroller }, { Components.stack("V", 6) })
		caseHead(card, case)
		local row = buttonRow(card, 5)
		smallButton(row, "Replay", "primary", function()
			replay(case)
		end, 1)
		if case.ticketId and detail.ticketAccess then
			smallButton(row, `Ticket #{case.ticketId}`, "ghost", function()
				ctx.open("Tribune", case.ticketId)
			end, 2)
		end
		Components.paragraph(
			"Replay hides the panel and shows the players in the world with their avatar, accessories and tools, on your screen only. Nobody else sees them, and your character does not move.",
			{
				TextSize = 12,
				TextColor3 = C.textFaint,
				LayoutOrder = 6,
				Parent = card,
			}
		)

		-- Who was recorded, and for how long.
		local people = Components.card({ LayoutOrder = 2, Parent = scroller }, { Components.stack("V", 6) })
		Components.section("Players", 0).Parent = people
		local othersShown = false
		for i, track in case.tracks do
			-- The players recorded with the involved ones come after them.
			if not othersShown and (track.role == "nearby" or track.role == "other") then
				othersShown = true
				Components.section(if track.role == "nearby" then "Nearby players" else "Other players", 3 * i - 1).Parent =
					people
			end
			local samples = track.samples
			local line = `{ROLES[track.role] or track.role}: {track.name} ({track.userId})`
			if #samples > 0 then
				line ..= `  ·  seen from {minutes(samples[1][1])} to {minutes(samples[#samples][1])}`
			else
				line ..= "  ·  no position recorded"
			end
			Components.paragraph(line, {
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = 3 * i,
				Parent = people,
			})
			if ctx.can("censor.view") then
				local recordRow = buttonRow(people, 3 * i + 1)
				smallButton(recordRow, `Record of {track.name}`, "ghost", function()
					ctx.open("Players", track.userId)
				end, 1)
			end
		end

		-- What happened, in order.
		local timeline = Components.card({ LayoutOrder = 3, Parent = scroller }, { Components.stack("V", 4) })
		Components.section("Events", 0).Parent = timeline
		if #case.events == 0 then
			Components.paragraph("Nothing happened to these players during the recording.", {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.textFaint,
				LayoutOrder = 1,
				Parent = timeline,
			})
		end
		for i, event in case.events do
			local kind = KINDS[event.kind] or { label = event.kind, color = C.text }
			local wall = os.date("%H:%M:%S", math.floor(case.startedAt + event.t)) :: string
			local line = create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = i,
				Parent = timeline,
			})
			Components.text({
				Text = `{minutes(event.t)}  {wall}`,
				FontFace = P.code,
				TextSize = 12,
				TextColor3 = C.textFaint,
				TextWrapped = false,
				Size = UDim2.new(0, 118, 0, 18),
				Parent = line,
			})
			Components.text({
				Text = string.upper(kind.label),
				FontFace = P.bold,
				TextSize = 11,
				TextColor3 = kind.color,
				TextWrapped = false,
				Position = UDim2.fromOffset(122, 0),
				Size = UDim2.new(0, 56, 0, 18),
				Parent = line,
			})
			Components.paragraph(event.text, {
				TextSize = 12,
				Position = UDim2.fromOffset(182, 1),
				Size = UDim2.new(1, -182, 0, 0),
				Parent = line,
			})
		end
	end

	local function draw()
		Components.clear(scroller)
		local inCase = detail ~= nil
		selector.Visible = not inCase
		backButton.Visible = inCase
		if inCase then
			drawDetail()
		elseif state then
			drawList()
		end
	end

	load = function()
		if openId and detail then
			draw()
			return
		end
		local response = ctx.request("quaesitor.list", { source = if source == "all" then nil else source })
		if response.ok then
			state = response
			detail = nil
			draw()
		else
			ctx.notify(ctx.errorMessage(response.err), "error")
		end
	end

	return {
		-- argument: a case id, or { id = number, replay = true }.
		show = function(argument: any?)
			if type(argument) == "number" then
				openCase(argument)
			elseif type(argument) == "table" and type(argument.id) == "number" then
				openCase(argument.id, argument.replay == true)
			else
				task.spawn(load)
			end
		end,
		update = function(kind: string)
			-- A case never changes once written: only the list needs refreshing.
			if kind ~= "quaesitor" or not frame.Visible or detail or pending then
				return
			end
			pending = true
			task.delay(REFRESH, function()
				pending = false
				if frame.Visible and not detail then
					load()
				end
			end)
		end,
	}
end
