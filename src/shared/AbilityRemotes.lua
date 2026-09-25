--[[
	Abyssara – Deep Tide Tycoon
	Module: AbilityRemotes
	Responsibility:
		Single place defining the Client<->Server communication channels for
		the purchasable abilities/boosts system (AbilityService.lua). Both
		server (AbilityServer.server.lua) and client (AbilityHUDController.
		client.lua) require ONLY this module instead of hardcoding Instance
		paths twice - identical bootstrap pattern to RaidRemotes.lua/
		BuddyRemotes.lua (see there for the full rationale).

	Rojo mount point:
		src/shared/AbilityRemotes.lua -> ReplicatedStorage.AbilityRemotes

	Exported channels:
		GetAbilityStatus (RemoteFunction, Client -> Server -> Client)
			No payload. Returns the requesting player's current ability
			status for the initial HUD sync: { TidalSurgeActiveUntil:
			number?, DepthChargeCount: number, DepthChargeCooldownUntil:
			number?, InRaidOnOwnPlot: boolean, HasSporeMagnet: boolean,
			HasExtraBuddySlot: boolean }.
		AbilityStatusChanged (RemoteEvent, Server -> Client)
			Pushed after any server-side change relevant to the HUD (Tidal
			Surge purchased/extended, Depth Charge purchased/used, raid
			started/ended). Same payload shape as GetAbilityStatus (always a
			FULL snapshot, not a delta - the HUD is cheap enough to rebuild).
		RequestDepthCharge (RemoteEvent, Client -> Server)
			No payload - "fire a Depth Charge now". Pure intent, fully
			re-validated server-side (active raid on the player's OWN plot,
			charge count > 0, cooldown elapsed) - see
			AbilityService.RequestDepthCharge.
		DepthChargeFired (RemoteEvent, Server -> Client)
			Result + FX trigger for RequestDepthCharge: { Success: boolean,
			Reason: string?, CenterPosition: Vector3?, EnemiesHit: number? }.
			CenterPosition is the raid's plot-center (for the client-side
			shockwave FX), only present on success.
		SporeShowerToast (RemoteEvent, Server -> Client)
			Fired once per successful Spore Shower purchase: { Message:
			string }. The client just shows this as a toast (see
			AbilityHUDController) - the server decides the exact wording
			(e.g. the "landed on your plot even though you weren't there"
			variant), see AbilityService.GrantSporeShower.
]]

local RunService = game:GetService("RunService")

local AbilityRemotes = {}

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
	AbilityRemotes.GetAbilityStatus = getOrCreateRemoteFunction(script, "GetAbilityStatus")
	AbilityRemotes.AbilityStatusChanged = getOrCreateRemoteEvent(script, "AbilityStatusChanged")
	AbilityRemotes.RequestDepthCharge = getOrCreateRemoteEvent(script, "RequestDepthCharge")
	AbilityRemotes.DepthChargeFired = getOrCreateRemoteEvent(script, "DepthChargeFired")
	AbilityRemotes.SporeShowerToast = getOrCreateRemoteEvent(script, "SporeShowerToast")
else
	AbilityRemotes.GetAbilityStatus = script:WaitForChild("GetAbilityStatus") :: RemoteFunction
	AbilityRemotes.AbilityStatusChanged = script:WaitForChild("AbilityStatusChanged") :: RemoteEvent
	AbilityRemotes.RequestDepthCharge = script:WaitForChild("RequestDepthCharge") :: RemoteEvent
	AbilityRemotes.DepthChargeFired = script:WaitForChild("DepthChargeFired") :: RemoteEvent
	AbilityRemotes.SporeShowerToast = script:WaitForChild("SporeShowerToast") :: RemoteEvent
end

return AbilityRemotes
