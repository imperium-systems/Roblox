--!strict
-- Censor — registre.
-- Tient la fiche de chaque joueur (première connexion, temps de jeu, pseudos, sanctions)
-- et le journal des actions du staff. Garantit la traçabilité.
-- Ne fait pas les logs techniques (Scriba).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signum = require(ReplicatedStorage.Shared.Imperium.Signum)

local TAILLE_JOURNAL = 200
local SANCTIONS_GARDEES = 50

export type Fiche = {
	premiere: number,
	derniere: number,
	tempsJeu: number,
	pseudos: { string },
	sanctions: { Sanction },
}

export type Sanction = {
	type: string,
	raison: string,
	par: string,
	parId: number?,
	date: number,
	duree: number?,
}

export type EntreeJournal = {
	date: number,
	acteur: string,
	acteurId: number,
	action: string,
	cible: string?,
	cibleId: number?,
	details: string?,
}

local Censor = {
	dependances = { "Tabularius" },
}

local magasin: any
local arrivees: { [Player]: number } = {}

local function ficheVide(): Fiche
	return {
		premiere = os.time(),
		derniere = os.time(),
		tempsJeu = 0,
		pseudos = {},
		sanctions = {},
	}
end

function Censor.fiche(userId: number): Fiche?
	local ok, fiche = magasin:lire(`joueur_{userId}`)
	if not ok then
		return nil
	end
	return fiche
end

-- Ajoute une sanction à la fiche du joueur (appelé par Praetor).
function Censor.noterSanction(userId: number, sanction: Sanction)
	magasin:modifier(`joueur_{userId}`, function(fiche: Fiche?)
		local f = fiche or ficheVide()
		table.insert(f.sanctions, sanction)
		while #f.sanctions > SANCTIONS_GARDEES do
			table.remove(f.sanctions, 1)
		end
		return f
	end)
end

-- Inscrit une action du staff au journal.
function Censor.journaliser(acteur: Player, action: string, cible: { nom: string, userId: number }?, details: string?)
	local entree: EntreeJournal = {
		date = os.time(),
		acteur = acteur.Name,
		acteurId = acteur.UserId,
		action = action,
		cible = cible and cible.nom,
		cibleId = cible and cible.userId,
		details = details,
	}
	task.spawn(function()
		magasin:modifier("journal", function(liste: { EntreeJournal }?)
			local l = liste or {}
			table.insert(l, entree)
			while #l > TAILLE_JOURNAL do
				table.remove(l, 1)
			end
			return l
		end)
	end)
	Signum.emit("censor.entree", entree)
end

-- Entrées les plus récentes d'abord.
function Censor.journal(limite: number?): { EntreeJournal }
	local ok, liste = magasin:lire("journal")
	if not ok or not liste then
		return {}
	end
	local resultat = {}
	for i = #liste, math.max(1, #liste - (limite or TAILLE_JOURNAL) + 1), -1 do
		table.insert(resultat, liste[i])
	end
	return resultat
end

function Censor.dureeSession(joueur: Player): number
	local arrivee = arrivees[joueur]
	return if arrivee then os.time() - arrivee else 0
end

-- Cycle de vie ---------------------------------------------------------------

local function surArrivee(joueur: Player)
	arrivees[joueur] = os.time()
	magasin:modifier(`joueur_{joueur.UserId}`, function(fiche: Fiche?)
		local f = fiche or ficheVide()
		f.derniere = os.time()
		if f.pseudos[#f.pseudos] ~= joueur.Name then
			table.insert(f.pseudos, joueur.Name)
		end
		return f
	end)
end

local function surDepart(joueur: Player)
	local duree = Censor.dureeSession(joueur)
	arrivees[joueur] = nil
	magasin:modifier(`joueur_{joueur.UserId}`, function(fiche: Fiche?)
		local f = fiche or ficheVide()
		f.tempsJeu += duree
		f.derniere = os.time()
		return f
	end)
end

function Censor.init(deps)
	magasin = deps.Tabularius.magasin("Censor")
end

function Censor.demarrer()
	Players.PlayerAdded:Connect(surArrivee)
	for _, joueur in Players:GetPlayers() do
		task.spawn(surArrivee, joueur)
	end
	Players.PlayerRemoving:Connect(surDepart)
end

function Censor.arreter()
	for _, joueur in Players:GetPlayers() do
		surDepart(joueur)
	end
end

return Censor
