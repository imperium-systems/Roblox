--!strict
-- Interface building blocks for the panel.
-- Temporary: these components will move to Fenestra once it exists.

local TweenService = game:GetService("TweenService")

local Logos = require(script.Parent.Logos)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local P = Theme.fonts
local T = Theme.sizes

local Components = {}

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ACCENTS: { [string]: string } = {
	["é"] = "É",
	["è"] = "È",
	["ê"] = "Ê",
	["à"] = "À",
	["â"] = "Â",
	["ç"] = "Ç",
	["î"] = "Î",
	["ô"] = "Ô",
	["ù"] = "Ù",
	["û"] = "Û",
}

-- string.upper does not handle accented letters.
function Components.uppercase(text: string): string
	local result = string.upper(text)
	for lowerChar, upperChar in ACCENTS do
		result = (string.gsub(result, lowerChar, upperChar))
	end
	return result
end

-- create("Frame", { Size = ... }, { child1, child2 })
function Components.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local object = Instance.new(className) :: any
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			object[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = object
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local create = Components.create

function Components.corners(radius: UDim?): UICorner
	return create("UICorner", { CornerRadius = radius or Theme.radius })
end

function Components.stroke(color: Color3?, thickness: number?): UIStroke
	return create("UIStroke", {
		Color = color or C.border,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function Components.stack(direction: "V" | "H", gap: number?, alignment: Enum.HorizontalAlignment?): UIListLayout
	return create("UIListLayout", {
		FillDirection = if direction == "H" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if direction == "H" then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Wraps = direction == "H",
	})
end

function Components.text(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = P.text,
		TextSize = T.normal,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = false,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for key, value in props do
		p[key] = value
	end
	return create("TextLabel", p)
end

-- A line of text that grows with its content.
function Components.paragraph(text: string, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = {
		Text = text,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextYAlignment = Enum.TextYAlignment.Top,
	}
	for key, value in props or {} do
		p[key] = value
	end
	return Components.text(p)
end

export type ButtonStyle = "primary" | "brand" | "secondary" | "danger" | "ghost"

local STYLES: { [string]: { background: Color3, hover: Color3, text: Color3, stroke: Color3? } } = {
	primary = { background = C.accent, hover = C.accentHover, text = C.onAccent },
	brand = { background = C.aurum, hover = C.text, text = C.onAccent },
	secondary = { background = C.card, hover = C.cardHover, text = C.text, stroke = C.textMuted },
	danger = { background = C.dangerSoft, hover = C.cardHover, text = C.danger, stroke = C.danger },
	ghost = { background = C.panel, hover = C.cardHover, text = C.textMuted },
}

function Components.button(
	label: string,
	style: ButtonStyle,
	onClick: () -> (),
	props: { [string]: any }?
): TextButton
	local s = STYLES[style]
	local p: { [string]: any } = {
		Text = Components.uppercase(label),
		FontFace = P.bold,
		TextSize = T.small,
		TextColor3 = s.text,
		BackgroundColor3 = s.background,
		AutoButtonColor = false,
		Size = UDim2.new(0, 0, 0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
	}
	for key, value in props or {} do
		p[key] = value
	end
	local children: { Instance } = { Components.corners(Theme.radiusSmall), Components.padding(0, Theme.margin) }
	if s.stroke then
		table.insert(children, Components.stroke(s.stroke))
	end
	local button = create("TextButton", p, children) :: TextButton

	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(button, FAST, { BackgroundColor3 = s.hover }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, FAST, { BackgroundColor3 = s.background }):Play()
	end)
	button.Activated:Connect(function()
		if button.Active then
			onClick()
		end
	end)
	return button
end

function Components.setEnabled(button: GuiButton, active: boolean)
	button.Active = active
	button.AutoButtonColor = false
	if button:IsA("TextButton") then
		button.TextTransparency = if active then 0 else 0.55
	end
	button.BackgroundTransparency = if active then 0 else 0.4
end

function Components.field(placeholder: string, props: { [string]: any }?): TextBox
	local p: { [string]: any } = {
		PlaceholderText = placeholder,
		Text = "",
		FontFace = P.text,
		TextSize = T.normal,
		TextColor3 = C.text,
		PlaceholderColor3 = C.textFaint,
		BackgroundColor3 = C.field,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 34),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props or {} do
		p[key] = value
	end
	local field = create("TextBox", p, {
		Components.corners(Theme.radiusSmall),
		Components.padding(0, 10),
	}) :: TextBox
	local stroke = Components.stroke()
	stroke.Parent = field
	field.Focused:Connect(function()
		stroke.Color = C.accentHover
	end)
	field.FocusLost:Connect(function()
		stroke.Color = C.border
	end)
	return field
end

-- Section label, small gold capitals.
function Components.section(label: string, order: number?): TextLabel
	return Components.text({
		Text = Components.uppercase(label),
		FontFace = P.bold,
		TextSize = T.small,
		TextColor3 = C.aurum,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order or 0,
	})
end

function Components.card(props: { [string]: any }?, children: { Instance }?): Frame
	local p: { [string]: any } = {
		BackgroundColor3 = C.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for key, value in props or {} do
		p[key] = value
	end
	local all: { Instance } = { Components.corners(), Components.padding(Theme.margin) }
	for _, e in children or {} do
		table.insert(all, e)
	end
	return create("Frame", p, all)
end

-- Scrolling area with a vertical stack.
function Components.scroller(props: { [string]: any }?, gap: number?): ScrollingFrame
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for key, value in props or {} do
		p[key] = value
	end
	return create("ScrollingFrame", p, {
		Components.stack("V", gap or 8),
		Components.padding(2, 8, 2, 2),
	})
end

-- On/off toggle. Returns the frame and a function that sets the state without a callback.
function Components.toggle(state: boolean, onChange: (boolean) -> ()): (TextButton, (boolean) -> ())
	local current = state
	local background = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(0, 44, 0, 24),
		BackgroundColor3 = C.border,
	}, { Components.corners(Theme.radiusSmall) }) :: TextButton
	local knob = create("Frame", {
		Size = UDim2.new(0, 18, 0, 18),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = C.text,
		Parent = background,
	}, { Components.corners(Theme.radiusSmall) })

	local function display(value: boolean)
		current = value
		TweenService:Create(background, FAST, { BackgroundColor3 = if value then C.accent else C.border }):Play()
		TweenService:Create(knob, FAST, {
			Position = if value then UDim2.new(1, -21, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end
	display(state)

	background.Activated:Connect(function()
		display(not current)
		onChange(current)
	end)
	return background, display
end

-- Exclusive choice between a few options.
function Components.selector(
	options: { { value: string, label: string } },
	value: string,
	onChange: (string) -> ()
): Frame
	local frame = create("Frame", {
		BackgroundColor3 = C.field,
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		Components.corners(Theme.radiusSmall),
		Components.padding(3),
		Components.stack("H", 3),
	})
	local buttons: { [string]: TextButton } = {}
	local function choose(v: string)
		for key, b in buttons do
			b.BackgroundColor3 = if key == v then C.accent else C.field
			b.TextColor3 = if key == v then C.onAccent else C.textMuted
		end
	end
	for i, option in options do
		buttons[option.value] = create("TextButton", {
			Text = Components.uppercase(option.label),
			FontFace = P.bold,
			TextSize = T.small,
			AutoButtonColor = false,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = frame,
		}, { Components.corners(Theme.radiusSmall), Components.padding(0, 12) })
		buttons[option.value].Activated:Connect(function()
			choose(option.value)
			onChange(option.value)
		end)
	end
	choose(value)
	return frame
end

-- Status badge (online, banned...): tinted background, diamond bullet.
function Components.badge(label: string, color: Color3): Frame
	return create("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		Size = UDim2.new(0, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		Components.corners(Theme.radiusSmall),
		Components.padding(0, 8),
		Components.stack("H", 6),
		create("Frame", {
			Size = UDim2.fromOffset(6, 6),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}),
		Components.text({
			Text = Components.uppercase(label),
			FontFace = P.bold,
			TextSize = 11,
			TextColor3 = color,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 1,
		}),
	})
end

-- Family insignia: the body, then the tinted white piece. Nil until it has been imported.
function Components.insignia(family: string, size: number, color: Color3): Frame?
	local insignia = Logos.insignias[family]
	if not insignia or insignia.body == 0 or insignia.color == 0 then
		return nil
	end
	local function layer(id: number, tint: Color3): ImageLabel
		return create("ImageLabel", {
			Image = `rbxassetid://{id}`,
			ImageColor3 = tint,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
	end
	return create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	}, {
		layer(insignia.body, Color3.new(1, 1, 1)),
		layer(insignia.color, color),
	})
end

function Components.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end

return Components
