--[[
	IMPERIUM: installation

	1. Ungroup this model (right click > Ungroup).

	2. Drag the content of each folder into the service with the same name:
	     ReplicatedStorage     > ImperiumShared   into ReplicatedStorage
	     ServerScriptService   > ImperiumServer   into ServerScriptService
	     StarterPlayerScripts  > ImperiumClient   into StarterPlayer > StarterPlayerScripts

	3. Declare your staff in ImperiumServer > Config > Senatus:
	     members = {
	         [123456789] = "admin",
	     },
	   Available ranks: "moderator", "admin", "founder".
	   The owner of the game is founder automatically.

	4. Delete the empty folders.

	Open the panel in game with F2, or the Imperium button at the bottom right.

	To save sanctions in Studio:
	Game Settings > Security > Enable Studio Access to API Services.

	This file does not run.
]]

return nil
