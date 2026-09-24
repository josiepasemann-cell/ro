--!strict
--[[
	AnimationConfig.lua
	Ort: ReplicatedStorage.CharacterAnimation.AnimationConfig

	Zentrale Stellschrauben für das prozedurale Animationssystem von
	"Abyssara – Deep Tide Tycoon" sowie der optionale Override-Mechanismus
	für echte, hochgeladene Roblox-Animationen (siehe docs/animations.md).

	WICHTIG für die Nutzerin: Um eigene Animationen (z.B. aus dem Animation
	Editor) statt der prozeduralen Bewegung zu verwenden, trage die
	Animation-ID (Format "rbxassetid://123456789") unten bei
	`AnimationOverrides` ein. Ist ein Feld gesetzt, lädt der Client die
	echte Animation über Animator:LoadAnimation() und deaktiviert für
	diesen Slot die prozedurale Version.
]]

export type AnimationSlot = "Idle" | "Walk" | "Run" | "Jump" | "Fall" | "Land"

export type AnimationOverrideTable = { [string]: string } -- Slot -> "rbxassetid://..."

local AnimationConfig = {}

-- ===== Optionaler Override: echte, hochgeladene Animationen =====
-- Leer lassen ("") = prozedurale Animation wird benutzt (Standard/Hauptweg).
-- Siehe docs/animations.md für die Upload-Anleitung.
AnimationConfig.AnimationOverrides: AnimationOverrideTable = {
	Idle = "",
	Walk = "",
	Run = "",
	Jump = "",
	Fall = "",
	Land = "",
}

-- Bevorzugte Priorität beim Abspielen mehrerer Override-Animationen gleichzeitig
AnimationConfig.OverridePriority = Enum.AnimationPriority.Movement

-- ===== Bewegungstuning =====
AnimationConfig.BaseWalkSpeed = 16
AnimationConfig.SprintSpeed = 26
AnimationConfig.SprintWalkSpeedCap = 34 -- serverseitige Obergrenze, auch bei künftigen Buffs

-- Distanz (Studs), ab der die Laufbewegung als "Sprint" gilt, für reine Client-Erkennung
-- bei Charakteren ohne eigene Sprint-Eingabe (z.B. NPC-artige Bewegung durch externe Systeme)
AnimationConfig.RunSpeedThreshold = 20

-- Stride-Länge in Studs: wie viele Studs Bewegung einem vollen Schrittzyklus entsprechen.
-- Direkt an die tatsächliche Geschwindigkeit gekoppelt -> kein Moonwalk/Rutschen.
AnimationConfig.StrideLength = 5.2

-- ===== Amplituden / Look & Feel =====
AnimationConfig.WalkArmSwing = 0.55 -- Radiant
AnimationConfig.WalkLegSwing = 0.65
AnimationConfig.RunArmSwing = 1.05
AnimationConfig.RunLegSwing = 1.25
AnimationConfig.RunLean = 0.22 -- Radiant Vorwärtsneigung beim Rennen
AnimationConfig.WalkBob = 0.09 -- Studs vertikaler Bob
AnimationConfig.RunBob = 0.16
AnimationConfig.HipSway = 0.12
AnimationConfig.HeadLookStrength = 0.35

-- ===== Sprung / Fall / Landung =====
AnimationConfig.AnticipationDip = 0.12 -- Sekunden-Feeling für kurzes Einknicken vor Absprung
AnimationConfig.JumpStretch = 0.18
AnimationConfig.AirTuck = 0.35
AnimationConfig.FallBrace = 0.28
AnimationConfig.LandSquashSpeed = 16 -- Federsteifigkeit
AnimationConfig.LandSquashDamping = 0.55 -- < 1 = etwas Überschwingen (Federgefühl)
AnimationConfig.MinFallSpeedForImpact = 8 -- Studs/s, ab wann eine Landung "hart" wirkt
AnimationConfig.MaxFallSpeedForImpact = 65

-- ===== Idle / Unterwasser-Flair =====
AnimationConfig.IdleBreatheSpeed = 1.1
AnimationConfig.IdleBreatheAmp = 0.045
AnimationConfig.UnderwaterFlairEnabled = true
AnimationConfig.UnderwaterHoverAmp = 0.06
AnimationConfig.UnderwaterHoverSpeed = 0.6
AnimationConfig.UnderwaterDragFactor = 0.85 -- >0 = trägere/weichere Übergänge

-- ===== Blend-Federn (Speed/Damping je Zustand) =====
AnimationConfig.WeightSpringSpeed = 9
AnimationConfig.WeightSpringDamping = 1
AnimationConfig.LeanSpringSpeed = 10
AnimationConfig.LeanSpringDamping = 0.9

-- ===== LOD (Level of Detail nach Distanz zur Kamera) =====
AnimationConfig.LODFullDistance = 45
AnimationConfig.LODReducedDistance = 110
-- > LODReducedDistance => Off (nur seltene Updates/Ruhepose)
AnimationConfig.LODReducedUpdateHz = 12 -- Update-Rate im Reduced-LOD
AnimationConfig.LODOffUpdateHz = 3

-- ===== FX =====
AnimationConfig.FootstepFXEnabled = true
AnimationConfig.LandingFXEnabled = true
AnimationConfig.FXPoolSize = 28
AnimationConfig.FootstepFXMinSpeed = 14 -- erst ab Lauftempo, nicht beim Gehen

-- ===== Carry-Pose (wird von einem externen Halte-System per Attribut gesetzt) =====
AnimationConfig.CarryBlendSpeed = 14
AnimationConfig.CarryBlendDamping = 1

function AnimationConfig.GetOverride(slot: string): string?
	local id = AnimationConfig.AnimationOverrides[slot]
	if id and id ~= "" then
		return id
	end
	return nil
end

return AnimationConfig
