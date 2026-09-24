--[[
	Abyssara – Deep Tide Tycoon
	Modul: BuddyService
	Zuständigkeit:
		Serverseitige Kernlogik des "Buddy"-Systems: jeder Spieler kann EINE
		besessene Kreaturen-ART als Begleiter wählen, der ihm sichtbar für
		ALLE Spieler durch die gesamte Welt folgt (Hub, eigener Plot,
		Zonen) - Schlüsselmotivation in Sammelspielen ("seltene Kreaturen
		zeigen"). Validiert/persistiert die Wahl serverseitig (Besitz-
		Pflicht, kein Client-Trust), erstellt/entfernt das rein kosmetische
		Buddy-Modell im Workspace und hält es mit Besitz-Änderungen
		synchron (z. B. Raid-Entführung der letzten Instanz einer Art).

	BEWEGUNGS-ARCHITEKTUR ("server-owned vs. client-driven", siehe Auftrag
	"Decide ..., justify it in docs/buddy.md"):
		Bewusst KOMPLETT CLIENT-GETRIEBEN - anders als
		CreatureDisplayService's servergesteuerter Plot-Wander-Loop! Die
		ausführliche Begründung steht in docs/buddy.md, Kurzfassung:

		Ein Buddy hat (anders als eine frei wandernde Plot-Kreatur, die
		KEIN reales Bewegungsvorbild hat) immer ein bereits vom Roblox-
		Netzwerk repliziertes Referenzobjekt: die HumanoidRootPart-CFrame
		des Besitzer-Charakters, die für die eigentliche Spielerbewegung
		ohnehin ununterbrochen repliziert. Jeder Client (auch der
		Besitzer selbst) berechnet daraus rein LOKAL, wo der Buddy gerade
		sein sollte (Feder-artige Annäherung an einen Punkt hinter/neben
		der Schulter, Bob, Blickrichtung) und ruft NUR lokal
		`Model:PivotTo(...)` auf - exakt dasselbe Prinzip wie
		ProceduralAnimator (setzt Motor6D.C0 auch nur lokal, nie
		repliziert, siehe src/shared/CharacterAnimation/). Dieses Modul
		HIER bewegt das Buddy-Modell NIE selbst - es erstellt/zerstört es
		nur und setzt es einmalig auf eine sinnvolle Startposition
		(Character:GetPivot() des Besitzers bei Erstellung/Respawn).

		Ergebnis: null zusätzlicher Positions-Netzwerkverkehr (im
		Unterschied zu CreatureDisplayService, dessen 5-Hz-Server-Tick dort
		gerechtfertigt ist, weil Plot-Kreaturen KEIN kostenlos bereits
		repliziertes Bewegungsvorbild haben - hier wäre ein analoger
		Server-Tick-Loop pure Redundanz zur ohnehin stattfindenden
		Charakter-Replikation), butterweiche lokale Interpolation auf
		JEDEM Client unabhängig von Server-Tick-Rate, und phone-freundlich
		(kein zusätzlicher Server-Tick-Loop pro Online-Spieler).

	Sicherheitsprinzip (kein Client-Trust):
		SetBuddy validiert JEDE Anfrage serverseitig neu (Besitz der
		CreatureId in PlayerDataService.CreatureInventory) - der Client
		liefert nur eine Absichtserklärung (BuddyRemotes-Kopfkommentar).
		Die tatsächliche Positionierung ist rein kosmetisch/client-lokal
		und hat daher KEINE Gameplay-Auswirkung, die Server-Autorität
		bräuchte - das ist der entscheidende Unterschied zu z. B.
		Charakterposition/Teleports (TravelService), wo der Server jede
		Positionsangabe vorgibt.

	BEWUSST ENTKOPPELT von CodexService/CreatureDisplayService (identisches
	Prinzip wie CreatureDisplayService's eigener Kopfkommentar): braucht
	keinen vollen Katalog, nur PlayerDataService.CreatureInventory +
	Workspace.Assets.Creatures (Live-Modell-Lookup, dupliziert bewusst den
	kleinen findCreatureTemplate-Helfer statt CreatureDisplayService zu
	requiren - vermeidet unnötige Kopplung zwischen zwei unabhängigen
	Anzeige-Systemen).

	Rojo-Einhängepunkt:
		src/server/BuddyService.lua -> ServerScriptService.BuddyService
		(reines Server-Modul; verdrahtet Players.PlayerAdded/PlayerRemoving
		selbst beim ersten require(), identisches Muster zu
		CreatureDisplayService - kein separates Bootstrap-Script für die
		Lifecycle-Verdrahtung nötig, nur für die Remote-Verdrahtung selbst,
		siehe BuddyServer.server.lua.)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local BuddyRemotes = require(ReplicatedStorage:WaitForChild("BuddyRemotes"))

local BuddyService = {}

-- // Konfiguration -------------------------------------------------------------

-- Einzige Quelle der Wahrheit für den CollectionService-Tag-String lebt in
-- BuddyRemotes (von Server UND Client requirebar), siehe dortigen
-- Kopfkommentar - vermeidet ein Auseinanderlaufen der Tag-Konstante.
local BUDDY_TAG = BuddyRemotes.BUDDY_TAG

local JOIN_DATA_TIMEOUT_SECONDS = 15

-- Sicherheitsnetz-Resync (identisches Prinzip zu CreatureDisplayService.
-- SAFETY_RESYNC_INTERVAL_SECONDS) - fängt Besitz-Änderungen ab, die aus
-- welchem Grund auch immer kein GameEvents-Signal feuern.
local SAFETY_RESYNC_INTERVAL_SECONDS = 25

-- // Laufzeit-Zustand -----------------------------------------------------------

local buddyFolder: Folder = (function()
	local folder = Workspace:FindFirstChild("PlayerBuddies")
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = "PlayerBuddies"
		folder.Parent = Workspace
	end
	return folder :: Folder
end)()

local buddyModelByUserId: { [number]: Model } = {}
local warnedMissingTemplate: { [string]: boolean } = {}

-- // Hilfsfunktionen --------------------------------------------------------

local function findCreatureTemplate(creatureId: string): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local creaturesFolder = assetsFolder and assetsFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template :: Model
	end
	return nil
end

--- Identisches Prinzip zu CreatureDisplayService.hardenLightsForPhone.
local function hardenLightsForPhone(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
			descendant.Shadows = false
		end
	end
end

local function ownsCreatureId(player: Player, creatureId: string): boolean
	for _, instance in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		if instance.CreatureId == creatureId then
			return true
		end
	end
	return false
end

local function destroyBuddyModel(player: Player)
	local model = buddyModelByUserId[player.UserId]
	if model then
		buddyModelByUserId[player.UserId] = nil
		model:Destroy()
	end
end

--- Startposition für ein frisch erstelltes/respawntes Buddy-Modell: knapp
--- neben dem Besitzer-Charakter, falls vorhanden, sonst ein harmloser
--- Weltpunkt (der Client zieht den Buddy beim nächsten Follow-Tick ohnehin
--- sofort zur echten Zielposition, siehe BuddyClient-Kopfkommentar).
local function initialSpawnCFrame(player: Player): CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (root :: BasePart).CFrame * CFrame.new(-3, 0, 3)
	end
	return CFrame.new(0, 5, 0)
end

local function spawnBuddyModel(player: Player, creatureId: string)
	destroyBuddyModel(player)

	local template = findCreatureTemplate(creatureId)
	if not template then
		if not warnedMissingTemplate[creatureId] then
			warnedMissingTemplate[creatureId] = true
			warn(
				("[BuddyService] Kein Workspace.Assets.Creatures-Modell für '%s' - Buddy-Anzeige übersprungen, bis das Buildscript in Studio ausgeführt wurde."):format(
					creatureId
				)
			)
		end
		return
	end

	local clone = template:Clone()
	clone.Name = "Buddy_" .. tostring(player.UserId)
	hardenLightsForPhone(clone)

	-- Vollständig anchored + nicht kollidierend/nicht anfragbar (Auftrag:
	-- "non-colliding model") - rein kosmetisch, darf weder Spieler noch
	-- Raycasts/ProximityPrompts stören.
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	-- Attribute für den client-seitigen Follow-/Flair-/Nameplate-Code
	-- (BuddyClient.client.lua) - Rarity/CreatureName kommen bereits vom
	-- Kreaturen-Buildscript-Template (identische Attribut-Konvention wie
	-- CodexService.GetCatalog liest), hier nur um Besitzer-Bezug ergänzt.
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("CreatureId", creatureId)
	CollectionService:AddTag(clone, BUDDY_TAG)

	clone:PivotTo(initialSpawnCFrame(player))
	clone.Parent = buddyFolder

	buddyModelByUserId[player.UserId] = clone
end

-- // Öffentliche API ----------------------------------------------------------

export type SetBuddyFailure = "DataNotLoaded" | "NotOwned" | "InvalidPayload"

--- Validiert + setzt (oder löscht, `creatureId == nil`) den Buddy von
--- `player`. `creatureId` kommt vom Client (Absichtserklärung) - wird
--- vollständig gegen das tatsächliche Inventar geprüft. Gibt
--- (ok, failure?, finalCreatureId?) zurück.
function BuddyService.SetBuddy(player: Player, creatureId: any): (boolean, SetBuddyFailure?, string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded", nil
	end

	if creatureId == nil then
		PlayerDataService.SetBuddyCreatureId(player, nil)
		destroyBuddyModel(player)
		return true, nil, nil
	end

	if typeof(creatureId) ~= "string" or creatureId == "" then
		return false, "InvalidPayload", nil
	end

	if not ownsCreatureId(player, creatureId) then
		return false, "NotOwned", nil
	end

	PlayerDataService.SetBuddyCreatureId(player, creatureId)
	spawnBuddyModel(player, creatureId)
	return true, nil, creatureId
end

--- Aktuell gewählte Buddy-CreatureId (oder nil).
function BuddyService.GetBuddyCreatureId(player: Player): string?
	return PlayerDataService.GetBuddyCreatureId(player)
end

--- Revalidiert die persistierte Buddy-Wahl gegen das aktuelle Inventar
--- (z. B. nach einer Raid-Entführung, die die letzte Instanz einer
--- favorisierten Buddy-Art wegnimmt) und stellt sicher, dass ein gültig
--- gewählter Buddy tatsächlich ein Modell im Workspace hat. Günstig genug
--- (ein Inventar-Scan), um sowohl ereignisgetrieben als auch periodisch im
--- Sicherheitsnetz aufgerufen zu werden, siehe runSafetyResyncLoop.
function BuddyService.RefreshForPlayer(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local creatureId = PlayerDataService.GetBuddyCreatureId(player)
	if not creatureId then
		destroyBuddyModel(player)
		return
	end

	if not ownsCreatureId(player, creatureId) then
		-- Letzte Instanz dieser Art nicht mehr besessen (z. B. entführt) -
		-- Buddy automatisch löschen statt eine ungültige Wahl zu behalten.
		PlayerDataService.SetBuddyCreatureId(player, nil)
		destroyBuddyModel(player)
		return
	end

	if not buddyModelByUserId[player.UserId] then
		spawnBuddyModel(player, creatureId)
	end
end

--- Setzt das Buddy-Modell knapp neben den (neuen) Besitzer-Charakter zurück
--- - aufgerufen bei CharacterAdded (Respawn), damit es nicht an der Stelle
--- des vorherigen (toten) Charakters "hängen bleibt". Reine Bequemlichkeit:
--- der Client zieht die tatsächliche Zielposition ohnehin selbst nach
--- (siehe Kopfkommentar "Bewegungs-Architektur"), dies vermeidet nur einen
--- unnötig langen sichtbaren Anlauf-Weg direkt nach dem Respawn.
function BuddyService.ResetPositionForRespawn(player: Player)
	local model = buddyModelByUserId[player.UserId]
	if model and model.Parent then
		model:PivotTo(initialSpawnCFrame(player))
	end
end

--- Entfernt das Buddy-Modell + Laufzeit-Zustand von `player` (PlayerRemoving).
--- Die persistierte Wahl selbst bleibt erhalten (Wiederherstellung beim
--- nächsten Join über RefreshForPlayer).
function BuddyService.CleanupPlayer(player: Player)
	destroyBuddyModel(player)
end

-- // Join/Leave/Respawn-Verdrahtung ---------------------------------------------

local function onCharacterAdded(player: Player)
	task.defer(BuddyService.ResetPositionForRespawn, player)
end

local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
	if not data then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end

	BuddyService.RefreshForPlayer(player)

	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
	if player.Character then
		onCharacterAdded(player)
	end
end

local function onPlayerRemoving(player: Player)
	BuddyService.CleanupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

-- // GameEvents-Reaktion (Besitz-relevante Ereignisse) --------------------------

local function onOwnershipRelevantEvent(player: Player, _payload: { [string]: any })
	task.defer(BuddyService.RefreshForPlayer, player)
end

-- Entführung kann die letzte Instanz einer als Buddy gewählten Art wegnehmen.
GameEvents.Connect(GameEvents.Events.RaidLost, onOwnershipRelevantEvent)

local function runSafetyResyncLoop()
	while true do
		task.wait(SAFETY_RESYNC_INTERVAL_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			if PlayerDataService.IsDataLoaded(player) then
				task.spawn(BuddyService.RefreshForPlayer, player)
			end
		end
	end
end

task.spawn(runSafetyResyncLoop)

print("[Abyssara] BuddyService bereit (Buddy-Modell-Lebenszyklus aktiv, Bewegung läuft client-seitig).")

return BuddyService
