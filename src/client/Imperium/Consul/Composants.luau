--!strict
-- Briques d'interface du panneau.
-- Provisoire : ces composants rejoindront Fenestra quand elle existera.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local C = Theme.couleurs
local P = Theme.polices
local T = Theme.tailles

local Composants = {}

local RAPIDE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- creer("Frame", { Size = ... }, { enfant1, enfant2 })
function Composants.creer(classe: string, proprietes: { [string]: any }?, enfants: { Instance }?): any
	local objet = Instance.new(classe) :: any
	local parent = nil
	for cle, valeur in proprietes or {} do
		if cle == "Parent" then
			parent = valeur
		else
			objet[cle] = valeur
		end
	end
	for _, enfant in enfants or {} do
		enfant.Parent = objet
	end
	if parent then
		objet.Parent = parent
	end
	return objet
end

local creer = Composants.creer

function Composants.coins(rayon: UDim?): UICorner
	return creer("UICorner", { CornerRadius = rayon or Theme.arrondi })
end

function Composants.contour(couleur: Color3?, epaisseur: number?): UIStroke
	return creer("UIStroke", {
		Color = couleur or C.bordure,
		Thickness = epaisseur or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Composants.marges(haut: number, droite: number?, bas: number?, gauche: number?): UIPadding
	return creer("UIPadding", {
		PaddingTop = UDim.new(0, haut),
		PaddingRight = UDim.new(0, droite or haut),
		PaddingBottom = UDim.new(0, bas or haut),
		PaddingLeft = UDim.new(0, gauche or droite or haut),
	})
end

function Composants.pile(direction: "V" | "H", ecart: number?, alignement: Enum.HorizontalAlignment?): UIListLayout
	return creer("UIListLayout", {
		FillDirection = if direction == "H" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, ecart or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = alignement or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if direction == "H" then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Wraps = direction == "H",
	})
end

function Composants.texte(proprietes: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = P.texte,
		TextSize = T.normal,
		TextColor3 = C.texte,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = false,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for cle, valeur in proprietes do
		p[cle] = valeur
	end
	return creer("TextLabel", p)
end

-- Une ligne de texte qui s'adapte en hauteur.
function Composants.paragraphe(texte: string, proprietes: { [string]: any }?): TextLabel
	local p: { [string]: any } = {
		Text = texte,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextYAlignment = Enum.TextYAlignment.Top,
	}
	for cle, valeur in proprietes or {} do
		p[cle] = valeur
	end
	return Composants.texte(p)
end

export type StyleBouton = "primaire" | "secondaire" | "danger" | "fantome"

local STYLES: { [string]: { fond: Color3, survol: Color3, texte: Color3, contour: Color3? } } = {
	primaire = { fond = C.purpura, survol = C.purpuraClair, texte = C.texte },
	secondaire = { fond = C.carte, survol = C.carteSurvol, texte = C.texte, contour = C.bordure },
	danger = { fond = Color3.fromRGB(110, 36, 32), survol = C.danger, texte = C.texte },
	fantome = { fond = C.panneau, survol = C.carte, texte = C.texteDoux },
}

function Composants.bouton(
	libelle: string,
	style: StyleBouton,
	auClic: () -> (),
	proprietes: { [string]: any }?
): TextButton
	local s = STYLES[style]
	local p: { [string]: any } = {
		Text = libelle,
		FontFace = P.moyen,
		TextSize = T.normal,
		TextColor3 = s.texte,
		BackgroundColor3 = s.fond,
		AutoButtonColor = false,
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
	}
	for cle, valeur in proprietes or {} do
		p[cle] = valeur
	end
	local enfants: { Instance } = { Composants.coins(UDim.new(0, 6)), Composants.marges(0, 14) }
	if s.contour then
		table.insert(enfants, Composants.contour(s.contour))
	end
	local bouton = creer("TextButton", p, enfants) :: TextButton

	bouton.MouseEnter:Connect(function()
		if bouton.Active then
			TweenService:Create(bouton, RAPIDE, { BackgroundColor3 = s.survol }):Play()
		end
	end)
	bouton.MouseLeave:Connect(function()
		TweenService:Create(bouton, RAPIDE, { BackgroundColor3 = s.fond }):Play()
	end)
	bouton.Activated:Connect(function()
		if bouton.Active then
			auClic()
		end
	end)
	return bouton
end

function Composants.activer(bouton: GuiButton, actif: boolean)
	bouton.Active = actif
	bouton.AutoButtonColor = false
	if bouton:IsA("TextButton") then
		bouton.TextTransparency = if actif then 0 else 0.55
	end
	bouton.BackgroundTransparency = if actif then 0 else 0.4
end

function Composants.champ(indication: string, proprietes: { [string]: any }?): TextBox
	local p: { [string]: any } = {
		PlaceholderText = indication,
		Text = "",
		FontFace = P.texte,
		TextSize = T.normal,
		TextColor3 = C.texte,
		PlaceholderColor3 = C.texteFaible,
		BackgroundColor3 = C.champ,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 34),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for cle, valeur in proprietes or {} do
		p[cle] = valeur
	end
	local champ = creer("TextBox", p, {
		Composants.coins(UDim.new(0, 6)),
		Composants.marges(0, 10),
	}) :: TextBox
	local contour = Composants.contour()
	contour.Parent = champ
	champ.Focused:Connect(function()
		contour.Color = C.purpuraClair
	end)
	champ.FocusLost:Connect(function()
		contour.Color = C.bordure
	end)
	return champ
end

-- Étiquette de section, petites capitales dorées.
function Composants.section(libelle: string, ordre: number?): TextLabel
	return Composants.texte({
		Text = string.upper(libelle),
		FontFace = P.gras,
		TextSize = T.petit,
		TextColor3 = C.aurum,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = ordre or 0,
	})
end

function Composants.carte(proprietes: { [string]: any }?, enfants: { Instance }?): Frame
	local p: { [string]: any } = {
		BackgroundColor3 = C.carte,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	for cle, valeur in proprietes or {} do
		p[cle] = valeur
	end
	local tous: { Instance } = { Composants.coins(), Composants.marges(Theme.marge) }
	for _, e in enfants or {} do
		table.insert(tous, e)
	end
	return creer("Frame", p, tous)
end

-- Zone défilante avec pile verticale.
function Composants.defilant(proprietes: { [string]: any }?, ecart: number?): ScrollingFrame
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.bordure,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for cle, valeur in proprietes or {} do
		p[cle] = valeur
	end
	return creer("ScrollingFrame", p, {
		Composants.pile("V", ecart or 8),
		Composants.marges(2, 8, 2, 2),
	})
end

-- Interrupteur on/off. Renvoie le cadre et une fonction pour fixer l'état sans rappel.
function Composants.interrupteur(etat: boolean, auChangement: (boolean) -> ()): (TextButton, (boolean) -> ())
	local courant = etat
	local fond = creer("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(0, 44, 0, 24),
		BackgroundColor3 = C.bordure,
	}, { Composants.coins(UDim.new(1, 0)) }) :: TextButton
	local pastille = creer("Frame", {
		Size = UDim2.new(0, 18, 0, 18),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = C.texte,
		Parent = fond,
	}, { Composants.coins(UDim.new(1, 0)) })

	local function afficher(valeur: boolean)
		courant = valeur
		TweenService:Create(fond, RAPIDE, { BackgroundColor3 = if valeur then C.purpura else C.bordure }):Play()
		TweenService:Create(pastille, RAPIDE, {
			Position = if valeur then UDim2.new(1, -21, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end
	afficher(etat)

	fond.Activated:Connect(function()
		afficher(not courant)
		auChangement(courant)
	end)
	return fond, afficher
end

-- Choix exclusif entre quelques options.
function Composants.selecteur(
	options: { { valeur: string, libelle: string } },
	valeur: string,
	auChangement: (string) -> ()
): Frame
	local cadre = creer("Frame", {
		BackgroundColor3 = C.champ,
		Size = UDim2.new(0, 0, 0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		Composants.coins(UDim.new(0, 6)),
		Composants.marges(3),
		Composants.pile("H", 3),
	})
	local boutons: { [string]: TextButton } = {}
	local function choisir(v: string)
		for cle, b in boutons do
			b.BackgroundColor3 = if cle == v then C.purpura else C.champ
			b.TextColor3 = if cle == v then C.texte else C.texteDoux
		end
	end
	for i, option in options do
		boutons[option.valeur] = creer("TextButton", {
			Text = option.libelle,
			FontFace = P.moyen,
			TextSize = T.petit,
			AutoButtonColor = false,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = cadre,
		}, { Composants.coins(UDim.new(0, 4)), Composants.marges(0, 12) })
		boutons[option.valeur].Activated:Connect(function()
			choisir(option.valeur)
			auChangement(option.valeur)
		end)
	end
	choisir(valeur)
	return cadre
end

-- Pastille de statut (« En ligne », « Banni »…).
function Composants.pastille(libelle: string, couleur: Color3): Frame
	return creer("Frame", {
		BackgroundColor3 = couleur,
		BackgroundTransparency = 0.75,
		Size = UDim2.new(0, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
	}, {
		Composants.coins(UDim.new(1, 0)),
		Composants.marges(0, 10),
		Composants.contour(couleur),
		Composants.texte({
			Text = libelle,
			FontFace = P.gras,
			TextSize = 12,
			TextColor3 = C.texte,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
		}),
	})
end

function Composants.vider(conteneur: Instance)
	for _, enfant in conteneur:GetChildren() do
		if not enfant:IsA("UIBase") then
			enfant:Destroy()
		end
	end
end

return Composants
