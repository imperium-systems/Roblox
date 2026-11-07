--!strict
-- Settings page: reads and live-edits the settings declared in Lex.
-- Changes apply to this server until it closes.

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Components = require(Consul.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

return function(ctx: any, frame: Frame)
	local scroller = Components.scroller({ Parent = frame }, 8)

	local load: () -> ()

	local function send(key: string, data: { [string]: any })
		data.key = key
		task.spawn(function()
			if not ctx.execute("lex.edit", data, `{key} updated.`) then
				load()
			end
		end)
	end

	local function row(order: number, r: any)
		local card = Components.card({ LayoutOrder = order, Parent = scroller })
		local changed = r.value ~= r.default

		Components.text({
			Text = r.key,
			FontFace = P.code,
			TextSize = Theme.sizes.small + 1,
			TextColor3 = if changed then C.aurum else C.text,
			Size = UDim2.new(0.55, 0, 0, 18),
			Parent = card,
		})
		local limits = ""
		if r.min or r.max then
			limits = `  (from {r.min or "—"} to {r.max or "—"})`
		end
		Components.text({
			Text = r.description .. limits,
			TextSize = Theme.sizes.small,
			TextColor3 = C.textMuted,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(0.55, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})

		local commands = create("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.45, 0, 0, 34),
			Parent = card,
		}, { Components.stack("H", 6, Enum.HorizontalAlignment.Right) })

		if r.type == "boolean" then
			local button = Components.toggle(r.value, function(v)
				send(r.key, { value = v })
			end)
			button.Parent = commands
		else
			local field = Components.field(tostring(r.default), {
				Text = tostring(r.value),
				Size = UDim2.new(1, -110, 0, 34),
				LayoutOrder = 1,
				Parent = commands,
			})
			Components.button("Apply", "primary", function()
				local value: any = field.Text
				if r.type == "number" then
					value = tonumber(field.Text)
					if value == nil then
						ctx.notify("This setting expects a number.", "error")
						return
					end
				end
				send(r.key, { value = value })
			end, { LayoutOrder = 2, Parent = commands })
		end

		if changed then
			Components.button("Default", "ghost", function()
				send(r.key, { reset = true })
			end, { LayoutOrder = 3, Parent = commands })
		end
	end

	load = function()
		local response = ctx.request("lex.list")
		Components.clear(scroller)
		if not response.ok then
			Components.paragraph(ctx.errorMessage(response.err), { TextColor3 = C.danger, Parent = scroller })
			return
		end
		Components.paragraph(
			"Gold values differ from their default. A change applies to this server until it closes.",
			{ TextColor3 = C.textFaint, TextSize = Theme.sizes.small, LayoutOrder = 0, Parent = scroller }
		)
		for i, r in response.settings do
			row(i, r)
		end
	end

	return {
		show = function()
			task.spawn(load)
		end,
		update = function(kind: string)
			if kind == "settings" and frame.Visible then
				task.spawn(load)
			end
		end,
	}
end
