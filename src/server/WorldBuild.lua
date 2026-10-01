--[[
	Abyssara – Deep Tide Tycoon
	Module: WorldBuild

	Makes a place playable without any manual Studio step. If the world was
	never built in Studio (no Workspace.Assets.Hub.TidalMarketHub), the first
	server script that calls WorldBuild.Ensure() runs every buildscript from
	ServerStorage.AbyssaraBuild (studio/BuildWorld.lua, same order as
	docs/release-checklist.md §3) at runtime: parts, CSG and Terrain all work
	on a live server. Every other caller waits until that build is finished,
	so no gameplay system starts against a missing world.

	A place where the world was built in Studio and saved skips all of this.
	After a runtime build, characters that spawned into the empty world are
	respawned so they land at the hub spawn.

	Every *.server.lua calls Ensure() before requiring anything else.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldBuild = {}

local state: "Idle" | "Building" | "Done" = "Idle"
local finished = Instance.new("BindableEvent")

local function worldExists(): boolean
	local assets = Workspace:FindFirstChild("Assets")
	local hubFolder = assets and assets:FindFirstChild("Hub")
	return hubFolder ~= nil and hubFolder:FindFirstChild("TidalMarketHub") ~= nil
end

local function build()
	if worldExists() then
		return
	end
	local root = ServerStorage:FindFirstChild("AbyssaraBuild")
	local builder = root and root:FindFirstChild("BuildWorld")
	if not builder or not builder:IsA("ModuleScript") then
		warn("[WorldBuild] No world in Workspace and no ServerStorage.AbyssaraBuild.BuildWorld - sync it with Rojo or build the world in Studio.")
		return
	end
	local started = os.clock()
	print("[WorldBuild] No built world found - building it now (one-time per server, a few seconds)...")
	local ok, err = pcall(function()
		(require(builder) :: any).Run()
	end)
	if not ok then
		warn("[WorldBuild] Building the world failed: " .. tostring(err))
	end
	print(("[WorldBuild] Done in %.1fs."):format(os.clock() - started))

	-- Anyone who spawned before the hub existed fell into the void or stands
	-- on the emergency spawn: respawn them at the real hub spawn.
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.spawn(function()
				pcall(function()
					player:LoadCharacter()
				end)
			end)
		end
	end
end

--- Builds the world once if needed; yields every caller until it is ready.
function WorldBuild.Ensure()
	if state == "Done" then
		return
	end
	if state == "Building" then
		finished.Event:Wait()
		return
	end
	state = "Building"
	build()
	state = "Done"
	finished:Fire()
end

return WorldBuild
