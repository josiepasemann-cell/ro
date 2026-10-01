--[[
	Abyssara – Deep Tide Tycoon
	Module: ClusterRemotes
	Responsibility:
		Single place for all client<->server channels of the Reef Cluster
		co-op groups (see ClusterService, docs/coop.md). Same bootstrap
		pattern as TradeRemotes/TravelRemotes. The server validates
		everything; the client only sends intent.

	Rojo mount point:
		src/shared/ClusterRemotes.lua -> ReplicatedStorage.ClusterRemotes

	Client -> Server (RemoteEvent):
		RequestCreateCluster ()
		RequestInviteToCluster (targetUserId: number)
		RespondClusterInvite (inviteId: string, accept: boolean)
		RequestLeaveCluster ()
		RequestKickFromCluster (targetUserId: number)
		RequestTeleportToMember (targetUserId: number)

	Client -> Server (RemoteFunction):
		GetClusterInfo () -> { State = <ClusterState>, Candidates = { { UserId, Name, Level, Nearby, Available, Text } } }

	Server -> Client (RemoteEvent):
		ClusterState { InCluster: boolean, ClusterId: string?, LeaderUserId: number?,
			Members: { { UserId, Name, Level, IsLeader, IsSelf } }, MaxMembers: number, BonusPercent: number }
		ClusterInviteReceived { InviteId, FromUserId, FromName, ExpiresIn }
		ClusterInviteClosed { InviteId }
		ClusterNotice { Text: string, Kind: "Info" | "Warning" | "Success" }
]]

local RunService = game:GetService("RunService")

local ClusterRemotes = {}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local EVENTS = {
	"RequestCreateCluster",
	"RequestInviteToCluster",
	"RespondClusterInvite",
	"RequestLeaveCluster",
	"RequestKickFromCluster",
	"RequestTeleportToMember",
	"ClusterState",
	"ClusterInviteReceived",
	"ClusterInviteClosed",
	"ClusterNotice",
}

if RunService:IsServer() then
	for _, name in ipairs(EVENTS) do
		ClusterRemotes[name] = getOrCreate(script, "RemoteEvent", name)
	end
	ClusterRemotes.GetClusterInfo = getOrCreate(script, "RemoteFunction", "GetClusterInfo")
else
	for _, name in ipairs(EVENTS) do
		ClusterRemotes[name] = script:WaitForChild(name)
	end
	ClusterRemotes.GetClusterInfo = script:WaitForChild("GetClusterInfo")
end

return ClusterRemotes
