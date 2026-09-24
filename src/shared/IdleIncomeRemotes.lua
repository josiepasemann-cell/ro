--[[
	Abyssara – Deep Tide Tycoon
	Modul: IdleIncomeRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle (RemoteEvents) für das Idle-Einkommen-/Produktionssystem
		definiert werden. Server (IdleIncomeService.lua) und Client
		(IdleIncomeClient.client.lua) requiren AUSSCHLIESSLICH dieses Modul
		statt Instance-Pfade doppelt zu hardcoden - identisches Bootstrap-
		Muster zu src/shared/HabitatRemotes.lua und src/shared/GachaRemotes.lua
		(siehe dort für die ausführliche Begründung).

	Rojo-Einhängepunkt:
		src/shared/IdleIncomeRemotes.lua -> ReplicatedStorage.IdleIncomeRemotes

	Sicherheitsprinzip (kein Client-Trust):
		BEIDE Kanäle sind reine Server->Client-Feedback-Events. Der Client
		sendet hierüber NICHTS an den Server (keine "RequestCollect" o. Ä. -
		die Gutschrift läuft ausschließlich über den serverseitigen Tick-Loop
		bzw. die Offline-Progress-Berechnung in IdleIncomeService). Die
		Zahlen in diesen Events sind reine Anzeige-Information; die einzige
		Autorität über den tatsächlichen Kontostand bleibt
		PlayerDataService.Currencies auf dem Server.

	Exportierte Kanäle:
		IncomeGranted (RemoteEvent, Server -> Client)
			Feuert bei jeder Online-Tick-Gutschrift für den betroffenen
			Spieler. Payload: { Amount: number, NewBalance: number }.
			Amount > 0 immer (Events mit Amount == 0 werden vom Server gar
			nicht erst gesendet) - reines "+X Tide Coins"-Popup-Feedback.
		OfflineProgressSummary (RemoteEvent, Server -> Client)
			Feuert einmalig kurz nach dem Login, falls seit der letzten
			Gutschrift spürbar Zeit vergangen ist. Payload: {
				Amount: number,          -- tatsächlich gutgeschriebene Tide Coins (bereits gedeckelt)
				NewBalance: number,
				ElapsedSeconds: number,  -- tatsächlich vergangene Zeit seit letzter Gutschrift
				CappedSeconds: number,   -- für die Berechnung verwendete (auf den Cap begrenzte) Zeit
				WasCapped: boolean,      -- true, falls ElapsedSeconds > Cap (GDD: max. 4h Offline-Gewinn)
			}.
]]

local RunService = game:GetService("RunService")

local IdleIncomeRemotes = {}

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
	IdleIncomeRemotes.IncomeGranted = getOrCreateRemoteEvent(script, "IncomeGranted")
	IdleIncomeRemotes.OfflineProgressSummary = getOrCreateRemoteEvent(script, "OfflineProgressSummary")
else
	IdleIncomeRemotes.IncomeGranted = script:WaitForChild("IncomeGranted") :: RemoteEvent
	IdleIncomeRemotes.OfflineProgressSummary = script:WaitForChild("OfflineProgressSummary") :: RemoteEvent
end

return IdleIncomeRemotes
