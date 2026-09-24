--[[
	Abyssara – Deep Tide Tycoon
	Modul: ShopRemotes
	Zuständigkeit:
		Zentraler, einziger Ort, an dem die Client<->Server-Kommunikations-
		kanäle (RemoteEvent/RemoteFunction) für das Monetarisierungs-/Shop-
		Backend definiert werden. Server (ShopServer.server.lua) UND ein
		künftiger UI-Agent requiren AUSSCHLIESSLICH dieses Modul statt
		Instance-Pfade doppelt zu hardcoden - identisches Bootstrap-Muster zu
		GachaRemotes/BreedingRemotes/RaidRemotes/IdleIncomeRemotes (siehe dort
		für die ausführliche Begründung).

	Rojo-Einhängepunkt:
		src/shared/ShopRemotes.lua -> ReplicatedStorage.ShopRemotes

	WICHTIG FÜR DEN UI-AGENTEN (kein Gameplay-Code in diesem Modul!):
		Dieses Modul legt ausschließlich die Remote-Instanzen an - keine
		Client-UI. Ein späterer UI-Agent baut Buttons/Panels, die diese
		Kanäle aufrufen. Die komplette Payload-Struktur ist unten je Kanal
		dokumentiert.

	Sicherheitsprinzip (kein Client-Trust):
		JEDE Client->Server-Anfrage hier trägt ausschließlich unvertraute,
		rohe Werte (ProductKey-Strings, ItemId-Strings, Slot-Strings) - die
		serverseitige Validierung/Preisberechnung/Berechtigungsprüfung läuft
		vollständig in ShopService/MonetizationService. Der Client bekommt
		niemals das Recht, direkt einen Preis, eine Menge oder ein
		Kaufergebnis vorzugeben.

	Exportierte Kanäle:
		GetShopCatalog (RemoteFunction, Client -> Server -> Client)
			Liefert den vollständigen, personalisierten Shop-Katalog (siehe
			ShopService.GetCatalog für die genaue Rückgabestruktur):
			Gamepasses (inkl. Besitzstatus + Purchasable-Flag), Entwickler-
			produkte (inkl. Mystery-Egg-Odds + Purchasable-Flag), Kosmetik-
			Artikel (inkl. Besitz-/Ausgerüstet-Status) und die heutige
			Angebote-Rotation.

		RequestPromptGamepassPurchase (RemoteEvent, Client -> Server)
			Payload: gamepassKey: string. Server validiert + ruft
			MarketplaceService:PromptGamePassPurchase auf (oder lehnt bei
			Id == 0/unbekanntem Key ab, siehe PurchasePromptRejected).

		RequestPromptDevProductPurchase (RemoteEvent, Client -> Server)
			Payload: productKey: string, targetId: string? (z. B.
			InstanceId der zu rettenden Kreatur bei "RescueToken", PlacementId
			des Brutbeckens bei "InstantBreeding" - siehe ShopConfig.
			DevProductDefinition.RequiresTarget). Server validiert den Target-
			Kontext SERVERSEITIG (Eigentümerschaft etc.), merkt ihn sich für
			den späteren ProcessReceipt-Handler vor und ruft dann
			MarketplaceService:PromptProductPurchase auf.

		PurchasePromptRejected (RemoteEvent, Server -> Client)
			Feuert, wenn ein Prompt-Request server-seitig VOR dem eigentlichen
			Roblox-Kaufdialog abgelehnt wurde (z. B. Id == 0/Platzhalter noch
			nicht konfiguriert, ungültiges Target, Paid-Random-Items-Policy-
			Sperre, Raid-Skip bereits heute genutzt). Payload: { Reason:
			string, ProductKey: string }. KEIN Kauf wurde angestoßen - dies
			ist kein ProcessReceipt-Ersatz.

		RequestPurchaseCosmetic (RemoteFunction, Client -> Server -> Client)
			Payload: itemId: string. Zieht bei Erfolg die Soft-Währung ab und
			schaltet den Artikel frei. Rückgabe: { Success: boolean, Reason:
			string?, NewBalance: number? }.

		RequestEquipCosmetic (RemoteFunction, Client -> Server -> Client)
			Payload: itemId: string (muss bereits im Besitz sein). Rückgabe:
			{ Success: boolean, Reason: string?, Slot: string? }.

		RequestSimulateStudioPurchase (RemoteEvent, Client -> Server)
			NUR IN STUDIO wirksam (siehe MonetizationService/ShopService -
			RunService:IsStudio()-Prüfung SERVERSEITIG, nicht nur im UI
			ausgeblendet). Payload: kind: "Gamepass" | "DevProduct", key:
			string. Simuliert einen erfolgreichen Kauf für Testzwecke, OHNE
			echtes Robux/MarketplaceService. Im Live-Spiel ignoriert der
			Server diesen Kanal vollständig (siehe MonetizationService-
			Kopfkommentar).

		ShopStateChanged (RemoteEvent, Server -> Client)
			Feuert nach jeder erfolgreichen Zustandsänderung (Kauf, Ausrüsten,
			Gamepass-Erwerb), Payload = aktueller GetCatalog()-Snapshot -
			erlaubt dem UI-Agenten, ohne Extra-Polling synchron zu bleiben.
]]

local RunService = game:GetService("RunService")

local ShopRemotes = {}

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
	ShopRemotes.GetShopCatalog = getOrCreateRemoteFunction(script, "GetShopCatalog")
	ShopRemotes.RequestPromptGamepassPurchase = getOrCreateRemoteEvent(script, "RequestPromptGamepassPurchase")
	ShopRemotes.RequestPromptDevProductPurchase = getOrCreateRemoteEvent(script, "RequestPromptDevProductPurchase")
	ShopRemotes.PurchasePromptRejected = getOrCreateRemoteEvent(script, "PurchasePromptRejected")
	ShopRemotes.RequestPurchaseCosmetic = getOrCreateRemoteFunction(script, "RequestPurchaseCosmetic")
	ShopRemotes.RequestEquipCosmetic = getOrCreateRemoteFunction(script, "RequestEquipCosmetic")
	ShopRemotes.RequestSimulateStudioPurchase = getOrCreateRemoteEvent(script, "RequestSimulateStudioPurchase")
	ShopRemotes.ShopStateChanged = getOrCreateRemoteEvent(script, "ShopStateChanged")
else
	ShopRemotes.GetShopCatalog = script:WaitForChild("GetShopCatalog") :: RemoteFunction
	ShopRemotes.RequestPromptGamepassPurchase = script:WaitForChild("RequestPromptGamepassPurchase") :: RemoteEvent
	ShopRemotes.RequestPromptDevProductPurchase = script:WaitForChild("RequestPromptDevProductPurchase") :: RemoteEvent
	ShopRemotes.PurchasePromptRejected = script:WaitForChild("PurchasePromptRejected") :: RemoteEvent
	ShopRemotes.RequestPurchaseCosmetic = script:WaitForChild("RequestPurchaseCosmetic") :: RemoteFunction
	ShopRemotes.RequestEquipCosmetic = script:WaitForChild("RequestEquipCosmetic") :: RemoteFunction
	ShopRemotes.RequestSimulateStudioPurchase = script:WaitForChild("RequestSimulateStudioPurchase") :: RemoteEvent
	ShopRemotes.ShopStateChanged = script:WaitForChild("ShopStateChanged") :: RemoteEvent
end

return ShopRemotes
