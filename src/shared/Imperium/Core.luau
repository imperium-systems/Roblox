--!strict
-- Core — racine de la suite.
-- Utilitaires partagés, constantes globales et version d'Imperium.
-- Aucune logique métier ici : un utilitaire qui ne sert qu'à un système reste dans ce système.

local Core = {}

Core.VERSION = "0.1.1"

-- Durées ---------------------------------------------------------------

local UNITES: { [string]: number } = {
	s = 1,
	m = 60,
	min = 60,
	h = 3600,
	j = 86400,
	d = 86400,
	sem = 604800,
	w = 604800,
}

local DEFINITIF: { [string]: boolean } = {
	[""] = true,
	["0"] = true,
	perm = true,
	definitif = true,
}

-- Lit une durée écrite par un humain : "30s", "10m", "2h", "7j", "1h30m".
-- Un nombre sans unité compte en minutes.
-- Renvoie (true, secondes) ou (true, nil) pour une durée définitive, (false) si illisible.
function Core.lireDuree(texte: string): (boolean, number?)
	local propre = string.lower((string.gsub(texte, "%s", "")))
	if DEFINITIF[propre] then
		return true, nil
	end
	if (string.gsub(propre, "%d+%a*", "")) ~= "" then
		return false, nil
	end
	local total = 0
	for nombre, unite in string.gmatch(propre, "(%d+)(%a*)") do
		local mult = UNITES[if unite == "" then "m" else unite]
		if not mult then
			return false, nil
		end
		total += (tonumber(nombre) :: number) * mult
	end
	if total <= 0 then
		return false, nil
	end
	return true, total
end

-- 9000 -> "2 h 30 min"
function Core.formaterDuree(secondes: number?): string
	if secondes == nil then
		return "définitif"
	end
	local s = math.max(0, math.floor(secondes))
	if s < 60 then
		return `{s} s`
	end
	local j = s // 86400
	local h = (s % 86400) // 3600
	local m = (s % 3600) // 60
	local morceaux = {}
	if j > 0 then
		table.insert(morceaux, `{j} j`)
	end
	if h > 0 then
		table.insert(morceaux, `{h} h`)
	end
	if m > 0 and j == 0 then
		table.insert(morceaux, `{m} min`)
	end
	return table.concat(morceaux, " ")
end

-- Horodatage Unix -> "17/10/2026 14:05" (heure locale de la machine qui appelle)
function Core.formaterDate(horodatage: number?): string
	if horodatage == nil then
		return "—"
	end
	return os.date("%d/%m/%Y %H:%M", horodatage) :: string
end

-- Tables ---------------------------------------------------------------

function Core.copie<T>(valeur: T): T
	if type(valeur) ~= "table" then
		return valeur
	end
	local resultat = {}
	for k, v in valeur :: any do
		resultat[Core.copie(k)] = Core.copie(v)
	end
	return resultat :: any
end

function Core.cles(t: { [any]: any }): { any }
	local liste = {}
	for k in t do
		table.insert(liste, k)
	end
	return liste
end

-- Validation -------------------------------------------------------------
-- Pour les données venues du réseau : jamais faire confiance au type annoncé.

function Core.estTexte(v: any, longueurMax: number?): boolean
	return type(v) == "string" and utf8.len(v) ~= nil and #v <= (longueurMax or 200)
end

function Core.estEntierPositif(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v % 1 == 0 and v < 2 ^ 53
end

-- UserId Roblox. Les joueurs de test Studio (Player1, Player2…) ont des identifiants négatifs.
function Core.estUserId(v: any): boolean
	return type(v) == "number" and v == v and v ~= 0 and v % 1 == 0 and math.abs(v) < 2 ^ 53
end

function Core.estNombre(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

return Core
