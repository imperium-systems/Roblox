--!strict
-- Lex — configuration et règles du jeu.
-- Chaque système déclare ses réglages avec une valeur par défaut. Consul peut les modifier à chaud ;
-- les abonnés sont prévenus via Signum ("lex.change").
-- Ne stocke ni les préférences du joueur (Optio) ni la progression (Tabularius).
--
-- Les modifications valent pour ce serveur, jusqu'à sa fermeture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.Shared.Imperium
local Core = require(Imperium.Core)
local Signum = require(Imperium.Signum)

export type TypeReglage = "number" | "boolean" | "string"

export type Definition = {
	defaut: any,
	type: TypeReglage,
	description: string,
	min: number?,
	max: number?,
}

type Reglage = Definition & { valeur: any }

local Lex = {}

local reglages: { [string]: Reglage } = {}

function Lex.definir(cle: string, definition: Definition)
	assert(reglages[cle] == nil, `[Lex] réglage déjà défini : {cle}`)
	assert(type(definition.defaut) == definition.type, `[Lex] défaut de {cle} n'est pas un {definition.type}`)
	local reglage = table.clone(definition) :: any
	reglage.valeur = definition.defaut
	reglages[cle] = reglage
end

function Lex.get(cle: string): any
	local reglage = reglages[cle]
	assert(reglage, `[Lex] réglage inconnu : {cle}`)
	return reglage.valeur
end

-- Renvoie (true) ou (false, code_erreur).
function Lex.set(cle: string, valeur: any): (boolean, string?)
	local reglage = reglages[cle]
	if not reglage then
		return false, "cle_inconnue"
	end
	if type(valeur) ~= reglage.type then
		return false, "valeur_invalide"
	end
	if reglage.type == "number" then
		if not Core.estNombre(valeur) then
			return false, "valeur_invalide"
		end
		if (reglage.min and valeur < reglage.min) or (reglage.max and valeur > reglage.max) then
			return false, "hors_limites"
		end
	elseif reglage.type == "string" and not Core.estTexte(valeur, 500) then
		return false, "valeur_invalide"
	end
	local ancienne = reglage.valeur
	if ancienne == valeur then
		return true
	end
	reglage.valeur = valeur
	Signum.emit("lex.change", cle, valeur, ancienne)
	return true
end

function Lex.reinitialiser(cle: string): (boolean, string?)
	local reglage = reglages[cle]
	if not reglage then
		return false, "cle_inconnue"
	end
	return Lex.set(cle, reglage.defaut)
end

-- Appelle fn(valeur, ancienne) à chaque changement de cette clé.
function Lex.surChangement(cle: string, fn: (any, any) -> ()): () -> ()
	return Signum.on("lex.change", function(cleChangee, valeur, ancienne)
		if cleChangee == cle then
			fn(valeur, ancienne)
		end
	end)
end

function Lex.liste(): { { [string]: any } }
	local liste = {}
	for cle, reglage in reglages do
		table.insert(liste, {
			cle = cle,
			valeur = reglage.valeur,
			defaut = reglage.defaut,
			type = reglage.type,
			description = reglage.description,
			min = reglage.min,
			max = reglage.max,
		})
	end
	table.sort(liste, function(a, b)
		return a.cle < b.cle
	end)
	return liste
end

return Lex
