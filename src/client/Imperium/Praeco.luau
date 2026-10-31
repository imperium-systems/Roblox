--!strict
-- Praeco — affichage des annonces officielles, pour tous les joueurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Imperium = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium")
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Consul = script.Parent:WaitForChild("Consul")
local Theme = require(Consul:WaitForChild("Theme"))
local Composants = require(Consul:WaitForChild("Composants"))

local C = Theme.couleurs
local creer = Composants.creer

local COULEURS: { [string]: Color3 } = {
	info = C.info,
	alerte = C.danger,
	maintenance = C.aurum,
	succes = C.succes,
}

local FOND_ALERTE = Color3.fromRGB(58, 20, 20)

local Praeco = {}

local file: { any } = {}
local enCours = false
local conteneur: Frame

-- Trait d'icône, centré sur (x, y) dans une pastille de 28 px.
local function trait(parent: Instance, couleur: Color3, x: number, y: number, l: number, h: number, rotation: number?)
	creer("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(l, h),
		Rotation = rotation or 0,
		BackgroundColor3 = couleur,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

-- Icônes dessinées avec des cadres : aucune image à héberger, nette à toute résolution.
local function icone(genre: string, couleur: Color3, fond: Color3): Frame
	local pastille = creer("Frame", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = couleur,
		BackgroundTransparency = 0.8,
	}, {
		Composants.coins(UDim.new(1, 0)),
		Composants.contour(couleur, 1.5),
	})
	if genre == "alerte" then
		trait(pastille, couleur, 14, 11, 3, 10)
		trait(pastille, couleur, 14, 20, 3, 3)
	elseif genre == "succes" then
		trait(pastille, couleur, 10, 16, 3, 7, -45)
		trait(pastille, couleur, 16, 14, 3, 13, 45)
	elseif genre == "maintenance" then
		-- Roue dentée : trois barres croisées, un disque, un trou.
		for _, rotation in { 0, 60, 120 } do
			trait(pastille, couleur, 14, 14, 4, 18, rotation)
		end
		creer("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = couleur,
			Parent = pastille,
		}, { Composants.coins(UDim.new(1, 0)) })
		creer("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = fond,
			Parent = pastille,
		}, { Composants.coins(UDim.new(1, 0)) })
	else
		trait(pastille, couleur, 14, 8, 3, 3)
		trait(pastille, couleur, 14, 16, 3, 9)
	end
	return pastille
end

local function afficher(annonce: any)
	local couleur = COULEURS[annonce.genre] or C.info
	local fond = if annonce.genre == "alerte" then FOND_ALERTE else C.panneau
	local banniere = creer("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = fond,
		BackgroundTransparency = 0.05,
		Parent = conteneur,
	}, {
		Composants.coins(),
		Composants.contour(couleur, 1.5),
		Composants.marges(10, 16),
	})
	icone(annonce.genre, couleur, fond).Parent = banniere
	local bloc = creer("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = banniere,
	}, { Composants.pile("V", 2) })
	if annonce.titre then
		Composants.texte({
			Text = annonce.titre,
			FontFace = Theme.polices.gras,
			TextColor3 = couleur,
			TextSize = Theme.tailles.petit,
			LayoutOrder = 1,
			Parent = bloc,
		})
	end
	Composants.paragraphe(tostring(annonce.texte), { LayoutOrder = 2, Parent = bloc })

	local entree = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(banniere, entree, { Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	task.wait(math.clamp(tonumber(annonce.duree) or 8, 2, 30))
	local sortie = TweenService:Create(banniere, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) })
	sortie:Play()
	sortie.Completed:Wait()
	banniere:Destroy()
end

local function suivante()
	if enCours then
		return
	end
	enCours = true
	while #file > 0 do
		afficher(table.remove(file, 1))
	end
	enCours = false
end

function Praeco.demarrer()
	local ecran = creer("ScreenGui", {
		Name = "ImperiumPraeco",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	conteneur = creer("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.9, 0, 0, 0),
		ClipsDescendants = false,
		Parent = ecran,
	}, {
		creer("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) }),
	})

	Veredarius.surReception("praeco", function(annonce)
		if type(annonce) ~= "table" then
			return
		end
		table.insert(file, annonce)
		task.spawn(suivante)
	end)
end

return Praeco
