--!strict
-- Log page: staff actions kept by Censor, most recent first, live.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("ImperiumShared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

return function(ctx: any, frame: Frame)
	local filter = Components.field("Filter by staff, player or action…", { Parent = frame })
	local scroller = Components.scroller({
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		Parent = frame,
	}, 6)

	local entries: { any } = {}

	local function matches(e: any, query: string): boolean
		if query == "" then
			return true
		end
		for _, field in { e.actor, e.action, e.target, e.details } do
			if field and string.find(string.lower(field), query, 1, true) then
				return true
			end
		end
		return false
	end

	local function draw()
		Components.clear(scroller)
		local query = string.lower(filter.Text)
		local n = 0
		for _, e in entries do
			if not matches(e, query) then
				continue
			end
			n += 1
			local row = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.card,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = n,
				Parent = scroller,
			}, { Components.corners(Theme.radiusSmall), Components.padding(8, 12), Components.stack("V", 2) })

			local summary = `{e.actor}  ·  {e.action}`
			if e.target then
				summary ..= `  →  {e.target}`
			end
			local top = create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 1,
				Parent = row,
			})
			Components.text({
				Text = summary,
				FontFace = P.medium,
				TextSize = Theme.sizes.small + 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -130, 1, 0),
				Parent = top,
			})
			Components.text({
				Text = Core.formatDate(e.date),
				TextSize = 12,
				TextColor3 = C.textFaint,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 125, 1, 0),
				Parent = top,
			})
			if e.details and e.details ~= "—" then
				Components.paragraph(e.details, {
					TextSize = Theme.sizes.small,
					TextColor3 = C.textMuted,
					LayoutOrder = 2,
					Parent = row,
				})
			end

			-- Clicking an entry that targets a player opens their record.
			if e.targetId and ctx.can("censor.view") then
				row.Activated:Connect(function()
					ctx.open("Players", e.targetId)
				end)
			end
		end
		if n == 0 then
			Components.paragraph(if #entries == 0 then "No recorded actions." else "No results.", {
				TextColor3 = C.textFaint,
				TextSize = Theme.sizes.small,
				Parent = scroller,
			})
		end
	end

	filter:GetPropertyChangedSignal("Text"):Connect(draw)

	local function load()
		local response = ctx.request("censor.log")
		if response.ok then
			entries = response.entries
			draw()
		end
	end

	return {
		show = function()
			task.spawn(load)
		end,
		update = function(kind: string, entry: any)
			if kind == "log" and type(entry) == "table" then
				table.insert(entries, 1, entry)
				if frame.Visible then
					draw()
				end
			end
		end,
	}
end
