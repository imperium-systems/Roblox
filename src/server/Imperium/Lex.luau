--!strict
-- Lex: game configuration and rules.
-- Each system declares its settings with a default value. Consul can edit them live;
-- subscribers are notified through Signum ("lex.change").
-- Stores neither player preferences (Optio) nor progression (Tabularius).
--
-- Changes apply to this server until it closes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Imperium = ReplicatedStorage.ImperiumShared.Imperium
local Core = require(Imperium.Core)
local Signum = require(Imperium.Signum)

export type SettingType = "number" | "boolean" | "string"

export type Definition = {
	default: any,
	type: SettingType,
	description: string,
	min: number?,
	max: number?,
}

type Setting = Definition & { value: any }

local Lex = {}

local settings: { [string]: Setting } = {}

function Lex.define(key: string, definition: Definition)
	assert(settings[key] == nil, `[Lex] setting already defined: {key}`)
	assert(type(definition.default) == definition.type, `[Lex] default of {key} is not a {definition.type}`)
	local setting = table.clone(definition) :: any
	setting.value = definition.default
	settings[key] = setting
end

function Lex.get(key: string): any
	local setting = settings[key]
	assert(setting, `[Lex] unknown setting: {key}`)
	return setting.value
end

-- Returns (true) or (false, error_code).
function Lex.set(key: string, value: any): (boolean, string?)
	local setting = settings[key]
	if not setting then
		return false, "unknown_key"
	end
	if type(value) ~= setting.type then
		return false, "invalid_value"
	end
	if setting.type == "number" then
		if not Core.isNumber(value) then
			return false, "invalid_value"
		end
		if (setting.min and value < setting.min) or (setting.max and value > setting.max) then
			return false, "out_of_range"
		end
	elseif setting.type == "string" and not Core.isText(value, 500) then
		return false, "invalid_value"
	end
	local previous = setting.value
	if previous == value then
		return true
	end
	setting.value = value
	Signum.emit("lex.change", key, value, previous)
	return true
end

function Lex.reset(key: string): (boolean, string?)
	local setting = settings[key]
	if not setting then
		return false, "unknown_key"
	end
	return Lex.set(key, setting.default)
end

-- Calls fn(value, previous) on every change of this key.
function Lex.onChange(key: string, fn: (any, any) -> ()): () -> ()
	return Signum.on("lex.change", function(changedKey, value, previous)
		if changedKey == key then
			fn(value, previous)
		end
	end)
end

function Lex.list(): { { [string]: any } }
	local list = {}
	for key, setting in settings do
		table.insert(list, {
			key = key,
			value = setting.value,
			default = setting.default,
			type = setting.type,
			description = setting.description,
			min = setting.min,
			max = setting.max,
		})
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

return Lex
