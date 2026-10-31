--!strict
-- Conditor — démarrage.
-- Lance les systèmes dans l'ordre de leurs dépendances, injecte à chacun les systèmes
-- dont il a besoin, détecte les cycles et les absents, et gère l'arrêt propre.
--
-- Un système est un ModuleScript qui renvoie une table pouvant contenir :
--   dependances : { string }            noms des systèmes requis (nom du ModuleScript)
--   init(deps)                           appelé dans l'ordre, deps[nom] = système
--   demarrer()                           appelé une fois tous les init() terminés
--   arreter()                            appelé à la fermeture du serveur, en ordre inverse
--
-- Les bibliothèques sans état de Core (Core, Signum, Scriba) et Veredarius
-- sont requises directement, elles ne passent pas par Conditor.

local RunService = game:GetService("RunService")

local Scriba = require(script.Parent.Scriba)

local journal = Scriba.pour("Conditor")

type Systeme = {
	dependances: { string }?,
	init: ((deps: { [string]: any }) -> ())?,
	demarrer: (() -> ())?,
	arreter: (() -> ())?,
}

local Conditor = {}

function Conditor.lancer(modules: { ModuleScript })
	local debut = os.clock()
	local systemes: { [string]: Systeme } = {}

	for _, module in modules do
		systemes[module.Name] = (require :: any)(module)
	end

	-- Tri topologique (parcours en profondeur).
	local ordre: { string } = {}
	local etat: { [string]: "en_cours" | "fait" } = {}

	local function visiter(nom: string, chemin: { string })
		if etat[nom] == "fait" then
			return
		end
		if etat[nom] == "en_cours" then
			table.insert(chemin, nom)
			error(`[Conditor] dépendance circulaire : {table.concat(chemin, " → ")}`, 0)
		end
		local systeme = systemes[nom]
		if not systeme then
			error(`[Conditor] système manquant : "{nom}" (requis par {chemin[#chemin] or "?"})`, 0)
		end
		etat[nom] = "en_cours"
		table.insert(chemin, nom)
		for _, dep in systeme.dependances or {} do
			visiter(dep, chemin)
		end
		table.remove(chemin)
		etat[nom] = "fait"
		table.insert(ordre, nom)
	end

	for _, module in modules do
		visiter(module.Name, {})
	end

	for _, nom in ordre do
		local systeme = systemes[nom]
		if systeme.init then
			local deps = {}
			for _, dep in systeme.dependances or {} do
				deps[dep] = systemes[dep]
			end
			systeme.init(deps)
		end
	end

	for _, nom in ordre do
		local systeme = systemes[nom]
		if systeme.demarrer then
			local ok, erreur = pcall(systeme.demarrer)
			if not ok then
				journal.erreur(`{nom}.demarrer a échoué :`, erreur)
			end
		end
	end

	if RunService:IsServer() then
		game:BindToClose(function()
			for i = #ordre, 1, -1 do
				local systeme = systemes[ordre[i]]
				if systeme.arreter then
					local ok, erreur = pcall(systeme.arreter)
					if not ok then
						journal.erreur(`{ordre[i]}.arreter a échoué :`, erreur)
					end
				end
			end
		end)
	end

	journal.info(
		`{#ordre} systèmes démarrés en {math.round((os.clock() - debut) * 1000)} ms : {table.concat(ordre, ", ")}`
	)

	return systemes
end

return Conditor
