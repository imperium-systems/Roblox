--!strict
-- Page Serveur : état, annonces, verrouillage et redémarrage (via Praefectus et Praeco).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Composants = require(Consul.Composants)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

local function maintenant(): number
	return workspace:GetServerTimeNow()
end

return function(ctx: any, cadre: Frame)
	local etat: any = nil

	local defilant = Composants.defilant({ Parent = cadre }, 12)

	-- État ------------------------------------------------------------------------------

	local grille = creer("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = defilant,
	}, {
		creer("UIGridLayout", {
			CellSize = UDim2.new(0.25, -6, 0, 72),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local valeurs: { [string]: TextLabel } = {}
	local function tuile(ordre: number, cle: string, libelle: string)
		local t = Composants.carte({ LayoutOrder = ordre, AutomaticSize = Enum.AutomaticSize.None, Parent = grille })
		Composants.texte({
			Text = libelle,
			TextSize = 12,
			TextColor3 = C.texteDoux,
			Size = UDim2.new(1, 0, 0, 16),
			Parent = t,
		})
		valeurs[cle] = Composants.texte({
			Text = "—",
			FontFace = P.titre,
			TextSize = Theme.tailles.grand,
			TextColor3 = C.texte,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = t,
		})
	end
	tuile(1, "joueurs", "Joueurs")
	tuile(2, "duree", "En ligne depuis")
	tuile(3, "statut", "Accès")
	tuile(4, "version", "Version de la place")

	local identifiant = Composants.texte({
		Text = "",
		FontFace = P.code,
		TextSize = 12,
		TextColor3 = C.texteFaible,
		LayoutOrder = 2,
		Parent = defilant,
	})

	local bandeau = Composants.carte({ LayoutOrder = 3, Visible = false, Parent = defilant }, {
		Composants.contour(C.aurum),
	})
	local texteBandeau = Composants.paragraphe("", { TextColor3 = C.aurum, FontFace = P.moyen, Parent = bandeau })

	local afficherVerrou: ((boolean) -> ())? = nil

	local function dessinerEtat()
		if not etat then
			return
		end
		valeurs.joueurs.Text = `{etat.joueurs} / {etat.max}`
		valeurs.duree.Text = Core.formaterDuree(maintenant() - etat.demarrage)
		valeurs.statut.Text = if etat.verrouille then "Verrouillé" else "Ouvert"
		valeurs.statut.TextColor3 = if etat.verrouille then C.alerte else C.succes
		valeurs.version.Text = tostring(etat.version)
		identifiant.Text = `Serveur {etat.jobId}`
		if etat.redemarrage then
			local reste = math.max(0, math.floor(etat.redemarrage.fin - maintenant()))
			bandeau.Visible = true
			texteBandeau.Text = `Redémarrage dans {Core.formaterCompte(reste)} : {etat.redemarrage.raison}`
		else
			bandeau.Visible = false
		end
		if afficherVerrou then
			afficherVerrou(etat.verrouille)
		end
	end

	local function charger()
		local reponse = ctx.demander("serveur.etat")
		if reponse.ok then
			etat = reponse.serveur
			dessinerEtat()
		end
	end

	-- Annonce ---------------------------------------------------------------------------

	if ctx.peut("praefectus.annoncer") then
		local carte = Composants.carte({ LayoutOrder = 10, Parent = defilant }, { Composants.pile("V", 8) })
		Composants.section("Annonce", 0).Parent = carte
		local message = Composants.champ("Message affiché à tous les joueurs…", {
			LayoutOrder = 1,
			Parent = carte,
		})
		local genre = "info"
		local partout = false
		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = carte,
		}, { Composants.pile("H", 10) })
		Composants.selecteur({
			{ valeur = "info", libelle = "Info" },
			{ valeur = "alerte", libelle = "Alerte" },
			{ valeur = "maintenance", libelle = "Maintenance" },
		}, genre, function(v)
			genre = v
		end).Parent =
			rangee
		local interrupteur = Composants.interrupteur(false, function(v)
			partout = v
		end)
		interrupteur.LayoutOrder = 2
		interrupteur.Parent = rangee
		Composants.texte({
			Text = "Tous les serveurs",
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 3,
			Parent = rangee,
		})
		Composants.bouton("Envoyer", "primaire", function()
			local texte = message.Text
			task.spawn(function()
				if ctx.executer("serveur.annoncer", { texte = texte, genre = genre, partout = partout }, "Annonce envoyée.") then
					message.Text = ""
				end
			end)
		end, { LayoutOrder = 4, Parent = rangee })
	end

	-- Verrouillage ----------------------------------------------------------------------

	if ctx.peut("praefectus.verrouiller") then
		local carte = Composants.carte({ LayoutOrder = 20, Parent = defilant }, { Composants.pile("V", 8) })
		Composants.section("Accès au serveur", 0).Parent = carte
		Composants.paragraphe(
			"Verrouillé, le serveur refuse les nouveaux joueurs qui ne sont pas du staff. Les joueurs présents restent.",
			{ TextColor3 = C.texteDoux, TextSize = Theme.tailles.petit + 1, LayoutOrder = 1, Parent = carte }
		)
		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Parent = carte,
		}, { Composants.pile("H", 10) })
		local partout = false
		local bouton, afficher = Composants.interrupteur(false, function(v)
			task.spawn(function()
				local message = if v then "Serveur verrouillé." else "Serveur ouvert."
				if not ctx.executer("serveur.verrouiller", { etat = v, partout = partout }, message) then
					charger()
				end
			end)
		end)
		afficherVerrou = afficher
		bouton.Parent = rangee
		Composants.texte({
			Text = "Verrouiller",
			FontFace = P.moyen,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = rangee,
		})
		local inter = Composants.interrupteur(false, function(v)
			partout = v
		end)
		inter.LayoutOrder = 3
		inter.Parent = rangee
		Composants.texte({
			Text = "Tous les serveurs",
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 4,
			Parent = rangee,
		})
	end

	-- Redémarrage -----------------------------------------------------------------------

	if ctx.peut("praefectus.redemarrer") then
		local carte = Composants.carte({ LayoutOrder = 30, Parent = defilant }, { Composants.pile("V", 8) })
		Composants.section("Redémarrage", 0).Parent = carte
		Composants.paragraphe(
			"Annonce un compte à rebours, puis expulse tout le monde avec un message de reconnexion. Le serveur se ferme une fois vide.",
			{ TextColor3 = C.texteDoux, TextSize = Theme.tailles.petit + 1, LayoutOrder = 1, Parent = carte }
		)
		local champs = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Parent = carte,
		})
		local raison = Composants.champ("Motif (ex. Mise à jour)", {
			Size = UDim2.new(0.7, -4, 1, 0),
			Parent = champs,
		})
		local delai = Composants.champ("Délai (s)", {
			Text = tostring(ctx.acces.reglages.delaiRedemarrage),
			Size = UDim2.new(0.3, -4, 1, 0),
			Position = UDim2.new(0.7, 4, 0, 0),
			Parent = champs,
		})
		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 3,
			Parent = carte,
		}, { Composants.pile("H", 10) })
		local partout = false
		local inter = Composants.interrupteur(false, function(v)
			partout = v
		end)
		inter.Parent = rangee
		Composants.texte({
			Text = "Tous les serveurs",
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = rangee,
		})
		Composants.bouton("Redémarrer", "danger", function()
			local secondes = tonumber(delai.Text)
			if not secondes or secondes < 5 or secondes > 600 then
				ctx.notifier("Délai entre 5 et 600 secondes.", "erreur")
				return
			end
			local portee = if partout then "TOUS les serveurs" else "ce serveur"
			ctx.confirmer("Redémarrer", `Redémarrer {portee} dans {Core.formaterCompte(secondes)} ?`, "Redémarrer", function()
				task.spawn(
					ctx.executer,
					"serveur.redemarrer",
					{ delai = secondes, raison = raison.Text, partout = partout },
					"Compte à rebours lancé."
				)
			end)
		end, { LayoutOrder = 3, Parent = rangee })
		Composants.bouton("Annuler", "secondaire", function()
			task.spawn(ctx.executer, "serveur.annuler", { partout = partout }, "Redémarrage annulé.")
		end, { LayoutOrder = 4, Parent = rangee })
	end

	-- Rafraîchit la durée et le compte à rebours tant que la page est visible.
	task.spawn(function()
		while true do
			task.wait(1)
			if cadre.Visible and cadre.Parent then
				dessinerEtat()
			end
		end
	end)

	return {
		montrer = function()
			task.spawn(charger)
		end,
		maj = function(genre: string, donnees: any)
			if genre == "serveur" and type(donnees) == "table" then
				etat = donnees
				dessinerEtat()
			end
		end,
	}
end
