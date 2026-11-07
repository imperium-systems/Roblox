--!strict
-- The 12 families and 130 systems of Imperium, as shown in the panel.
--   active     the system already exists in this game
--   page       panel page that represents it (Pages folder)
--   permission permission required to open that page

export type System = {
	name: string,
	role: string,
	active: boolean?,
	page: string?,
	permission: string?,
}

export type Family = {
	name: string,
	theme: string,
	color: Color3,
	systems: { System },
}

local catalog: { Family } = {
	{
		name = "Core",
		theme = "Common services",
		color = Color3.fromHex("#D9B45B"), -- Aurum
		systems = {
			{ name = "Core", role = "Suite root", active = true },
			{ name = "Conditor", role = "Startup", active = true },
			{ name = "Lex", role = "Configuration and rules", active = true, page = "Settings", permission = "lex.edit" },
			{ name = "Signum", role = "Events", active = true },
			{ name = "Clepsydra", role = "Engine time" },
			{ name = "Scriba", role = "Technical logs", active = true },
			{ name = "Sors", role = "Randomness and seeds" },
			{ name = "Interpres", role = "Translation" },
			{ name = "Horrearius", role = "In-memory assets" },
		},
	},
	{
		name = "Curia",
		theme = "Staff tools",
		color = Color3.fromHex("#E8A0EC"), -- Purpura
		systems = {
			{ name = "Senatus", role = "Ranks and permissions", active = true },
			{ name = "Consul", role = "Admin panel", active = true },
			{ name = "Praetor", role = "Moderation and sanctions", active = true, page = "Players", permission = "consul.open" },
			{ name = "Censor", role = "Registry", active = true, page = "Log", permission = "censor.log" },
			{ name = "Lictor", role = "Anticheat" },
			{ name = "Quaesitor", role = "Investigations" },
			{ name = "Praefectus", role = "Servers", active = true, page = "Server", permission = "consul.open" },
			{ name = "Nuntius", role = "External notifications" },
			{ name = "Speculator", role = "Performance and statistics" },
		},
	},
	{
		name = "Forum",
		theme = "Social and community",
		color = Color3.fromHex("#66D2CE"), -- Aerugo
		systems = {
			{ name = "Ianitor", role = "Welcome" },
			{ name = "Tiro", role = "Tutorial" },
			{ name = "Optio", role = "Player settings" },
			{ name = "Auxilium", role = "Accessibility" },
			{ name = "Legatus", role = "Teams" },
			{ name = "Sodalis", role = "Friends and parties" },
			{ name = "Collegium", role = "Guilds and clans" },
			{ name = "Rostra", role = "Chat" },
			{ name = "Epistula", role = "Mail" },
			{ name = "Praeco", role = "Announcements", active = true },
			{ name = "Tribune", role = "Reports and support" },
			{ name = "Comitia", role = "Votes" },
			{ name = "Aedile", role = "Events" },
			{ name = "Fasti", role = "Leaderboards" },
			{ name = "Phalerae", role = "Achievements and badges" },
			{ name = "Vestiarius", role = "Cosmetics" },
			{ name = "Saltator", role = "Emotes" },
			{ name = "Viator", role = "Fast travel" },
		},
	},
	{
		name = "Aerarium",
		theme = "Economy",
		color = Color3.fromHex("#FBA962"), -- Orichalcum
		systems = {
			{ name = "Quaestor", role = "Currencies" },
			{ name = "Mercator", role = "Shops" },
			{ name = "Negotiator", role = "Trading" },
			{ name = "Auctionator", role = "Auction house" },
			{ name = "Patronus", role = "Rewards" },
			{ name = "Eques", role = "VIP and subscriptions" },
		},
	},
	{
		name = "Ludus",
		theme = "Action and progression",
		color = Color3.fromHex("#FF908E"), -- Cinnabaris
		systems = {
			{ name = "Gradus", role = "Movement" },
			{ name = "Salus", role = "Health" },
			{ name = "Statio", role = "Spawn and checkpoints" },
			{ name = "Pugna", role = "Combat" },
			{ name = "Armamentarium", role = "Weapons and equipment" },
			{ name = "Facultas", role = "Active abilities" },
			{ name = "Virtus", role = "Attributes and talents" },
			{ name = "Affectus", role = "Status effects" },
			{ name = "Cursus", role = "Progression" },
			{ name = "Centurio", role = "Quests" },
			{ name = "Fabula", role = "Narration" },
			{ name = "Colloquium", role = "Dialogue" },
			{ name = "Fides", role = "Reputation and factions" },
			{ name = "Forma", role = "Map" },
			{ name = "Caligo", role = "Fog of war" },
			{ name = "Praeda", role = "Loot" },
			{ name = "Auriga", role = "Vehicles and mounts" },
			{ name = "Tactus", role = "Interactions" },
			{ name = "Certamen", role = "Modes and rounds" },
		},
	},
	{
		name = "Villa",
		theme = "Survival, crafting, life",
		color = Color3.fromHex("#B7C874"), -- Oliva
		systems = {
			{ name = "Cellarius", role = "Inventory" },
			{ name = "Artifex", role = "Crafting" },
			{ name = "Structor", role = "Construction" },
			{ name = "Domus", role = "Housing" },
			{ name = "Agricola", role = "Agriculture" },
			{ name = "Domitor", role = "Pets" },
			{ name = "Officium", role = "Jobs and roles" },
			{ name = "Annona", role = "Survival" },
		},
	},
	{
		name = "Mundus",
		theme = "Environment",
		color = Color3.fromHex("#83D494"), -- Viridis
		systems = {
			{ name = "Lux", role = "Lighting" },
			{ name = "Caelum", role = "Sky" },
			{ name = "Hora", role = "Day and night" },
			{ name = "Annus", role = "Seasons" },
			{ name = "Tempestas", role = "Weather" },
			{ name = "Ventus", role = "Wind" },
			{ name = "Calor", role = "Temperature" },
			{ name = "Gravitas", role = "Gravity" },
			{ name = "Aqua", role = "Water" },
			{ name = "Ignis", role = "Fire" },
			{ name = "Terra", role = "Terrain" },
			{ name = "Provincia", role = "Biomes" },
			{ name = "Agrimensor", role = "Procedural generation" },
			{ name = "Silva", role = "Vegetation" },
			{ name = "Ferae", role = "Wildlife" },
			{ name = "Metallum", role = "Natural resources" },
			{ name = "Ruina", role = "Destruction" },
			{ name = "Limes", role = "World limits" },
			{ name = "Pomerium", role = "Zones" },
		},
	},
	{
		name = "Theatrum",
		theme = "Visual rendering",
		color = Color3.fromHex("#C3AEFF"), -- Amethystus
		systems = {
			{ name = "Pictor", role = "Rendering engine" },
			{ name = "Figura", role = "3D models" },
			{ name = "Textura", role = "Textures" },
			{ name = "Materia", role = "Materials" },
			{ name = "Pigmentum", role = "Shaders" },
			{ name = "Velum", role = "Post-processing" },
			{ name = "Scintilla", role = "Particles" },
			{ name = "Visus", role = "Camera" },
			{ name = "Pantomimus", role = "Animations" },
			{ name = "Motus", role = "Interpolations" },
			{ name = "Scaena", role = "Cutscenes" },
			{ name = "Fenestra", role = "Interface and HUD" },
			{ name = "Littera", role = "Text and fonts" },
			{ name = "Imago", role = "Images 2D" },
			{ name = "Tremor", role = "Camera shake" },
		},
	},
	{
		name = "Odeum",
		theme = "Audio",
		color = Color3.fromHex("#FB9DC2"), -- Rosa
		systems = {
			{ name = "Sonus", role = "Sound effects" },
			{ name = "Cantus", role = "Music" },
			{ name = "Murmur", role = "Ambience" },
			{ name = "Vox", role = "Voice" },
		},
	},
	{
		name = "Machina",
		theme = "Simulation and engine logic",
		color = Color3.fromHex("#7DCAEB"), -- Chalybs
		systems = {
			{ name = "Impetus", role = "Physics" },
			{ name = "Res", role = "Entities" },
			{ name = "Mens", role = "Artificial intelligence" },
			{ name = "Iter", role = "Navigation" },
			{ name = "Manus", role = "Input" },
			{ name = "Ordo", role = "Game states" },
			{ name = "Locus", role = "Scenes and levels" },
			{ name = "Operae", role = "Parallel tasks" },
		},
	},
	{
		name = "Viae",
		theme = "Network and data",
		color = Color3.fromHex("#93BEFF"), -- Caeruleum
		systems = {
			{ name = "Veredarius", role = "Network", active = true },
			{ name = "Hospes", role = "Servers and instances" },
			{ name = "Tessera", role = "Accounts and authentication" },
			{ name = "Tabularius", role = "Save data", active = true },
			{ name = "Lanista", role = "Matchmaking" },
		},
	},
	{
		name = "Fabrica",
		theme = "Development tools",
		color = Color3.fromHex("#B2BFCE"), -- Ferrum
		systems = {
			{ name = "Augur", role = "Antivirus" },
			{ name = "Faber", role = "Build and versions" },
			{ name = "Architectus", role = "Level editor" },
			{ name = "Machinator", role = "Visual scripting" },
			{ name = "Thesaurus", role = "Asset library" },
			{ name = "Portitor", role = "Asset import" },
			{ name = "Medicus", role = "Debugging" },
			{ name = "Probator", role = "Automated tests" },
			{ name = "Commentarius", role = "Documentation" },
			{ name = "Peregrinus", role = "Mods" },
		},
	},
}

return catalog
