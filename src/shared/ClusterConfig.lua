--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: ClusterConfig
	Responsibility:
		Single source of truth for the Reef Cluster co-op groups (GDD
		sections 4 + 7, Phase 2): size, invite timing and the shared income
		bonus. Pure data, read by ClusterService (authoritative) and
		ClusterUIController (display only).

	Rojo mount point:
		src/shared/ClusterConfig.lua -> ReplicatedStorage.ClusterConfig
]]

local ClusterConfig = {}

ClusterConfig.MAX_MEMBERS = 4 -- leader included

-- // Invites ----------------------------------------------------------------------
ClusterConfig.INVITE_TIMEOUT_SECONDS = 45
ClusterConfig.INVITE_SEND_COOLDOWN_SECONDS = 2 -- min. gap between two invites of one player
ClusterConfig.INVITE_DECLINE_COOLDOWN_SECONDS = 15 -- same inviter -> same target after a decline/expiry
ClusterConfig.NEARBY_STUDS = 80 -- only used to sort/label "nearby" players in the panel

-- // Benefits -----------------------------------------------------------------------
-- Idle income multiplier = 1 + min(CAP, PER_OTHER_MEMBER * (online members - 1)).
-- With 4 members that is +15 %, so the cap only matters if MAX_MEMBERS grows.
ClusterConfig.INCOME_BONUS_PER_OTHER_MEMBER = 0.05
ClusterConfig.INCOME_BONUS_CAP = 0.15
ClusterConfig.TELEPORT_COOLDOWN_SECONDS = 8

ClusterConfig.REASON_TEXT = {
	NotLoaded = "Your data is still loading. Try again in a moment.",
	TargetNotLoaded = "That player is still loading.",
	UnknownPlayer = "That player is not in this server.",
	Self = "That is you!",
	RateLimited = "Slow down a little.",
	AlreadyInCluster = "You are already in a Reef Cluster.",
	NotInCluster = "You are not in a Reef Cluster.",
	NotLeader = "Only the cluster leader can do that.",
	ClusterFull = "The cluster is full (%d players).",
	TargetInCluster = "That player is already in a cluster.",
	TargetHasInvite = "That player already has an invite waiting.",
	InviteCooldown = "Please wait a moment before inviting again.",
	DeclinedRecently = "That player said no a moment ago. Try again soon.",
	InviteExpired = "That invite has expired.",
	InviteDeclined = "%s declined your cluster invite.",
	InviteTimeout = "Your cluster invite timed out.",
	NotInSameCluster = "That player is not in your cluster.",
	NoPlot = "That player's reef plot is not ready yet.",
	NoCharacter = "Your character is not ready.",
	TeleportCooldown = "Teleport is recharging (%d s).",
	CannotKickSelf = "Use Leave to leave the cluster.",
} :: { [string]: string }

return ClusterConfig
