--!strict
-- Tabularius — sauvegarde.
-- Lecture et écriture des données persistantes, avec nouvelles tentatives.
-- Ne sait pas ce que représentent les données.
--
-- Version minimale : magasins clé/valeur sur DataStoreService.
-- Si les DataStores sont indisponibles (Studio sans « Enable Studio Access to API Services »),
-- bascule en mémoire et le signale : rien n'est perdu pendant la session, tout l'est à la fermeture.
-- À venir : profils joueur avec verrouillage de session et migrations de format.

local DataStoreService = game:GetService("DataStoreService")

local Scriba = require(game:GetService("ReplicatedStorage").Shared.Imperium.Scriba)

local journal = Scriba.pour("Tabularius")

local PREFIXE = "Imperium_"
local TENTATIVES = 3

export type Magasin = {
	lire: (self: Magasin, cle: string) -> (boolean, any),
	modifier: (self: Magasin, cle: string, fn: (ancien: any) -> any) -> (boolean, any),
}

local Tabularius = {}

local enMemoire = false
local memoire: { [string]: { [string]: any } } = {}

local function avecTentatives<T>(operation: () -> T): (boolean, any)
	local derniereErreur
	for essai = 1, TENTATIVES do
		local ok, resultat = pcall(operation)
		if ok then
			return true, resultat
		end
		derniereErreur = resultat
		if essai < TENTATIVES then
			task.wait(essai)
		end
	end
	return false, derniereErreur
end

function Tabularius.magasin(nom: string): Magasin
	local store: DataStore? = nil
	if not enMemoire then
		store = DataStoreService:GetDataStore(PREFIXE .. nom)
	end
	memoire[nom] = memoire[nom] or {}
	local local_ = memoire[nom]

	local magasin = {}

	function magasin.lire(_self: Magasin, cle: string): (boolean, any)
		if enMemoire or not store then
			return true, local_[cle]
		end
		local actif = store :: DataStore
		local ok, valeur = avecTentatives(function()
			return actif:GetAsync(cle)
		end)
		if not ok then
			journal.erreur(`lecture {nom}/{cle} :`, valeur)
		end
		return ok, valeur
	end

	function magasin.modifier(_self: Magasin, cle: string, fn: (any) -> any): (boolean, any)
		if enMemoire or not store then
			local nouveau = fn(local_[cle])
			if nouveau ~= nil then
				local_[cle] = nouveau
			end
			return true, local_[cle]
		end
		local actif = store :: DataStore
		local ok, valeur = avecTentatives(function()
			return actif:UpdateAsync(cle, fn)
		end)
		if not ok then
			journal.erreur(`écriture {nom}/{cle} :`, valeur)
		end
		return ok, valeur
	end

	return magasin :: any
end

function Tabularius.estEnMemoire(): boolean
	return enMemoire
end

function Tabularius.init()
	local ok, erreur = pcall(function()
		DataStoreService:GetDataStore(PREFIXE .. "Sonde"):GetAsync("sonde")
	end)
	if not ok then
		enMemoire = true
		journal.avertissement(
			"DataStores indisponibles, sauvegarde en mémoire seulement. "
				.. "En Studio : Game Settings > Security > Enable Studio Access to API Services. ("
				.. tostring(erreur)
				.. ")"
		)
	end
end

return Tabularius
