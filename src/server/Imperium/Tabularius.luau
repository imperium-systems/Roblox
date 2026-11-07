--!strict
-- Tabularius: persistence.
-- Reads and writes persistent data, with retries.
-- Does not know what the data represents.
--
-- Minimal version: key/value stores on DataStoreService.
-- If DataStores are unavailable (Studio without "Enable Studio Access to API Services"),
-- falls back to memory and says so: nothing is lost during the session, everything is on close.
-- Coming later: player profiles with session locking and format migrations.

local DataStoreService = game:GetService("DataStoreService")

local Scriba = require(game:GetService("ReplicatedStorage").ImperiumShared.Imperium.Scriba)

local logger = Scriba.scoped("Tabularius")

-- Bumped when saved field names change: older test data stays behind.
local PREFIX = "ImperiumV2_"
local RETRIES = 3

export type KeyStore = {
	read: (self: KeyStore, key: string) -> (boolean, any),
	update: (self: KeyStore, key: string, fn: (previous: any) -> any) -> (boolean, any),
}

local Tabularius = {}

local inMemory = false
local memory: { [string]: { [string]: any } } = {}

local function withRetries<T>(operation: () -> T): (boolean, any)
	local lastError
	for attempt = 1, RETRIES do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < RETRIES then
			task.wait(attempt)
		end
	end
	return false, lastError
end

function Tabularius.keyStore(name: string): KeyStore
	local store: DataStore? = nil
	if not inMemory then
		store = DataStoreService:GetDataStore(PREFIX .. name)
	end
	memory[name] = memory[name] or {}
	local localValues = memory[name]

	local keyStore = {}

	function keyStore.read(_self: KeyStore, key: string): (boolean, any)
		if inMemory or not store then
			return true, localValues[key]
		end
		local active = store :: DataStore
		local ok, value = withRetries(function()
			return active:GetAsync(key)
		end)
		if not ok then
			logger.err(`read {name}/{key}:`, value)
		end
		return ok, value
	end

	function keyStore.update(_self: KeyStore, key: string, fn: (any) -> any): (boolean, any)
		if inMemory or not store then
			local fresh = fn(localValues[key])
			if fresh ~= nil then
				localValues[key] = fresh
			end
			return true, localValues[key]
		end
		local active = store :: DataStore
		local ok, value = withRetries(function()
			return active:UpdateAsync(key, fn)
		end)
		if not ok then
			logger.err(`write {name}/{key}:`, value)
		end
		return ok, value
	end

	return keyStore :: any
end

function Tabularius.isInMemory(): boolean
	return inMemory
end

function Tabularius.init()
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(PREFIX .. "Probe"):GetAsync("probe")
	end)
	if not ok then
		inMemory = true
		logger.warning(
			"DataStores unavailable, saving in memory only. "
				.. "In Studio: Game Settings > Security > Enable Studio Access to API Services. ("
				.. tostring(err)
				.. ")"
		)
	end
end

return Tabularius
