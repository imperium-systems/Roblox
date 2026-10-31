--!strict
-- Consul — panneau admin, côté client.
-- N'est construit que pour le staff (le serveur décide). L'interface n'affiche que les onglets
-- et boutons permis, mais chaque action est revérifiée par le serveur.
-- Raccourci : F2. Sur mobile : le bouton « Consul » en bas à gauche.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Imperium = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Imperium")
local Veredarius = require(Imperium:WaitForChild("Veredarius"))

local Theme = require(script.Theme)
local Composants = require(script.Composants)

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

local ONGLETS = {
	{ id = "Joueurs", libelle = "Joueurs", permission = "consul.ouvrir" },
	{ id = "Serveur", libelle = "Serveur", permission = "consul.ouvrir" },
	{ id = "Reglages", libelle = "Réglages", permission = "lex.modifier" },
	{ id = "Journal", libelle = "Journal", permission = "censor.journal" },
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
		Text = "CONSUL",
		FontFace = P.titre,
		TextSize = Theme.tailles.titre,
		TextColor3 = C.aurum,
		Position = UDim2.new(0, 20, 0, 8),
		Size = UDim2.new(0.6, 0, 0, 24),
		Parent = entete,
	})
	Composants.texte({
		Text = `Imperium {acces.version}  ·  {acces.rang}`,
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

	-- Corps : barre latérale + contenu
	local largeurBarre = 150
	local barre = creer("Frame", {
		Position = UDim2.new(0, 0, 0, 57),
		Size = UDim2.new(0, largeurBarre, 1, -57),
		BackgroundTransparency = 1,
		Parent = fenetre,
	}, {
		Composants.marges(12, 8),
		Composants.pile("V", 4),
	})
	local contenu = creer("Frame", {
		Position = UDim2.new(0, largeurBarre, 0, 57),
		Size = UDim2.new(1, -largeurBarre, 1, -57),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = fenetre,
	}, {
		Composants.marges(14, 16, 14, 8),
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

	-- Onglets et pages --------------------------------------------------------------------

	local pages: { [string]: { cadre: Frame, montrer: (any?) -> (), maj: (string, any?) -> () } } = {}
	local boutonsOnglets: { [string]: { bouton: TextButton, indicateur: Frame } } = {}
	local ongletActif: string? = nil

	local ctx: Contexte

	local function ouvrir(id: string, argument: any?)
		if not pages[id] then
			return
		end
		ongletActif = id
		for autre, page in pages do
			page.cadre.Visible = autre == id
			local b = boutonsOnglets[autre]
			b.bouton.BackgroundColor3 = if autre == id then C.carte else C.fond
			b.bouton.TextColor3 = if autre == id then C.texte else C.texteDoux
			b.indicateur.Visible = autre == id
		end
		pages[id].montrer(argument)
	end

	ctx = {
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

	local premier: string? = nil
	for i, onglet in ONGLETS do
		if not peut(onglet.permission) then
			continue
		end
		premier = premier or onglet.id
		local bouton = creer("TextButton", {
			Text = onglet.libelle,
			FontFace = P.moyen,
			TextSize = Theme.tailles.normal,
			TextColor3 = C.texteDoux,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = C.fond,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = i,
			Parent = barre,
		}, { Composants.coins(UDim.new(0, 6)), Composants.marges(0, 14) })
		local indicateur = creer("Frame", {
			Size = UDim2.new(0, 3, 0, 18),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -14, 0.5, 0),
			BackgroundColor3 = C.aurum,
			BorderSizePixel = 0,
			Visible = false,
			Parent = bouton,
		})
		boutonsOnglets[onglet.id] = { bouton = bouton, indicateur = indicateur }
		bouton.Activated:Connect(function()
			ouvrir(onglet.id)
		end)

		local cadre = creer("Frame", {
			Name = onglet.id,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = contenu,
		})
		local fabrique = require(script.Pages:WaitForChild(onglet.id)) :: any
		local page = fabrique(ctx, cadre)
		page.cadre = cadre
		pages[onglet.id] = page
	end

	-- Mises à jour poussées par le serveur.
	Veredarius.surReception("consul.maj", function(genre: string, donnees: any)
		for _, page in pages do
			page.maj(genre, donnees)
		end
	end)

	-- Ouverture -----------------------------------------------------------------------------

	local pilule = Composants.bouton("Consul", "primaire", function()
		basculer()
		if fenetre.Visible and not ongletActif and premier then
			ouvrir(premier)
		end
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		FontFace = P.titre,
		TextColor3 = C.aurum,
		Parent = ecran,
	})

	UserInputService.InputBegan:Connect(function(entree, traite)
		if traite or entree.KeyCode ~= RACCOURCI then
			return
		end
		basculer()
		if fenetre.Visible and not ongletActif and premier then
			ouvrir(premier)
		end
	end)

	notifier(`Consul prêt — F2 pour ouvrir le panneau ({acces.rang}).`, "info")
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
