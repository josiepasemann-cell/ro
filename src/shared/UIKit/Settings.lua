--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Settings
	Zuständigkeit:
		Winzige clientseitige Flag-Ablage für UIKit-weite Einstellungen -
		aktuell nur "Reduzierte Effekte" (deaktiviert Partikel-Bursts,
		Idle-Pulsieren, Screen-Shake für Spieler mit Bewegungsempfindlich-
		keit/Low-End-Geräten). Button.lua, ScreenFX.lua und ParticlePool.lua
		fragen dieses Flag ab, bevor sie teure Tweens/Partikel erzeugen.

		Bewusst kein DataStore-Zugriff hier - Persistenz über mehrere
		Sessions ist Aufgabe des Menü-Agenten, der dieses Modul später an
		ein echtes Einstellungsmenü/ProfileService-Pattern anschließt.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Settings.lua -> ReplicatedStorage.UIKit.Settings
]]

local Signal = require(script.Parent:WaitForChild("Signal"))

local Settings = {}

Settings.Changed = Signal.new() :: any -- fires (key: string, value: any)

local state = {
	ReducedEffects = false,
}

function Settings.GetReducedEffects(): boolean
	return state.ReducedEffects
end

function Settings.SetReducedEffects(value: boolean)
	if state.ReducedEffects == value then
		return
	end
	state.ReducedEffects = value
	Settings.Changed:Fire("ReducedEffects", value)
end

-- Kurzform für FX-Module: true, wenn aufwändige Effekte (Partikel, Glow-
-- Animation, Idle-Pulsieren, Screen-Shake) übersprungen werden sollen.
function Settings.ShouldSkipFX(): boolean
	return state.ReducedEffects
end

return Settings
