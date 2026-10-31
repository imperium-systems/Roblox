--!strict
-- Les 12 familles et les 130 systèmes d'Imperium, tels que les montre le panneau.
--   actif      le système existe déjà dans ce jeu
--   page       page du panneau qui le représente (dossier Pages)
--   permission permission requise pour ouvrir cette page

export type Systeme = {
	nom: string,
	role: string,
	actif: boolean?,
	page: string?,
	permission: string?,
}

export type Famille = {
	nom: string,
	theme: string,
	couleur: Color3,
	systemes: { Systeme },
}

local catalogue: { Famille } = {
	{
		nom = "Core",
		theme = "Services communs",
		couleur = Color3.fromRGB(201, 162, 74), -- Aurum
		systemes = {
			{ nom = "Core", role = "Racine de la suite", actif = true },
			{ nom = "Conditor", role = "Démarrage", actif = true },
			{ nom = "Lex", role = "Configuration et règles", actif = true, page = "Reglages", permission = "lex.modifier" },
			{ nom = "Signum", role = "Événements", actif = true },
			{ nom = "Clepsydra", role = "Temps moteur" },
			{ nom = "Scriba", role = "Journaux techniques", actif = true },
			{ nom = "Sors", role = "Hasard et graines" },
			{ nom = "Interpres", role = "Traduction" },
			{ nom = "Horrearius", role = "Assets en mémoire" },
		},
	},
	{
		nom = "Curia",
		theme = "Outils du staff",
		couleur = Color3.fromRGB(167, 91, 190), -- Purpura
		systemes = {
			{ nom = "Senatus", role = "Rangs et permissions", actif = true },
			{ nom = "Consul", role = "Panneau admin", actif = true },
			{ nom = "Praetor", role = "Modération et sanctions", actif = true, page = "Joueurs", permission = "consul.ouvrir" },
			{ nom = "Censor", role = "Registre", actif = true, page = "Journal", permission = "censor.journal" },
			{ nom = "Lictor", role = "Anticheat" },
			{ nom = "Quaesitor", role = "Enquêtes" },
			{ nom = "Praefectus", role = "Serveurs", actif = true, page = "Serveur", permission = "consul.ouvrir" },
			{ nom = "Nuntius", role = "Notifications externes" },
			{ nom = "Speculator", role = "Performances et statistiques" },
		},
	},
	{
		nom = "Forum",
		theme = "Social et communauté",
		couleur = Color3.fromRGB(86, 165, 150), -- Aerugo
		systemes = {
			{ nom = "Ianitor", role = "Accueil" },
			{ nom = "Tiro", role = "Tutoriel" },
			{ nom = "Optio", role = "Paramètres du joueur" },
			{ nom = "Auxilium", role = "Accessibilité" },
			{ nom = "Legatus", role = "Équipes" },
			{ nom = "Sodalis", role = "Amis et groupes" },
			{ nom = "Collegium", role = "Guildes et clans" },
			{ nom = "Rostra", role = "Chat" },
			{ nom = "Epistula", role = "Courrier" },
			{ nom = "Praeco", role = "Annonces", actif = true },
			{ nom = "Tribune", role = "Signalements et support" },
			{ nom = "Comitia", role = "Votes" },
			{ nom = "Aedile", role = "Événements" },
			{ nom = "Fasti", role = "Classements" },
			{ nom = "Phalerae", role = "Succès et badges" },
			{ nom = "Vestiarius", role = "Cosmétiques" },
			{ nom = "Saltator", role = "Emotes" },
			{ nom = "Viator", role = "Voyage rapide" },
		},
	},
	{
		nom = "Aerarium",
		theme = "Économie",
		couleur = Color3.fromRGB(205, 133, 70), -- Orichalcum
		systemes = {
			{ nom = "Quaestor", role = "Monnaies" },
			{ nom = "Mercator", role = "Boutiques" },
			{ nom = "Negotiator", role = "Échanges" },
			{ nom = "Auctionator", role = "Hôtel des ventes" },
			{ nom = "Patronus", role = "Récompenses" },
			{ nom = "Eques", role = "VIP et abonnements" },
		},
	},
	{
		nom = "Ludus",
		theme = "Action et progression",
		couleur = Color3.fromRGB(214, 78, 56), -- Cinnabaris
		systemes = {
			{ nom = "Gradus", role = "Déplacements" },
			{ nom = "Salus", role = "Santé" },
			{ nom = "Statio", role = "Apparition et sauvegarde" },
			{ nom = "Pugna", role = "Combat" },
			{ nom = "Armamentarium", role = "Armes et équipements" },
			{ nom = "Facultas", role = "Capacités actives" },
			{ nom = "Virtus", role = "Attributs et talents" },
			{ nom = "Affectus", role = "Effets d'état" },
			{ nom = "Cursus", role = "Progression" },
			{ nom = "Centurio", role = "Quêtes" },
			{ nom = "Fabula", role = "Narration" },
			{ nom = "Colloquium", role = "Dialogues" },
			{ nom = "Fides", role = "Réputation et factions" },
			{ nom = "Forma", role = "Carte" },
			{ nom = "Caligo", role = "Brouillard de guerre" },
			{ nom = "Praeda", role = "Butin" },
			{ nom = "Auriga", role = "Véhicules et montures" },
			{ nom = "Tactus", role = "Interactions" },
			{ nom = "Certamen", role = "Modes et manches" },
		},
	},
	{
		nom = "Villa",
		theme = "Survie, artisanat, vie",
		couleur = Color3.fromRGB(150, 155, 72), -- Oliva
		systemes = {
			{ nom = "Cellarius", role = "Inventaire" },
			{ nom = "Artifex", role = "Artisanat" },
			{ nom = "Structor", role = "Construction" },
			{ nom = "Domus", role = "Logements" },
			{ nom = "Agricola", role = "Agriculture" },
			{ nom = "Domitor", role = "Familiers" },
			{ nom = "Officium", role = "Métiers et rôles" },
			{ nom = "Annona", role = "Survie" },
		},
	},
	{
		nom = "Mundus",
		theme = "Environnement",
		couleur = Color3.fromRGB(78, 165, 98), -- Viridis
		systemes = {
			{ nom = "Lux", role = "Éclairage" },
			{ nom = "Caelum", role = "Ciel" },
			{ nom = "Hora", role = "Jour et nuit" },
			{ nom = "Annus", role = "Saisons" },
			{ nom = "Tempestas", role = "Météo" },
			{ nom = "Ventus", role = "Vent" },
			{ nom = "Calor", role = "Température" },
			{ nom = "Gravitas", role = "Gravité" },
			{ nom = "Aqua", role = "Eau" },
			{ nom = "Ignis", role = "Feu" },
			{ nom = "Terra", role = "Terrain" },
			{ nom = "Provincia", role = "Biomes" },
			{ nom = "Agrimensor", role = "Génération procédurale" },
			{ nom = "Silva", role = "Végétation" },
			{ nom = "Ferae", role = "Faune" },
			{ nom = "Metallum", role = "Ressources naturelles" },
			{ nom = "Ruina", role = "Destruction" },
			{ nom = "Limes", role = "Limites du monde" },
			{ nom = "Pomerium", role = "Zones" },
		},
	},
	{
		nom = "Theatrum",
		theme = "Rendu visuel",
		couleur = Color3.fromRGB(150, 110, 215), -- Amethystus
		systemes = {
			{ nom = "Pictor", role = "Moteur de rendu" },
			{ nom = "Figura", role = "Modèles 3D" },
			{ nom = "Textura", role = "Textures" },
			{ nom = "Materia", role = "Matériaux" },
			{ nom = "Pigmentum", role = "Shaders" },
			{ nom = "Velum", role = "Post-traitement" },
			{ nom = "Scintilla", role = "Particules" },
			{ nom = "Visus", role = "Caméra" },
			{ nom = "Pantomimus", role = "Animations" },
			{ nom = "Motus", role = "Interpolations" },
			{ nom = "Scaena", role = "Cinématiques" },
			{ nom = "Fenestra", role = "Interface et HUD" },
			{ nom = "Littera", role = "Texte et polices" },
			{ nom = "Imago", role = "Images 2D" },
			{ nom = "Tremor", role = "Secousses" },
		},
	},
	{
		nom = "Odeum",
		theme = "Audio",
		couleur = Color3.fromRGB(222, 125, 155), -- Rosa
		systemes = {
			{ nom = "Sonus", role = "Effets sonores" },
			{ nom = "Cantus", role = "Musique" },
			{ nom = "Murmur", role = "Ambiances" },
			{ nom = "Vox", role = "Voix" },
		},
	},
	{
		nom = "Machina",
		theme = "Simulation et logique moteur",
		couleur = Color3.fromRGB(125, 145, 165), -- Chalybs
		systemes = {
			{ nom = "Impetus", role = "Physique" },
			{ nom = "Res", role = "Entités" },
			{ nom = "Mens", role = "Intelligence artificielle" },
			{ nom = "Iter", role = "Navigation" },
			{ nom = "Manus", role = "Entrées" },
			{ nom = "Ordo", role = "États du jeu" },
			{ nom = "Locus", role = "Scènes et niveaux" },
			{ nom = "Operae", role = "Tâches parallèles" },
		},
	},
	{
		nom = "Viae",
		theme = "Réseau et données",
		couleur = Color3.fromRGB(80, 135, 205), -- Caeruleum
		systemes = {
			{ nom = "Veredarius", role = "Réseau", actif = true },
			{ nom = "Hospes", role = "Serveurs et instances" },
			{ nom = "Tessera", role = "Comptes et authentification" },
			{ nom = "Tabularius", role = "Sauvegarde", actif = true },
			{ nom = "Lanista", role = "Matchmaking" },
		},
	},
	{
		nom = "Fabrica",
		theme = "Outils de développement",
		couleur = Color3.fromRGB(145, 135, 130), -- Ferrum
		systemes = {
			{ nom = "Augur", role = "Antivirus" },
			{ nom = "Faber", role = "Build et versions" },
			{ nom = "Architectus", role = "Éditeur de niveaux" },
			{ nom = "Machinator", role = "Scripting visuel" },
			{ nom = "Thesaurus", role = "Bibliothèque d'assets" },
			{ nom = "Portitor", role = "Import des assets" },
			{ nom = "Medicus", role = "Débogage" },
			{ nom = "Probator", role = "Tests automatisés" },
			{ nom = "Commentarius", role = "Documentation" },
			{ nom = "Peregrinus", role = "Mods" },
		},
	},
}

return catalogue
