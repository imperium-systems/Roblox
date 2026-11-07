--!strict
-- Dark theme of the Imperium design system (tokens.json).
-- Stone, not plastic: nearly sharp corners, thin lines, no pills, no gradients.

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"

return {
	colors = {
		background = Color3.fromHex("#13110F"), -- surface
		panel = Color3.fromHex("#1D1A17"), -- surface-raised
		card = Color3.fromHex("#1D1A17"),
		cardHover = Color3.fromHex("#2A2622"), -- hover, not a token
		field = Color3.fromHex("#13110F"),
		border = Color3.fromHex("#3A342C"), -- line

		accent = Color3.fromHex("#E8A0EC"), -- curia: Consul belongs to the Curia
		accentHover = Color3.fromHex("#F2C4F4"), -- hover, not a token
		aurum = Color3.fromHex("#D9B45B"), -- core
		onAccent = Color3.fromHex("#13110F"),

		text = Color3.fromHex("#F1EADB"), -- ink
		textMuted = Color3.fromHex("#B3A895"), -- ink-muted
		textFaint = Color3.fromHex("#8A8071"), -- dimmed, not a token

		danger = Color3.fromHex("#F27777"),
		dangerSoft = Color3.fromHex("#45181A"),
		warning = Color3.fromHex("#E9BE52"), -- warning
		success = Color3.fromHex("#74C67A"),
		info = Color3.fromHex("#93BEFF"), -- viae
	},

	fonts = {
		-- Roblox does not ship Cinzel: Merriweather replaces it for written titles.
		-- The IMPERIUM name itself is an image (see Logos).
		title = Font.fromEnum(Enum.Font.Merriweather),
		text = Font.new(MONTSERRAT, Enum.FontWeight.Medium),
		medium = Font.new(MONTSERRAT, Enum.FontWeight.SemiBold),
		bold = Font.new(MONTSERRAT, Enum.FontWeight.Bold),
		code = Font.fromEnum(Enum.Font.RobotoMono),
	},

	sizes = {
		small = 12,
		normal = 14,
		large = 16,
		title = 22,
	},

	radius = UDim.new(0, 4), -- radius-md: panels and windows
	radiusSmall = UDim.new(0, 2), -- radius-sm: buttons, badges, fields
	margin = 16,
}
