--!strict
-- Veredarius — réseau.
-- Communication client-serveur nommée, avec limitation de débit par joueur côté serveur.
-- Les gestionnaires serveur doivent toujours valider ce qu'ils reçoivent : le client ment.
--
-- Serveur :
--   Veredarius.servir(nom, fn(joueur, ...) -> reponse)    requête / réponse
--   Veredarius.envoyer(nom, joueur, ...)                   serveur -> un client
--   Veredarius.envoyerA(nom, joueurs, ...)                 serveur -> plusieurs clients
--   Veredarius.envoyerATous(nom, ...)                      serveur -> tous les clients
-- Client :
--   Veredarius.demander(nom, ...) -> reponse
--   Veredarius.surReception(nom, fn(...))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signum = require(script.Parent.Signum)
local Scriba = require(script.Parent.Scriba)

local journal = Scriba.pour("Veredarius")

local NOM_DOSSIER = "ImperiumVeredarius"
local EST_SERVEUR = RunService:IsServer()

-- Seau à jetons : CAPACITE requêtes d'un coup, puis RECHARGE par seconde.
local CAPACITE = 15
local RECHARGE = 6

local Veredarius = {}

local function dossier(): Folder
	if EST_SERVEUR then
		local existant = ReplicatedStorage:FindFirstChild(NOM_DOSSIER)
		if existant then
			return existant :: Folder
		end
		local nouveau = Instance.new("Folder")
		nouveau.Name = NOM_DOSSIER
		nouveau.Parent = ReplicatedStorage
		return nouveau
	end
	return ReplicatedStorage:WaitForChild(NOM_DOSSIER) :: Folder
end

local function distant(nom: string, classe: "RemoteFunction" | "RemoteEvent"): any
	local parent = dossier()
	local cle = `{classe == "RemoteFunction" and "F" or "E"}:{nom}`
	if EST_SERVEUR then
		local existant = parent:FindFirstChild(cle)
		if existant then
			return existant
		end
		local nouveau = Instance.new(classe)
		nouveau.Name = cle
		nouveau.Parent = parent
		return nouveau
	end
	return parent:WaitForChild(cle)
end

-- Limitation de débit -----------------------------------------------------

local seaux: { [Player]: { [string]: { jetons: number, maj: number } } } = {}

local function autoriser(joueur: Player, nom: string): boolean
	local parJoueur = seaux[joueur]
	if not parJoueur then
		parJoueur = {}
		seaux[joueur] = parJoueur
	end
	local maintenant = os.clock()
	local seau = parJoueur[nom]
	if not seau then
		seau = { jetons = CAPACITE, maj = maintenant }
		parJoueur[nom] = seau
	end
	seau.jetons = math.min(CAPACITE, seau.jetons + (maintenant - seau.maj) * RECHARGE)
	seau.maj = maintenant
	if seau.jetons < 1 then
		-- Lictor pourra écouter cet événement pour noter les abus.
		Signum.emit("veredarius.abus", joueur, nom)
		return false
	end
	seau.jetons -= 1
	return true
end

if EST_SERVEUR then
	Players.PlayerRemoving:Connect(function(joueur)
		seaux[joueur] = nil
	end)
end

-- Serveur ----------------------------------------------------------------

function Veredarius.servir(nom: string, gestionnaire: (Player, ...any) -> any)
	assert(EST_SERVEUR, "Veredarius.servir est réservé au serveur")
	local fonction = distant(nom, "RemoteFunction") :: RemoteFunction
	fonction.OnServerInvoke = function(joueur: Player, ...: any)
		if not autoriser(joueur, nom) then
			return { ok = false, erreur = "trop_de_requetes" }
		end
		local ok, reponse = pcall(gestionnaire, joueur, ...)
		if not ok then
			journal.erreur(`"{nom}" a échoué pour {joueur.Name} :`, reponse)
			return { ok = false, erreur = "erreur_interne" }
		end
		return reponse
	end
end

function Veredarius.envoyer(nom: string, joueur: Player, ...: any)
	assert(EST_SERVEUR, "Veredarius.envoyer est réservé au serveur");
	(distant(nom, "RemoteEvent") :: RemoteEvent):FireClient(joueur, ...)
end

function Veredarius.envoyerA(nom: string, joueurs: { Player }, ...: any)
	assert(EST_SERVEUR, "Veredarius.envoyerA est réservé au serveur")
	local evenement = distant(nom, "RemoteEvent") :: RemoteEvent
	for _, joueur in joueurs do
		evenement:FireClient(joueur, ...)
	end
end

function Veredarius.envoyerATous(nom: string, ...: any)
	assert(EST_SERVEUR, "Veredarius.envoyerATous est réservé au serveur");
	(distant(nom, "RemoteEvent") :: RemoteEvent):FireAllClients(...)
end

-- Déclare un canal serveur -> client à l'avance, pour que les clients puissent l'attendre.
function Veredarius.declarer(nom: string)
	assert(EST_SERVEUR, "Veredarius.declarer est réservé au serveur")
	distant(nom, "RemoteEvent")
end

-- Client -----------------------------------------------------------------

function Veredarius.demander(nom: string, ...: any): any
	assert(not EST_SERVEUR, "Veredarius.demander est réservé au client")
	local fonction = distant(nom, "RemoteFunction") :: RemoteFunction
	local ok, reponse = pcall(fonction.InvokeServer, fonction, ...)
	if not ok then
		journal.avertissement(`"{nom}" sans réponse :`, reponse)
		return { ok = false, erreur = "reseau" }
	end
	return reponse
end

function Veredarius.surReception(nom: string, fn: (...any) -> ()): RBXScriptConnection
	assert(not EST_SERVEUR, "Veredarius.surReception est réservé au client")
	return (distant(nom, "RemoteEvent") :: RemoteEvent).OnClientEvent:Connect(fn)
end

return Veredarius
