--[[
	Abyssara – Deep Tide Tycoon
	Module: ZoneProgressService
	Purpose:
		Keeps PlayerDataService's "deepest zone" record up to date
		(PlayerDataService.RecordZoneReached, zone index 1 = Sun Zone ...
		4 = Hadal Depths). It feeds the "Deepest Zone" leaderboard
		(LeaderboardService reads GetDeepestZoneEver and listens for the
		DataChanged "DeepestZone" kind).

		A zone counts as reached when
			- the player's level unlocks it (ZoneEconomyConfig.GetZoneForLevel),
			  checked on login and after every level-up (ProgressionService), or
			- the player actually travels there (TravelService.RequestTravelToZone).

		RecordZoneReached only ever raises the values, so calling this often is
		harmless. Level and visit are both server-side facts, nothing comes
		from the client.

	Rojo mount:
		src/server/ZoneProgressService.lua -> ServerScriptService.ZoneProgressService
		(plain server module; wires its own PlayerAdded hook on first require)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ZoneEconomyConfig = require(ReplicatedStorage:WaitForChild("ZoneEconomyConfig"))

local JOIN_DATA_TIMEOUT_SECONDS = 15

local ZoneProgressService = {}

--- Records the deepest zone the player's current level unlocks.
function ZoneProgressService.SyncFromLevel(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local zoneIndex = ZoneEconomyConfig.GetZoneIndex(ZoneEconomyConfig.GetZoneForLevel(PlayerDataService.GetLevel(player)))
	if zoneIndex then
		PlayerDataService.RecordZoneReached(player, zoneIndex)
	end
end

--- Records a zone the player was teleported to (zone ids as in TravelService.ZONE_IDS).
function ZoneProgressService.RecordVisit(player: Player, zoneId: string)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local zoneIndex = ZoneEconomyConfig.GetZoneIndex(zoneId)
	if zoneIndex then
		PlayerDataService.RecordZoneReached(player, zoneIndex)
	end
end

local function onPlayerAdded(player: Player)
	if not PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS) then
		return
	end
	if player.Parent ~= Players then
		return
	end
	ZoneProgressService.SyncFromLevel(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

return ZoneProgressService
