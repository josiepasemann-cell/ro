--[[
	Abyssara – Deep Tide Tycoon
	Module: PrestigeRemotes
	Responsibility:
		Single place that defines the client<->server channels of the
		prestige system "Resurface" (see PrestigeConfig). Same bootstrap
		pattern as GachaRemotes/HabitatRemotes: the server creates the
		remotes as children of this ModuleScript, the client only waits
		for them.

	Rojo mount point:
		src/shared/PrestigeRemotes.lua -> ReplicatedStorage.PrestigeRemotes

	Channels:
		GetPrestigeInfo (RemoteFunction, Client -> Server -> Client)
			No payload. Returns the data for the Prestige panel:
			{ AscendCount: number, IncomeMultiplier: number,
			  NextIncomeMultiplier: number, NextBonusPercent: number,
			  NextShardReward: number, NextTitle: string?,
			  NextTitleAtAscend: number?, Eligible: boolean,
			  BlockReason: string?, -- see BlockReasons in PrestigeService
			  Level: number, RequiredLevel: number, DeepestZone: number,
			  RequiredZone: number }.
		ArmResurface (RemoteFunction, Client -> Server -> Client)
			Step 1 of the two-step confirmation: the client calls this after
			the player accepted the FIRST confirm dialog. The server checks
			eligibility and "arms" the player for ARM_WINDOW_SECONDS.
			Returns { Success: boolean, Reason: string? }.
		RequestResurface (RemoteEvent, Client -> Server)
			Step 2: no payload. Only works while armed (consumes the armed
			state). The server re-checks everything.
		ResurfaceResult (RemoteEvent, Server -> Client)
			{ Success: boolean, Reason: string?, AscendCount: number?,
			  IncomeMultiplier: number?, ShardsGranted: number?,
			  TitleGranted: string?, NextRaidAt: number? }.
]]

local RunService = game:GetService("RunService")

local PrestigeRemotes = {}

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
	PrestigeRemotes.GetPrestigeInfo = getOrCreateRemoteFunction(script, "GetPrestigeInfo")
	PrestigeRemotes.ArmResurface = getOrCreateRemoteFunction(script, "ArmResurface")
	PrestigeRemotes.RequestResurface = getOrCreateRemoteEvent(script, "RequestResurface")
	PrestigeRemotes.ResurfaceResult = getOrCreateRemoteEvent(script, "ResurfaceResult")
else
	PrestigeRemotes.GetPrestigeInfo = script:WaitForChild("GetPrestigeInfo") :: RemoteFunction
	PrestigeRemotes.ArmResurface = script:WaitForChild("ArmResurface") :: RemoteFunction
	PrestigeRemotes.RequestResurface = script:WaitForChild("RequestResurface") :: RemoteEvent
	PrestigeRemotes.ResurfaceResult = script:WaitForChild("ResurfaceResult") :: RemoteEvent
end

return PrestigeRemotes
