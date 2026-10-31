-- Point d'entrée serveur d'Imperium.
-- L'ordre de la liste n'a pas d'importance : Conditor trie selon les dépendances déclarées.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Conditor = require(ReplicatedStorage.Shared.Imperium.Conditor)

local systemes = script.Imperium

Conditor.lancer({
	-- Viae
	systemes.Tabularius,
	-- Core
	systemes.Lex,
	-- Forum
	systemes.Praeco,
	-- Curia
	systemes.Senatus,
	systemes.Censor,
	systemes.Praetor,
	systemes.Praefectus,
	systemes.Consul,
})
