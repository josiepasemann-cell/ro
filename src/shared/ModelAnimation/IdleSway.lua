--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: IdleSway
	Zuständigkeit:
		Gemeinsame, günstige "am Leben"-Idle-Animation (Bob + Sway +
		Flossen-/Tentakel-Zucken) für JEDES Kreaturen-Modell, egal ob als
		Plot-Anzeige-Kreatur (CreatureDisplayService), Buddy (BuddyClient)
		oder Raid-Gegner (RaidService) verwendet - EIN Modul, damit alle drei
		optisch konsistent "atmen" (siehe docs/animation-system.md).

		Reine Funktions-API, KEIN eigener Loop/keine eigene Registry - der
		Aufrufer (typischerweise src/client/ModelAnimator.client.lua) hält
		den `SwayState` selbst und ruft `IdleSway.Apply(...)` jeden Frame
		auf. So bleibt die Renderloop-/LOD-Verantwortung komplett beim
		Aufrufer (ein einziger RunService-Connect fürs ganze Spiel, siehe
		Auftrag "no per-model connections").

	Ansatzpunkte am Modell (siehe assets/models/creatures/*.lua-Buildscripts,
	assets/models/README.md):
		- PrimaryPart "Body" trägt ein Attachment "PulseAttachment" (bereits
		  vorhanden, aktuell ungenutzt) - wird hier NUR als Marker gelesen
		  ("hat dieses Modell überhaupt eine Idle-Pulse-Konvention"), die
		  eigentliche Bob-/Puls-Bewegung wird als RIGIDE Pivot-Transform auf
		  das gesamte Modell angewendet (identisches Prinzip zu
		  NpcAmbientController.client.lua) - kein Bone/Motor6D nötig, jeder
		  Part (inkl. undekorierter starrer Teile) bewegt sich mit.
		- Benannte Flossen-/Anhang-Parts (TailFin, DorsalFin, SideFin, Wing,
		  Tentacle1..N, Spine/SpineSpike, Horn, Nose, LowerJaw, Tip/TailTip,
		  Facet) werden zusätzlich einzeln in kleinem Winkel geschwenkt, falls
		  vorhanden - rein namensbasiert (KEINE feste Kreaturen-Liste nötig,
		  neue Kreaturen-Buildscripts profitieren automatisch).

	Rojo-Einhängepunkt:
		src/shared/ModelAnimation/IdleSway.lua ->
		ReplicatedStorage.ModelAnimation.IdleSway
]]

local IdleSway = {}

-- // Tuning ---------------------------------------------------------------------

local BOB_AMPLITUDE_STUDS = 0.5
local BOB_SPEED_MIN, BOB_SPEED_MAX = 0.7, 1.3
local ROLL_ANGLE = math.rad(3)
local ROLL_SPEED = 0.5

local PART_SWAY_ANGLE = math.rad(14)
local PART_SWAY_SPEED_MIN, PART_SWAY_SPEED_MAX = 1.0, 2.2

-- Namensbasierte Erkennung schwenkbarer Anhang-Parts (siehe Kopfkommentar) -
-- Präfix-Match (z. B. deckt "Tentacle1".."Tentacle6" ab), reine
-- Kleinbuchstaben-Vergleiche.
local SWAYABLE_PREFIXES = {
	"tailfin",
	"dorsalfin",
	"sidefin",
	"wing",
	"tentacle",
	"spinespike",
	"tailtip",
	"tip",
	"lowerjaw",
	"horn",
	"nose",
	"facet",
	"claw",
	"antenna",
}

local function isSwayablePartName(name: string): boolean
	local lower = string.lower(name)
	for _, prefix in ipairs(SWAYABLE_PREFIXES) do
		if string.sub(lower, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

export type SwayPart = { Part: BasePart, RestOffset: CFrame, Speed: number, PhaseOffset: number }

export type SwayState = {
	Model: Model,
	PrimaryPart: BasePart,
	Seed: number,
	BobSpeed: number,
	SwayParts: { SwayPart },
	HasBob: boolean,
}

--- Baut den (einmaligen, günstigen) Sway-Zustand für `model`. `model.PrimaryPart`
--- muss gesetzt sein (Buildscript-Konvention "Body"), sonst wird `nil`
--- zurückgegeben (Aufrufer überspringt Idle-Animation für dieses Modell).
function IdleSway.BuildState(model: Model, seed: number?): SwayState?
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		return nil
	end

	local restPivot = model:GetPivot()
	local swayParts: { SwayPart } = {}
	for index, descendant in ipairs(model:GetChildren()) do
		if descendant:IsA("BasePart") and descendant ~= primaryPart and isSwayablePartName(descendant.Name) then
			table.insert(swayParts, {
				Part = descendant,
				RestOffset = restPivot:ToObjectSpace(descendant.CFrame),
				Speed = PART_SWAY_SPEED_MIN + (index % 5) / 5 * (PART_SWAY_SPEED_MAX - PART_SWAY_SPEED_MIN),
				PhaseOffset = index * 0.7,
			})
		end
	end

	local hasBob = primaryPart:FindFirstChild("PulseAttachment") ~= nil or true -- jedes Modell darf idle-bobben, PulseAttachment ist nur die dokumentierte Konvention

	return {
		Model = model,
		PrimaryPart = primaryPart,
		Seed = seed or (math.random() * 1000),
		BobSpeed = BOB_SPEED_MIN + math.random() * (BOB_SPEED_MAX - BOB_SPEED_MIN),
		SwayParts = swayParts,
		HasBob = hasBob,
	}
end

--- Wendet die Idle-Animation auf `state.Model` an: `basePivot` ist die vom
--- Aufrufer bereits berechnete "Fahr-/Wander-Pivot" (Position + Blickrichtung,
--- OHNE Bob) - IdleSway legt Bob/Roll nur noch ON TOP drauf und setzt am Ende
--- `Model:PivotTo(...)` EINMAL (billig - kein zweiter PivotTo-Aufruf für die
--- Anhang-Parts, die werden direkt einzeln gesetzt). `intensityScale` erlaubt
--- Bosse/verlangsamte Gegner schwerere bzw. trägere Bewegung (siehe RaidService-
--- Attribute "IsBoss"/"Slowed", ausgewertet vom Aufrufer).
function IdleSway.Apply(state: SwayState, basePivot: CFrame, now: number, allowFX: boolean, intensityScale: number?)
	if not allowFX then
		state.Model:PivotTo(basePivot)
		return
	end

	local scale = intensityScale or 1
	local bob = math.sin(now * state.BobSpeed * scale + state.Seed) * BOB_AMPLITUDE_STUDS * scale
	local roll = math.sin(now * ROLL_SPEED * scale + state.Seed * 0.5) * ROLL_ANGLE * scale
	local currentPivot = basePivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, roll)
	state.Model:PivotTo(currentPivot)

	for _, swayPart in ipairs(state.SwayParts) do
		local part = swayPart.Part
		if part.Parent then
			local angle = math.sin(now * swayPart.Speed * scale + state.Seed + swayPart.PhaseOffset) * PART_SWAY_ANGLE * scale
			part.CFrame = currentPivot * swayPart.RestOffset * CFrame.Angles(0, angle, angle * 0.4)
		end
	end
end

return IdleSway
