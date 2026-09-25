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

local buddyModelByUserId: { [number]: Model } = {} -- slot 1
-- Extra Buddy Slot gamepass (Auftrag "purchasable abilities/boosts", 149
-- Robux): a SECOND, independent buddy slot. Kept as its own parallel table
-- (instead of e.g. buddyModelByUserId[userId] = {slot1, slot2}) to keep
-- every EXISTING slot-1 line above/below untouched - a minimal, additive
-- change on top of the pre-existing one-buddy system.
local buddyModelByUserId2: { [number]: Model } = {} -- slot 2
local warnedMissingTemplate: { [string]: boolean } = {}

local function modelTableForSlot(slot: number): { [number]: Model }
	return if slot == 2 then buddyModelByUserId2 else buddyModelByUserId
end

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

--- `slot` defaults to 1 (the original, always-available buddy) - `slot == 2`
--- is the Extra Buddy Slot gamepass' second slot, see modelTableForSlot.
local function destroyBuddyModel(player: Player, slot: number?)
	local table_ = modelTableForSlot(slot or 1)
	local model = table_[player.UserId]
	if model then
		table_[player.UserId] = nil
		model:Destroy()
	end
end

--- Startposition für ein frisch erstelltes/respawntes Buddy-Modell: knapp
--- neben dem Besitzer-Charakter, falls vorhanden, sonst ein harmloser
--- Weltpunkt (der Client zieht den Buddy beim nächsten Follow-Tick ohnehin
--- sofort zur echten Zielposition, siehe BuddyClient-Kopfkommentar).
--- Slot 2 spawnt auf der GEGENÜBERLIEGENDEN Seite (Auftrag: "follows on the
--- other side") - BuddyClient spiegelt denselben Seitenwechsel dauerhaft im
--- eigentlichen Follow-Offset, dies ist nur der initiale, harmlose Startpunkt.
local function initialSpawnCFrame(player: Player, slot: number?): CFrame
	local localOffset = if slot == 2 then Vector3.new(3, 0, 3) else Vector3.new(-3, 0, 3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (root :: BasePart).CFrame * CFrame.new(localOffset)
	end
	return CFrame.new(0, 5, 0)
end

--- `slot` defaults to 1 (see destroyBuddyModel/modelTableForSlot).
local function spawnBuddyModel(player: Player, creatureId: string, slot: number?)
	local resolvedSlot = slot or 1
	destroyBuddyModel(player, resolvedSlot)

	local template = findCreatureTemplate(creatureId)
	if not template then
		if not warnedMissingTemplate[creatureId] then
			warnedMissingTemplate[creatureId] = true
			warn(
				("[BuddyService] No Workspace.Assets.Creatures model for '%s' - buddy display skipped until the buildscript has been run in Studio."):format(
					creatureId
				)
			)
		end
		return
	end

	local clone = template:Clone()
	clone.Name = "Buddy_" .. tostring(player.UserId) .. (if resolvedSlot == 2 then "_2" else "")
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
	-- `BuddySlot` (Auftrag "Extra Buddy Slot"-Gamepass): BuddyClient nutzt
	-- dies ausschließlich, um Slot 2 auf der ANDEREN Seite folgen zu lassen
	-- (gespiegelter Follow-Offset) - fehlt das Attribut, gilt Slot 1.
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("CreatureId", creatureId)
	clone:SetAttribute("BuddySlot", resolvedSlot)
	CollectionService:AddTag(clone, BUDDY_TAG)

	clone:PivotTo(initialSpawnCFrame(player, resolvedSlot))
	clone.Parent = buddyFolder

	modelTableForSlot(resolvedSlot)[player.UserId] = clone
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

export type SetBuddy2Failure = "DataNotLoaded" | "NotOwned" | "InvalidPayload" | "NoExtraSlot"

--- SCHEMA_VERSION 8 / Extra Buddy Slot Gamepass (149 Robux, see
--- AbilityConfig.lua): identical validation to BuddyService.SetBuddy above,
--- for the SECOND buddy slot - ADDITIONALLY requires gamepass ownership
--- (checked server-side, never trusting the client). Clearing (`creatureId
--- == nil`) is always allowed, even without the gamepass (e.g. a player who
--- refunds/loses the pass elsewhere shouldn't get stuck unable to clear a
--- stale slot - RefreshForPlayer below also proactively clears it).
--- BEWUSST ein LAZY require() von MonetizationService (Funktionskörper statt
--- Modul-Kopf) - identische Begründung wie überall sonst in diesem Projekt
--- (BuddyService selbst wird nicht von MonetizationService benötigt, aber
--- die Projekt-Konvention ist, jeden MonetizationService-Zugriff konsequent
--- lazy zu halten, um künftige Zyklen zu vermeiden).
function BuddyService.SetBuddy2(player: Player, creatureId: any): (boolean, SetBuddy2Failure?, string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded", nil
	end

	if creatureId == nil then
		PlayerDataService.SetBuddyCreatureId2(player, nil)
		destroyBuddyModel(player, 2)
		return true, nil, nil
	end

	if typeof(creatureId) ~= "string" or creatureId == "" then
		return false, "InvalidPayload", nil
	end

	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	if not MonetizationService.PlayerOwnsGamepass(player, "ExtraBuddySlot") then
		return false, "NoExtraSlot", nil
	end

	if not ownsCreatureId(player, creatureId) then
		return false, "NotOwned", nil
	end

	PlayerDataService.SetBuddyCreatureId2(player, creatureId)
	spawnBuddyModel(player, creatureId, 2)
	return true, nil, creatureId
end

--- Aktuell gewählte Buddy-CreatureId für Slot 2 (oder nil).
function BuddyService.GetBuddyCreatureId2(player: Player): string?
	return PlayerDataService.GetBuddyCreatureId2(player)
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
	elseif not ownsCreatureId(player, creatureId) then
		-- Letzte Instanz dieser Art nicht mehr besessen (z. B. entführt) -
		-- Buddy automatisch löschen statt eine ungültige Wahl zu behalten.
		PlayerDataService.SetBuddyCreatureId(player, nil)
		destroyBuddyModel(player)
	elseif not buddyModelByUserId[player.UserId] then
		spawnBuddyModel(player, creatureId)
	end

	-- Slot 2 (Extra Buddy Slot Gamepass) - identisches Revalidierungsmuster,
	-- ZUSÄTZLICH gated auf Gamepass-Besitz (siehe SetBuddy2 oben).
	local creatureId2 = PlayerDataService.GetBuddyCreatureId2(player)
	if creatureId2 then
		local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
		if not MonetizationService.PlayerOwnsGamepass(player, "ExtraBuddySlot") or not ownsCreatureId(player, creatureId2) then
			PlayerDataService.SetBuddyCreatureId2(player, nil)
			destroyBuddyModel(player, 2)
		elseif not buddyModelByUserId2[player.UserId] then
			spawnBuddyModel(player, creatureId2, 2)
		end
	elseif buddyModelByUserId2[player.UserId] then
		destroyBuddyModel(player, 2)
	end
end

--- Setzt die Buddy-Modelle knapp neben den (neuen) Besitzer-Charakter zurück
--- - aufgerufen bei CharacterAdded (Respawn), damit sie nicht an der Stelle
--- des vorherigen (toten) Charakters "hängen bleiben". Reine Bequemlichkeit:
--- der Client zieht die tatsächliche Zielposition ohnehin selbst nach
--- (siehe Kopfkommentar "Bewegungs-Architektur"), dies vermeidet nur einen
--- unnötig langen sichtbaren Anlauf-Weg direkt nach dem Respawn. Deckt BEIDE
--- Slots ab (Slot 2 nur, falls ein zweiter Buddy tatsächlich existiert).
function BuddyService.ResetPositionForRespawn(player: Player)
	local model = buddyModelByUserId[player.UserId]
	if model and model.Parent then
		model:PivotTo(initialSpawnCFrame(player, 1))
	end
	local model2 = buddyModelByUserId2[player.UserId]
	if model2 and model2.Parent then
		model2:PivotTo(initialSpawnCFrame(player, 2))
	end
end

--- Entfernt BEIDE Buddy-Modelle + Laufzeit-Zustand von `player`
--- (PlayerRemoving). Die persistierte Wahl selbst bleibt erhalten
--- (Wiederherstellung beim nächsten Join über RefreshForPlayer).
function BuddyService.CleanupPlayer(player: Player)
	destroyBuddyModel(player, 1)
	destroyBuddyModel(player, 2)
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

print("[Abyssara] BuddyService ready (buddy model lifecycle active, movement runs client-side).")

return BuddyService
