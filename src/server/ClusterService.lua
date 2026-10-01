--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: ClusterService
	Responsibility:
		Reef Cluster co-op groups (GDD sections 4 + 7, Phase 2): up to
		ClusterConfig.MAX_MEMBERS players in the SAME server with one leader.
		Create, invite, accept/decline, leave, kick; members can teleport to
		each other's plots, get a small shared idle-income bonus and show up
		on the "Cluster" leaderboard (best cluster raid wave).

		State lives per server session only (no DataStore). The only persisted
		co-op data are the stats in PlayerData.CoopState, written through
		ClusterService.RecordClusterRaid -> PlayerDataService.RecordClusterRaid.

	Public API (used by other services, e.g. the co-op raid code):
		ClusterService.GetCluster(player) -> { Id, Leader, Members }?
		ClusterService.GetClusterMembers(player) -> { Player }   -- { player } when solo
		ClusterService.AreInSameCluster(a, b) -> boolean
		ClusterService.GetIncomeMultiplier(player) -> number     -- used by IdleIncomeService
		ClusterService.RecordClusterRaid(player, wave, won)      -- persists stats + leaderboard dirty
		GameEvents "ClusterChanged" (player, { ClusterId, Members, LeaderUserId, Reason })
			fired for EVERY affected player on create/join/leave/kick/leader change.
		GameEvents "ClusterRaidFinished" (player, { Wave, Won }) fired by RecordClusterRaid.

	Rojo mount point:
		src/server/ClusterService.lua -> ServerScriptService.ClusterService
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local ClusterConfig = require(ReplicatedStorage:WaitForChild("ClusterConfig"))
local ClusterRemotes = require(ReplicatedStorage:WaitForChild("ClusterRemotes"))

type Cluster = {
	Id: string,
	Leader: Player,
	Members: { Player }, -- join order; index 1 is promoted when the leader leaves
}

type Invite = {
	Id: string,
	Cluster: Cluster,
	From: Player,
	To: Player,
	Closed: boolean,
}

export type ClusterInfo = {
	Id: string,
	Leader: Player,
	Members: { Player },
}

local ClusterService = {}

-- // Runtime state ------------------------------------------------------------------

local clusters: { [string]: Cluster } = {}
local clusterOf: { [number]: Cluster } = {}
local inviteById: { [string]: Invite } = {}
local inviteByTo: { [number]: Invite } = {}
local lastInviteAt: { [number]: number } = {}
local declinedUntil: { [string]: number } = {} -- "fromUserId:toUserId" -> os.clock()
local lastTeleportAt: { [number]: number } = {}
local lastCallAt: { [number]: { [string]: number } } = {}

local TELEPORT_RAY_HEIGHT_STUDS = 60
local TELEPORT_RAY_DEPTH_STUDS = 250
local TELEPORT_SAFETY_OFFSET_STUDS = 3

-- // Helpers ---------------------------------------------------------------------------

local function formatReason(reason: string, arg: any?): string
	local text = ClusterConfig.REASON_TEXT[reason] or "That did not work."
	if arg ~= nil and string.find(text, "%", 1, true) then
		text = string.format(text, arg)
	end
	return text
end

local function notice(player: Player, text: string, kind: string?)
	if player.Parent then
		ClusterRemotes.ClusterNotice:FireClient(player, { Text = text, Kind = kind or "Warning" })
	end
end

local function noticeReason(player: Player, reason: string, arg: any?)
	notice(player, formatReason(reason, arg), "Warning")
end

local function rateLimited(player: Player, key: string, interval: number): boolean
	local perPlayer = lastCallAt[player.UserId]
	if not perPlayer then
		perPlayer = {}
		lastCallAt[player.UserId] = perPlayer
	end
	local table_ = perPlayer :: { [string]: number }
	local now = os.clock()
	local last = table_[key]
	if last and now - last < interval then
		return true
	end
	table_[key] = now
	return false
end

local function isReady(player: Player): boolean
	return player.Parent == Players and PlayerDataService.IsDataLoaded(player)
end

local function onlineMembers(cluster: Cluster): { Player }
	local list: { Player } = {}
	for _, member in ipairs(cluster.Members) do
		if member.Parent == Players then
			table.insert(list, member)
		end
	end
	return list
end

local function bonusFraction(onlineCount: number): number
	return math.min(
		ClusterConfig.INCOME_BONUS_CAP,
		ClusterConfig.INCOME_BONUS_PER_OTHER_MEMBER * math.max(0, onlineCount - 1)
	)
end

local function distanceBetween(a: Player, b: Player): number?
	local rootA = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
	local rootB = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
	if rootA and rootB and rootA:IsA("BasePart") and rootB:IsA("BasePart") then
		return (rootA.Position - rootB.Position).Magnitude
	end
	return nil
end

-- // State snapshots / events -----------------------------------------------------------

local function buildState(player: Player): { [string]: any }
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return {
			InCluster = false,
			Members = {},
			MaxMembers = ClusterConfig.MAX_MEMBERS,
			BonusPercent = 0,
		}
	end
	local members = {}
	local online = onlineMembers(cluster)
	for _, member in ipairs(online) do
		table.insert(members, {
			UserId = member.UserId,
			Name = member.DisplayName,
			Level = PlayerDataService.GetLevel(member),
			IsLeader = member == cluster.Leader,
			IsSelf = member == player,
		})
	end
	return {
		InCluster = true,
		ClusterId = cluster.Id,
		LeaderUserId = cluster.Leader.UserId,
		Members = members,
		MaxMembers = ClusterConfig.MAX_MEMBERS,
		BonusPercent = math.floor(bonusFraction(#online) * 100 + 0.5),
	}
end

local function pushState(player: Player)
	if player.Parent then
		ClusterRemotes.ClusterState:FireClient(player, buildState(player))
	end
end

local function fireChanged(player: Player, reason: string)
	local cluster = clusterOf[player.UserId]
	local members = if cluster then onlineMembers(cluster) else { player }
	GameEvents.Fire("ClusterChanged", player, {
		ClusterId = if cluster then cluster.Id else nil,
		Members = members,
		LeaderUserId = if cluster then cluster.Leader.UserId else nil,
		Reason = reason,
	})
end

--- Fires GameEvents + pushes the client state to `players`.
local function announce(players: { Player }, reason: string)
	for _, player in ipairs(players) do
		fireChanged(player, reason)
		pushState(player)
	end
end

-- // Invites ----------------------------------------------------------------------------------

local function closeInvite(invite: Invite, notifyTarget: boolean)
	if invite.Closed then
		return
	end
	invite.Closed = true
	inviteById[invite.Id] = nil
	if inviteByTo[invite.To.UserId] == invite then
		inviteByTo[invite.To.UserId] = nil
	end
	if notifyTarget and invite.To.Parent then
		ClusterRemotes.ClusterInviteClosed:FireClient(invite.To, { InviteId = invite.Id })
	end
end

local function openInvitesFor(cluster: Cluster): number
	local count = 0
	for _, invite in pairs(inviteById) do
		if invite.Cluster == cluster and not invite.Closed then
			count += 1
		end
	end
	return count
end

-- // Membership -----------------------------------------------------------------------------------

local function createCluster(leader: Player): Cluster
	local cluster: Cluster = {
		Id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		Leader = leader,
		Members = { leader },
	}
	clusters[cluster.Id] = cluster
	clusterOf[leader.UserId] = cluster
	print(("[Cluster] %s created by %s (%d)"):format(cluster.Id, leader.Name, leader.UserId))
	return cluster
end

--- Removes `player` from their cluster. `reason`: "Left" | "Kicked" | "Disconnected".
local function removeMember(player: Player, reason: string)
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return
	end
	local index = table.find(cluster.Members, player)
	if index then
		table.remove(cluster.Members, index)
	end
	clusterOf[player.UserId] = nil

	-- Invites sent by the leaving player no longer make sense.
	for _, invite in pairs(table.clone(inviteById)) do
		if invite.Cluster == cluster and invite.From == player then
			closeInvite(invite, true)
		end
	end

	print(("[Cluster] %s: %s (%d) removed (%s), %d left"):format(cluster.Id, player.Name, player.UserId, reason, #cluster.Members))

	if #cluster.Members == 0 then
		clusters[cluster.Id] = nil
		for _, invite in pairs(table.clone(inviteById)) do
			if invite.Cluster == cluster then
				closeInvite(invite, true)
			end
		end
	else
		local leaderChanged = false
		if cluster.Leader == player then
			cluster.Leader = cluster.Members[1]
			leaderChanged = true
			notice(cluster.Leader, "You are the cluster leader now.", "Info")
		end
		announce(onlineMembers(cluster), if leaderChanged then "LeaderChanged" else reason)
	end

	if reason ~= "Disconnected" and player.Parent == Players then
		announce({ player }, reason)
	end
end

local function addMember(cluster: Cluster, player: Player)
	table.insert(cluster.Members, player)
	clusterOf[player.UserId] = cluster
	print(("[Cluster] %s: %s (%d) joined, %d members"):format(cluster.Id, player.Name, player.UserId, #cluster.Members))
	announce(onlineMembers(cluster), "Joined")
end

-- // Requests (untrusted input) -------------------------------------------------------------------------

function ClusterService.RequestCreate(player: Player)
	if rateLimited(player, "Create", 0.5) then
		return
	end
	if not isReady(player) then
		return noticeReason(player, "NotLoaded")
	end
	if clusterOf[player.UserId] then
		return noticeReason(player, "AlreadyInCluster")
	end
	createCluster(player)
	announce({ player }, "Created")
	notice(player, "Reef Cluster created. Invite friends from the Cluster panel!", "Success")
end

function ClusterService.RequestInvite(from: Player, targetUserId: any)
	if rateLimited(from, "Invite", 0.5) then
		return
	end
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target.Parent ~= Players then
		return noticeReason(from, "UnknownPlayer")
	end
	if target == from then
		return noticeReason(from, "Self")
	end
	if not isReady(from) then
		return noticeReason(from, "NotLoaded")
	end
	if not isReady(target) then
		return noticeReason(from, "TargetNotLoaded")
	end

	local cluster = clusterOf[from.UserId]
	if cluster and cluster.Leader ~= from then
		return noticeReason(from, "NotLeader")
	end
	if cluster and #cluster.Members + openInvitesFor(cluster) >= ClusterConfig.MAX_MEMBERS then
		return noticeReason(from, "ClusterFull", ClusterConfig.MAX_MEMBERS)
	end
	if clusterOf[target.UserId] then
		return noticeReason(from, "TargetInCluster")
	end
	if inviteByTo[target.UserId] then
		return noticeReason(from, "TargetHasInvite")
	end

	local now = os.clock()
	if now - (lastInviteAt[from.UserId] or -math.huge) < ClusterConfig.INVITE_SEND_COOLDOWN_SECONDS then
		return noticeReason(from, "InviteCooldown")
	end
	if (declinedUntil[from.UserId .. ":" .. target.UserId] or 0) > now then
		return noticeReason(from, "DeclinedRecently")
	end
	lastInviteAt[from.UserId] = now

	-- Inviting without a cluster creates one (the inviter becomes the leader).
	if not cluster then
		cluster = createCluster(from)
		announce({ from }, "Created")
	end
	local activeCluster = cluster :: Cluster

	local invite: Invite = {
		Id = string.sub(HttpService:GenerateGUID(false), 1, 8),
		Cluster = activeCluster,
		From = from,
		To = target,
		Closed = false,
	}
	inviteById[invite.Id] = invite
	inviteByTo[target.UserId] = invite

	ClusterRemotes.ClusterInviteReceived:FireClient(target, {
		InviteId = invite.Id,
		FromUserId = from.UserId,
		FromName = from.DisplayName,
		ExpiresIn = ClusterConfig.INVITE_TIMEOUT_SECONDS,
	})
	notice(from, ("Cluster invite sent to %s."):format(target.DisplayName), "Info")

	task.delay(ClusterConfig.INVITE_TIMEOUT_SECONDS, function()
		if invite.Closed then
			return
		end
		closeInvite(invite, true)
		declinedUntil[from.UserId .. ":" .. target.UserId] = os.clock() + ClusterConfig.INVITE_DECLINE_COOLDOWN_SECONDS
		noticeReason(from, "InviteTimeout")
	end)
end

function ClusterService.RespondToInvite(player: Player, inviteId: any, accept: any)
	if rateLimited(player, "Respond", 0.3) then
		return
	end
	if type(inviteId) ~= "string" or type(accept) ~= "boolean" then
		return
	end
	local invite = inviteById[inviteId]
	if not invite or invite.Closed or invite.To ~= player then
		return noticeReason(player, "InviteExpired")
	end
	closeInvite(invite, false)

	if not accept then
		declinedUntil[invite.From.UserId .. ":" .. player.UserId] = os.clock()
			+ ClusterConfig.INVITE_DECLINE_COOLDOWN_SECONDS
		noticeReason(invite.From, "InviteDeclined", player.DisplayName)
		return
	end

	local cluster = invite.Cluster
	if clusters[cluster.Id] ~= cluster or invite.From.Parent ~= Players then
		return noticeReason(player, "InviteExpired")
	end
	if not isReady(player) then
		return noticeReason(player, "NotLoaded")
	end
	if clusterOf[player.UserId] then
		return noticeReason(player, "AlreadyInCluster")
	end
	if #cluster.Members >= ClusterConfig.MAX_MEMBERS then
		return noticeReason(player, "ClusterFull", ClusterConfig.MAX_MEMBERS)
	end
	addMember(cluster, player)
end

function ClusterService.RequestLeave(player: Player)
	if rateLimited(player, "Leave", 0.5) then
		return
	end
	if not clusterOf[player.UserId] then
		return noticeReason(player, "NotInCluster")
	end
	removeMember(player, "Left")
	notice(player, "You left the Reef Cluster.", "Info")
end

function ClusterService.RequestKick(leader: Player, targetUserId: any)
	if rateLimited(leader, "Kick", 0.5) then
		return
	end
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return
	end
	local cluster = clusterOf[leader.UserId]
	if not cluster then
		return noticeReason(leader, "NotInCluster")
	end
	if cluster.Leader ~= leader then
		return noticeReason(leader, "NotLeader")
	end
	if targetUserId == leader.UserId then
		return noticeReason(leader, "CannotKickSelf")
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or clusterOf[target.UserId] ~= cluster then
		return noticeReason(leader, "NotInSameCluster")
	end
	removeMember(target, "Kicked")
	notice(target, "You were removed from the Reef Cluster.", "Warning")
end

-- // Teleport to a member's plot (pattern from TravelService.RequestTravelToPlot) ---------------------------

local function findSafeLandingCFrame(approxPosition: Vector3): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local origin = approxPosition + Vector3.new(0, TELEPORT_RAY_HEIGHT_STUDS, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -TELEPORT_RAY_DEPTH_STUDS, 0), params)
	local landY = if result then result.Position.Y + TELEPORT_SAFETY_OFFSET_STUDS else approxPosition.Y + TELEPORT_SAFETY_OFFSET_STUDS
	return CFrame.new(approxPosition.X, landY, approxPosition.Z)
end

function ClusterService.RequestTeleportToMember(player: Player, targetUserId: any)
	if rateLimited(player, "Teleport", 0.5) then
		return
	end
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return
	end
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return noticeReason(player, "NotInCluster")
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player or clusterOf[target.UserId] ~= cluster then
		return noticeReason(player, "NotInSameCluster")
	end

	local remaining = ClusterConfig.TELEPORT_COOLDOWN_SECONDS - (os.clock() - (lastTeleportAt[player.UserId] or -math.huge))
	if remaining > 0 then
		return noticeReason(player, "TeleportCooldown", math.ceil(remaining))
	end

	local plot = PlotRegistry.GetPlot(target)
	if not plot or not plot.PrimaryPart then
		return noticeReason(player, "NoPlot")
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not character.PrimaryPart or not humanoid or humanoid.Health <= 0 then
		return noticeReason(player, "NoCharacter")
	end

	lastTeleportAt[player.UserId] = os.clock()
	character:PivotTo(findSafeLandingCFrame(plot.PrimaryPart.Position))
	notice(player, ("Teleported to %s's reef."):format(target.DisplayName), "Success")
end

-- // Info for the panel -----------------------------------------------------------------------------------------

function ClusterService.GetInfo(player: Player): { [string]: any }?
	if rateLimited(player, "GetInfo", 0.5) then
		return nil
	end
	local cluster = clusterOf[player.UserId]
	local canInvite = cluster == nil or cluster.Leader == player
	local full = cluster ~= nil and #cluster.Members + openInvitesFor(cluster) >= ClusterConfig.MAX_MEMBERS

	local candidates = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and PlayerDataService.IsDataLoaded(other) and (not cluster or clusterOf[other.UserId] ~= cluster) then
			local distance = distanceBetween(player, other)
			local text: string? = nil
			if clusterOf[other.UserId] then
				text = formatReason("TargetInCluster")
			elseif inviteByTo[other.UserId] then
				text = formatReason("TargetHasInvite")
			elseif not canInvite then
				text = formatReason("NotLeader")
			elseif full then
				text = formatReason("ClusterFull", ClusterConfig.MAX_MEMBERS)
			end
			table.insert(candidates, {
				UserId = other.UserId,
				Name = other.DisplayName,
				Level = PlayerDataService.GetLevel(other),
				Nearby = distance ~= nil and distance <= ClusterConfig.NEARBY_STUDS,
				Distance = distance,
				Available = text == nil,
				Text = text,
			})
		end
	end
	table.sort(candidates, function(a, b)
		if a.Available ~= b.Available then
			return a.Available
		end
		if a.Nearby ~= b.Nearby then
			return a.Nearby
		end
		return a.Name:lower() < b.Name:lower()
	end)

	return { State = buildState(player), Candidates = candidates }
end

-- // Public API for other services ---------------------------------------------------------------------------------

--- The player's cluster as a plain snapshot, or nil when they are not in one.
--- `Members` is a fresh array (safe to modify) of players still in the server.
function ClusterService.GetCluster(player: Player): ClusterInfo?
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return nil
	end
	return {
		Id = cluster.Id,
		Leader = cluster.Leader,
		Members = onlineMembers(cluster),
	}
end

--- All members of the player's cluster (including the player), or just
--- { player } when they are solo.
function ClusterService.GetClusterMembers(player: Player): { Player }
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return { player }
	end
	return onlineMembers(cluster)
end

function ClusterService.AreInSameCluster(a: Player, b: Player): boolean
	local cluster = clusterOf[a.UserId]
	return cluster ~= nil and clusterOf[b.UserId] == cluster
end

--- Idle income multiplier from cluster membership: 1 + 5 % per other member
--- online (loaded), capped (ClusterConfig). 1 when solo.
function ClusterService.GetIncomeMultiplier(player: Player): number
	local cluster = clusterOf[player.UserId]
	if not cluster then
		return 1
	end
	local count = 0
	for _, member in ipairs(cluster.Members) do
		if isReady(member) then
			count += 1
		end
	end
	return 1 + bonusFraction(count)
end

--- Persists the result of a cluster raid for ONE player (PlayerData.CoopState)
--- and tells the leaderboard to refresh. The raid code calls it once per
--- participating member.
function ClusterService.RecordClusterRaid(player: Player, wave: number, won: boolean): boolean
	local ok = PlayerDataService.RecordClusterRaid(player, wave, won)
	if ok then
		GameEvents.Fire("ClusterRaidFinished", player, { Wave = wave, Won = won })
	end
	return ok
end

-- // Player leaving ------------------------------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player: Player)
	local userId = player.UserId
	removeMember(player, "Disconnected")
	local incoming = inviteByTo[userId]
	if incoming then
		closeInvite(incoming, false)
	end
	for _, invite in pairs(table.clone(inviteById)) do
		if invite.From == player then
			closeInvite(invite, true)
		end
	end
	lastInviteAt[userId] = nil
	lastTeleportAt[userId] = nil
	lastCallAt[userId] = nil
	for key in pairs(declinedUntil) do
		local fromId, toId = string.match(key, "^(%d+):(%d+)$")
		if tonumber(fromId) == userId or tonumber(toId) == userId then
			declinedUntil[key] = nil
		end
	end
end)

return ClusterService
