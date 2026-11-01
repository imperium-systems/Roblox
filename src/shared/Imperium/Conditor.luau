--!strict
-- Conditor: startup.
-- Starts systems in dependency order, injects into each one the systems
-- it needs, detects cycles and missing systems, and handles clean shutdown.
--
-- A system is a ModuleScript returning a table that may contain:
--   dependencies: { string }            names of required systems (ModuleScript name)
--   init(deps)                           called in order, deps[name] = system
--   start()                              called once all init() calls are done
--   stop()                               called when the server closes, in reverse order
--
-- The stateless Core libraries (Core, Signum, Scriba) and Veredarius
-- are required directly and do not go through Conditor.

local RunService = game:GetService("RunService")

local Scriba = require(script.Parent.Scriba)

local logger = Scriba.scoped("Conditor")

type System = {
	dependencies: { string }?,
	init: ((deps: { [string]: any }) -> ())?,
	start: (() -> ())?,
	stop: (() -> ())?,
}

local Conditor = {}

function Conditor.run(modules: { ModuleScript })
	local startTime = os.clock()
	local systems: { [string]: System } = {}

	for _, module in modules do
		systems[module.Name] = (require :: any)(module)
	end

	-- Topological sort (depth-first traversal).
	local order: { string } = {}
	local state: { [string]: "visiting" | "done" } = {}

	local function visit(name: string, path: { string })
		if state[name] == "done" then
			return
		end
		if state[name] == "visiting" then
			table.insert(path, name)
			error(`[Conditor] circular dependency: {table.concat(path, " → ")}`, 0)
		end
		local system = systems[name]
		if not system then
			error(`[Conditor] missing system: "{name}" (required by {path[#path] or "?"})`, 0)
		end
		state[name] = "visiting"
		table.insert(path, name)
		for _, dep in system.dependencies or {} do
			visit(dep, path)
		end
		table.remove(path)
		state[name] = "done"
		table.insert(order, name)
	end

	for _, module in modules do
		visit(module.Name, {})
	end

	for _, name in order do
		local system = systems[name]
		if system.init then
			local deps = {}
			for _, dep in system.dependencies or {} do
				deps[dep] = systems[dep]
			end
			system.init(deps)
		end
	end

	for _, name in order do
		local system = systems[name]
		if system.start then
			local ok, err = pcall(system.start)
			if not ok then
				logger.err(`{name}.start failed:`, err)
			end
		end
	end

	if RunService:IsServer() then
		game:BindToClose(function()
			for i = #order, 1, -1 do
				local system = systems[order[i]]
				if system.stop then
					local ok, err = pcall(system.stop)
					if not ok then
						logger.err(`{order[i]}.stop failed:`, err)
					end
				end
			end
		end)
	end

	logger.info(
		`{#order} systems started in {math.round((os.clock() - startTime) * 1000)} ms: {table.concat(order, ", ")}`
	)

	return systems
end

return Conditor
