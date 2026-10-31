--!strict
-- Praeco — annonces officielles dans le jeu.
-- Bannières pour tous les joueurs (ce serveur ou tous les serveurs) et avis individuels.
-- Ne fait pas les notifications hors du jeu (Nuntius).
-- Les textes reçus doivent déjà être filtrés par l'appelant.

local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.Shared.Imperium
local Scriba = require(Imperium.Scriba)
local Veredarius = require(Imperium.Veredarius)

local journal = Scriba.pour("Praeco")

local CANAL = "praeco"
local SUJET = "Imperium_Praeco"

export type Genre = "info" | "alerte" | "maintenance" | "succes"

export type Annonce = {
	texte: string,
	genre: Genre,
	duree: number?,
	titre: string?,
}

local Praeco = {}

function Praeco.annoncer(annonce: Annonce)
	Veredarius.envoyerATous(CANAL, annonce)
end

-- Diffuse sur tous les serveurs du jeu, y compris celui-ci.
function Praeco.annoncerPartout(annonce: Annonce)
	local ok, erreur = pcall(MessagingService.PublishAsync, MessagingService, SUJET, annonce)
	if not ok then
		journal.avertissement("diffusion inter-serveurs impossible, annonce locale seulement :", erreur)
		Praeco.annoncer(annonce)
	end
end

function Praeco.notifier(joueur: Player, annonce: Annonce)
	Veredarius.envoyer(CANAL, joueur, annonce)
end

function Praeco.init()
	Veredarius.declarer(CANAL)
end

function Praeco.demarrer()
	local ok, erreur = pcall(MessagingService.SubscribeAsync, MessagingService, SUJET, function(message)
		Praeco.annoncer(message.Data)
	end)
	if not ok then
		journal.avertissement("abonnement inter-serveurs impossible :", erreur)
	end
end

return Praeco
