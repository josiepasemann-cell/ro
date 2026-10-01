--[[
	Abyssara – Deep Tide Tycoon
	Script: ClusterServer (Script, not a ModuleScript)
	Responsibility:
		Thin bootstrap for the Reef Cluster co-op groups: wires the
		ClusterRemotes channels to ClusterService. No cluster logic lives here.

	Rojo mount point:
		src/server/ClusterServer.server.lua -> ServerScriptService.ClusterServer
]]

require(script.Parent:WaitForChild("WorldBuild")).Ensure() -- builds the world on first start if the place has none (see WorldBuild.lua)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClusterService = require(script.Parent:WaitForChild("ClusterService"))
local ClusterRemotes = require(ReplicatedStorage:WaitForChild("ClusterRemotes"))

ClusterRemotes.RequestCreateCluster.OnServerEvent:Connect(function(player: Player)
	ClusterService.RequestCreate(player)
end)

ClusterRemotes.RequestInviteToCluster.OnServerEvent:Connect(function(player: Player, targetUserId)
	ClusterService.RequestInvite(player, targetUserId)
end)

ClusterRemotes.RespondClusterInvite.OnServerEvent:Connect(function(player: Player, inviteId, accept)
	ClusterService.RespondToInvite(player, inviteId, accept)
end)

ClusterRemotes.RequestLeaveCluster.OnServerEvent:Connect(function(player: Player)
	ClusterService.RequestLeave(player)
end)

ClusterRemotes.RequestKickFromCluster.OnServerEvent:Connect(function(player: Player, targetUserId)
	ClusterService.RequestKick(player, targetUserId)
end)

ClusterRemotes.RequestTeleportToMember.OnServerEvent:Connect(function(player: Player, targetUserId)
	ClusterService.RequestTeleportToMember(player, targetUserId)
end)

ClusterRemotes.GetClusterInfo.OnServerInvoke = function(player: Player)
	return ClusterService.GetInfo(player)
end

print("[Abyssara] ClusterServer ready (Reef Cluster remotes wired up).")
