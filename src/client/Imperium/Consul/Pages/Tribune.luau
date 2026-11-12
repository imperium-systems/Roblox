--!strict
-- Tribune page: player reports, to claim and close.
-- Opening a ticket shows everything about it: the record, the log and the chat of both
-- players, teleports, and the closing comment sent to the webhook.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

-- Several tickets can change at once: redraw at most this often.
local REFRESH = 1
-- Below this width, the two players are shown one under the other.
local TWO_COLUMNS = 560

local function statusOf(ticket: any): (string, Color3)
	if ticket.status == "open" then
		return "Open", C.info
	elseif ticket.status == "claimed" then
		return `Claimed by {ticket.claimedBy}`, C.warning
	elseif ticket.outcome == "resolved" then
		return "Resolved", C.success
	end
	return "Dismissed", C.textMuted
end

local function clock(date: number): string
	return os.date("%H:%M:%S", date) :: string
end

return function(ctx: any, frame: Frame)
	local filter = "open"
	local state: any = nil
	local detail: any = nil
	local openId: number? = nil
	local pending = false
	local commentDraft = ""
	local commentBox: TextBox? = nil
	local load: () -> ()

	-- Top bar: filters for the list, Back in a ticket.
	local top = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = frame,
	})
	local selector = Components.selector({
		{ value = "open", label = "To handle" },
		{ value = "closed", label = "Closed" },
		{ value = "all", label = "All" },
	}, filter, function(value)
		filter = value
		task.spawn(load)
	end)
	selector.Parent = top
	local backButton = Components.button("Back to the list", "ghost", function()
		openId = nil
		detail = nil
		commentDraft = ""
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

	local function act(action: string, data: { [string]: any }, message: string)
		task.spawn(function()
			if ctx.execute(action, data, message) then
				load()
			end
		end)
	end

	local function buttonRow(parent: Instance, order: number): Frame
		local row = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = parent,
		})
		local layout = Components.stack("H", 6)
		layout.Wraps = true
		layout.Parent = row
		return row
	end

	local function smallButton(row: Instance, text: string, style: string, onClick: () -> (), order: number, active: boolean?)
		local b = Components.button(text, style :: any, onClick, {
			Size = UDim2.new(0, 0, 0, 28),
			LayoutOrder = order,
			Parent = row,
		})
		if active == false then
			Components.setEnabled(b, false)
		end
		return b
	end

	-- Claim / Release / Resolved / Dismiss, as the rank and the claim allow.
	local function ticketButtons(row: Instance, ticket: any, withClose: boolean)
		if ticket.status == "closed" then
			return
		end
		local free = ticket.status == "open" or ticket.claimedById == ctx.me or ctx.can("tribune.manage")
		if ticket.status == "open" then
			smallButton(row, "Claim", "primary", function()
				act("tribune.claim", { id = ticket.id }, `Report #{ticket.id} claimed.`)
			end, 2)
		elseif free then
			smallButton(row, "Release", "ghost", function()
				act("tribune.release", { id = ticket.id }, `Report #{ticket.id} released.`)
			end, 2)
		end
		if withClose and free then
			smallButton(row, "Resolved", "secondary", function()
				act("tribune.close", { id = ticket.id, outcome = "resolved" }, `Report #{ticket.id} closed as resolved.`)
			end, 3)
			smallButton(row, "Dismiss", "ghost", function()
				act("tribune.close", { id = ticket.id, outcome = "dismissed" }, `Report #{ticket.id} dismissed.`)
			end, 4)
		end
	end

	local function ticketHead(parent: Instance, ticket: any)
		local head = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = parent,
		})
		Components.text({
			Text = `#{ticket.id}  {ticket.categoryLabel}{if ticket.kind == "bug" then "  ·  Bug" else ""}`,
			FontFace = P.bold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -190, 1, 0),
			Parent = head,
		})
		local label, color = statusOf(ticket)
		local badge = Components.badge(label, color)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.fromScale(1, 0)
		badge.Parent = head

		local who = `From <b>{ticket.reporterName}</b>`
		if ticket.targetName then
			who ..= ` about <b>{ticket.targetName}</b>`
		end
		Components.paragraph(`{who}  ·  {Core.formatDate(ticket.date)}`, {
			RichText = true,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Parent = parent,
		})
		-- Player text: never as rich text.
		Components.paragraph(ticket.description, { LayoutOrder = 3, Parent = parent })
	end

	local function contextLine(parent: Instance, ticket: any, order: number)
		local details = {}
		for _, pair in ticket.context or {} do
			table.insert(details, `{pair[1]}: <font color="#F1EADB">{pair[2]}</font>`)
		end
		if #details > 0 then
			Components.paragraph(table.concat(details, "   ·   "), {
				RichText = true,
				TextSize = 12,
				TextColor3 = C.textFaint,
				LayoutOrder = order,
				Parent = parent,
			})
		end
	end

	-- List ---------------------------------------------------------------------------------

	local function ticketCard(order: number, ticket: any)
		local card = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 6) })
		if ticket.status == "open" then
			Components.stroke(C.info).Parent = card
		end
		ticketHead(card, ticket)
		if ticket.status == "closed" and ticket.comment then
			Components.paragraph(`Comment: {ticket.comment}`, {
				TextSize = Theme.sizes.small,
				TextColor3 = C.textMuted,
				LayoutOrder = 4,
				Parent = card,
			})
		end
		local row = buttonRow(card, 5)
		smallButton(row, "Open", "secondary", function()
			openId = ticket.id
			commentDraft = ""
			task.spawn(load)
		end, 1)
		ticketButtons(row, ticket, false)
	end

	local function drawList()
		local hooks = {}
		for name, on in state.webhooks or {} do
			if on then
				table.insert(hooks, name)
			end
		end
		table.sort(hooks)
		local webhooks = if #hooks > 0
			then `Webhooks on: {table.concat(hooks, ", ")}.`
			else "No webhook configured (Config > Nuntius)."
		topLabel.Text = if state.openCount == 1 then "1 report to handle" else `{state.openCount} reports to handle`
		Components.paragraph(
			`Open a report to see both players, their chat and teleports, and to close it with a comment. {webhooks}`,
			{ TextColor3 = C.textFaint, TextSize = Theme.sizes.small, LayoutOrder = 0, Parent = scroller }
		)
		if #state.tickets == 0 then
			Components.paragraph(if filter == "open" then "Nothing to handle." else "No reports.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small + 1,
				LayoutOrder = 1,
				Parent = scroller,
			})
		end
		for i, ticket in state.tickets do
			ticketCard(i, ticket)
		end
	end

	-- Ticket -------------------------------------------------------------------------------

	local function personColumn(parent: Instance, order: number, role: string, person: any, chat: { any }?, width: UDim2)
		local column = Components.card({
			Size = width,
			LayoutOrder = order,
			Parent = parent,
		}, { Components.stack("V", 6) })

		Components.section(role, 0).Parent = column
		local nameRow = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = column,
		})
		Components.text({
			Text = person.displayName or person.name,
			FontFace = P.bold,
			TextSize = Theme.sizes.large,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -150, 1, 0),
			Parent = nameRow,
		})
		local badge = if person.online
			then Components.badge("On this server", C.success)
			else Components.badge("Not here", C.textFaint)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.fromScale(1, 0)
		badge.Parent = nameRow

		local facts = { `@{person.name}  ·  {person.userId}` }
		if person.rank then
			table.insert(facts, `Rank: {person.rank}`)
		end
		if person.firstSeen then
			table.insert(facts, `First seen: {Core.formatDate(person.firstSeen)}`)
		end
		if person.playtime then
			table.insert(facts, `Playtime: {Core.formatDuration(person.playtime)}`)
		end
		table.insert(facts, `Warnings: {person.warnings}  ·  Sanctions: {person.sanctionCount}`)
		if person.lictor then
			table.insert(facts, `Lictor score: {person.lictor}`)
		end
		Components.paragraph(table.concat(facts, "\n"), {
			TextSize = Theme.sizes.small + 1,
			TextColor3 = C.textMuted,
			LayoutOrder = 2,
			Parent = column,
		})
		if person.ban then
			local until_ = if person.ban.expiresAt then Core.formatDate(person.ban.expiresAt) else "permanent"
			Components.paragraph(`Banned until {until_}: {person.ban.reason}`, {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.danger,
				LayoutOrder = 3,
				Parent = column,
			})
		end
		if person.mute then
			local until_ = if person.mute.expiresAt then Core.formatDate(person.mute.expiresAt) else "permanent"
			Components.paragraph(`Muted until {until_}: {person.mute.reason}`, {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.warning,
				LayoutOrder = 4,
				Parent = column,
			})
		end

		local function list(title: string, lines: { string }, empty: string, listOrder: number)
			Components.section(title, listOrder).Parent = column
			Components.paragraph(if #lines > 0 then table.concat(lines, "\n") else empty, {
				TextSize = 12,
				TextColor3 = if #lines > 0 then C.text else C.textFaint,
				LayoutOrder = listOrder + 1,
				Parent = column,
			})
		end

		if chat ~= nil then
			local lines = {}
			for _, line in chat do
				table.insert(lines, `[{clock(line.date)}] {line.text}`)
			end
			list("Chat before the report", lines, "Nothing written in the last 5 minutes.", 10)
		end

		local sanctions = {}
		for _, sanction in person.sanctions do
			table.insert(sanctions, `{Core.formatDate(sanction.date)}  {sanction.type} by {sanction.by}: {sanction.reason}`)
		end
		list("Last sanctions", sanctions, "None.", 20)

		local log = {}
		for _, entry in person.log do
			local line = `{Core.formatDate(entry.date)}  {entry.actor} · {entry.action}`
			if entry.target then
				line ..= ` · {entry.target}`
			end
			if entry.details then
				line ..= `: {entry.details}`
			end
			table.insert(log, line)
		end
		list("Log", log, "No staff action about this player.", 30)

		if ctx.can("censor.view") then
			local row = buttonRow(column, 40)
			smallButton(row, "Full record", "ghost", function()
				ctx.open("Players", person.userId)
			end, 1)
		end
	end

	local function teleportCard(order: number, ticket: any)
		if not ctx.can("consul.teleport") then
			return
		end
		local card = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 8) })
		Components.section("Teleport", 0).Parent = card
		local people = { { role = "Reporter", person = detail.reporter } }
		if detail.target then
			table.insert(people, { role = "Reported", person = detail.target })
		end

		local function move(person: any, direction: string, slot: number, message: string)
			act("teleport", { userId = person.userId, direction = direction, slot = slot }, message)
		end

		for i, entry in people do
			local person = entry.person
			local row = buttonRow(card, i)
			Components.text({
				Text = `{entry.role}: {person.name}`,
				FontFace = P.medium,
				TextSize = Theme.sizes.small + 1,
				Size = UDim2.new(0, 170, 0, 28),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				LayoutOrder = 0,
				Parent = row,
			})
			local here = person.online
			local canMove = here and person.canAct
			smallButton(row, "Go to", "secondary", function()
				move(person, "to", 0, `Teleported to {person.name}.`)
			end, 1, here)
			smallButton(row, "Bring", "secondary", function()
				move(person, "bring", i, `{person.name} brought to you.`)
			end, 2, canMove)
			smallButton(row, "To point", "ghost", function()
				move(person, "point", i, `{person.name} sent to the staff point.`)
			end, 3, canMove and detail.staffPoint)
		end

		if detail.target then
			local row = buttonRow(card, 10)
			Components.text({
				Text = "Both",
				FontFace = P.medium,
				TextSize = Theme.sizes.small + 1,
				Size = UDim2.new(0, 170, 0, 28),
				LayoutOrder = 0,
				Parent = row,
			})
			local both = detail.reporter.online and detail.target.online and detail.reporter.canAct and detail.target.canAct
			local function moveBoth(direction: string, message: string)
				task.spawn(function()
					local first = ctx.execute("teleport", { userId = detail.reporter.userId, direction = direction, slot = 1 })
					local second = ctx.execute("teleport", { userId = detail.target.userId, direction = direction, slot = 2 })
					if first and second then
						ctx.notify(message, "success")
					end
				end)
			end
			smallButton(row, "Bring both", "secondary", function()
				moveBoth("bring", "Both players brought to you.")
			end, 1, both)
			smallButton(row, "Both to point", "ghost", function()
				moveBoth("point", "Both players sent to the staff point.")
			end, 2, both and detail.staffPoint)
		end

		local notes = {}
		if not detail.staffPoint then
			table.insert(notes, "No staff point: add a part named ImperiumStaffPoint in Workspace to send players there.")
		end
		if not detail.reporter.online or (detail.target and not detail.target.online) then
			table.insert(notes, "Teleports only reach players on this server.")
		end
		if #notes > 0 then
			Components.paragraph(table.concat(notes, " "), {
				TextSize = 12,
				TextColor3 = C.textFaint,
				LayoutOrder = 20,
				Parent = card,
			})
		end
	end

	-- Quaesitor case file of a report: the minutes around it, for the players involved.
	local function caseCard(order: number, ticket: any)
		if not ctx.can("quaesitor.view") then
			return
		end
		local card = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 8) })
		Components.section("Case file", 0).Parent = card
		local case = detail.case
		if not case then
			Components.paragraph(
				"No case file yet: it is saved a few seconds after the report (quaesitor.after in Settings), unless recording was off.",
				{ TextSize = Theme.sizes.small + 1, TextColor3 = C.textFaint, LayoutOrder = 1, Parent = card }
			)
			return
		end
		local events = if case.eventCount == 1 then "1 event" else `{case.eventCount} events`
		local who = if ticket.kind == "bug" then "the reporter" else "both players"
		local before = math.floor(case.triggerAt or case.duration)
		local after = math.floor(case.duration - before)
		Components.paragraph(
			`Case #{case.id}: positions of {who} from {before} s before the report to {after} s after it, {events}. Deleted on {Core.formatDate(case.expiresAt)}.`,
			{ TextSize = Theme.sizes.small + 1, TextColor3 = C.textMuted, LayoutOrder = 1, Parent = card }
		)
		local row = buttonRow(card, 2)
		smallButton(row, "Replay", "primary", function()
			ctx.open("Quaesitor", { id = case.id, replay = true })
		end, 1)
		smallButton(row, "Open case", "secondary", function()
			ctx.open("Quaesitor", case.id)
		end, 2)
	end

	local function closingCard(order: number, ticket: any)
		local card = Components.card({ LayoutOrder = order, Parent = scroller }, { Components.stack("V", 8) })
		if ticket.status == "closed" then
			Components.section("Closed", 0).Parent = card
			local outcome = if ticket.outcome == "resolved" then "Resolved" else "Dismissed"
			Components.paragraph(`{outcome} by {ticket.closedBy or "?"}, {Core.formatDate(ticket.updated)}.`, {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.textMuted,
				LayoutOrder = 1,
				Parent = card,
			})
			Components.paragraph(ticket.comment or "No comment.", {
				TextColor3 = if ticket.comment then C.text else C.textFaint,
				LayoutOrder = 2,
				Parent = card,
			})
			return
		end

		Components.section("Handling", 0).Parent = card
		local free = ticket.status == "open" or ticket.claimedById == ctx.me or ctx.can("tribune.manage")
		local claimRow = buttonRow(card, 1)
		ticketButtons(claimRow, ticket, false)
		if not free then
			Components.paragraph(`{ticket.claimedBy} is handling this report.`, {
				TextSize = Theme.sizes.small + 1,
				TextColor3 = C.textMuted,
				LayoutOrder = 2,
				Parent = card,
			})
			return
		end

		local box = Components.field("Short comment for the record and the webhook (optional).", {
			Text = commentDraft,
			MultiLine = true,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 70),
			LayoutOrder = 3,
			Parent = card,
		})
		local padding = box:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingTop = UDim.new(0, 8)
			padding.PaddingBottom = UDim.new(0, 8)
		end
		commentBox = box
		local counter = Components.text({
			Text = `{#commentDraft}/{detail.maxComment}`,
			TextSize = 12,
			TextColor3 = C.textFaint,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = 4,
			Parent = card,
		})
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > detail.maxComment then
				box.Text = string.sub(box.Text, 1, detail.maxComment)
				return
			end
			commentDraft = box.Text
			counter.Text = `{#box.Text}/{detail.maxComment}`
		end)

		local row = buttonRow(card, 5)
		local function close(outcome: string, message: string)
			task.spawn(function()
				local data = { id = ticket.id, outcome = outcome, comment = commentDraft }
				if ctx.execute("tribune.close", data, message) then
					commentDraft = ""
					load()
				end
			end)
		end
		smallButton(row, "Close as resolved", "primary", function()
			close("resolved", `Report #{ticket.id} closed as resolved.`)
		end, 1)
		smallButton(row, "Dismiss", "ghost", function()
			close("dismissed", `Report #{ticket.id} dismissed.`)
		end, 2)
		Components.paragraph("The reporter is told the report was handled, without your name, the sanction or this comment.", {
			TextSize = 12,
			TextColor3 = C.textFaint,
			LayoutOrder = 6,
			Parent = card,
		})
	end

	local function drawDetail()
		local ticket = detail.ticket
		topLabel.Text = `Report #{ticket.id}`

		local card = Components.card({ LayoutOrder = 1, Parent = scroller }, { Components.stack("V", 6) })
		if ticket.status == "open" then
			Components.stroke(C.info).Parent = card
		end
		ticketHead(card, ticket)
		contextLine(card, ticket, 4)

		closingCard(2, ticket)
		caseCard(3, ticket)
		teleportCard(4, ticket)

		-- The two players side by side, or one under the other on a narrow window.
		local wide = scroller.AbsoluteSize.X >= TWO_COLUMNS and detail.target ~= nil
		local holder = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 5,
			Parent = scroller,
		})
		local layout = Components.stack(if wide then "H" else "V", 10)
		layout.Parent = holder
		local width = if wide then UDim2.new(0.5, -5, 0, 0) else UDim2.new(1, 0, 0, 0)
		local chat = ticket.chat
		local pendingChat = ticket.kind == "player" and chat == nil
		personColumn(holder, 1, "Reporter", detail.reporter, if chat then chat.reporter else nil, width)
		if detail.target then
			personColumn(holder, 2, "Reported player", detail.target, if chat then chat.target else nil, width)
		end
		if pendingChat then
			Components.paragraph("The chat is still going through the Roblox filter: it appears in a few seconds.", {
				TextSize = 12,
				TextColor3 = C.textFaint,
				LayoutOrder = 6,
				Parent = scroller,
			})
		end
	end

	local function draw()
		Components.clear(scroller)
		commentBox = nil
		local inTicket = detail ~= nil
		selector.Visible = not inTicket
		backButton.Visible = inTicket
		if inTicket then
			drawDetail()
		elseif state then
			drawList()
		end
	end

	load = function()
		if openId then
			local response = ctx.request("tribune.detail", { id = openId })
			if response.ok then
				detail = response
				draw()
			else
				ctx.notify(ctx.errorMessage(response.err), "error")
				openId = nil
				detail = nil
				load()
			end
			return
		end
		local response = ctx.request("tribune.list", { filter = filter })
		if response.ok then
			state = response
			detail = nil
			draw()
		else
			ctx.notify(ctx.errorMessage(response.err), "error")
		end
	end

	return {
		-- argument: a ticket id to open directly (from a case file).
		show = function(id: number?)
			if type(id) == "number" then
				openId = id
				commentDraft = ""
			end
			task.spawn(load)
		end,
		update = function(kind: string, data: any)
			if kind ~= "tribune" or not frame.Visible or pending then
				return
			end
			-- In a ticket, only its own changes matter.
			if openId and data ~= openId then
				return
			end
			pending = true
			task.delay(REFRESH, function()
				pending = false
				local box = commentBox
				-- Do not redraw under someone typing their comment.
				if box and box:IsFocused() then
					return
				end
				if frame.Visible then
					load()
				end
			end)
		end,
	}
end
