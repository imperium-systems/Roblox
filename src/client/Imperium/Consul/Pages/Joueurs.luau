--!strict
-- Page Joueurs : liste du serveur, recherche hors ligne, fiche, sanctions et téléportation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium"):WaitForChild("Core"))

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Composants = require(Consul.Composants)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

local LIBELLES_SANCTIONS: { [string]: string } = {
	avertissement = "Avertissement",
	mute = "Mute",
	expulsion = "Expulsion",
	bannissement = "Bannissement",
	debannissement = "Débannissement",
}

local function avatar(userId: number, taille: number): ImageLabel
	return creer("ImageLabel", {
		Image = if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else "",
		BackgroundColor3 = C.champ,
		Size = UDim2.new(0, taille, 0, taille),
	}, { Composants.coins(UDim.new(1, 0)) })
end

return function(ctx: any, cadre: Frame)
	local joueurs: { any } = {}
	local selection: number? = nil
	local filtre = ""

	-- Colonne gauche : recherche + liste -------------------------------------------------

	local gauche = creer("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.36, -8, 1, 0),
		Parent = cadre,
	})
	local recherche = Composants.champ("Filtrer ou chercher un pseudo…", { Parent = gauche })
	local decalageListe = 42
	if ctx.peut("censor.consulter") then
		decalageListe = 84
	end
	local liste = Composants.defilant({
		Position = UDim2.new(0, 0, 0, decalageListe),
		Size = UDim2.new(1, 0, 1, -decalageListe),
		Parent = gauche,
	}, 4)

	-- Colonne droite : fiche ---------------------------------------------------------------

	local droite = Composants.defilant({
		Position = UDim2.new(0.36, 8, 0, 0),
		Size = UDim2.new(0.64, -8, 1, 0),
		Parent = cadre,
	}, 10)

	local function vide(message: string)
		Composants.vider(droite)
		Composants.paragraphe(message, {
			TextColor3 = C.texteFaible,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = droite,
		})
	end

	local afficherFiche: (any) -> ()
	local chargerFiche: (number) -> ()

	-- Liste ----------------------------------------------------------------------------------

	local function dessinerListe()
		Composants.vider(liste)
		local motif = string.lower(filtre)
		local n = 0
		for _, j in joueurs do
			if
				motif ~= ""
				and not string.find(string.lower(j.nom), motif, 1, true)
				and not string.find(string.lower(j.affichage), motif, 1, true)
			then
				continue
			end
			n += 1
			local choisi = j.userId == selection
			local ligne = creer("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if choisi then C.carteSurvol else C.carte,
				Size = UDim2.new(1, 0, 0, 52),
				LayoutOrder = n,
				Parent = liste,
			}, {
				Composants.coins(UDim.new(0, 6)),
				Composants.marges(8),
			})
			if choisi then
				Composants.contour(C.purpuraClair).Parent = ligne
			end
			local image = avatar(j.userId, 36)
			image.Position = UDim2.new(0, 0, 0.5, -18)
			image.Parent = ligne
			Composants.texte({
				Text = j.affichage,
				FontFace = P.moyen,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.new(0, 46, 0, 0),
				Size = UDim2.new(1, -46, 0, 18),
				Parent = ligne,
			})
			local sousTitre = `@{j.nom}`
			if j.muet then
				sousTitre ..= "  ·  muet"
			end
			Composants.texte({
				Text = sousTitre,
				TextSize = Theme.tailles.petit,
				TextColor3 = if j.muet then C.alerte else C.texteDoux,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.new(0, 46, 0, 18),
				Size = UDim2.new(1, -46, 0, 16),
				Parent = ligne,
			})
			if j.rang then
				local tag = Composants.texte({
					Text = j.rang,
					FontFace = P.gras,
					TextSize = 11,
					TextColor3 = j.couleurRang or C.aurum,
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0, 90, 0, 18),
					Parent = ligne,
				})
				tag.ZIndex = 2
			end
			ligne.Activated:Connect(function()
				selection = j.userId
				dessinerListe()
				chargerFiche(j.userId)
			end)
		end
		if n == 0 then
			Composants.paragraphe(if filtre == "" then "Aucun joueur." else "Personne sur ce serveur.", {
				TextColor3 = C.texteFaible,
				TextSize = Theme.tailles.petit,
				Parent = liste,
			})
		end
	end

	local function chargerListe()
		local reponse = ctx.demander("joueurs.liste")
		if reponse.ok then
			joueurs = reponse.joueurs
			dessinerListe()
		end
	end

	recherche:GetPropertyChangedSignal("Text"):Connect(function()
		filtre = recherche.Text
		dessinerListe()
	end)

	local function chercherHorsLigne()
		local texte = recherche.Text
		if not string.match(texte, "%S") then
			return
		end
		local reponse = ctx.executer("joueurs.chercher", { texte = texte })
		if reponse then
			selection = reponse.userId
			dessinerListe()
			chargerFiche(reponse.userId)
		end
	end

	if ctx.peut("censor.consulter") then
		Composants.bouton("Chercher hors ligne", "secondaire", chercherHorsLigne, {
			Position = UDim2.new(0, 0, 0, 42),
			Size = UDim2.new(1, 0, 0, 34),
			AutomaticSize = Enum.AutomaticSize.None,
			TextSize = Theme.tailles.petit + 1,
			Parent = gauche,
		})
		recherche.FocusLost:Connect(function(entree)
			if entree then
				-- Entrée sur un nom absent du serveur : on cherche hors ligne.
				local motif = string.lower(recherche.Text)
				for _, j in joueurs do
					if string.lower(j.nom) == motif then
						selection = j.userId
						dessinerListe()
						chargerFiche(j.userId)
						return
					end
				end
				chercherHorsLigne()
			end
		end)
	end

	-- Fiche ------------------------------------------------------------------------------------

	local function ligneInfo(parent: Instance, ordre: number, cle: string, valeur: string)
		local ligne = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = ordre,
			Parent = parent,
		})
		Composants.texte({
			Text = cle,
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			Size = UDim2.new(0.42, 0, 0, 20),
			Parent = ligne,
		})
		Composants.texte({
			Text = valeur,
			TextSize = Theme.tailles.petit + 1,
			Position = UDim2.new(0.42, 0, 0, 0),
			Size = UDim2.new(0.58, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = ligne,
		})
	end

	afficherFiche = function(f: any)
		Composants.vider(droite)

		-- En-tête
		local entete = Composants.carte({ LayoutOrder = 1, Parent = droite })
		local image = avatar(f.userId, 64)
		image.Parent = entete
		local bloc = creer("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 78, 0, 0),
			Size = UDim2.new(1, -78, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = entete,
		}, { Composants.pile("V", 4) })
		Composants.texte({
			Text = f.affichage or f.nom,
			FontFace = P.titre,
			TextSize = Theme.tailles.grand,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = bloc,
		})
		Composants.texte({
			Text = `@{f.nom}  ·  #{f.userId}`,
			TextSize = Theme.tailles.petit,
			TextColor3 = C.texteDoux,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 16),
			Parent = bloc,
		})
		local pastilles = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = bloc,
		}, { Composants.pile("H", 6) })
		Composants.pastille(if f.enLigne then "En ligne" else "Hors ligne", if f.enLigne then C.succes else C.texteFaible).Parent =
			pastilles
		if f.rang then
			Composants.pastille(f.rang, f.couleurRang or C.aurum).Parent = pastilles
		end
		if f.mute then
			Composants.pastille("Muet", C.alerte).Parent = pastilles
		end
		if f.ban then
			Composants.pastille("Banni", C.danger).Parent = pastilles
		end

		-- Informations
		if f.premiere ~= nil or f.enLigne then
			local infos = Composants.carte({ LayoutOrder = 2, Parent = droite }, { Composants.pile("V", 4) })
			Composants.section("Registre", 0).Parent = infos
			ligneInfo(infos, 1, "Première connexion", Core.formaterDate(f.premiere))
			ligneInfo(infos, 2, "Dernière connexion", Core.formaterDate(f.derniere))
			ligneInfo(infos, 3, "Temps de jeu", Core.formaterDuree((f.tempsJeu or 0) + (f.session or 0)))
			if f.session then
				ligneInfo(infos, 4, "Session en cours", Core.formaterDuree(f.session))
			end
			ligneInfo(infos, 5, "Avertissements", tostring(f.avertissements or 0))
			if f.pseudos and #f.pseudos > 1 then
				ligneInfo(infos, 6, "Anciens pseudos", table.concat(f.pseudos, ", "))
			end
		end

		-- Mesures en cours
		local function mesure(ordre: number, titre: string, m: any, couleur: Color3)
			local carte = Composants.carte({ LayoutOrder = ordre, Parent = droite }, {
				Composants.pile("V", 4),
				Composants.contour(couleur),
			})
			local etiquette = Composants.section(titre, 0)
			etiquette.TextColor3 = couleur
			etiquette.Parent = carte
			ligneInfo(carte, 1, "Motif", m.raison)
			ligneInfo(carte, 2, "Par", m.par)
			ligneInfo(carte, 3, "Depuis", Core.formaterDate(m.date))
			ligneInfo(carte, 4, "Fin", if m.fin then Core.formaterDate(m.fin) else "Définitif")
		end
		if f.ban then
			mesure(3, "Bannissement en cours", f.ban, C.danger)
		end
		if f.mute then
			mesure(4, "Mute en cours", f.mute, C.alerte)
		end

		-- Actions
		local actions = Composants.carte({ LayoutOrder = 5, Parent = droite }, { Composants.pile("V", 8) })
		Composants.section("Actions", 0).Parent = actions

		if not f.peutAgir then
			Composants.paragraphe(
				if f.userId == ctx.moi
					then "C'est toi."
					else "Rang égal ou supérieur au tien : sanctions indisponibles.",
				{ TextColor3 = C.texteDoux, TextSize = Theme.tailles.petit + 1, LayoutOrder = 1, Parent = actions }
			)
		end

		local champs = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 2,
			Visible = f.peutAgir,
			Parent = actions,
		})
		local motif = Composants.champ("Motif (affiché au joueur)", {
			Size = UDim2.new(0.68, -4, 1, 0),
			Parent = champs,
		})
		local reglages = ctx.acces.reglages
		local duree = Composants.champ("Durée", {
			Size = UDim2.new(0.32, -4, 1, 0),
			Position = UDim2.new(0.68, 4, 0, 0),
			Parent = champs,
		})
		-- Champ vide : durée par défaut de Lex, différente pour un mute et un bannissement.
		local function dureeOu(defaut: string): string
			return if string.match(duree.Text, "%S") then duree.Text else defaut
		end
		Composants.paragraphe(
			`Durée : 30s, 10m, 2h, 7j ou perm. Vide = {reglages.dureeMute} (mute), {reglages.dureeBan} (ban). Le motif est filtré par Roblox.`,
			{
			TextColor3 = C.texteFaible,
			TextSize = 12,
				LayoutOrder = 3,
				Visible = f.peutAgir,
				Parent = actions,
			}
		)

		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			Parent = actions,
		}, { Composants.pile("H", 6) })

		local function lancer(action: string, donnees: { [string]: any }, message: string)
			donnees.userId = f.userId
			task.spawn(function()
				if ctx.executer(action, donnees, message) then
					chargerFiche(f.userId)
				end
			end)
		end

		local function bouton(libelle: string, style: any, permission: string, condition: boolean, fn: () -> ())
			if condition and ctx.peut(permission) then
				Composants.bouton(libelle, style, fn, { Parent = rangee })
			end
		end

		local agir = f.peutAgir == true
		bouton("Avertir", "secondaire", "praetor.avertir", agir, function()
			lancer("praetor.avertir", { raison = motif.Text }, `{f.nom} a été averti.`)
		end)
		bouton("Mute", "secondaire", "praetor.mute", agir and not f.mute, function()
			lancer("praetor.mute", { raison = motif.Text, duree = dureeOu(reglages.dureeMute) }, `{f.nom} est muet.`)
		end)
		bouton("Démute", "secondaire", "praetor.mute", agir and f.mute ~= nil, function()
			lancer("praetor.demute", {}, `{f.nom} peut de nouveau parler.`)
		end)
		bouton("Expulser", "danger", "praetor.kick", agir and f.enLigne, function()
			ctx.confirmer("Expulser", `Expulser {f.nom} du serveur ?`, "Expulser", function()
				lancer("praetor.kick", { raison = motif.Text }, `{f.nom} a été expulsé.`)
			end)
		end)
		bouton("Bannir", "danger", "praetor.ban", agir and not f.ban, function()
			local texteDuree = dureeOu(reglages.dureeBan)
			local ok, secondes = Core.lireDuree(texteDuree)
			if not ok then
				ctx.notifier(ctx.messageErreur("duree_invalide"), "erreur")
				return
			end
			ctx.confirmer("Bannir", `Bannir {f.nom} — durée : {Core.formaterDuree(secondes)} ?`, "Bannir", function()
				lancer("praetor.ban", { raison = motif.Text, duree = texteDuree }, `{f.nom} a été banni.`)
			end)
		end)
		bouton("Débannir", "secondaire", "praetor.unban", f.ban ~= nil, function()
			lancer("praetor.unban", {}, `{f.nom} a été débanni.`)
		end)
		bouton("Aller vers", "fantome", "consul.teleporter", f.enLigne and f.userId ~= ctx.moi, function()
			lancer("teleporter", { sens = "vers" }, `Téléporté vers {f.nom}.`)
		end)
		bouton("Amener", "fantome", "consul.teleporter", agir and f.enLigne, function()
			lancer("teleporter", { sens = "amener" }, `{f.nom} a été amené.`)
		end)

		-- Historique
		local historique = Composants.carte({ LayoutOrder = 6, Parent = droite }, { Composants.pile("V", 6) })
		Composants.section("Historique des sanctions", 0).Parent = historique
		if not f.sanctions or #f.sanctions == 0 then
			Composants.paragraphe("Aucune sanction.", {
				TextColor3 = C.texteFaible,
				TextSize = Theme.tailles.petit + 1,
				LayoutOrder = 1,
				Parent = historique,
			})
		else
			for i, s in f.sanctions do
				local entree = creer("Frame", {
					BackgroundColor3 = C.champ,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = i,
					Parent = historique,
				}, { Composants.coins(UDim.new(0, 6)), Composants.marges(8, 10), Composants.pile("V", 2) })
				local titre = LIBELLES_SANCTIONS[s.type] or s.type
				if s.duree or s.type == "bannissement" or s.type == "mute" then
					titre ..= ` · {Core.formaterDuree(s.duree)}`
				end
				Composants.texte({
					Text = titre,
					FontFace = P.gras,
					TextSize = Theme.tailles.petit + 1,
					LayoutOrder = 1,
					Parent = entree,
				})
				Composants.paragraphe(`{s.raison}  —  par {s.par}, le {Core.formaterDate(s.date)}`, {
					TextSize = Theme.tailles.petit,
					TextColor3 = C.texteDoux,
					LayoutOrder = 2,
					Parent = entree,
				})
			end
		end
	end

	chargerFiche = function(userId: number)
		if not ctx.peut("censor.consulter") then
			-- Sans accès au registre : fiche réduite à partir de la liste.
			for _, j in joueurs do
				if j.userId == userId then
					afficherFiche({
						userId = j.userId,
						nom = j.nom,
						affichage = j.affichage,
						enLigne = true,
						rang = j.rang,
						couleurRang = j.couleurRang,
						mute = if j.muet then { raison = "—", par = "—" } else nil,
						peutAgir = j.niveau < ctx.acces.niveau and j.userId ~= ctx.moi,
						sanctions = {},
					})
				end
			end
			return
		end
		local reponse = ctx.demander("joueurs.fiche", { userId = userId })
		if selection ~= userId then
			return
		end
		if not reponse.ok then
			vide(ctx.messageErreur(reponse.erreur))
			return
		end
		afficherFiche(reponse)
	end

	vide("Choisis un joueur dans la liste.")

	return {
		montrer = function(userId: number?)
			task.spawn(chargerListe)
			if userId then
				selection = userId
				task.spawn(chargerFiche, userId)
			end
		end,
		maj = function(genre: string, donnees: any)
			if not cadre.Visible then
				return
			end
			if genre == "joueurs" then
				task.spawn(chargerListe)
			elseif genre == "fiche" and donnees == selection then
				task.spawn(chargerFiche, donnees)
			end
		end,
	}
end
