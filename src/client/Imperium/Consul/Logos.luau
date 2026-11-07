--!strict
-- Brand images, imported into Roblox from assets/ (Asset Manager > Bulk Import).
-- At 0, the panel falls back to text and color.

export type Insignia = { body: number, color: number }

local Logos = {
	horizontal = 103258510028969, -- assets/imperium-horizontal.png
	symbol = 89987018608722, -- assets/imperium-symbol.png

	-- assets/insignia/<family>-body.png and <family>-color.png
	insignias = {
		Core = { body = 92900521317016, color = 116190485508387 },
		Curia = { body = 101397921121225, color = 101624408962328 },
		Forum = { body = 127553236233846, color = 117237410602115 },
		Aerarium = { body = 134789204935106, color = 94626311320189 },
		Ludus = { body = 132629786595813, color = 97408256102368 },
		Villa = { body = 87950850881929, color = 129531850199919 },
		Mundus = { body = 97541437806566, color = 79894883474379 },
		Theatrum = { body = 105427026995197, color = 127263697174998 },
		Odeum = { body = 108667281621478, color = 99765896392950 },
		Machina = { body = 123604536459943, color = 91186991716531 },
		Viae = { body = 112237538278403, color = 77525441090248 },
		Fabrica = { body = 86961672985593, color = 121332058649108 },
	} :: { [string]: Insignia },
}

return Logos
