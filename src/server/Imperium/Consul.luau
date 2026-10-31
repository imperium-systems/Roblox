--!strict
-- Consul — panneau admin, côté serveur.
-- Point d'entrée unique des requêtes du panneau : valide chaque requête, vérifie la permission
-- auprès de Senatus, puis délègue au système responsable (Praetor, Praefectus, Lex, Censor).
-- N'exécute pas lui-même les sanctions ni les opérations serveur.
-- Toute action du staff est inscrite au journal de Censor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Imperium = ReplicatedStorage.Shared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)
local Veredarius = require(Imperium.Veredarius)

local journal = Scriba.pour("Consul")

local Consul = {
	dependances = { "Senatus", "Praetor", "Praefectus", "Censor", "Lex", "Praeco" },
}

local Senatus: any
local Praetor: any
local Praefectus: any
local Censor: any
local Lex: any
local Praeco: any

type Reponse = { [string]: any }
type Action = {
	permission: string,
	executer: (acteur: Player, donnees: { [string]: any }) -> Reponse,
}

local function echec(code: string): Reponse
	return { ok = false, erreur = code }
end

local function succes(donnees: Reponse?): Reponse
	local r = donnees or {}
	r.ok = true
	return r
end

-- Tout texte libre du staff passe par le filtre de Roblox avant d'être montré à d'autres.
local function filtrer(texte: string, auteur: Player): string?
	local ok, resultat = pcall(function()
		local filtre = TextService:FilterStringAsync(texte, auteur.UserId)
		return filtre:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		-- En Studio, le filtre refuse souvent les joueurs de test : on laisse passer.
		if RunService:IsStudio() then
			return texte
		end
		journal.avertissement("filtrage impossible :", resultat)
		return nil
	end
	return resultat
end

local function nomDe(userId: number): string
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		return joueur.Name
	end
	local ok, nom = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok then nom else `#{userId}`
end

-- Lit et vérifie les champs communs aux sanctions : cible, motif filtré, durée.
local function lireSanction(
	acteur: Player,
	d: { [string]: any },
	avecDuree: boolean
): (Reponse?, number?, string?, number?)
	if not Core.estUserId(d.userId) then
		return echec("joueur_introuvable")
	end
	if not Senatus.peutAgirSur(acteur, d.userId) then
		return echec("rang_insuffisant")
	end
	local raison = "—"
	if d.raison ~= nil then
		if not Core.estTexte(d.raison, 200) then
			return echec("texte_invalide")
		end
		if string.match(d.raison, "%S") then
			local filtre = filtrer(d.raison, acteur)
			if not filtre then
				return echec("filtrage_echoue")
			end
			raison = filtre
		end
	end
	local duree: number? = nil
	if avecDuree then
		if not Core.estTexte(d.duree, 20) then
			return echec("duree_invalide")
		end
		local ok, secondes = Core.lireDuree(d.duree)
		if not ok then
			return echec("duree_invalide")
		end
		duree = secondes
	end
	return nil, d.userId, raison, duree
end

local function resultatPraetor(
	acteur: Player,
	action: string,
	userId: number,
	details: string,
	ok: boolean,
	erreur: string?
): Reponse
	if not ok then
		return echec(erreur or "erreur_interne")
	end
	Censor.journaliser(acteur, action, { nom = nomDe(userId), userId = userId }, details)
	return succes()
end

local function personnage(joueur: Player): Model?
	local modele = joueur.Character
	if modele and modele.PrimaryPart then
		return modele
	end
	return nil
end

-- Vue d'un joueur en ligne pour la liste du panneau.
local function resumeJoueur(joueur: Player): Reponse
	local rang = Senatus.rang(joueur)
	return {
		userId = joueur.UserId,
		nom = joueur.Name,
		affichage = joueur.DisplayName,
		rang = rang and rang.nom,
		couleurRang = rang and rang.couleur,
		niveau = Senatus.niveau(joueur),
		muet = Praetor.estMuet(joueur),
		session = Censor.dureeSession(joueur),
	}
end

-- Actions ----------------------------------------------------------------------------

local actions: { [string]: Action } = {}

actions["acces"] = {
	permission = "consul.ouvrir",
	executer = function(acteur)
		local rang = Senatus.rang(acteur)
		return succes({
			permissions = Senatus.permissionsDe(acteur),
			rang = rang.nom,
			couleurRang = rang.couleur,
			niveau = rang.niveau,
			version = Core.VERSION,
			reglages = {
				dureeMute = Lex.get("praetor.duree_mute_defaut"),
				dureeBan = Lex.get("praetor.duree_ban_defaut"),
				delaiRedemarrage = Lex.get("praefectus.delai_redemarrage"),
			},
		})
	end,
}

actions["joueurs.liste"] = {
	permission = "consul.ouvrir",
	executer = function()
		local liste = {}
		for _, joueur in Players:GetPlayers() do
			table.insert(liste, resumeJoueur(joueur))
		end
		table.sort(liste, function(a, b)
			return string.lower(a.nom) < string.lower(b.nom)
		end)
		return succes({ joueurs = liste })
	end,
}

actions["joueurs.chercher"] = {
	permission = "censor.consulter",
	executer = function(_, d)
		if not Core.estTexte(d.texte, 40) then
			return echec("texte_invalide")
		end
		local texte = string.gsub(d.texte, "^%s*@?(.-)%s*$", "%1")
		local userId = tonumber(texte)
		if not userId then
			local ok, resultat = pcall(Players.GetUserIdFromNameAsync, Players, texte)
			if not ok then
				return echec("joueur_introuvable")
			end
			userId = resultat
		end
		if not Core.estUserId(userId) then
			return echec("joueur_introuvable")
		end
		return succes({ userId = userId })
	end,
}

actions["joueurs.fiche"] = {
	permission = "censor.consulter",
	executer = function(acteur, d)
		if not Core.estUserId(d.userId) then
			return echec("joueur_introuvable")
		end
		local userId = d.userId
		local enLigne = Players:GetPlayerByUserId(userId)
		local nom = nomDe(userId)
		local fiche = Censor.fiche(userId)
		-- Un joueur de test parti n'a plus de nom chez Roblox, mais sa fiche existe encore.
		if not enLigne and not fiche and string.sub(nom, 1, 1) == "#" then
			return echec("joueur_introuvable")
		end
		local etat = Praetor.etat(userId)
		local rang = enLigne and Senatus.rang(enLigne)

		local ban = etat and etat.ban
		local mute = etat and etat.mute
		local maintenant = os.time()
		local function siActif(m)
			if m and (m.fin == nil or m.fin > maintenant) then
				return { fin = m.fin, raison = m.raison, par = m.par, date = m.date }
			end
			return nil
		end

		local sanctions = {}
		if fiche then
			for i = #fiche.sanctions, 1, -1 do
				table.insert(sanctions, fiche.sanctions[i])
			end
		end

		return succes({
			userId = userId,
			nom = nom,
			affichage = if enLigne then enLigne.DisplayName else nil,
			enLigne = enLigne ~= nil,
			session = if enLigne then Censor.dureeSession(enLigne) else nil,
			rang = rang and rang.nom,
			couleurRang = rang and rang.couleur,
			premiere = fiche and fiche.premiere,
			derniere = fiche and fiche.derniere,
			tempsJeu = fiche and fiche.tempsJeu,
			pseudos = fiche and fiche.pseudos,
			avertissements = if etat then etat.avertissements else 0,
			ban = siActif(ban),
			mute = siActif(mute),
			sanctions = sanctions,
			peutAgir = Senatus.peutAgirSur(acteur, userId),
		})
	end,
}

actions["praetor.avertir"] = {
	permission = "praetor.avertir",
	executer = function(acteur, d)
		local erreur, userId, raison = lireSanction(acteur, d, false)
		if erreur then
			return erreur
		end
		local ok, code = Praetor.avertir(acteur, userId, raison)
		return resultatPraetor(acteur, "avertissement", userId :: number, raison :: string, ok, code)
	end,
}

actions["praetor.mute"] = {
	permission = "praetor.mute",
	executer = function(acteur, d)
		local erreur, userId, raison, duree = lireSanction(acteur, d, true)
		if erreur then
			return erreur
		end
		local ok, code = Praetor.mute(acteur, userId, duree, raison)
		return resultatPraetor(
			acteur,
			"mute",
			userId :: number,
			`{raison} ({Core.formaterDuree(duree)})`,
			ok,
			code
		)
	end,
}

actions["praetor.demute"] = {
	permission = "praetor.mute",
	executer = function(acteur, d)
		local erreur, userId = lireSanction(acteur, { userId = d.userId }, false)
		if erreur then
			return erreur
		end
		local ok, code = Praetor.demute(acteur, userId)
		return resultatPraetor(acteur, "démute", userId :: number, "—", ok, code)
	end,
}

actions["praetor.kick"] = {
	permission = "praetor.kick",
	executer = function(acteur, d)
		local erreur, userId, raison = lireSanction(acteur, d, false)
		if erreur then
			return erreur
		end
		local ok, code = Praetor.kick(acteur, userId, raison)
		return resultatPraetor(acteur, "expulsion", userId :: number, raison :: string, ok, code)
	end,
}

actions["praetor.ban"] = {
	permission = "praetor.ban",
	executer = function(acteur, d)
		local erreur, userId, raison, duree = lireSanction(acteur, d, true)
		if erreur then
			return erreur
		end
		local ok, code = Praetor.bannir(acteur, userId, duree, raison)
		return resultatPraetor(
			acteur,
			"bannissement",
			userId :: number,
			`{raison} ({Core.formaterDuree(duree)})`,
			ok,
			code
		)
	end,
}

actions["praetor.unban"] = {
	permission = "praetor.unban",
	executer = function(acteur, d)
		if not Core.estUserId(d.userId) then
			return echec("joueur_introuvable")
		end
		local ok, code = Praetor.debannir(acteur, d.userId)
		return resultatPraetor(acteur, "débannissement", d.userId, "—", ok, code)
	end,
}

-- Téléportation du staff. Provisoire : reviendra à Viator quand il existera.
actions["teleporter"] = {
	permission = "consul.teleporter",
	executer = function(acteur, d)
		if not Core.estUserId(d.userId) or (d.sens ~= "vers" and d.sens ~= "amener") then
			return echec("valeur_invalide")
		end
		local cible = Players:GetPlayerByUserId(d.userId)
		if not cible then
			return echec("hors_ligne")
		end
		if d.sens == "amener" and not Senatus.peutAgirSur(acteur, d.userId) then
			return echec("rang_insuffisant")
		end
		local depart = personnage(if d.sens == "vers" then acteur else cible)
		local arrivee = personnage(if d.sens == "vers" then cible else acteur)
		if not depart or not arrivee then
			return echec("sans_personnage")
		end
		depart:PivotTo(arrivee:GetPivot() * CFrame.new(0, 0, 4))
		Censor.journaliser(
			acteur,
			if d.sens == "vers" then "téléportation vers" else "téléportation amener",
			{ nom = cible.Name, userId = cible.UserId }
		)
		return succes()
	end,
}

actions["serveur.etat"] = {
	permission = "consul.ouvrir",
	executer = function()
		return succes({ serveur = Praefectus.etat() })
	end,
}

local GENRES = { info = true, alerte = true, maintenance = true }

actions["serveur.annoncer"] = {
	permission = "praefectus.annoncer",
	executer = function(acteur, d)
		if not Core.estTexte(d.texte, 200) or not string.match(d.texte, "%S") then
			return echec("texte_invalide")
		end
		if not GENRES[d.genre] then
			return echec("valeur_invalide")
		end
		local texte = filtrer(d.texte, acteur)
		if not texte then
			return echec("filtrage_echoue")
		end
		local annonce = { genre = d.genre, texte = texte, titre = "Annonce", duree = 10 }
		if d.partout == true then
			Praeco.annoncerPartout(annonce)
		else
			Praeco.annoncer(annonce)
		end
		Censor.journaliser(acteur, if d.partout == true then "annonce (tous serveurs)" else "annonce", nil, texte)
		return succes()
	end,
}

actions["serveur.verrouiller"] = {
	permission = "praefectus.verrouiller",
	executer = function(acteur, d)
		if type(d.etat) ~= "boolean" then
			return echec("valeur_invalide")
		end
		if d.partout == true then
			local ok, code = Praefectus.ordonnerPartout("verrouiller", { etat = d.etat })
			if not ok then
				return echec(code)
			end
		else
			Praefectus.verrouiller(d.etat)
		end
		local action = if d.etat then "verrouillage" else "déverrouillage"
		Censor.journaliser(acteur, if d.partout == true then `{action} (tous serveurs)` else action)
		return succes()
	end,
}

actions["serveur.redemarrer"] = {
	permission = "praefectus.redemarrer",
	executer = function(acteur, d)
		if not Core.estNombre(d.delai) or d.delai < 5 or d.delai > 600 then
			return echec("valeur_invalide")
		end
		local raison = "Maintenance"
		if Core.estTexte(d.raison, 120) and string.match(d.raison, "%S") then
			local filtre = filtrer(d.raison, acteur)
			if not filtre then
				return echec("filtrage_echoue")
			end
			raison = filtre
		end
		local delai = math.floor(d.delai)
		local ok, code
		if d.partout == true then
			ok, code = Praefectus.ordonnerPartout("redemarrer", { delai = delai, raison = raison })
		else
			ok, code = Praefectus.redemarrer(delai, raison)
		end
		if not ok then
			return echec(code)
		end
		Censor.journaliser(
			acteur,
			if d.partout == true then "redémarrage (tous serveurs)" else "redémarrage",
			nil,
			`{raison} — {delai} s`
		)
		return succes()
	end,
}

actions["serveur.annuler"] = {
	permission = "praefectus.redemarrer",
	executer = function(acteur, d)
		if d.partout == true then
			local ok, code = Praefectus.ordonnerPartout("annuler", {})
			if not ok then
				return echec(code)
			end
		elseif not Praefectus.annulerRedemarrage() then
			return echec("rien_a_annuler")
		end
		Censor.journaliser(acteur, "annulation du redémarrage")
		return succes()
	end,
}

actions["lex.liste"] = {
	permission = "lex.modifier",
	executer = function()
		return succes({ reglages = Lex.liste() })
	end,
}

actions["lex.modifier"] = {
	permission = "lex.modifier",
	executer = function(acteur, d)
		if not Core.estTexte(d.cle, 80) then
			return echec("cle_inconnue")
		end
		local ancienne = select(2, pcall(Lex.get, d.cle))
		local ok, code
		if d.reinitialiser == true then
			ok, code = Lex.reinitialiser(d.cle)
		else
			ok, code = Lex.set(d.cle, d.valeur)
		end
		if not ok then
			return echec(code)
		end
		Censor.journaliser(acteur, "réglage", nil, `{d.cle} : {tostring(ancienne)} → {tostring(Lex.get(d.cle))}`)
		return succes({ valeur = Lex.get(d.cle) })
	end,
}

actions["censor.journal"] = {
	permission = "censor.journal",
	executer = function()
		return succes({ entrees = Censor.journal(100) })
	end,
}

-- Diffusion vers les panneaux ouverts --------------------------------------------------

local function staffAvec(permission: string): { Player }
	local liste = {}
	for _, joueur in Players:GetPlayers() do
		if Senatus.peut(joueur, permission) then
			table.insert(liste, joueur)
		end
	end
	return liste
end

local function pousser(genre: string, donnees: any?, permission: string?)
	Veredarius.envoyerA("consul.maj", staffAvec(permission or "consul.ouvrir"), genre, donnees)
end

-- Cycle de vie ---------------------------------------------------------------------------

function Consul.init(deps)
	Senatus = deps.Senatus
	Praetor = deps.Praetor
	Praefectus = deps.Praefectus
	Censor = deps.Censor
	Lex = deps.Lex
	Praeco = deps.Praeco

	Veredarius.declarer("consul.maj")
	Veredarius.declarer("consul.acces")
end

function Consul.demarrer()
	Veredarius.servir("consul", function(acteur: Player, nom: any, donnees: any)
		if type(nom) ~= "string" then
			return echec("action_inconnue")
		end
		local action = actions[nom]
		if not action then
			return echec("action_inconnue")
		end
		if not Senatus.peut(acteur, "consul.ouvrir") or not Senatus.peut(acteur, action.permission) then
			-- Chaque client demande l'accès au démarrage : un refus là est normal.
			if nom == "acces" then
				return echec("non_autorise")
			end
			journal.avertissement(`{acteur.Name} a tenté "{nom}" sans permission`)
			return echec("non_autorise")
		end
		return action.executer(acteur, if type(donnees) == "table" then donnees else {})
	end)

	-- Le rang peut arriver après le chargement du client (groupes) : on le prévient.
	Signum.on("senatus.rang", function(joueur: Player)
		if Senatus.peut(joueur, "consul.ouvrir") then
			Veredarius.envoyer("consul.acces", joueur)
		end
	end)

	Players.PlayerAdded:Connect(function()
		pousser("joueurs")
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(pousser, "joueurs")
	end)
	Signum.on("praetor.sanction", function(_genre, userId)
		pousser("joueurs")
		pousser("fiche", userId)
	end)
	Signum.on("praefectus.etat", function(etat)
		pousser("serveur", etat)
	end)
	Signum.on("censor.entree", function(entree)
		pousser("journal", entree, "censor.journal")
	end)
	Signum.on("lex.change", function()
		pousser("reglages", nil, "lex.modifier")
	end)
end

return Consul
