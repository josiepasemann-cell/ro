--[[
	Abyssara – Deep Tide Tycoon
	Module: AchievementRemotes
	Responsibility:
		Single, central location for the client<->server communication
		channels of the Achievements system (rewards, titles, Roblox
		badges). Identical bootstrap pattern to QuestRemotes/LiveEventRemotes
		(remotes as children of this ModuleScript itself, server creates
		them, client only WaitForChild's).

	Rojo mount point:
		src/shared/AchievementRemotes.lua -> ReplicatedStorage.AchievementRemotes

	Exported channels:
		GetState (RemoteFunction, Client -> Server -> Client)
			Payload: none. Returns the full achievement state for the
			requesting player (initial UI sync):
				{
					Achievements: {
						{
							Id: string,
							Category: string,
							Icon: string,
							Name: string,        -- "???" if Secret and not yet unlocked
							Description: string, -- SecretHint if Secret and not yet unlocked
							Secret: boolean,
							Unlocked: boolean,
							Progress: number,    -- 0 while a locked secret achievement
							Target: number,
							Claimed: boolean,
							RewardTideCoins: number,
							RewardAbyssalShards: number,
							RewardTitle: string?,
						}
					},
					EquippedTitle: string?,
					UnlockedTitles: { string },
				}
		AchievementUnlocked (RemoteEvent, Server -> Client)
			Pushed the instant an achievement gets unlocked (independent of
			whether the reward has already been claimed): { Id, Name, Icon,
			RewardTideCoins, RewardAbyssalShards, RewardTitle }.
		AchievementProgressUpdated (RemoteEvent, Server -> Client)
			Pushed on every progress change of ONE achievement (before it
			unlocks): { Id, Progress, Target }.
		RequestClaimReward (RemoteEvent, Client -> Server)
			Payload: (achievementId: string) - the allegedly-unlocked
			achievement whose reward should be claimed. Pure declaration of
			intent - the server re-validates Unlocked/Claimed completely
			against its own persistent achievement state.
		ClaimRewardResult (RemoteEvent, Server -> Client)
			Response to RequestClaimReward: { Success: boolean, Reason:
			string?, Id: string?, RewardTideCoins: number?,
			RewardAbyssalShards: number?, RewardTitle: string?,
			NewTideCoinBalance: number? }.
		RequestEquipTitle (RemoteEvent, Client -> Server)
			Payload: (title: string?) - the title to equip, or nil to
			unequip. Pure declaration of intent - the server re-validates
			ownership against PlayerDataService.GetUnlockedTitles.
		EquipTitleResult (RemoteEvent, Server -> Client)
			Response to RequestEquipTitle: { Success: boolean, Reason:
			string?, Title: string? }.
]]

local RunService = game:GetService("RunService")

local AchievementRemotes = {}

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

if RunService:IsServer() then
	AchievementRemotes.GetState = getOrCreateRemoteFunction(script, "GetState")
	AchievementRemotes.AchievementUnlocked = getOrCreateRemoteEvent(script, "AchievementUnlocked")
	AchievementRemotes.AchievementProgressUpdated = getOrCreateRemoteEvent(script, "AchievementProgressUpdated")
	AchievementRemotes.RequestClaimReward = getOrCreateRemoteEvent(script, "RequestClaimReward")
	AchievementRemotes.ClaimRewardResult = getOrCreateRemoteEvent(script, "ClaimRewardResult")
	AchievementRemotes.RequestEquipTitle = getOrCreateRemoteEvent(script, "RequestEquipTitle")
	AchievementRemotes.EquipTitleResult = getOrCreateRemoteEvent(script, "EquipTitleResult")
else
	AchievementRemotes.GetState = script:WaitForChild("GetState") :: RemoteFunction
	AchievementRemotes.AchievementUnlocked = script:WaitForChild("AchievementUnlocked") :: RemoteEvent
	AchievementRemotes.AchievementProgressUpdated = script:WaitForChild("AchievementProgressUpdated") :: RemoteEvent
	AchievementRemotes.RequestClaimReward = script:WaitForChild("RequestClaimReward") :: RemoteEvent
	AchievementRemotes.ClaimRewardResult = script:WaitForChild("ClaimRewardResult") :: RemoteEvent
	AchievementRemotes.RequestEquipTitle = script:WaitForChild("RequestEquipTitle") :: RemoteEvent
	AchievementRemotes.EquipTitleResult = script:WaitForChild("EquipTitleResult") :: RemoteEvent
end

return AchievementRemotes
