--[[
	Abyssara – Deep Tide Tycoon
	Modul: HeldItemService
	Zuständigkeit:
		Autoritatives Kernsystem für "Items in der Hand" (Wunsch der
		Nutzerin: aufgehobene Dinge sollen sichtbar am Charakter getragen
		werden). Jeder Charakter hält serverseitig maximal EIN Item
		gleichzeitig. Das Item wird per `RigidConstraint` an ein
		"RightGripAttachment" auf der rechten Hand angebracht (R15:
		"RightHand", R6-Fallback: "Right Arm" - beide werden unterstützt),
		über `Model:ScaleTo()` auf eine für's Halten passende Größe skaliert
		und physikalisch neutral gemacht (CanCollide = false, Massless =
		true), damit es weder den Spieler noch andere Spieler behindert.

		Bei Item-Arten mit "TwoHand"-Trageweise (siehe HeldItemConfig, z. B.
		künftig Eier/Kreaturen) setzt dieses Modul zusätzlich das Attribut
		`Character:SetAttribute("CarryPose", "TwoHand"|"OneHand")`. Das
		prozedurale Animationssystem (src/shared/CharacterAnimation/
		ProceduralAnimator.lua) liest dieses Attribut bereits selbst aus
		(siehe dortige Zeile `self.Character:GetAttribute("CarryPose")`) und
		posiert die Arme entsprechend - dieses Modul muss dafür NICHTS
		Animationsspezifisches wissen, reines Attribut-Contract.

		Bietet eine bewusst generische, von konkreten Item-Arten unabhängige
		öffentliche API (HoldItem/DropHeld/GetHeld/ConsumeHeld), die von
		PickupSpawner (Glow Spores) UND künftig von GachaService/
		BreedingService (Eier/Kreaturen) genutzt werden kann/soll - siehe
		docs/held-items.md für die genauen Anknüpfpunkte in jenen (fremden,
		hier NICHT geänderten) Modulen.

	Sicherheitsprinzip (kein Client-Trust):
		Alle Funktionen hier sind server-interne API (kein RemoteFunction-
		Zugriff für den Client). Der Client kann über HeldItemRemotes.
		RequestDropHeld ausschließlich DropHeld für SEINEN EIGENEN Charakter
		anstoßen (siehe HeldItemServer.server.lua) - welches Item gehalten
		wird, entscheidet immer ausschließlich der Server.

	Rojo-Einhängepunkt:
		src/server/HeldItemService.lua -> ServerScriptService.HeldItemService
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeldItemConfig = require(ReplicatedStorage:WaitForChild("HeldItemConfig"))
local HeldItemRemotes = require(ReplicatedStorage:WaitForChild("HeldItemRemotes"))

export type HoldOptions = {
	CarryPose: string?, -- Override von HeldItemConfig.GetCarryPose(itemKind); explizit "" um KEIN Attribut zu setzen
	DisplayName: string?, -- Override von HeldItemConfig.GetDisplayName(itemKind)
	HoldScale: number?, -- Override von HeldItemConfig.GetHoldScale(itemKind)
	GripOffset: CFrame?, -- Override von HeldItemConfig.GetGripOffset(itemKind)
	Reparent: boolean?, -- true = `templateOrModel` DIREKT verwenden (z. B. ein bereits existierendes Welt-Pickup) statt zu klonen
	DestroyOnDrop: boolean?, -- true = DropHeld zerstört das Item statt es als Welt-Pickup abzulegen
}

export type HeldInfo = {
	ItemKind: string,
	Model: Model,
	DisplayName: string,
	CarryPose: string?,
}

type HeldRecord = {
	Model: Model,
	ItemKind: string,
	DisplayName: string,
	CarryPose: string?,
	DestroyOnDrop: boolean,
	Constraint: RigidConstraint?,
	ItemAttachment: Attachment?,
}

local HeldItemService = {}

local HELD_TAG = "HeldItem"
local GRIP_ATTACHMENT_NAME = "RightGripAttachment"
local DROP_FORWARD_OFFSET = CFrame.new(0, -1.5, -3)

local droppedBindable = Instance.new("BindableEvent")
--- Feuert (player: Player, model: Model, itemKind: string, dropWorldCFrame:
--- CFrame), sobald ein gehaltenes Item über DropHeld (NICHT ConsumeHeld!) in
--- die Welt fallen gelassen wurde. PickupSpawner abonniert dies, um
--- "GlowSpore"-Items wieder als aufhebbares Welt-Pickup mit ProximityPrompt
--- zu registrieren - siehe docs/held-items.md, Abschnitt "Fallenlassen".
HeldItemService.ItemDropped = droppedBindable.Event

local heldByUser: { [number]: HeldRecord } = {}

-- // Hilfsfunktionen ----------------------------------------------------------

--- Liefert die rechte Hand des Charakters - unterstützt sowohl R15
--- ("RightHand") als auch R6 ("Right Arm"), siehe Auftrag.
local function getHandPart(character: Model): BasePart?
	local rightHand = character:FindFirstChild("RightHand")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end
	local rightArm = character:FindFirstChild("Right Arm")
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm
	end
	return nil
end

--- Roblox-Standardcharaktere bringen für Tool-Equip i. d. R. bereits ein
--- "RightGripAttachment" an der Hand mit - wird es (z. B. bei einem
--- untypischen Rig) nicht gefunden, legt diese Funktion defensiv eines an,
--- statt fehlzuschlagen.
local function getOrCreateGripAttachment(handPart: BasePart): Attachment
	local existing = handPart:FindFirstChild(GRIP_ATTACHMENT_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = GRIP_ATTACHMENT_NAME
	attachment.CFrame = CFrame.new(0, -handPart.Size.Y / 2, 0)
	attachment.Parent = handPart
	return attachment
end

--- Ermittelt den PrimaryPart eines gehaltenen Items. Fällt auf die in
--- assets/models/README.md dokumentierten Namenskonventionen zurück
--- ("Body" bei Kreaturen, "Shell" bei Gacha-Eiern, "Base" bei Gebäuden/
--- Pickups), falls PrimaryPart nicht bereits gesetzt ist.
local function resolvePrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, candidateName in ipairs({ "Body", "Shell", "Base" }) do
		local part = model:FindFirstChild(candidateName)
		if part and part:IsA("BasePart") then
			model.PrimaryPart = part
			return part
		end
	end
	return nil
end

--- Macht alle Parts eines gehaltenen Items physikalisch neutral: kollidiert
--- nicht mit Spieler/Welt, hat kein Eigengewicht (stört die Bewegung nicht,
--- siehe Auftrag), ist nicht angeheftet (damit der RigidConstraint greift).
local function setPhysicsForHolding(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Massless = true
			descendant.Anchored = false
		end
	end
end

--- Räumt die interne Buchführung eines Spielers auf, OHNE das Modell in die
--- Welt zu legen oder ein HeldItemChanged-Event zu feuern (Charakter/Spieler
--- ist bereits weg - siehe onCharacterRemoving/PlayerRemoving unten). Das
--- Modell selbst wird dabei bewusst NICHT zerstört: es hängt am Charakter
--- und wird mit diesem ohnehin entfernt.
local function clearRecordSilently(userId: number)
	local record = heldByUser[userId]
	if not record then
		return
	end
	heldByUser[userId] = nil
	if record.Constraint then
		record.Constraint:Destroy()
	end
	if record.ItemAttachment then
		record.ItemAttachment:Destroy()
	end
end

-- // Öffentliche API ----------------------------------------------------------

--- Bringt `templateOrModel` sichtbar in der rechten Hand von `player` an.
--- Hält der Spieler bereits ein anderes Item, wird dieses zuerst über
--- DropHeld() abgelegt. Gibt (true, dieInstanz) bei Erfolg zurück, sonst
--- (false, nil) - z. B. falls der Spieler aktuell keinen Charakter/keine
--- rechte Hand hat oder kein PrimaryPart ermittelbar ist.
---
--- `opts.Reparent = true` verschiebt `templateOrModel` DIREKT (statt es zu
--- klonen) - gedacht für bereits im Workspace existierende Welt-Pickups
--- (siehe PickupSpawner), damit deren Identität (z. B. für spätere
--- Referenzen) erhalten bleibt. Ohne `Reparent` wird IMMER geklont, das
--- Original (z. B. eine ReplicatedStorage-Vorlage) bleibt unangetastet -
--- so rufen künftig GachaService/BreedingService dies mit einer
--- wiederverwendbaren Kreaturen-/Ei-Vorlage auf (siehe docs/held-items.md).
function HeldItemService.HoldItem(player: Player, itemKind: string, templateOrModel: Model, opts: HoldOptions?): (boolean, Model?)
	local character = player.Character
	if not character then
		return false, nil
	end

	local handPart = getHandPart(character)
	if not handPart then
		return false, nil
	end

	if heldByUser[player.UserId] then
		HeldItemService.DropHeld(player)
	end

	local options: HoldOptions = opts or {}
	local instance: Model
	if options.Reparent then
		instance = templateOrModel
	else
		instance = templateOrModel:Clone()
	end

	local primaryPart = resolvePrimaryPart(instance)
	if not primaryPart then
		if not options.Reparent then
			instance:Destroy()
		end
		return false, nil
	end

	-- Erst skalieren, DANN das Griff-Attachment anbringen: die
	-- GripOffset-Werte in HeldItemConfig sind für die bereits skalierte
	-- Halte-Größe kalibriert (siehe dortiger Kommentar).
	local holdScale = options.HoldScale or HeldItemConfig.GetHoldScale(itemKind)
	if holdScale and holdScale > 0 and holdScale ~= 1 then
		local scaleOk = pcall(function()
			instance:ScaleTo(holdScale)
		end)
		if not scaleOk then
			warn(("[HeldItemService] ScaleTo(%.2f) für '%s' fehlgeschlagen - Item bleibt unskaliert."):format(holdScale, itemKind))
		end
	end

	local gripAttachment = getOrCreateGripAttachment(handPart)

	local itemAttachment = Instance.new("Attachment")
	itemAttachment.Name = "ItemGripAttachment"
	itemAttachment.CFrame = options.GripOffset or HeldItemConfig.GetGripOffset(itemKind)
	itemAttachment.Parent = primaryPart

	setPhysicsForHolding(instance)

	-- Vorab nah an die Hand positionieren, damit der RigidConstraint nicht
	-- sichtbar über eine große Distanz "einschnappt".
	instance:PivotTo(handPart.CFrame)
	instance.Parent = character

	local constraint = Instance.new("RigidConstraint")
	constraint.Name = "HeldItemGrip"
	constraint.Attachment0 = gripAttachment
	constraint.Attachment1 = itemAttachment
	constraint.Parent = primaryPart

	local displayName = options.DisplayName or HeldItemConfig.GetDisplayName(itemKind)
	local carryPoseOverride = options.CarryPose
	local carryPose: string? = if carryPoseOverride ~= nil
		then (if carryPoseOverride == "" then nil else carryPoseOverride)
		else HeldItemConfig.GetCarryPose(itemKind)

	instance:SetAttribute("IsHeldItem", true)
	instance:SetAttribute("ItemKind", itemKind)
	instance:SetAttribute("HeldByUserId", player.UserId)
	CollectionService:AddTag(instance, HELD_TAG)

	character:SetAttribute("CarryPose", carryPose)

	heldByUser[player.UserId] = {
		Model = instance,
		ItemKind = itemKind,
		DisplayName = displayName,
		CarryPose = carryPose,
		DestroyOnDrop = options.DestroyOnDrop == true,
		Constraint = constraint,
		ItemAttachment = itemAttachment,
	}

	HeldItemRemotes.HeldItemChanged:FireClient(player, {
		Holding = true,
		ItemKind = itemKind,
		DisplayName = displayName,
		CarryPose = carryPose,
	})

	return true, instance
end

--- Legt das aktuell gehaltene Item von `player` ab (z. B. Spieler-Aktion
--- "G"/Touch-Button, siehe HeldItemClient). Ohne `opts.DestroyOnDrop`
--- (Default aus HoldItem) wird das Item vor dem Charakter im Workspace
--- abgelegt und `ItemDropped` gefeuert, damit z. B. PickupSpawner es wieder
--- zu einem aufhebbaren Welt-Pickup macht. Gibt false zurück, wenn der
--- Spieler aktuell nichts hält.
function HeldItemService.DropHeld(player: Player): boolean
	local userId = player.UserId
	local record = heldByUser[userId]
	if not record then
		return false
	end

	heldByUser[userId] = nil

	if record.Constraint then
		record.Constraint:Destroy()
	end
	if record.ItemAttachment then
		record.ItemAttachment:Destroy()
	end

	local character = player.Character
	if character then
		character:SetAttribute("CarryPose", nil)
	end

	local model = record.Model
	CollectionService:RemoveTag(model, HELD_TAG)
	model:SetAttribute("IsHeldItem", nil)
	model:SetAttribute("HeldByUserId", nil)

	if record.DestroyOnDrop or not model.Parent then
		model:Destroy()
	else
		local dropCFrame = if character then character:GetPivot() * DROP_FORWARD_OFFSET else model:GetPivot()

		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Massless = false
				-- Welt-Pickups sind bewusst nicht begehbar (siehe
				-- PickupSpawner) - kein CanCollide, um Spieler nicht auf
				-- einer kleinen Spore hängenzubleiben.
				descendant.CanCollide = false
				descendant.Anchored = true
			end
		end

		model.Parent = workspace
		model:PivotTo(dropCFrame)

		droppedBindable:Fire(player, model, record.ItemKind, dropCFrame)
	end

	if character then
		HeldItemRemotes.HeldItemChanged:FireClient(player, { Holding = false })
	end

	return true
end

--- Liefert eine schreibgeschützte Momentaufnahme dessen, was `player`
--- aktuell hält, oder nil.
function HeldItemService.GetHeld(player: Player): HeldInfo?
	local record = heldByUser[player.UserId]
	if not record then
		return nil
	end
	return {
		ItemKind = record.ItemKind,
		Model = record.Model,
		DisplayName = record.DisplayName,
		CarryPose = record.CarryPose,
	}
end

--- Entfernt das gehaltene Item aus der Hand von `player` OHNE es in die Welt
--- zu legen (kein `ItemDropped`-Event) - gedacht für "Verbrauchen" bei einer
--- Abgabe/Turn-in-Aktion (z. B. GlowBuoyStation-Abgabe in PickupSpawner).
--- Gibt (itemKind, model) zurück; der AUFRUFER übernimmt danach die
--- Verantwortung für `model` (z. B. selbst `:Destroy()` aufrufen, NACHDEM
--- die zugehörige Belohnung gewährt wurde). Gibt (nil, nil) zurück, falls
--- der Spieler nichts hält.
function HeldItemService.ConsumeHeld(player: Player): (string?, Model?)
	local userId = player.UserId
	local record = heldByUser[userId]
	if not record then
		return nil, nil
	end

	heldByUser[userId] = nil

	if record.Constraint then
		record.Constraint:Destroy()
	end
	if record.ItemAttachment then
		record.ItemAttachment:Destroy()
	end

	local character = player.Character
	if character then
		character:SetAttribute("CarryPose", nil)
	end

	CollectionService:RemoveTag(record.Model, HELD_TAG)
	record.Model:SetAttribute("IsHeldItem", nil)
	record.Model:SetAttribute("HeldByUserId", nil)

	HeldItemRemotes.HeldItemChanged:FireClient(player, { Holding = false })

	return record.ItemKind, record.Model
end

-- // Aufräumen bei Tod/Respawn/Leave ------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterRemoving:Connect(function()
		-- Der Charakter (und damit das per RigidConstraint daran hängende
		-- Item) wird gleich zerstört - nur Buchführung aufräumen, KEIN
		-- Welt-Drop (das würde ein "GlowSpore"-Item mitten in der Respawn-
		-- Animation irgendwo hinterlegen) und kein FireClient nötig.
		clearRecordSilently(player.UserId)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

Players.PlayerRemoving:Connect(function(player: Player)
	clearRecordSilently(player.UserId)
end)

return HeldItemService
