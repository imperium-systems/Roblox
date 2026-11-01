--!strict
-- Brand images, once imported into Roblox.
-- The files are in assets/: import them in Studio (Asset Manager > Bulk Import),
-- then paste each id here. At 0, the panel falls back to text and color.

export type Insignia = { body: number, color: number }

local Logos = {
	horizontal = 0, -- assets/imperium-horizontal.png
	symbol = 0, -- assets/imperium-symbol.png

	-- assets/insignia/<family>-body.png and <family>-color.png
	insignias = {
		Core = { body = 0, color = 0 },
		Curia = { body = 0, color = 0 },
		Forum = { body = 0, color = 0 },
		Aerarium = { body = 0, color = 0 },
		Ludus = { body = 0, color = 0 },
		Villa = { body = 0, color = 0 },
		Mundus = { body = 0, color = 0 },
		Theatrum = { body = 0, color = 0 },
		Odeum = { body = 0, color = 0 },
		Machina = { body = 0, color = 0 },
		Viae = { body = 0, color = 0 },
		Fabrica = { body = 0, color = 0 },
	} :: { [string]: Insignia },
}

return Logos
