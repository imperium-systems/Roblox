--!strict
-- Page Réglages : lecture et modification à chaud des réglages déclarés dans Lex.
-- Les modifications valent pour ce serveur jusqu'à sa fermeture.

local Consul = script.Parent.Parent
local Theme = require(Consul.Theme)
local Composants = require(Consul.Composants)

local C = Theme.couleurs
local P = Theme.polices
local creer = Composants.creer

return function(ctx: any, cadre: Frame)
	local defilant = Composants.defilant({ Parent = cadre }, 8)

	local charger: () -> ()

	local function envoyer(cle: string, donnees: { [string]: any })
		donnees.cle = cle
		task.spawn(function()
			if not ctx.executer("lex.modifier", donnees, `{cle} mis à jour.`) then
				charger()
			end
		end)
	end

	local function ligne(ordre: number, r: any)
		local carte = Composants.carte({ LayoutOrder = ordre, Parent = defilant })
		local modifie = r.valeur ~= r.defaut

		Composants.texte({
			Text = r.cle,
			FontFace = P.code,
			TextSize = Theme.tailles.petit + 1,
			TextColor3 = if modifie then C.aurum else C.texte,
			Size = UDim2.new(0.55, 0, 0, 18),
			Parent = carte,
		})
		local limites = ""
		if r.min or r.max then
			limites = `  (de {r.min or "—"} à {r.max or "—"})`
		end
		Composants.texte({
			Text = r.description .. limites,
			TextSize = Theme.tailles.petit,
			TextColor3 = C.texteDoux,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.new(0, 0, 0, 20),
			Size = UDim2.new(0.55, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = carte,
		})

		local commandes = creer("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.45, 0, 0, 34),
			Parent = carte,
		}, { Composants.pile("H", 6, Enum.HorizontalAlignment.Right) })

		if r.type == "boolean" then
			local bouton = Composants.interrupteur(r.valeur, function(v)
				envoyer(r.cle, { valeur = v })
			end)
			bouton.Parent = commandes
		else
			local champ = Composants.champ(tostring(r.defaut), {
				Text = tostring(r.valeur),
				Size = UDim2.new(1, -110, 0, 34),
				LayoutOrder = 1,
				Parent = commandes,
			})
			Composants.bouton("Appliquer", "primaire", function()
				local valeur: any = champ.Text
				if r.type == "number" then
					valeur = tonumber(champ.Text)
					if valeur == nil then
						ctx.notifier("Ce réglage attend un nombre.", "erreur")
						return
					end
				end
				envoyer(r.cle, { valeur = valeur })
			end, { LayoutOrder = 2, Parent = commandes })
		end

		if modifie then
			Composants.bouton("Défaut", "fantome", function()
				envoyer(r.cle, { reinitialiser = true })
			end, { LayoutOrder = 3, Parent = commandes })
		end
	end

	charger = function()
		local reponse = ctx.demander("lex.liste")
		Composants.vider(defilant)
		if not reponse.ok then
			Composants.paragraphe(ctx.messageErreur(reponse.erreur), { TextColor3 = C.danger, Parent = defilant })
			return
		end
		Composants.paragraphe(
			"Les valeurs en or diffèrent de leur défaut. Une modification vaut pour ce serveur jusqu'à sa fermeture.",
			{ TextColor3 = C.texteFaible, TextSize = Theme.tailles.petit, LayoutOrder = 0, Parent = defilant }
		)
		for i, r in reponse.reglages do
			ligne(i, r)
		end
	end

	return {
		montrer = function()
			task.spawn(charger)
		end,
		maj = function(genre: string)
			if genre == "reglages" and cadre.Visible then
				task.spawn(charger)
			end
		end,
	}
end
