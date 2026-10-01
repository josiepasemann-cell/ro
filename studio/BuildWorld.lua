--[[
	Abyssara – Deep Tide Tycoon
	BuildWorld (ModuleScript in ServerStorage.AbyssaraBuild, only in the place
	built from studio.project.json)

	Runs every buildscript from assets/models/** in the order of
	docs/release-checklist.md §3, so the whole world is built with ONE line in
	the Studio Command Bar (Edit mode, not Play):

		require(game.ServerStorage.AbyssaraBuild.BuildWorld).Run()

	The buildscripts live next to this module as ModuleScripts
	(ServerStorage.AbyssaraBuild.Models.<folder>.<Name>). Each one is run from
	its source with loadstring, so a script that errors is reported and the
	rest still runs. Running it again rebuilds everything (all buildscripts
	replace their old model). You normally don't need this at all: a game
	server that starts without a built world builds it itself
	(src/server/WorldBuild.lua). Running it in Studio and saving just makes
	server start faster.

	After it finishes: optionally import the meshes and run
	require(game.ServerStorage.AbyssaraBuild.ApplyMeshes) (see the README in
	the place), then save/publish.
]]

local ServerStorage = game:GetService("ServerStorage")

local BuildWorld = {}

-- Order from docs/release-checklist.md §3 (hub before NPCs, terrain and hub
-- before the world dressing, plot template before PlotSurroundings).
local ORDER: { { string } } = {
	{ "terrain", "HabitatPlotBase" },
	{ "world", "PlotSurroundings" },
	{ "buildings", "*" },
	{ "enemies", "*" },
	{ "pickups", "*" },
	{ "creatures", "*" },
	{ "gacha", "*" },
	{ "terrain", "SunZoneTerrainChunk" },
	{ "terrain", "TwilightZoneTerrainChunk" },
	{ "terrain", "MidnightZoneTerrainChunk" },
	{ "terrain", "HadalDepthsTerrainChunk" },
	{ "decorations", "*" },
	{ "hub", "HubTerrain" }, -- smooth terrain around the plaza (idempotent, wipes only the hub region)
	{ "hub", "TidalMarketHub" },
	{ "npcs", "*" },
	{ "world", "SunZoneDressing" },
	{ "world", "TwilightZoneDressing" },
	{ "world", "MidnightZoneDressing" },
	{ "world", "HadalDepthsDressing" },
	{ "world", "HubDressing" },
}

local function runScript(module: ModuleScript): (boolean, string?)
	local source = (module :: any).Source
	local chunk, compileError = loadstring(source, "=" .. module:GetFullName())
	if not chunk then
		return false, compileError
	end
	local ok, runError = pcall(chunk)
	if not ok then
		return false, tostring(runError)
	end
	return true, nil
end

-- At runtime on a game server loadstring is disabled, so each buildscript is
-- required instead. Buildscripts return nothing, which makes require() raise
-- "did not return exactly one value" AFTER the script has run - that error
-- means success; anything else is a real failure.
local function requireScript(module: ModuleScript): (boolean, string?)
	local ok, err = pcall(require, module)
	if ok or string.find(tostring(err), "exactly one value", 1, true) then
		return true, nil
	end
	return false, tostring(err)
end

--- Runs every buildscript. Uses loadstring (Command Bar) when available,
--- otherwise require() (game server, see WorldBuild.lua).
function BuildWorld.Run()
	local root = ServerStorage:FindFirstChild("AbyssaraBuild")
	local models = root and root:FindFirstChild("Models")
	assert(models, "ServerStorage.AbyssaraBuild.Models is missing - sync ServerStorage.AbyssaraBuild with Rojo")
	local canLoadstring = pcall(function()
		return loadstring("return 1")
	end) and loadstring("return 1") ~= nil
	local runner = if canLoadstring then runScript else requireScript

	local done, failed = 0, {}
	local ran: { [ModuleScript]: boolean } = {}
	for _, step in ipairs(ORDER) do
		local folder = models:FindFirstChild(step[1])
		local targets = {}
		if folder and step[2] == "*" then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("ModuleScript") then
					table.insert(targets, child)
				end
			end
			table.sort(targets, function(a, b)
				return a.Name < b.Name
			end)
		elseif folder and folder:FindFirstChild(step[2]) then
			table.insert(targets, folder[step[2]])
		else
			table.insert(failed, step[1] .. "/" .. step[2] .. ": not found")
		end
		for _, module in ipairs(targets) do
			if not ran[module] then
				ran[module] = true
				local ok, err = runner(module)
				if ok then
					done += 1
				else
					table.insert(failed, step[1] .. "/" .. module.Name .. ": " .. tostring(err))
				end
				task.wait() -- let Studio breathe between big scripts
			end
		end
	end

	print(("[BuildWorld] %d buildscript(s) ran."):format(done))
	for _, line in ipairs(failed) do
		warn("[BuildWorld] FAILED " .. line)
	end
	if #failed == 0 then
		print("[BuildWorld] World built. Optional: import the meshes, then require(game.ServerStorage.AbyssaraBuild.ApplyMeshes). Then File > Save / Publish.")
	end
	return done, failed
end

return BuildWorld
