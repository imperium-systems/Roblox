--!strict
-- Consul — panneau admin, côté client.
-- N'est construit que pour le staff (le serveur décide). L'interface n'affiche que les onglets
-- et boutons permis, mais chaque action est revérifiée par le serveur.
-- Raccourci : F2, ou le bouton « Imperium » en bas à droite.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Imperium = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium")
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Theme = require(script.Theme)
local Composants = require(script.Composants)
local Catalogue = require(script.Catalogue)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

local RACCOURCI = Enum.KeyCode.F2

local MESSAGES: { [string]: string } = {
	non_autorise = "Tu n'as pas la permission de faire ça.",
	rang_insuffisant = "Ce joueur a un rang égal ou supérieur au tien.",
	joueur_introuvable = "Joueur introuvable.",
	hors_ligne = "Ce joueur n'est pas sur ce serveur.",
	sans_personnage = "Personnage introuvable (mort ou en chargement ?).",
	duree_invalide = "Durée illisible. Exemples : 30s, 10m, 2h, 7j, perm.",
	texte_invalide = "Texte invalide ou trop long.",
	valeur_invalide = "Valeur invalide.",
	hors_limites = "Valeur hors des limites autorisées.",
	cle_inconnue = "Réglage inconnu.",
	filtrage_echoue = "Le filtre de texte de Roblox n'a pas répondu, réessaie.",
	deja_en_cours = "Un redémarrage est déjà en cours.",
	rien_a_annuler = "Aucun redémarrage en cours.",
	pas_banni = "Ce joueur n'est pas banni.",
	inter_serveurs = "Impossible de joindre les autres serveurs.",
	sauvegarde = "La sauvegarde n'a pas répondu, réessaie.",
	trop_de_requetes = "Trop de requêtes, ralentis un peu.",
	reseau = "Le serveur ne répond pas.",
	erreur_interne = "Erreur interne du serveur.",
	action_inconnue = "Action inconnue.",
}


local Consul = {}

local construit = false

export type Contexte = {
	acces: { [string]: any },
	moi: number,
	peut: (permission: string) -> boolean,
	demander: (action: string, donnees: { [string]: any }?) -> { [string]: any },
	executer: (action: string, donnees: { [string]: any }?, succes: string?) -> { [string]: any }?,
	notifier: (message: string, genre: ("succes" | "erreur" | "info")?) -> (),
	confirmer: (titre: string, message: string, libelle: string, auValider: () -> ()) -> (),
	ouvrir: (onglet: string, argument: any?) -> (),
	messageErreur: (code: string?) -> string,
}

local function construire(acces: { [string]: any })
	construit = true
	local moi = Players.LocalPlayer

	local ecran = creer("ScreenGui", {
		Name = "ImperiumConsul",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = moi:WaitForChild("PlayerGui"),
	})

	-- Notifications ------------------------------------------------------------------

	local zoneNotifications = creer("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 20,
		Parent = ecran,
	}, {
		Composants.pile("V", 6, Enum.HorizontalAlignment.Center),
		creer("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }),
	})

	local function notifier(message: string, genre: ("succes" | "erreur" | "info")?)
		local couleur = if genre == "erreur" then C.danger elseif genre == "succes" then C.succes else C.info
		local bulle = creer("Frame", {
			BackgroundColor3 = C.panneau,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 20,
			Parent = zoneNotifications,
		}, {
			Composants.coins(),
			Composants.contour(couleur, 1.5),
			Composants.marges(10, 14),
			Composants.paragraphe(message, { ZIndex = 21, TextSize = Theme.tailles.petit + 1 }),
		})
		task.delay(4, function()
			bulle:Destroy()
		end)
	end

	local function messageErreur(code: string?): string
		return MESSAGES[code or ""] or `Échec ({code or "inconnu"}).`
	end

	local function demander(action: string, donnees: { [string]: any }?): { [string]: any }
		local reponse = Veredarius.demander("consul", action, donnees or {})
		if type(reponse) ~= "table" then
			return { ok = false, erreur = "reseau" }
		end
		return reponse
	end

	-- Comme demander, mais affiche le résultat. Renvoie la réponse si elle a réussi.
	local function executer(action: string, donnees: { [string]: any }?, succes: string?): { [string]: any }?
		local reponse = demander(action, donnees)
		if not reponse.ok then
			notifier(messageErreur(reponse.erreur), "erreur")
			return nil
		end
		if succes then
			notifier(succes, "succes")
		end
		return reponse
	end

	local function peut(permission: string): boolean
		return acces.permissions[permission] == true
	end

	-- Fenêtre --------------------------------------------------------------------------

	local fenetre = creer("Frame", {
		Name = "Fenetre",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.88),
		BackgroundColor3 = C.fond,
		Visible = false,
		Parent = ecran,
	}, {
		creer("UISizeConstraint", { MaxSize = Vector2.new(940, 600), MinSize = Vector2.new(320, 300) }),
		Composants.coins(UDim.new(0, 12)),
		Composants.contour(C.bordure),
	})
	local echelle = creer("UIScale", { Scale = 1, Parent = fenetre })

	-- En-tête
	local entete = creer("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = C.panneau,
		Parent = fenetre,
	}, {
		Composants.coins(UDim.new(0, 12)),
		-- Cache l'arrondi du bas de l'en-tête.
		creer("Frame", {
			Size = UDim2.new(1, 0, 0, 12),
			Position = UDim2.new(0, 0, 1, -12),
			BackgroundColor3 = C.panneau,
			BorderSizePixel = 0,
		}),
		creer("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = C.bordure,
			BorderSizePixel = 0,
		}),
	})
	Composants.texte({
		Text = "IMPERIUM",
		FontFace = P.titre,
		TextSize = Theme.tailles.titre,
		TextColor3 = C.aurum,
		Position = UDim2.new(0, 20, 0, 8),
		Size = UDim2.new(0.6, 0, 0, 24),
		Parent = entete,
	})
	Composants.texte({
		Text = `Version {acces.version}  ·  {acces.rang}`,
		TextSize = Theme.tailles.petit,
		TextColor3 = C.texteDoux,
		Position = UDim2.new(0, 20, 0, 31),
		Size = UDim2.new(0.6, 0, 0, 16),
		Parent = entete,
	})

	local function basculer(visible: boolean?)
		local cible = if visible == nil then not fenetre.Visible else visible
		if cible then
			fenetre.Visible = true
			echelle.Scale = 0.96
			TweenService:Create(echelle, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		else
			fenetre.Visible = false
		end
	end

	Composants.bouton("Fermer", "fantome", function()
		basculer(false)
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = entete,
	})

	-- Déplacement par l'en-tête.
	do
		local depart: Vector3? = nil
		local origine: UDim2? = nil
		entete.InputBegan:Connect(function(entree)
			if
				entree.UserInputType == Enum.UserInputType.MouseButton1
				or entree.UserInputType == Enum.UserInputType.Touch
			then
				depart = entree.Position
				origine = fenetre.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(entree)
			if
				depart
				and origine
				and (
					entree.UserInputType == Enum.UserInputType.MouseMovement
					or entree.UserInputType == Enum.UserInputType.Touch
				)
			then
				local delta = entree.Position - depart
				fenetre.Position = UDim2.new(
					origine.X.Scale,
					origine.X.Offset + delta.X,
					origine.Y.Scale,
					origine.Y.Offset + delta.Y
				)
			end
		end)
		UserInputService.InputEnded:Connect(function(entree)
			if
				entree.UserInputType == Enum.UserInputType.MouseButton1
				or entree.UserInputType == Enum.UserInputType.Touch
			then
				depart = nil
			end
		end)
	end

	-- Corps : familles à gauche, sous-familles en haut, contenu en dessous
	local largeurBarre = 150
	local barre = Composants.defilant({
		Position = UDim2.new(0, 8, 0, 69),
		Size = UDim2.new(0, largeurBarre - 8, 1, -77),
		ScrollBarThickness = 2,
		Parent = fenetre,
	}, 3)
	local contenu = creer("Frame", {
		Position = UDim2.new(0, largeurBarre, 0, 57),
		Size = UDim2.new(1, -largeurBarre, 1, -57),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = fenetre,
	}, {
		Composants.marges(12, 16, 14, 8),
	})
	local pileOnglets = Composants.pile("H", 4)
	pileOnglets.Wraps = false
	local barreOnglets = creer("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 38),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.bordure,
		Parent = contenu,
	}, { pileOnglets })
	local zonePage = creer("Frame", {
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		Parent = contenu,
	})

	-- Confirmation ---------------------------------------------------------------------

	local function confirmer(titre: string, message: string, libelle: string, auValider: () -> ())
		local voile = creer("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = fenetre,
		}, { Composants.coins(UDim.new(0, 12)) })
		local boite = Composants.carte({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 380, 0, 0),
			BackgroundColor3 = C.panneau,
			ZIndex = 11,
			Parent = voile,
		}, {
			Composants.contour(C.bordure),
			Composants.pile("V", 10),
			creer("UISizeConstraint", { MaxSize = Vector2.new(380, math.huge) }),
		})
		boite.Size = UDim2.new(0.9, 0, 0, 0)
		Composants.texte({
			Text = titre,
			FontFace = P.titre,
			TextSize = Theme.tailles.grand,
			TextColor3 = C.aurum,
			LayoutOrder = 1,
			ZIndex = 12,
			Parent = boite,
		})
		Composants.paragraphe(message, { LayoutOrder = 2, ZIndex = 12, TextColor3 = C.texteDoux, Parent = boite })
		local rangee = creer("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 3,
			Parent = boite,
		}, { Composants.pile("H", 8, Enum.HorizontalAlignment.Right) })
		Composants.bouton("Annuler", "secondaire", function()
			voile:Destroy()
		end, { ZIndex = 12, LayoutOrder = 1, Parent = rangee })
		Composants.bouton(libelle, "danger", function()
			voile:Destroy()
			auValider()
		end, { ZIndex = 12, LayoutOrder = 2, Parent = rangee })
	end

	-- Navigation ---------------------------------------------------------------------------

	local pages: { [string]: { cadre: Frame, montrer: (any?) -> (), maj: (string, any?) -> () } } = {}
	local boutonsFamilles: { [any]: TextButton } = {}
	local familleActive: any = nil
	local systemeActif: any = nil
	local afficher: (any, any?, any?) -> ()

	-- L'aide n'est pas un système : elle a sa propre entrée, sous les familles.
	local aide: any = {
		nom = "Aide",
		couleur = C.aurum,
		sansOnglets = true,
		systemes = { { nom = "Aide", page = "Aide", permission = "consul.ouvrir" } },
	}
	local entrees: { any } = table.clone(Catalogue) :: any
	table.insert(entrees, aide)

	local function ouvrir(id: string, argument: any?)
		for _, famille in Catalogue do
			for _, systeme in famille.systemes do
				if systeme.page == id and pages[id] then
					afficher(famille, systeme, argument)
					return
				end
			end
		end
	end

	local ctx: Contexte = {
		acces = acces,
		moi = moi.UserId,
		peut = peut,
		demander = demander,
		executer = executer,
		notifier = notifier,
		confirmer = confirmer,
		ouvrir = ouvrir,
		messageErreur = messageErreur,
	}

	-- Une page n'est construite que si le rang y donne accès.
	for _, famille in entrees do
		for _, systeme in famille.systemes do
			if systeme.page and peut(systeme.permission) then
				local cadre = creer("Frame", {
					Name = systeme.page,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Visible = false,
					Parent = zonePage,
				})
				local fabrique = require(script.Pages:WaitForChild(systeme.page)) :: any
				local page = fabrique(ctx, cadre)
				page.cadre = cadre
				pages[systeme.page] = page
			end
		end
	end

	-- Seuls les systèmes accessibles au rang sont montrés : une page refusée n'apparaît nulle part.
	local function visibles(famille: any): { any }
		local liste = {}
		for _, systeme in famille.systemes do
			if not systeme.page or pages[systeme.page] then
				table.insert(liste, systeme)
			end
		end
		return liste
	end

	local function statut(famille: any, systeme: any): (string, Color3)
		if systeme.page then
			return "Disponible", C.succes
		end
		if systeme.actif then
			return "Actif", famille.couleur
		end
		return "À venir", C.texteFaible
	end

	-- Vue d'ensemble : les systèmes de la famille, en tableau de 3 colonnes.
	local vueEnsemble = creer("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.bordure,
		Visible = false,
		Parent = zonePage,
	}, {
		creer("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -8, 0, 96),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local vueFiche = Composants.defilant({ Visible = false, Parent = zonePage }, 10)

	local function remplirVue(famille: any)
		Composants.vider(vueEnsemble)
		for i, systeme in visibles(famille) do
			local libelle, couleur = statut(famille, systeme)
			local carte = creer("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.carte,
				LayoutOrder = i,
				Parent = vueEnsemble,
			}, { Composants.coins(), Composants.marges(10, 12) })
			if systeme.actif then
				Composants.contour(famille.couleur).Parent = carte
			end
			Composants.texte({
				Text = systeme.nom,
				FontFace = P.moyen,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, 0, 0, 18),
				Parent = carte,
			})
			Composants.texte({
				Text = systeme.role,
				TextSize = Theme.tailles.petit,
				TextColor3 = C.texteDoux,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.new(0, 0, 0, 20),
				Size = UDim2.new(1, 0, 0, 34),
				Parent = carte,
			})
			Composants.texte({
				Text = libelle,
				FontFace = P.gras,
				TextSize = 12,
				TextColor3 = couleur,
				Position = UDim2.new(0, 0, 0, 58),
				Size = UDim2.new(1, 0, 0, 16),
				Parent = carte,
			})
			carte.Activated:Connect(function()
				afficher(famille, systeme)
			end)
		end
	end

	local function remplirFiche(famille: any, systeme: any)
		Composants.vider(vueFiche)
		local carte = Composants.carte({ Parent = vueFiche }, { Composants.pile("V", 8) })
		Composants.texte({
			Text = systeme.nom,
			FontFace = P.titre,
			TextSize = Theme.tailles.grand,
			TextColor3 = famille.couleur,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 1,
			Parent = carte,
		})
		Composants.paragraphe(`{systeme.role}  ·  {famille.nom}`, {
			TextColor3 = C.texteDoux,
			LayoutOrder = 2,
			Parent = carte,
		})
		local libelle, couleur = statut(famille, systeme)
		local pastille = Composants.pastille(libelle, couleur)
		pastille.LayoutOrder = 3
		pastille.Parent = carte
		local explication = "Ce système n'est pas encore développé."
		if systeme.actif then
			explication = "Ce système tourne en arrière-plan : il n'a pas de page dans le panneau."
		end
		Composants.paragraphe(explication, {
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = C.texteDoux,
			LayoutOrder = 4,
			Parent = carte,
		})
	end

	-- Sous-familles : la vue d'ensemble, puis chaque système de la famille.
	local function dessinerOnglets()
		Composants.vider(barreOnglets)
		local famille = familleActive
		local boutonChoisi: TextButton? = nil

		local function ajouter(libelle: string, ordre: number, systeme: any)
			local choisi = systeme == systemeActif
			local bouton = creer("TextButton", {
				Text = libelle,
				FontFace = P.moyen,
				TextSize = Theme.tailles.petit + 1,
				TextColor3 = if choisi
					then famille.couleur
					elseif systeme == nil or systeme.actif then C.texte
					else C.texteFaible,
				BackgroundColor3 = if choisi then C.carte else C.fond,
				AutoButtonColor = false,
				Size = UDim2.new(0, 0, 0, 32),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = ordre,
				Parent = barreOnglets,
			}, { Composants.coins(UDim.new(0, 6)), Composants.marges(0, 12) })
			bouton.Activated:Connect(function()
				afficher(famille, systeme)
			end)
			if choisi then
				boutonChoisi = bouton
			end
		end

		ajouter("Vue d'ensemble", 0, nil)
		for i, systeme in visibles(famille) do
			ajouter(systeme.nom, i, systeme)
		end

		-- Amène l'onglet choisi dans la zone visible, une fois la pile calculée.
		task.defer(function()
			local bouton = boutonChoisi
			if bouton and bouton.Parent then
				local x = bouton.AbsolutePosition.X - barreOnglets.AbsolutePosition.X + barreOnglets.CanvasPosition.X
				barreOnglets.CanvasPosition = Vector2.new(math.max(0, x - 8), 0)
			end
		end)
	end

	afficher = function(famille: any, systeme: any?, argument: any?)
		familleActive = famille
		systemeActif = systeme
		for f, bouton in boutonsFamilles do
			bouton.BackgroundColor3 = if f == famille then C.carte else C.fond
			bouton.TextColor3 = if f == famille then C.texte else C.texteDoux
		end
		dessinerOnglets()
		local hautPage = if famille.sansOnglets then 0 else 46
		barreOnglets.Visible = not famille.sansOnglets
		zonePage.Position = UDim2.new(0, 0, 0, hautPage)
		zonePage.Size = UDim2.new(1, 0, 1, -hautPage)

		for _, page in pages do
			page.cadre.Visible = false
		end
		vueEnsemble.Visible = false
		vueFiche.Visible = false

		local page = systeme and systeme.page and pages[systeme.page]
		if page then
			page.cadre.Visible = true
			page.montrer(argument)
		elseif systeme then
			remplirFiche(famille, systeme)
			vueFiche.Visible = true
		else
			remplirVue(famille)
			vueEnsemble.Visible = true
		end
	end

	-- Familles, dans la colonne de gauche.
	for i, famille in entrees do
		local liste = visibles(famille)
		local actifs = 0
		for _, systeme in liste do
			if systeme.actif then
				actifs += 1
			end
		end
		local bouton = creer("TextButton", {
			Text = famille.nom,
			FontFace = P.moyen,
			TextSize = Theme.tailles.normal,
			TextColor3 = C.texteDoux,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = C.fond,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = i,
			Parent = barre,
		}, {
			Composants.coins(UDim.new(0, 6)),
			Composants.marges(0, 10, 0, 14),
			creer("Frame", {
				Size = UDim2.new(0, 3, 0, 18),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, -8, 0.5, 0),
				BackgroundColor3 = famille.couleur,
				BorderSizePixel = 0,
			}),
			Composants.texte({
				Text = if famille.sansOnglets then "" else `{actifs}/{#liste}`,
				TextSize = 12,
				TextColor3 = C.texteFaible,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.fromScale(1, 1),
			}),
		})
		boutonsFamilles[famille] = bouton
		bouton.Activated:Connect(function()
			afficher(famille, if famille.sansOnglets then liste[1] else nil)
		end)
	end

	-- Mises à jour poussées par le serveur.
	Veredarius.surReception("consul.maj", function(genre: string, donnees: any)
		for _, page in pages do
			page.maj(genre, donnees)
		end
	end)

	-- Ouverture -----------------------------------------------------------------------------

	local function basculerPanneau()
		basculer()
		if fenetre.Visible and not familleActive then
			ouvrir("Joueurs")
		end
	end

	-- Sur mobile, le bouton de saut occupe déjà le coin bas droit.
	local margeBas = if UserInputService.TouchEnabled then 180 else 16
	Composants.bouton("Imperium", "primaire", basculerPanneau, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -margeBas),
		FontFace = P.titre,
		TextColor3 = C.aurum,
		Parent = ecran,
	})

	UserInputService.InputBegan:Connect(function(entree, traite)
		if traite or entree.KeyCode ~= RACCOURCI then
			return
		end
		basculerPanneau()
	end)

	notifier(`Imperium prêt : F2 pour ouvrir le panneau ({acces.rang}).`, "info")
end

local function tenterAcces()
	if construit then
		return
	end
	local reponse = Veredarius.demander("consul", "acces", {})
	if type(reponse) == "table" and reponse.ok and not construit then
		construire(reponse)
	end
end

function Consul.demarrer()
	-- Le serveur prévient dès que le rang est connu ; on tente aussi tout de suite.
	Veredarius.surReception("consul.acces", function()
		task.spawn(tenterAcces)
	end)
	task.spawn(tenterAcces)
end

return Consul
