--[[
	Abyssara – Deep Tide Tycoon
	Modul: HeldItemRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle für das "Items in der Hand"-System definiert werden. Sowohl
		Server (HeldItemService/HeldItemServer.server.lua) als auch Client
		(HeldItemClient.client.lua) requiren AUSSCHLIESSLICH dieses Modul,
		identisches Bootstrap-Muster zu src/shared/GachaRemotes.lua /
		BreedingRemotes.lua (siehe dort für die ausführliche Begründung:
		Remotes als Kinder dieses ModuleScripts selbst, Server legt sie an,
		Client wartet nur per WaitForChild).

		Das eigentliche Aufheben von Welt-Pickups (Glow Spores) und das
		Abgeben an der GlowBuoyStation laufen bewusst NICHT über eigene
		RemoteEvents hier, sondern über serverseitig angebrachte
		`ProximityPrompt`-Instanzen (siehe PickupSpawner) - ProximityPrompt
		repliziert sein Triggered-Event bereits von sich aus zuverlässig
		plattformübergreifend (PC/Mobile/Konsole) an den Server, ein
		zusätzlicher Remote-Kanal wäre nur redundant.

	Rojo-Einhängepunkt:
		src/shared/HeldItemRemotes.lua -> ReplicatedStorage.HeldItemRemotes

	Exportierte Kanäle:
		RequestDropHeld (RemoteEvent, Client -> Server)
			Feuert OHNE Payload - der Server legt anhand des anfragenden
			`player` fest, ob/was aktuell gehalten wird (HeldItemService.
			DropHeld). Kein Client-Trust nötig, da kein Wert übernommen wird.
		HeldItemChanged (RemoteEvent, Server -> Client)
			Server sendet den aktuellen Halte-Zustand NUR an den betroffenen
			Spieler selbst (für das minimale HUD-Feedback/Ablegen-Aktion in
			HeldItemClient.client.lua):
				{ Holding: boolean, ItemKind: string?, DisplayName: string?,
				  CarryPose: string? }
			`Holding = false` bei allen übrigen Feldern = nil (Item abgelegt/
			verbraucht/Charakter verloren).
]]

local RunService = game:GetService("RunService")

local HeldItemRemotes = {}

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

if RunService:IsServer() then
	HeldItemRemotes.RequestDropHeld = getOrCreateRemoteEvent(script, "RequestDropHeld")
	HeldItemRemotes.HeldItemChanged = getOrCreateRemoteEvent(script, "HeldItemChanged")
else
	HeldItemRemotes.RequestDropHeld = script:WaitForChild("RequestDropHeld") :: RemoteEvent
	HeldItemRemotes.HeldItemChanged = script:WaitForChild("HeldItemChanged") :: RemoteEvent
end

return HeldItemRemotes
