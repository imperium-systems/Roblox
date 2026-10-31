--!strict
-- Praefectus — opérations sur les serveurs en cours.
-- Annonces de maintenance, verrouillage de l'accès, redémarrage avec compte à rebours,
-- sur ce serveur ou sur tous.
-- Ne crée pas les serveurs et ne place pas les joueurs (Hospes, Lanista).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.Shared.Imperium
local Scriba = require(Imperium.Scriba)
local Signum = require(Imperium.Signum)

local journal = Scriba.pour("Praefectus")

local SUJET = "Imperium_Praefectus"
local PALIERS = { 300, 120, 60, 30, 15, 10, 5, 4, 3, 2, 1 }

local Praefectus = {
	dependances = { "Senatus", "Praeco", "Lex" },
}

local Senatus: any
local Praeco: any
local Lex: any

local verrouille = false
local demarrage = os.time()
local compteARebours: { fin: number, raison: string, jeton: {} }? = nil

local function changement()
	Signum.emit("praefectus.etat", Praefectus.etat())
end

-- API ---------------------------------------------------------------------------

function Praefectus.etat()
	return {
		verrouille = verrouille,
		joueurs = #Players:GetPlayers(),
		max = Players.MaxPlayers,
		jobId = if game.JobId == "" then "studio" else game.JobId,
		version = game.PlaceVersion,
		demarrage = demarrage,
		redemarrage = compteARebours and { fin = compteARebours.fin, raison = compteARebours.raison },
	}
end

function Praefectus.verrouiller(etat: boolean)
	verrouille = etat
	journal.info(if etat then "serveur verrouillé" else "serveur déverrouillé")
	changement()
end

function Praefectus.estVerrouille(): boolean
	return verrouille
end

-- Lance un compte à rebours puis vide le serveur. Le serveur se ferme une fois vide.
function Praefectus.redemarrer(delai: number, raison: string): (boolean, string?)
	if compteARebours then
		return false, "deja_en_cours"
	end
	local jeton = {}
	compteARebours = { fin = os.time() + delai, raison = raison, jeton = jeton }
	changement()

	local function enCours()
		return compteARebours ~= nil and compteARebours.jeton == jeton
	end

	task.spawn(function()
		local annonces: { [number]: boolean } = {}
		local premier = true
		while enCours() do
			local reste = (compteARebours :: any).fin - os.time()
			if reste <= 0 then
				break
			end
			-- Annonce au départ, puis à chaque palier franchi.
			local franchi = false
			for _, palier in PALIERS do
				if reste <= palier and not annonces[palier] then
					annonces[palier] = true
					franchi = true
				end
			end
			if premier or franchi then
				premier = false
				Praeco.annoncer({
					genre = "maintenance",
					titre = "Redémarrage du serveur",
					texte = `{raison} — dans {reste} s`,
					duree = math.min(8, reste),
				})
			end
			task.wait(1)
		end
		if not enCours() then
			return
		end
		verrouille = true
		for _, joueur in Players:GetPlayers() do
			joueur:Kick(`Le serveur redémarre : {raison}\nReconnecte-toi dans un instant.`)
		end
	end)
	return true
end

function Praefectus.annulerRedemarrage(): boolean
	if not compteARebours then
		return false
	end
	compteARebours = nil
	Praeco.annoncer({ genre = "succes", titre = "Redémarrage annulé", texte = "Le serveur reste en ligne.", duree = 6 })
	changement()
	return true
end

-- Envoie un ordre à tous les serveurs, y compris celui-ci.
function Praefectus.ordonnerPartout(ordre: string, donnees: { [string]: any }): (boolean, string?)
	local message = table.clone(donnees)
	message.ordre = ordre
	local ok, erreur = pcall(MessagingService.PublishAsync, MessagingService, SUJET, message)
	if not ok then
		journal.avertissement("ordre inter-serveurs impossible :", erreur)
		return false, "inter_serveurs"
	end
	return true
end

local function executerOrdre(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.ordre == "redemarrer" and type(message.delai) == "number" and type(message.raison) == "string" then
		Praefectus.redemarrer(math.clamp(message.delai, 5, 600), message.raison)
	elseif message.ordre == "annuler" then
		Praefectus.annulerRedemarrage()
	elseif message.ordre == "verrouiller" and type(message.etat) == "boolean" then
		Praefectus.verrouiller(message.etat)
	end
end

-- Cycle de vie --------------------------------------------------------------------

function Praefectus.init(deps)
	Senatus = deps.Senatus
	Praeco = deps.Praeco
	Lex = deps.Lex

	Lex.definir("praefectus.delai_redemarrage", {
		defaut = 60,
		type = "number",
		description = "Délai proposé par défaut avant un redémarrage, en secondes.",
		min = 5,
		max = 600,
	})
	Lex.definir("praefectus.message_verrouille", {
		defaut = "Ce serveur est en maintenance. Réessaie dans quelques minutes.",
		type = "string",
		description = "Message affiché aux joueurs refusés quand le serveur est verrouillé.",
	})
end

function Praefectus.demarrer()
	-- Le rang est calculé par Senatus à l'arrivée ; on attend son verdict.
	Signum.on("senatus.rang", function(joueur: Player)
		if verrouille and not Senatus.estStaff(joueur) then
			joueur:Kick(Lex.get("praefectus.message_verrouille"))
		end
	end)
	Players.PlayerAdded:Connect(changement)
	Players.PlayerRemoving:Connect(function()
		task.defer(changement)
	end)

	local ok, erreur = pcall(MessagingService.SubscribeAsync, MessagingService, SUJET, function(message)
		executerOrdre(message.Data)
	end)
	if not ok then
		journal.avertissement("abonnement inter-serveurs impossible :", erreur)
	end
end

return Praefectus
