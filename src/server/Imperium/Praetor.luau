--!strict
-- Praetor — modération et sanctions.
-- Applique avertissements, mutes, expulsions et bannissements ; gère leur durée et leur levée.
-- Vérifie à la connexion si un joueur est banni.
-- N'est pas responsable des permissions : l'appelant (Consul, plus tard Lictor) a déjà décidé.
-- Ne détecte pas la triche (Lictor) et n'enquête pas (Quaesitor).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Imperium = ReplicatedStorage.Shared.Imperium
local Core = require(Imperium.Core)
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local journal = Scriba.pour("Praetor")

local SUJET = "Imperium_Praetor"

type Mesure = {
	fin: number?, -- nil = définitif
	raison: string,
	par: string,
	date: number,
}

export type Etat = {
	ban: Mesure?,
	mute: Mesure?,
	avertissements: number,
}

local Praetor = {
	dependances = { "Tabularius", "Censor", "Praeco", "Lex" },
}

local magasin: any
local Censor: any
local Praeco: any
local Lex: any

local etatsEnLigne: { [number]: Etat } = {}

local function actif(mesure: Mesure?): boolean
	return mesure ~= nil and (mesure.fin == nil or mesure.fin > os.time())
end

local function etatVide(): Etat
	return { avertissements = 0 }
end

local function messageBan(mesure: Mesure): string
	local fin = if mesure.fin then os.date("!%d/%m/%Y %H:%M UTC", mesure.fin) else "définitif"
	return `Tu es banni de ce jeu.\nMotif : {mesure.raison}\nFin : {fin}`
end

-- Mute : on coupe la parole sur chaque canal de TextChatService.
local function appliquerMute(joueur: Player)
	local muet = actif((etatsEnLigne[joueur.UserId] or etatVide()).mute)
	for _, objet in TextChatService:GetDescendants() do
		if objet:IsA("TextSource") and objet.UserId == joueur.UserId then
			objet.CanSend = not muet
		end
	end
end

local function modifier(userId: number, fn: (Etat) -> ()): Etat?
	local ok, nouveau = magasin:modifier(tostring(userId), function(ancien: Etat?)
		local etat = ancien or etatVide()
		fn(etat)
		return etat
	end)
	if not ok then
		return nil
	end
	if etatsEnLigne[userId] then
		etatsEnLigne[userId] = nouveau
	end
	return nouveau
end

local function nomActeur(acteur: Player?): string
	return if acteur then acteur.Name else "Système"
end

-- Prévient les autres serveurs qu'une sanction concerne peut-être un de leurs joueurs.
local function diffuser(userId: number, genre: string, raison: string?)
	task.spawn(function()
		local ok, erreur = pcall(MessagingService.PublishAsync, MessagingService, SUJET, {
			userId = userId,
			genre = genre,
			raison = raison,
		})
		if not ok then
			journal.avertissement("diffusion inter-serveurs impossible :", erreur)
		end
	end)
end

local function surMessage(userId: number, genre: string, raison: string?)
	local joueur = Players:GetPlayerByUserId(userId)
	if not joueur then
		return
	end
	if genre == "kick" then
		joueur:Kick(`Tu as été expulsé.\nMotif : {raison or "—"}`)
		return
	end
	-- Pour ban, mute et démute, on relit l'état depuis la sauvegarde.
	local ok, etat = magasin:lire(tostring(userId))
	if not ok then
		return
	end
	etatsEnLigne[userId] = etat or etatVide()
	if genre == "ban" and etat and actif(etat.ban) then
		joueur:Kick(messageBan(etat.ban))
	else
		appliquerMute(joueur)
	end
end

-- API --------------------------------------------------------------------------
-- Toutes les fonctions renvoient (true) ou (false, code_erreur).

function Praetor.etat(userId: number): Etat?
	if etatsEnLigne[userId] then
		return etatsEnLigne[userId]
	end
	local ok, etat = magasin:lire(tostring(userId))
	if not ok then
		return nil
	end
	return etat or etatVide()
end

function Praetor.estMuet(joueur: Player): boolean
	local etat = etatsEnLigne[joueur.UserId]
	return etat ~= nil and actif(etat.mute)
end

function Praetor.estBanni(etat: Etat): boolean
	return actif(etat.ban)
end

function Praetor.avertir(acteur: Player?, userId: number, raison: string): (boolean, string?)
	local etat = modifier(userId, function(e)
		e.avertissements += 1
	end)
	if not etat then
		return false, "sauvegarde"
	end
	Censor.noterSanction(userId, {
		type = "avertissement",
		raison = raison,
		par = nomActeur(acteur),
		parId = acteur and acteur.UserId,
		date = os.time(),
	})
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		Praeco.notifier(joueur, {
			genre = "alerte",
			titre = "Avertissement",
			texte = raison,
			duree = 12,
		})
	end
	Signum.emit("praetor.sanction", "avertissement", userId, acteur)
	return true
end

function Praetor.mute(acteur: Player?, userId: number, duree: number?, raison: string): (boolean, string?)
	local maintenant = os.time()
	local etat = modifier(userId, function(e)
		e.mute = {
			fin = if duree then maintenant + duree else nil,
			raison = raison,
			par = nomActeur(acteur),
			date = maintenant,
		}
	end)
	if not etat then
		return false, "sauvegarde"
	end
	Censor.noterSanction(userId, {
		type = "mute",
		raison = raison,
		par = nomActeur(acteur),
		parId = acteur and acteur.UserId,
		date = maintenant,
		duree = duree,
	})
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		appliquerMute(joueur)
		Praeco.notifier(joueur, {
			genre = "alerte",
			titre = "Tu es muet",
			texte = `{raison} — durée : {Core.formaterDuree(duree)}`,
			duree = 10,
		})
	else
		diffuser(userId, "mute")
	end
	Signum.emit("praetor.sanction", "mute", userId, acteur)
	return true
end

function Praetor.demute(acteur: Player?, userId: number): (boolean, string?)
	local etat = modifier(userId, function(e)
		e.mute = nil
	end)
	if not etat then
		return false, "sauvegarde"
	end
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		appliquerMute(joueur)
		Praeco.notifier(joueur, { genre = "succes", texte = "Tu peux de nouveau parler.", duree = 6 })
	else
		diffuser(userId, "demute")
	end
	Signum.emit("praetor.sanction", "demute", userId, acteur)
	return true
end

function Praetor.kick(acteur: Player?, userId: number, raison: string): (boolean, string?)
	Censor.noterSanction(userId, {
		type = "expulsion",
		raison = raison,
		par = nomActeur(acteur),
		parId = acteur and acteur.UserId,
		date = os.time(),
	})
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		joueur:Kick(`Tu as été expulsé.\nMotif : {raison}`)
	else
		diffuser(userId, "kick", raison)
	end
	Signum.emit("praetor.sanction", "kick", userId, acteur)
	return true
end

function Praetor.bannir(acteur: Player?, userId: number, duree: number?, raison: string): (boolean, string?)
	local maintenant = os.time()
	local mesure: Mesure = {
		fin = if duree then maintenant + duree else nil,
		raison = raison,
		par = nomActeur(acteur),
		date = maintenant,
	}
	local etat = modifier(userId, function(e)
		e.ban = mesure
	end)
	if not etat then
		return false, "sauvegarde"
	end
	Censor.noterSanction(userId, {
		type = "bannissement",
		raison = raison,
		par = mesure.par,
		parId = acteur and acteur.UserId,
		date = maintenant,
		duree = duree,
	})
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		joueur:Kick(messageBan(mesure))
	else
		diffuser(userId, "ban")
	end
	Signum.emit("praetor.sanction", "ban", userId, acteur)
	return true
end

function Praetor.debannir(acteur: Player?, userId: number): (boolean, string?)
	local dejaLibre = false
	local etat = modifier(userId, function(e)
		dejaLibre = not actif(e.ban)
		e.ban = nil
	end)
	if not etat then
		return false, "sauvegarde"
	end
	if dejaLibre then
		return false, "pas_banni"
	end
	Censor.noterSanction(userId, {
		type = "debannissement",
		raison = "—",
		par = nomActeur(acteur),
		parId = acteur and acteur.UserId,
		date = os.time(),
	})
	Signum.emit("praetor.sanction", "unban", userId, acteur)
	return true
end

-- Cycle de vie -------------------------------------------------------------------

local function surArrivee(joueur: Player)
	local ok, etat = magasin:lire(tostring(joueur.UserId))
	if not ok then
		-- Sauvegarde illisible : on laisse entrer plutôt que de bloquer tout le monde.
		journal.avertissement(`état de {joueur.Name} illisible, entrée autorisée`)
		etat = nil
	end
	local e: Etat = etat or etatVide()
	if actif(e.ban) then
		joueur:Kick(messageBan(e.ban :: Mesure))
		return
	end
	etatsEnLigne[joueur.UserId] = e
	appliquerMute(joueur)
end

function Praetor.init(deps)
	magasin = deps.Tabularius.magasin("Praetor")
	Censor = deps.Censor
	Praeco = deps.Praeco
	Lex = deps.Lex

	Lex.definir("praetor.duree_mute_defaut", {
		defaut = "10m",
		type = "string",
		description = "Durée proposée par défaut pour un mute (ex. 10m, 2h, 1j).",
	})
	Lex.definir("praetor.duree_ban_defaut", {
		defaut = "1j",
		type = "string",
		description = "Durée proposée par défaut pour un bannissement (« perm » pour définitif).",
	})
end

function Praetor.demarrer()
	Players.PlayerAdded:Connect(surArrivee)
	for _, joueur in Players:GetPlayers() do
		task.spawn(surArrivee, joueur)
	end
	Players.PlayerRemoving:Connect(function(joueur)
		etatsEnLigne[joueur.UserId] = nil
	end)

	-- Les TextSource apparaissent quand le joueur rejoint un canal.
	TextChatService.DescendantAdded:Connect(function(objet)
		if objet:IsA("TextSource") then
			local joueur = Players:GetPlayerByUserId(objet.UserId)
			if joueur then
				appliquerMute(joueur)
			end
		end
	end)

	-- Levée automatique des mutes expirés.
	task.spawn(function()
		while true do
			task.wait(15)
			for _, joueur in Players:GetPlayers() do
				local etat = etatsEnLigne[joueur.UserId]
				if etat and etat.mute and not actif(etat.mute) then
					etat.mute = nil
					appliquerMute(joueur)
				end
			end
		end
	end)

	local ok, erreur = pcall(MessagingService.SubscribeAsync, MessagingService, SUJET, function(message)
		local data = message.Data
		if type(data) == "table" and Core.estUserId(data.userId) then
			surMessage(data.userId, data.genre, data.raison)
		end
	end)
	if not ok then
		journal.avertissement("abonnement inter-serveurs impossible :", erreur)
	end
end

return Praetor
