--!strict
-- Palette du panneau : Purpura (Curia) sur fond sombre, accents Aurum.

return {
	couleurs = {
		fond = Color3.fromRGB(16, 12, 20),
		panneau = Color3.fromRGB(24, 19, 30),
		carte = Color3.fromRGB(34, 27, 42),
		carteSurvol = Color3.fromRGB(44, 35, 54),
		champ = Color3.fromRGB(20, 16, 26),
		bordure = Color3.fromRGB(62, 49, 74),

		purpura = Color3.fromRGB(122, 46, 142),
		purpuraClair = Color3.fromRGB(167, 91, 190),
		aurum = Color3.fromRGB(201, 162, 74),

		texte = Color3.fromRGB(237, 230, 242),
		texteDoux = Color3.fromRGB(168, 155, 179),
		texteFaible = Color3.fromRGB(112, 100, 124),

		danger = Color3.fromRGB(192, 69, 58),
		alerte = Color3.fromRGB(214, 140, 52),
		succes = Color3.fromRGB(78, 154, 106),
		info = Color3.fromRGB(96, 140, 200),
	},

	polices = {
		titre = Font.fromEnum(Enum.Font.Merriweather),
		texte = Font.fromEnum(Enum.Font.BuilderSans),
		gras = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
		moyen = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
		code = Font.fromEnum(Enum.Font.RobotoMono),
	},

	tailles = {
		petit = 13,
		normal = 15,
		grand = 18,
		titre = 22,
	},

	arrondi = UDim.new(0, 8),
	marge = 12,
}
