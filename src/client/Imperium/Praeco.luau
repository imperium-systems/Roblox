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
	alerte = C.alerte,
	maintenance = C.aurum,
	succes = C.succes,
}

local Praeco = {}

local file: { any } = {}
local enCours = false
local conteneur: Frame

local function afficher(annonce: any)
	local couleur = COULEURS[annonce.genre] or C.info
	local banniere = creer("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panneau,
		BackgroundTransparency = 0.05,
		Parent = conteneur,
	}, {
		Composants.coins(),
		Composants.contour(couleur, 1.5),
		Composants.marges(10, 16),
		Composants.pile("V", 2),
	})
	if annonce.titre then
		Composants.texte({
			Text = annonce.titre,
			FontFace = Theme.polices.gras,
			TextColor3 = couleur,
			TextSize = Theme.tailles.petit,
			LayoutOrder = 1,
			Parent = banniere,
		})
	end
	Composants.paragraphe(tostring(annonce.texte), { LayoutOrder = 2, Parent = banniere })

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
