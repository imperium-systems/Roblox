--!strict
-- Signum — bus d'événements.
-- Un système émet, ceux que ça intéresse s'abonnent, sans que l'émetteur sache qui écoute.
-- Local à une machine : pour traverser le réseau, voir Veredarius.

type Ecouteur = {
	fn: (...any) -> (),
	priorite: number,
}

local Signum = {}

local ecouteurs: { [string]: { Ecouteur } } = {}

-- S'abonne à un événement. Les priorités élevées sont appelées en premier.
-- Renvoie une fonction de désabonnement.
function Signum.on(nom: string, fn: (...any) -> (), priorite: number?): () -> ()
	local liste = ecouteurs[nom]
	if not liste then
		liste = {}
		ecouteurs[nom] = liste
	end
	local ecouteur: Ecouteur = { fn = fn, priorite = priorite or 0 }
	table.insert(liste, ecouteur)
	table.sort(liste, function(a, b)
		return a.priorite > b.priorite
	end)

	return function()
		local index = table.find(liste, ecouteur)
		if index then
			table.remove(liste, index)
		end
	end
end

-- Émet un événement. Une erreur dans un écouteur n'empêche pas les suivants d'être appelés.
function Signum.emit(nom: string, ...: any)
	local liste = ecouteurs[nom]
	if not liste then
		return
	end
	for _, ecouteur in table.clone(liste) do
		local ok, erreur = pcall(ecouteur.fn, ...)
		if not ok then
			warn(`[Signum] écouteur de "{nom}" en erreur : {erreur}`)
		end
	end
end

return Signum
