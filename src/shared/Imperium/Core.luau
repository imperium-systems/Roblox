--!strict
-- Core: root of the suite.
-- Shared utilities, global constants and the Imperium version.
-- No business logic here: a utility used by a single system stays in that system.

local Core = {}

Core.VERSION = "0.1.4"

-- Durations ---------------------------------------------------------------

local UNITS: { [string]: number } = {
	s = 1,
	m = 60,
	min = 60,
	h = 3600,
	d = 86400,
	w = 604800,
}

local PERMANENT: { [string]: boolean } = {
	[""] = true,
	["0"] = true,
	perm = true,
}

-- Reads a human-written duration: "30s", "10m", "2h", "7d", "1h30m".
-- A number without a unit counts as minutes.
-- Returns (true, seconds) or (true, nil) for a permanent duration, (false) if unreadable.
function Core.parseDuration(text: string): (boolean, number?)
	local clean = string.lower((string.gsub(text, "%s", "")))
	if PERMANENT[clean] then
		return true, nil
	end
	if (string.gsub(clean, "%d+%a*", "")) ~= "" then
		return false, nil
	end
	local total = 0
	for amount, unit in string.gmatch(clean, "(%d+)(%a*)") do
		local mult = UNITS[if unit == "" then "m" else unit]
		if not mult then
			return false, nil
		end
		total += (tonumber(amount) :: number) * mult
	end
	if total <= 0 then
		return false, nil
	end
	return true, total
end

-- 9000 -> "2 h 30 min"
function Core.formatDuration(seconds: number?): string
	if seconds == nil then
		return "permanent"
	end
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return `{s} s`
	end
	local days = s // 86400
	local h = (s % 86400) // 3600
	local m = (s % 3600) // 60
	local parts = {}
	if days > 0 then
		table.insert(parts, `{days} d`)
	end
	if h > 0 then
		table.insert(parts, `{h} h`)
	end
	if m > 0 and days == 0 then
		table.insert(parts, `{m} min`)
	end
	return table.concat(parts, " ")
end

-- Compact countdown: 45 -> "45s", 90 -> "1m30s", 3600 -> "1h"
function Core.formatCountdown(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	local text = ""
	if h > 0 then
		text ..= `{h}h`
	end
	if m > 0 then
		text ..= `{m}m`
	end
	if r > 0 or text == "" then
		text ..= `{r}s`
	end
	return text
end

-- Unix timestamp -> "17/10/2026 14:05" (local time of the calling machine)
function Core.formatDate(timestamp: number?): string
	if timestamp == nil then
		return "—"
	end
	return os.date("%d/%m/%Y %H:%M", timestamp) :: string
end

-- Tables ---------------------------------------------------------------

function Core.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value :: any do
		result[Core.deepCopy(k)] = Core.deepCopy(v)
	end
	return result :: any
end

function Core.keys(t: { [any]: any }): { any }
	local list = {}
	for k in t do
		table.insert(list, k)
	end
	return list
end

-- Validation -------------------------------------------------------------
-- For data coming from the network: never trust the announced type.

function Core.isText(v: any, maxLength: number?): boolean
	return type(v) == "string" and utf8.len(v) ~= nil and #v <= (maxLength or 200)
end

function Core.isPositiveInteger(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v % 1 == 0 and v < 2 ^ 53
end

-- Roblox UserId. Studio test players (Player1, Player2...) have negative ids.
function Core.isUserId(v: any): boolean
	return type(v) == "number" and v == v and v ~= 0 and v % 1 == 0 and math.abs(v) < 2 ^ 53
end

function Core.isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

return Core
