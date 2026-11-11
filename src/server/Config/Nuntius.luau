-- Nuntius configuration: where outside notifications go (Discord or any webhook).
-- Server-side file only, never replicated to players.
--
-- For each channel, give either:
--   secret  the name of a Roblox secret holding the webhook URL (recommended: the URL
--           stays out of the place file and of Git). Creator Dashboard > your game >
--           Secrets; in Studio: Game Settings > Security > Secrets.
--   url     the webhook URL itself (only in a private copy: anyone who reads it can post).
-- Leave both empty to turn the channel off.
--
-- Also turn on: Game Settings > Security > Allow HTTP Requests.

return {
	-- "discord" sends Discord embeds; "json" sends a plain JSON object to any other service.
	format = "discord",

	channels = {
		-- Each bug report, as soon as it is sent.
		bugs = { secret = "", url = "" },
		-- Each player report, as soon as it is sent (useful when no staff is online).
		reports = { secret = "", url = "" },
		-- Each closed ticket, with the staff comment.
		closed = { secret = "", url = "" },
	},
}
