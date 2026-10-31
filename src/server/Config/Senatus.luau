-- Configuration de Senatus : rangs du staff et qui les détient.
-- Fichier côté serveur uniquement, jamais répliqué chez les joueurs.

return {
	-- Du plus bas au plus haut. Un rang hérite des permissions du rang nommé dans `herite`.
	-- Un staff ne peut agir que sur un joueur de niveau strictement inférieur au sien.
	rangs = {
		{
			id = "moderateur",
			nom = "Modérateur",
			niveau = 1,
			couleur = Color3.fromRGB(110, 160, 210),
			permissions = {
				"consul.ouvrir",
				"consul.teleporter",
				"censor.consulter",
				"praetor.avertir",
				"praetor.mute",
				"praetor.kick",
			},
		},
		{
			id = "admin",
			nom = "Administrateur",
			niveau = 2,
			couleur = Color3.fromRGB(167, 91, 190),
			herite = "moderateur",
			permissions = {
				"praetor.ban",
				"praetor.unban",
				"praefectus.annoncer",
				"praefectus.verrouiller",
				"censor.journal",
			},
		},
		{
			id = "fondateur",
			nom = "Fondateur",
			niveau = 3,
			couleur = Color3.fromRGB(201, 162, 74),
			herite = "admin",
			permissions = { "*" },
		},
	},

	-- Attribution par UserId. Exemple : [123456789] = "admin"
	membres = {740494040},

	-- Attribution par rang dans un groupe Roblox (0 pour désactiver).
	-- Chaque entrée : rang minimal dans le groupe -> rang Imperium.
	groupe = {
		id = 0,
		rangs = {
			-- [255] = "fondateur",
			-- [250] = "admin",
			-- [200] = "moderateur",
		},
	},

	-- Le propriétaire du jeu (ou du groupe propriétaire) est fondateur.
	createurEstFondateur = true,

	-- En Studio, ton compte (Play solo) ou Player1 (serveur de test local) est fondateur.
	studioEstFondateur = true,
}
