--!strict
-- Quaesitor appearance: what a character looks like, saved with a case, and the avatar
-- models rebuilt from it for a replay.
--   look      last known avatar of the player (body, clothes, accessories), kept after they leave
--   items     accessories and tools seen during the recording, by name. Those that are not
--             part of the avatar (a vest, a weapon given by the game) are copied from the
--             player if they are still on the server, else from a model of the same name in
--             ServerStorage, ReplicatedStorage or StarterPack.
-- Built models carry no script, sound or prompt, and none of their parts collide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")

local Appearance = {}

export type Look = { rig: string, description: { [string]: any }? }

local NUMBERS = {
	"Face",
	"Head",
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
	"Shirt",
	"Pants",
	"GraphicTShirt",
	"BodyTypeScale",
	"DepthScale",
	"HeadScale",
	"HeightScale",
	"ProportionScale",
	"WidthScale",
}
local COLORS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

-- Recording ----------------------------------------------------------------------------

-- Accessories worn (sorted names, one per line) and the tool in hand ("" for none).
function Appearance.itemsOf(character: Model): (string, string)
	local names = {}
	local tool = ""
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			table.insert(names, child.Name)
		elseif child:IsA("Tool") then
			tool = child.Name
		end
	end
	table.sort(names)
	return table.concat(names, "\n"), tool
end

-- The avatar of a player, as plain data that can be saved.
function Appearance.lookOf(player: Player): Look?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local look: Look = { rig = humanoid.RigType.Name }
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return look
	end
	local data: { [string]: any } = {}
	for _, key in NUMBERS do
		data[key] = (description :: any)[key]
	end
	for _, key in COLORS do
		data[key] = ((description :: any)[key] :: Color3):ToHex()
	end
	local accessories = {}
	for _, accessory in description:GetAccessories(true) do
		table.insert(accessories, {
			type = accessory.AccessoryType.Name,
			id = accessory.AssetId,
			layered = accessory.IsLayered,
			order = accessory.Order,
			puffiness = accessory.Puffiness,
		})
	end
	data.accessories = accessories
	look.description = data
	return look
end

-- Rebuilding ---------------------------------------------------------------------------

local function descriptionFrom(data: { [string]: any }): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	for _, key in NUMBERS do
		if type(data[key]) == "number" then
			pcall(function()
				(description :: any)[key] = data[key]
			end)
		end
	end
	for _, key in COLORS do
		if type(data[key]) == "string" then
			pcall(function()
				(description :: any)[key] = Color3.fromHex(data[key])
			end)
		end
	end
	local list = {}
	for _, accessory in data.accessories or {} do
		local ok, accessoryType = pcall(function()
			return (Enum.AccessoryType :: any)[accessory.type]
		end)
		if ok and accessoryType and type(accessory.id) == "number" then
			table.insert(list, {
				AccessoryType = accessoryType,
				AssetId = accessory.id,
				IsLayered = accessory.layered == true,
				Order = accessory.order,
				Puffiness = accessory.puffiness,
			})
		end
	end
	pcall(function()
		description:SetAccessories(list, true)
	end)
	return description
end

local function avatarOf(track: any): Model?
	local look = track.look
	local rig = if look and look.rig == "R6" then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
	local description: HumanoidDescription? = nil
	if look and look.description then
		description = descriptionFrom(look.description)
	elseif track.userId > 0 then
		-- No saved look: their avatar of today.
		local ok, current = pcall(Players.GetHumanoidDescriptionFromUserId, Players, track.userId)
		if ok then
			description = current
		end
	end
	if not description then
		-- Nothing known (Studio test players have no Roblox avatar): a plain one.
		description = Instance.new("HumanoidDescription")
	end
	local ok, model = pcall(
		Players.CreateHumanoidModelFromDescription,
		Players,
		description,
		rig,
		Enum.AssetTypeVerification.Always
	)
	return if ok then model else nil
end

-- Copies an instance even when it is not archivable (characters are not).
local function copy(instance: Instance): Instance?
	local archivable = instance.Archivable
	instance.Archivable = true
	local ok, clone = pcall(instance.Clone, instance)
	instance.Archivable = archivable
	return if ok then clone else nil
end

local function sanitize(root: Instance)
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("Sound")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
			or descendant:IsA("ForceField")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

-- Game items by name, indexed once per build.
local function storedItems(): { [string]: Instance }
	local index = {}
	for _, root in { ServerStorage, ReplicatedStorage, StarterPack } do
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Accessory") or descendant:IsA("Tool") then
				local key = `{descendant.ClassName}|{descendant.Name}`
				if not index[key] then
					index[key] = descendant
				end
			end
		end
	end
	return index
end

local function findItem(player: Player?, name: string, className: string, stored: () -> { [string]: Instance }): Instance?
	if player then
		for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
			local found = container and container:FindFirstChild(name)
			if found and found:IsA(className) then
				return found
			end
		end
	end
	return stored()[`{className}|{name}`]
end

-- One avatar model per track, named by UserId, with the tools in a "QuaesitorTools" folder
-- (as plain models, so nothing equips them). Tracks whose avatar cannot be built are skipped.
function Appearance.build(case: any): Folder
	local folder = Instance.new("Folder")
	-- Accessories only attach to a model in the data model; ServerStorage does not replicate.
	folder.Parent = ServerStorage

	local index: { [string]: Instance }? = nil
	local function stored(): { [string]: Instance }
		if not index then
			index = storedItems()
		end
		return index :: { [string]: Instance }
	end

	for _, track in case.tracks do
		local model = avatarOf(track)
		if not model then
			continue
		end
		model.Name = tostring(track.userId)
		model.Parent = folder
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local player = Players:GetPlayerByUserId(track.userId)

		-- Accessories the avatar does not have: given by the game.
		for _, name in track.accessories or {} do
			local present = model:FindFirstChild(name)
			if humanoid and not (present and present:IsA("Accessory")) then
				local source = findItem(player, name, "Accessory", stored)
				local clone = source and copy(source)
				if clone then
					sanitize(clone)
					pcall(humanoid.AddAccessory, humanoid, clone :: Accessory)
				end
			end
		end

		local tools = Instance.new("Folder")
		tools.Name = "QuaesitorTools"
		tools.Parent = model
		for _, name in track.tools or {} do
			local source = findItem(player, name, "Tool", stored)
			local clone = source and copy(source)
			if clone then
				local holder = Instance.new("Model")
				holder.Name = name
				for _, child in clone:GetChildren() do
					child.Parent = holder
				end
				local grip = (clone :: Tool).Grip
				clone:Destroy()
				holder:SetAttribute("Grip", grip)
				holder.Parent = tools
			end
		end

		sanitize(model)
	end
	return folder
end

return Appearance
