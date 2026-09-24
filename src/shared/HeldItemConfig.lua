--[[
	Abyssara – Deep Tide Tycoon
	Modul: HeldItemConfig
	Zuständigkeit:
		Zentrale, statische Stellschrauben für das "Items in der Hand"-System
		(HeldItemService/PickupSpawner/HeldItemClient): Anzeigenamen,
		Trageposen, Halte-Skalierung/-Versatz je Item-Art, sowie die
		Spawn-/Belohnungs-Parameter für aufhebbare Glow-Spore-Pickups und die
		GlowBuoyStation-Abgabe. Einzige Quelle der Wahrheit, damit Server
		(HeldItemService, PickupSpawner) und Client (HeldItemClient) nie
		auseinanderlaufen.

	Rojo-Einhängepunkt:
		src/shared/HeldItemConfig.lua -> ReplicatedStorage.HeldItemConfig
		(reines Datenmodul, für Server UND Client sicher lesbar - die
		alleinige Autorität über tatsächliches Halten/Aufheben/Abgeben bleibt
		serverseitig in HeldItemService/PickupSpawner.)

	Anbindung für andere Systeme (siehe docs/held-items.md):
		GachaService (geschlüpfte/gewürfelte Kreaturen) und BreedingService
		(fertige Zucht-Ergebnisse) sollen künftig `ItemKind = "Creature"`
		bzw. `ItemKind = "Egg"` an HeldItemService.HoldItem übergeben - die
		zugehörigen Trageposen/Skalierungen sind hier bereits vordefiniert,
		auch wenn die aufrufende Stelle in jenen Services noch nicht existiert
		(siehe Kopfkommentar dieser Datei / docs/held-items.md, Abschnitt
		"Künftige Aufrufer").
]]

export type CarryPose = "OneHand" | "TwoHand"

local HeldItemConfig = {}

-- // Item-Arten (ItemKind) ---------------------------------------------------
-- Bewusst als einfache Strings (nicht als geschlossene Union) modelliert,
-- damit künftige Item-Arten (z. B. weitere Sammel-Ressourcen) ergänzt werden
-- können, ohne dieses Modul zwingend anzufassen - fehlende Einträge fallen
-- unten überall sauber auf einen generischen Default zurück.
HeldItemConfig.ItemKinds = {
	GlowSpore = "GlowSpore", -- Sammel-Ressource, siehe PickupSpawner (GDD Abschnitt 3)
	Egg = "Egg", -- gekaufte/gewürfelte Mystery-Eggs, siehe GachaService (künftiger Aufrufer)
	Creature = "Creature", -- geschlüpfte/gezüchtete Kreaturen, siehe BreedingService (künftiger Aufrufer)
	FrozenSpore = "FrozenSpore", -- Frozen-Current-Event-Pickup (Auftauen + Aufheben), siehe PickupSpawner
}

HeldItemConfig.DefaultCarryPose = "OneHand" :: CarryPose
local DEFAULT_HOLD_SCALE = 0.6
local DEFAULT_GRIP_OFFSET = CFrame.new(0, -0.3, -0.6)

local CARRY_POSE_BY_KIND: { [string]: CarryPose } = {
	GlowSpore = "OneHand",
	Egg = "TwoHand", -- Eier sind sperrig - siehe ProceduralAnimator.CarryPose-Auswertung
	Creature = "TwoHand",
	FrozenSpore = "OneHand", -- verhält sich wie GlowSpore, siehe HeldItemConfig-Kopfkommentar
}

-- Model:ScaleTo()-Faktor beim Anbringen in der Hand (Items sollen kompakt in
-- der Hand wirken statt in Originalgröße mit der Bewegung zu kollidieren).
local HOLD_SCALE_BY_KIND: { [string]: number } = {
	GlowSpore = 0.5,
	Egg = 0.85,
	Creature = 0.65,
	FrozenSpore = 0.5,
}

local DISPLAY_NAME_BY_KIND: { [string]: string } = {
	GlowSpore = "Glow Spore",
	Egg = "Mystery Egg",
	Creature = "Creature",
	FrozenSpore = "Frozen Spore",
}

-- Lokaler CFrame-Versatz des "ItemGripAttachment" relativ zum PrimaryPart des
-- gehaltenen Items (NICHT relativ zur Hand!) - legt fest, wie das Item
-- gegenüber dem Greifpunkt der Hand ausgerichtet in Erscheinung tritt. Werte
-- gelten für die BEREITS skalierte Halte-Größe (siehe HoldScale oben), da
-- HeldItemService zuerst skaliert und danach das Attachment anbringt.
local GRIP_OFFSET_BY_KIND: { [string]: CFrame } = {
	GlowSpore = CFrame.new(0, -0.2, -0.5),
	Egg = CFrame.new(0, -0.7, -1.1) * CFrame.Angles(math.rad(-8), 0, 0),
	Creature = CFrame.new(0, -0.6, -1.0),
	FrozenSpore = CFrame.new(0, -0.2, -0.5),
}

--- Liefert die Trageposen-Attribut für `itemKind` ("OneHand"/"TwoHand"),
--- die HeldItemService in Character:SetAttribute("CarryPose", ...) schreibt.
--- Das prozedurale Animationssystem (ProceduralAnimator.lua) liest exakt
--- dieses Attribut, um die Arme entsprechend zu posieren - siehe
--- docs/held-items.md, Abschnitt "CarryPose-Attribut".
function HeldItemConfig.GetCarryPose(itemKind: string): CarryPose
	return CARRY_POSE_BY_KIND[itemKind] or HeldItemConfig.DefaultCarryPose
end

function HeldItemConfig.GetHoldScale(itemKind: string): number
	return HOLD_SCALE_BY_KIND[itemKind] or DEFAULT_HOLD_SCALE
end

function HeldItemConfig.GetDisplayName(itemKind: string): string
	return DISPLAY_NAME_BY_KIND[itemKind] or itemKind
end

function HeldItemConfig.GetGripOffset(itemKind: string): CFrame
	return GRIP_OFFSET_BY_KIND[itemKind] or DEFAULT_GRIP_OFFSET
end

-- // Glow-Spore-Weltpickups (PickupSpawner) ----------------------------------
HeldItemConfig.Pickup = {
	MaxPerPlot = 3, -- Obergrenze gleichzeitig liegender Sporen pro Plot (Performance/Balance)
	SpawnCheckIntervalSeconds = 20, -- Tick-Intervall: spawnt höchstens 1 neue Spore pro Tick, falls unter MaxPerPlot
	SpawnRadiusStuds = 20, -- max. Abstand vom Plot-Zentrum (bleibt sicher innerhalb der ~60-Stud-Sechseck-Plattform)
	MinSpawnRadiusStuds = 6, -- min. Abstand vom Plot-Zentrum (nicht direkt auf dem Spawnpunkt des Spielers)
	PromptHoldDurationSeconds = 0.3,
	PromptMaxActivationDistance = 8,
}

-- // GlowBuoyStation-Abgabe (Bonus-Tide-Coins) --------------------------------
HeldItemConfig.Deposit = {
	PromptHoldDurationSeconds = 0.5,
	PromptMaxActivationDistance = 10,
	TideCoinsReward = 25, -- Bonus-Tide-Coins pro abgegebener Glow Spore, siehe PlayerDataService.AddCurrency
}

return HeldItemConfig
