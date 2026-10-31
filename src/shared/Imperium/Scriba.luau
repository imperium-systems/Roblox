--!strict
-- Scriba — journaux techniques du moteur.
-- Ne trace pas les actions du staff ni des joueurs : c'est le rôle de Censor.

local RunService = game:GetService("RunService")

local Signum = require(script.Parent.Signum)

local NIVEAUX = {
	debug = 1,
	info = 2,
	avertissement = 3,
	erreur = 4,
}

export type Journal = {
	debug: (...any) -> (),
	info: (...any) -> (),
	avertissement: (...any) -> (),
	erreur: (...any) -> (),
}

local Scriba = {}

-- Niveau minimal affiché. Plus bavard en Studio.
Scriba.niveau = if RunService:IsStudio() then NIVEAUX.debug else NIVEAUX.info

local function assembler(...: any): string
	local morceaux = table.pack(...)
	for i = 1, morceaux.n do
		morceaux[i] = tostring(morceaux[i])
	end
	return table.concat(morceaux, " ", 1, morceaux.n)
end

-- Renvoie un journal préfixé par le nom du système.
function Scriba.pour(systeme: string): Journal
	local prefixe = `[{systeme}]`

	return {
		debug = function(...)
			if Scriba.niveau <= NIVEAUX.debug then
				print(prefixe, assembler(...))
			end
		end,
		info = function(...)
			if Scriba.niveau <= NIVEAUX.info then
				print(prefixe, assembler(...))
			end
		end,
		avertissement = function(...)
			if Scriba.niveau <= NIVEAUX.avertissement then
				warn(prefixe, assembler(...))
			end
		end,
		erreur = function(...)
			local message = assembler(...)
			warn(prefixe, "ERREUR", message)
			-- Nuntius pourra s'abonner pour relayer les erreurs graves hors du jeu.
			Signum.emit("scriba.erreur", systeme, message)
		end,
	}
end

return Scriba
