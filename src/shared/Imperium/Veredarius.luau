--!strict
-- Veredarius: network.
-- Named client-server communication, with per-player rate limiting on the server.
-- Server handlers must always validate what they receive: the client lies.
--
-- Server:
--   Veredarius.serve(name, fn(player, ...) -> response)    request / response
--   Veredarius.send(name, player, ...)                     server -> one client
--   Veredarius.sendTo(name, players, ...)                  server -> several clients
--   Veredarius.sendToAll(name, ...)                       server -> all clients
-- Client:
--   Veredarius.request(name, ...) -> response
--   Veredarius.onReceive(name, fn(...))

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signum = require(script.Parent.Signum)
local Scriba = require(script.Parent.Scriba)

local logger = Scriba.scoped("Veredarius")

local FOLDER_NAME = "ImperiumVeredarius"
local IS_SERVER = RunService:IsServer()

-- Token bucket: CAPACITY requests at once, then REFILL per second.
local CAPACITY = 15
local REFILL = 6

local Veredarius = {}

local function folder(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local fresh = Instance.new("Folder")
		fresh.Name = FOLDER_NAME
		fresh.Parent = ReplicatedStorage
		return fresh
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function remote(name: string, className: "RemoteFunction" | "RemoteEvent"): any
	local parent = folder()
	local key = `{className == "RemoteFunction" and "F" or "E"}:{name}`
	if IS_SERVER then
		local existing = parent:FindFirstChild(key)
		if existing then
			return existing
		end
		local fresh = Instance.new(className)
		fresh.Name = key
		fresh.Parent = parent
		return fresh
	end
	return parent:WaitForChild(key)
end

-- Rate limiting -----------------------------------------------------

local buckets: { [Player]: { [string]: { tokens: number, update: number } } } = {}

local function allow(player: Player, name: string): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = CAPACITY, update = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(CAPACITY, bucket.tokens + (now - bucket.update) * REFILL)
	bucket.update = now
	if bucket.tokens < 1 then
		-- Lictor can listen to this event to record abuse.
		Signum.emit("veredarius.abuse", player, name)
		return false
	end
	bucket.tokens -= 1
	return true
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-- Server ----------------------------------------------------------------

function Veredarius.serve(name: string, handler: (Player, ...any) -> any)
	assert(IS_SERVER, "Veredarius.serve is server-only")
	local remoteFunction = remote(name, "RemoteFunction") :: RemoteFunction
	remoteFunction.OnServerInvoke = function(player: Player, ...: any)
		if not allow(player, name) then
			return { ok = false, err = "rate_limited" }
		end
		local ok, response = pcall(handler, player, ...)
		if not ok then
			logger.err(`"{name}" failed for {player.Name}:`, response)
			return { ok = false, err = "internal_error" }
		end
		return response
	end
end

function Veredarius.send(name: string, player: Player, ...: any)
	assert(IS_SERVER, "Veredarius.send is server-only");
	(remote(name, "RemoteEvent") :: RemoteEvent):FireClient(player, ...)
end

function Veredarius.sendTo(name: string, players: { Player }, ...: any)
	assert(IS_SERVER, "Veredarius.sendTo is server-only")
	local remoteEvent = remote(name, "RemoteEvent") :: RemoteEvent
	for _, player in players do
		remoteEvent:FireClient(player, ...)
	end
end

function Veredarius.sendToAll(name: string, ...: any)
	assert(IS_SERVER, "Veredarius.sendToAll is server-only");
	(remote(name, "RemoteEvent") :: RemoteEvent):FireAllClients(...)
end

-- Declares a server -> client channel in advance, so clients can wait for it.
function Veredarius.declare(name: string)
	assert(IS_SERVER, "Veredarius.declare is server-only")
	remote(name, "RemoteEvent")
end

-- Client -----------------------------------------------------------------

function Veredarius.request(name: string, ...: any): any
	assert(not IS_SERVER, "Veredarius.request is client-only")
	local remoteFunction = remote(name, "RemoteFunction") :: RemoteFunction
	local ok, response = pcall(remoteFunction.InvokeServer, remoteFunction, ...)
	if not ok then
		logger.warning(`"{name}" got no response:`, response)
		return { ok = false, err = "network" }
	end
	return response
end

function Veredarius.onReceive(name: string, fn: (...any) -> ()): RBXScriptConnection
	assert(not IS_SERVER, "Veredarius.onReceive is client-only")
	return (remote(name, "RemoteEvent") :: RemoteEvent).OnClientEvent:Connect(fn)
end

return Veredarius
