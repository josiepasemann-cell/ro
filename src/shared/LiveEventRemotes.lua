--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: LiveEventRemotes
	Zuständigkeit:
		Zentraler, einziger Ort für die Client<->Server-Kommunikationskanäle
		des rotierenden Live-Event-Systems (docs/content-update-1.md,
		Abschnitt 1 + 7b). Identisches Bootstrap-Muster wie QuestRemotes/
		RaidRemotes/BreedingRemotes (Remotes als Kinder dieses ModuleScripts
		selbst, Server legt sie an, Client wartet nur per WaitForChild).

	Rojo-Einhängepunkt:
		src/shared/LiveEventRemotes.lua -> ReplicatedStorage.LiveEventRemotes

	Exportierte Kanäle:
		GetEventState (RemoteFunction, Client -> Server -> Client)
			Payload: keine. Liefert den vollständigen Client-Zustand für den
			initialen UI-Sync:
				{
					EventId: string, DisplayName: string,
					ColorPrimary: Color3, ColorSecondary: Color3,
					SlotStart: number, SlotEnd: number, Now: number,
					CurrencyId: string, CurrencyDisplayName: string,
					CurrencyGlyph: string, CurrencyBalance: number,
					ShopItems: { {Id,DisplayName,Cost,Type,Owned:boolean?} },
					QuestLine: { Title, Steps: {{Id,Description,Target,Progress}}, Claimed: boolean, RewardTideCoins, RewardTitle },
				}
		EventChanged (RemoteEvent, Server -> Client)
			Push bei JEDEM Slot-Wechsel (auch beim allerersten Server-Tick) -
			identisches Payload-Format wie GetEventState. Der Client löst
			hierüber den Banner-Wechsel + einen "großen Moment"-FX-Stoß aus
			(siehe EventUIController).
		EventCurrencyChanged (RemoteEvent, Server -> Client)
			Push bei JEDER Änderung der Event-Währungs-Bilanz des
			anfragenden Spielers: { Balance: number, Reason: string? }.
		EventQuestProgressUpdated (RemoteEvent, Server -> Client)
			Push bei JEDER Fortschrittsänderung EINES Quest-Schritts:
			{ StepIndex: number, Progress: number, Target: number }.
		RequestPurchaseShopItem (RemoteEvent, Client -> Server)
			Payload: (itemId: string) - reine Absichtserklärung, der Server
			validiert Preis/Event-Zugehörigkeit/Bilanz komplett neu.
		ShopPurchaseResult (RemoteEvent, Server -> Client)
			Antwort: { Success: boolean, Reason: string?, ItemId: string?,
			NewBalance: number?, CreatureId: string?, Rarity: string?,
			NewTideCoinBalance: number? }.
		RequestClaimEventQuest (RemoteEvent, Client -> Server)
			Payload: keine (bezieht sich immer auf die Quest-Linie des
			AKTUELL aktiven Events).
		ClaimEventQuestResult (RemoteEvent, Server -> Client)
			Antwort: { Success: boolean, Reason: string?, RewardTideCoins:
			number?, RewardTitle: string?, NewTideCoinBalance: number? }.
]]

local RunService = game:GetService("RunService")

local LiveEventRemotes = {}

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
	LiveEventRemotes.GetEventState = getOrCreateRemoteFunction(script, "GetEventState")
	LiveEventRemotes.EventChanged = getOrCreateRemoteEvent(script, "EventChanged")
	LiveEventRemotes.EventCurrencyChanged = getOrCreateRemoteEvent(script, "EventCurrencyChanged")
	LiveEventRemotes.EventQuestProgressUpdated = getOrCreateRemoteEvent(script, "EventQuestProgressUpdated")
	LiveEventRemotes.RequestPurchaseShopItem = getOrCreateRemoteEvent(script, "RequestPurchaseShopItem")
	LiveEventRemotes.ShopPurchaseResult = getOrCreateRemoteEvent(script, "ShopPurchaseResult")
	LiveEventRemotes.RequestClaimEventQuest = getOrCreateRemoteEvent(script, "RequestClaimEventQuest")
	LiveEventRemotes.ClaimEventQuestResult = getOrCreateRemoteEvent(script, "ClaimEventQuestResult")
else
	LiveEventRemotes.GetEventState = script:WaitForChild("GetEventState") :: RemoteFunction
	LiveEventRemotes.EventChanged = script:WaitForChild("EventChanged") :: RemoteEvent
	LiveEventRemotes.EventCurrencyChanged = script:WaitForChild("EventCurrencyChanged") :: RemoteEvent
	LiveEventRemotes.EventQuestProgressUpdated = script:WaitForChild("EventQuestProgressUpdated") :: RemoteEvent
	LiveEventRemotes.RequestPurchaseShopItem = script:WaitForChild("RequestPurchaseShopItem") :: RemoteEvent
	LiveEventRemotes.ShopPurchaseResult = script:WaitForChild("ShopPurchaseResult") :: RemoteEvent
	LiveEventRemotes.RequestClaimEventQuest = script:WaitForChild("RequestClaimEventQuest") :: RemoteEvent
	LiveEventRemotes.ClaimEventQuestResult = script:WaitForChild("ClaimEventQuestResult") :: RemoteEvent
end

return LiveEventRemotes
