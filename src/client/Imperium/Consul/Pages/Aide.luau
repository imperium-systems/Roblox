--!strict
-- Page Aide : ce que chaque page permet de faire et où la trouver.
-- N'affiche que ce que le rang de la personne autorise.

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Composants = require(Consul.Composants)
local Catalogue = require(Consul.Catalogue)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

local RUBRIQUES = {
	{
		page = "Joueurs",
		titre = "Joueurs",
		chemin = "Curia > Praetor",
		permission = "consul.ouvrir",
		resume = "Liste des joueurs du serveur et fiche de chacun.",
		commandes = {
			{ "censor.consulter", "Chercher hors ligne", "Retrouve la fiche d'un joueur absent, par pseudo ou UserId." },
			{ "praetor.avertir", "Avertir", "Prévient le joueur et ajoute l'avertissement à sa fiche." },
			{ "praetor.mute", "Mute / Démute", "Coupe ou rend la parole dans le chat." },
			{ "praetor.kick", "Expulser", "Retire le joueur du serveur. Il peut revenir." },
			{ "praetor.ban", "Bannir", "Interdit l'accès au jeu pour une durée ou définitivement." },
			{ "praetor.unban", "Débannir", "Lève un bannissement en cours." },
			{ "consul.teleporter", "Aller vers / Amener", "Te téléporte vers le joueur, ou l'amène à toi." },
		},
	},
	{
		page = "Serveur",
		titre = "Serveur",
		chemin = "Curia > Praefectus",
		permission = "consul.ouvrir",
		resume = "État du serveur : joueurs, durée en ligne, version.",
		commandes = {
			{ "praefectus.annoncer", "Annonce", "Affiche une bannière à tous les joueurs." },
			{ "praefectus.verrouiller", "Verrouiller", "Refuse les nouveaux joueurs qui ne sont pas du staff." },
			{ "praefectus.redemarrer", "Redémarrer", "Lance un compte à rebours, puis vide le serveur." },
		},
	},
	{
		page = "Journal",
		titre = "Journal",
		chemin = "Curia > Censor",
		permission = "censor.journal",
		resume = "Historique des actions du staff. Un clic ouvre la fiche du joueur visé.",
		commandes = {},
	},
	{
		page = "Reglages",
		titre = "Réglages",
		chemin = "Core > Lex",
		permission = "lex.modifier",
		resume = "Réglages du jeu, modifiables à chaud sur ce serveur jusqu'à sa fermeture.",
		commandes = {},
	},
}

local STATUTS = {
	{ "Disponible", "le système a une page dans ce panneau." },
	{ "Actif", "le système tourne en arrière-plan, sans page." },
	{ "À venir", "le système n'est pas encore développé." },
}

return function(ctx: any, cadre: Frame)
	local defilant = Composants.defilant({ Parent = cadre }, 10)
	local ordre = 0

	local function carte(titre: string): Frame
		ordre += 1
		local c = Composants.carte({ LayoutOrder = ordre, Parent = defilant }, { Composants.pile("V", 6) })
		Composants.section(titre, 0).Parent = c
		return c
	end

	local function ligne(parent: Instance, ordreLigne: number, gras: string, texte: string)
		Composants.paragraphe(`<b>{gras}</b> : {texte}`, {
			RichText = true,
			TextSize = Theme.tailles.petit + 1,
			LayoutOrder = ordreLigne,
			Parent = parent,
		})
	end

	-- Bienvenue
	local accueil = carte(`Ton rang : {ctx.acces.rang}`)
	Composants.paragraphe(
		"Cette aide n'affiche que ce que ton rang permet. Choisis une famille à gauche, puis un système en haut. F2 ouvre et ferme le panneau.",
		{ TextColor3 = C.texteDoux, TextSize = Theme.tailles.petit + 1, LayoutOrder = 1, Parent = accueil }
	)

	-- Ce à quoi la personne a accès
	for _, rubrique in RUBRIQUES do
		if not ctx.peut(rubrique.permission) then
			continue
		end
		local c = carte(rubrique.titre)
		Composants.paragraphe(rubrique.resume, {
			TextColor3 = C.texteDoux,
			TextSize = Theme.tailles.petit + 1,
			LayoutOrder = 1,
			Parent = c,
		})
		local n = 1
		for _, commande in rubrique.commandes do
			if ctx.peut(commande[1]) then
				n += 1
				ligne(c, n, commande[2], commande[3])
			end
		end
		Composants.bouton(`Ouvrir : {rubrique.chemin}`, "secondaire", function()
			ctx.ouvrir(rubrique.page)
		end, { LayoutOrder = n + 1, TextSize = Theme.tailles.petit + 1, Parent = c })
	end

	-- Règles communes aux sanctions
	if ctx.peut("praetor.mute") or ctx.peut("praetor.ban") then
		local c = carte("Sanctions")
		ligne(c, 1, "Durées", "30s, 10m, 2h, 7j, ou perm pour définitif.")
		ligne(c, 2, "Hiérarchie", "tu ne peux agir que sur un rang inférieur au tien.")
		ligne(c, 3, "Motif", "il est montré au joueur et passe par le filtre de Roblox.")
	end

	-- Statuts et familles
	local legende = carte("Statuts des systèmes")
	for i, statut in STATUTS do
		ligne(legende, i, statut[1], statut[2])
	end

	local familles = carte("Les familles")
	for i, famille in Catalogue do
		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = i,
			Parent = familles,
		})
		creer("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(3, 16),
			BackgroundColor3 = famille.couleur,
			BorderSizePixel = 0,
			Parent = rangee,
		})
		Composants.texte({
			Text = famille.nom,
			FontFace = P.moyen,
			TextSize = Theme.tailles.petit + 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, 90, 1, 0),
			Parent = rangee,
		})
		Composants.texte({
			Text = famille.theme,
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			Position = UDim2.fromOffset(104, 0),
			Size = UDim2.new(1, -104, 1, 0),
			Parent = rangee,
		})
	end

	return {
		montrer = function() end,
		maj = function() end,
	}
end
