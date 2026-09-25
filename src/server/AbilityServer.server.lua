--[[
	Abyssara – Deep Tide Tycoon
	Script: AbilityServer (Script, not a ModuleScript)
	Responsibility:
		Bootstrap/wiring of the purchasable abilities/boosts system on the
		server side: connects the RemoteEvent/RemoteFunction channels from
		AbilityRemotes to the pure logic in AbilityService. Contains NO
		validation logic itself - identical thin-bootstrap pattern to
		BuddyServer.server.lua/RaidServer.server.lua.

	Rojo mount point:
		src/server/AbilityServer.server.lua -> ServerScriptService.AbilityServer

	Security principle (no client trust):
		Every request is passed 1:1 to AbilityService, which fully
		re-validates everything (charge count, cooldown, active raid
		ownership, purchase target). The only trustworthy value is `player`,
		supplied directly by the Roblox engine.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityService = require(script.Parent:WaitForChild("AbilityService"))
local AbilityRemotes = require(ReplicatedStorage:WaitForChild("AbilityRemotes"))

AbilityRemotes.GetAbilityStatus.OnServerInvoke = function(player: Player)
	return AbilityService.GetStatus(player)
end

AbilityRemotes.RequestDepthCharge.OnServerEvent:Connect(function(player: Player)
	local ok, reason = AbilityService.RequestDepthCharge(player)
	if not ok then
		AbilityRemotes.DepthChargeFired:FireClient(player, { Success = false, Reason = reason })
	end
	-- Success case already fires DepthChargeFired (with FX payload) from
	-- inside AbilityService.RequestDepthCharge itself.
end)

print("[Abyssara] AbilityServer ready (GetAbilityStatus / RequestDepthCharge wired up).")
