-- Senatus configuration: staff ranks and who holds them.
-- Server-side file only, never replicated to players.

return {
	-- From lowest to highest. A rank inherits the permissions of the rank named in `inherits`.
	-- Staff can only act on a player of a strictly lower level.
	ranks = {
		{
			id = "moderator",
			name = "Moderator",
			level = 1,
			color = Color3.fromRGB(110, 160, 210),
			permissions = {
				"consul.open",
				"consul.teleport",
				"censor.view",
				"praetor.warn",
				"praetor.mute",
				"praetor.kick",
			},
		},
		{
			id = "admin",
			name = "Administrator",
			level = 2,
			color = Color3.fromRGB(167, 91, 190),
			inherits = "moderator",
			permissions = {
				"praetor.ban",
				"praetor.unban",
				"praefectus.announce",
				"praefectus.lock",
				"censor.log",
			},
		},
		{
			id = "founder",
			name = "Founder",
			level = 3,
			color = Color3.fromRGB(201, 162, 74),
			inherits = "admin",
			permissions = { "*" },
		},
	},

	-- Assignment by UserId. Example: [123456789] = "admin"
	members = {},

	-- Assignment by rank in a Roblox group (0 to disable).
	-- Each entry: minimum rank in the group -> Imperium rank.
	group = {
		id = 0,
		ranks = {
			-- [255] = "founder",
			-- [250] = "admin",
			-- [200] = "moderator",
		},
	},

	-- The owner of the game (or of the owning group) is founder.
	creatorIsFounder = true,

	-- In Studio, your account (solo Play) or Player1 (local test server) is founder.
	studioIsFounder = true,
}
