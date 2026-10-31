--!strict
-- Senatus — rangs et permissions du staff.
-- Répond à « ce joueur a-t-il le droit de… ? ». Gère l'héritage entre rangs.
-- Ne gère ni les rangs de jeu (Cursus) ni le statut VIP (Eques).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Imperium = ReplicatedStorage.Shared.Imperium
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local config = require(script.Parent.Parent.Config.Senatus) :: any

local journal = Scriba.pour("Senatus")

export type Rang = {
	id: string,
	nom: string,
	niveau: number,
	couleur: Color3,
	permissions: { [string]: true },
}

local Senatus = {}

local rangs: { [string]: Rang } = {}
local rangDesJoueurs: { [Player]: Rang } = {}

local function compilerRangs()
	local brut: { [string]: any } = {}
	for _, definition in config.rangs do
		brut[definition.id] = definition
	end

	local function permissionsDe(id: string, vus: { [string]: boolean }): { [string]: true }
		assert(not vus[id], `[Senatus] héritage circulaire autour de "{id}"`)
		vus[id] = true
		local definition = brut[id]
		assert(definition, `[Senatus] rang inconnu : "{id}"`)
		local resultat: { [string]: true } = {}
		if definition.herite then
			for permission in permissionsDe(definition.herite, vus) do
				resultat[permission] = true
			end
		end
		for _, permission in definition.permissions do
			resultat[permission] = true
		end
		return resultat
	end

	for id, definition in brut do
		rangs[id] = {
			id = id,
			nom = definition.nom,
			niveau = definition.niveau,
			couleur = definition.couleur,
			permissions = permissionsDe(id, {}),
		}
	end
end

local function meilleur(a: Rang?, b: Rang?): Rang?
	if not a then
		return b
	end
	if not b then
		return a
	end
	return if b.niveau > a.niveau then b else a
end

local function rangParGroupe(rangDansGroupe: number): Rang?
	local trouve: Rang? = nil
	for seuil, id in config.groupe.rangs do
		if rangDansGroupe >= seuil then
			trouve = meilleur(trouve, rangs[id])
		end
	end
	return trouve
end

-- Calcule le rang d'un UserId, en ligne ou non. Peut céder (appels web).
local function calculerRang(userId: number, joueur: Player?): Rang?
	local rang: Rang? = nil

	local id = config.membres[userId]
	if id then
		rang = meilleur(rang, rangs[id])
	end

	-- En Studio : ton propre compte en Play solo, ou Player1 en serveur de test local.
	-- Player2, Player3… restent de simples joueurs pour pouvoir tester les sanctions.
	if config.studioEstFondateur and RunService:IsStudio() and joueur and (userId > 0 or userId == -1) then
		rang = meilleur(rang, rangs.fondateur)
	end

	if config.createurEstFondateur then
		if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
			rang = meilleur(rang, rangs.fondateur)
		end
	end

	-- Rangs de groupe : celui du groupe configuré, et propriétaire du groupe créateur.
	local groupeConfig = config.groupe.id
	local groupeCreateur = if config.createurEstFondateur and game.CreatorType == Enum.CreatorType.Group
		then game.CreatorId
		else 0
	if groupeConfig ~= 0 or groupeCreateur ~= 0 then
		local ok, groupes = pcall(GroupService.GetGroupsAsync, GroupService, userId)
		if ok then
			for _, groupe in groupes do
				if groupe.Id == groupeConfig then
					rang = meilleur(rang, rangParGroupe(groupe.Rank))
				end
				if groupe.Id == groupeCreateur and groupe.Rank == 255 then
					rang = meilleur(rang, rangs.fondateur)
				end
			end
		else
			journal.avertissement(`groupes de {userId} illisibles :`, groupes)
		end
	end

	return rang
end

-- API ----------------------------------------------------------------------

function Senatus.rang(joueur: Player): Rang?
	return rangDesJoueurs[joueur]
end

function Senatus.niveau(joueur: Player): number
	local rang = rangDesJoueurs[joueur]
	return if rang then rang.niveau else 0
end

-- Niveau d'un joueur qui peut être hors ligne. Peut céder.
function Senatus.niveauDe(userId: number): number
	local joueur = Players:GetPlayerByUserId(userId)
	if joueur then
		return Senatus.niveau(joueur)
	end
	local rang = calculerRang(userId, nil)
	return if rang then rang.niveau else 0
end

-- "praetor.ban" est accordé par "praetor.ban", "praetor.*" ou "*".
function Senatus.peut(joueur: Player, permission: string): boolean
	local rang = rangDesJoueurs[joueur]
	if not rang then
		return false
	end
	local p = rang.permissions
	if p["*"] or p[permission] then
		return true
	end
	local famille = string.match(permission, "^([^%.]+)%.")
	return famille ~= nil and p[famille .. ".*"] == true
end

-- Un staff ne peut agir que sur plus petit que lui.
function Senatus.peutAgirSur(acteur: Player, cibleUserId: number): boolean
	if acteur.UserId == cibleUserId then
		return false
	end
	return Senatus.niveau(acteur) > Senatus.niveauDe(cibleUserId)
end

-- Liste des permissions connues, pour que l'interface sache quoi afficher.
local PERMISSIONS_CONNUES = {
	"consul.ouvrir",
	"consul.teleporter",
	"censor.consulter",
	"censor.journal",
	"praetor.avertir",
	"praetor.mute",
	"praetor.kick",
	"praetor.ban",
	"praetor.unban",
	"praefectus.annoncer",
	"praefectus.verrouiller",
	"praefectus.redemarrer",
	"lex.modifier",
}

function Senatus.permissionsDe(joueur: Player): { [string]: boolean }
	local resultat = {}
	for _, permission in PERMISSIONS_CONNUES do
		resultat[permission] = Senatus.peut(joueur, permission)
	end
	return resultat
end

function Senatus.estStaff(joueur: Player): boolean
	return Senatus.niveau(joueur) > 0
end

-- Cycle de vie ---------------------------------------------------------------

local function surArrivee(joueur: Player)
	local rang = calculerRang(joueur.UserId, joueur)
	if not joueur.Parent then
		return
	end
	if rang then
		rangDesJoueurs[joueur] = rang
		journal.info(`{joueur.Name} : {rang.nom}`)
	end
	Signum.emit("senatus.rang", joueur, rang)
end

function Senatus.init()
	compilerRangs()
end

function Senatus.demarrer()
	Players.PlayerAdded:Connect(surArrivee)
	for _, joueur in Players:GetPlayers() do
		task.spawn(surArrivee, joueur)
	end
	Players.PlayerRemoving:Connect(function(joueur)
		rangDesJoueurs[joueur] = nil
	end)
end

return Senatus
