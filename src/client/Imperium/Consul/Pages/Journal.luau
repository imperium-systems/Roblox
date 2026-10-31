--!strict
-- Page Journal : actions du staff tenues par Censor, les plus récentes d'abord, en direct.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Composants = require(Consul.Composants)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

return function(ctx: any, cadre: Frame)
	local filtre = Composants.champ("Filtrer par staff, joueur ou action…", { Parent = cadre })
	local defilant = Composants.defilant({
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		Parent = cadre,
	}, 6)

	local entrees: { any } = {}

	local function correspond(e: any, motif: string): boolean
		if motif == "" then
			return true
		end
		for _, champ in { e.acteur, e.action, e.cible, e.details } do
			if champ and string.find(string.lower(champ), motif, 1, true) then
				return true
			end
		end
		return false
	end

	local function dessiner()
		Composants.vider(defilant)
		local motif = string.lower(filtre.Text)
		local n = 0
		for _, e in entrees do
			if not correspond(e, motif) then
				continue
			end
			n += 1
			local ligne = creer("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.carte,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = n,
				Parent = defilant,
			}, { Composants.coins(UDim.new(0, 6)), Composants.marges(8, 12), Composants.pile("V", 2) })

			local resume = `{e.acteur}  ·  {e.action}`
			if e.cible then
				resume ..= `  →  {e.cible}`
			end
			local haut = creer("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 1,
				Parent = ligne,
			})
			Composants.texte({
				Text = resume,
				FontFace = P.moyen,
				TextSize = Theme.tailles.petit + 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -130, 1, 0),
				Parent = haut,
			})
			Composants.texte({
				Text = Core.formaterDate(e.date),
				TextSize = 12,
				TextColor3 = C.texteFaible,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 125, 1, 0),
				Parent = haut,
			})
			if e.details and e.details ~= "—" then
				Composants.paragraphe(e.details, {
					TextSize = Theme.tailles.petit,
					TextColor3 = C.texteDoux,
					LayoutOrder = 2,
					Parent = ligne,
				})
			end

			-- Un clic sur une entrée qui vise un joueur ouvre sa fiche.
			if e.cibleId and ctx.peut("censor.consulter") then
				ligne.Activated:Connect(function()
					ctx.ouvrir("Joueurs", e.cibleId)
				end)
			end
		end
		if n == 0 then
			Composants.paragraphe(if #entrees == 0 then "Aucune action enregistrée." else "Aucun résultat.", {
				TextColor3 = C.texteFaible,
				TextSize = Theme.tailles.petit,
				Parent = defilant,
			})
		end
	end

	filtre:GetPropertyChangedSignal("Text"):Connect(dessiner)

	local function charger()
		local reponse = ctx.demander("censor.journal")
		if reponse.ok then
			entrees = reponse.entrees
			dessiner()
		end
	end

	return {
		montrer = function()
			task.spawn(charger)
		end,
		maj = function(genre: string, entree: any)
			if genre == "journal" and type(entree) == "table" then
				table.insert(entrees, 1, entree)
				if cadre.Visible then
					dessiner()
				end
			end
		end,
	}
end
