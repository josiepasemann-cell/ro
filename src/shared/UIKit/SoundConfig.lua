--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.SoundConfig
	Zuständigkeit:
		Zentrale Sound-ID-Tabelle für alle UIKit-Klick-/Feedback-Sounds.

		Alle IDs sind bewusst leer: eine erratene Asset-ID spielt entweder
		nichts oder einen fremden, womöglich unpassenden Sound ab. Leere Id =
		es wird nichts abgespielt. Vor dem Launch eigene, selbst hochgeladene
		oder lizenzierte rbxassetid://-Werte eintragen (siehe
		docs/release-checklist.md). Nur diese Datei referenziert Sound-IDs.

	Rojo-Einhängepunkt:
		src/shared/UIKit/SoundConfig.lua -> ReplicatedStorage.UIKit.SoundConfig
]]

export type SoundDefinition = {
	Id: string,
	Volume: number,
	PitchRange: NumberRange?, -- optionale Zufalls-Pitch-Variation gegen Wiederholungs-Ermüdung
}

local SoundConfig: { [string]: SoundDefinition } = {
	-- Standard-Klick, für jeden Button aus der Button-Factory.
	Click = { Id = "", Volume = 0.45, PitchRange = NumberRange.new(0.97, 1.05) }, -- PLATZHALTER
	-- Leiser Hover-Blip, nur auf Geräten mit echtem Hover (Maus).
	Hover = { Id = "", Volume = 0.2, PitchRange = NumberRange.new(1.0, 1.08) }, -- PLATZHALTER
	-- Bestätigungs-/Erfolgs-Sound (Kauf abgeschlossen, Dialog bestätigt).
	Confirm = { Id = "", Volume = 0.5 }, -- PLATZHALTER
	-- Abbrechen/Schließen eines Panels oder Dialogs.
	Close = { Id = "", Volume = 0.4 }, -- PLATZHALTER
	-- Fehler/nicht erlaubt (z. B. zu wenig Tide Coins).
	Error = { Id = "", Volume = 0.5 }, -- PLATZHALTER
	-- Toast/Benachrichtigung erscheint.
	Toast = { Id = "", Volume = 0.35 }, -- PLATZHALTER
	-- Großer Moment: Level-Up.
	LevelUp = { Id = "", Volume = 0.6 }, -- PLATZHALTER
	-- Großer Moment: Mythic-Drop aus dem Gacha.
	MythicDrop = { Id = "", Volume = 0.7 }, -- PLATZHALTER

	-- // Musik/Ambiente (AudioController.client.lua) ---------------------------
	-- Loops; AudioController setzt Looped = true.
	BackgroundMusic = { Id = "", Volume = 0.5 }, -- PLATZHALTER: eigene Musik-Asset-ID hier eintragen
	UnderwaterAmbience = { Id = "", Volume = 0.35 }, -- PLATZHALTER: eigene Ambiente-Asset-ID hier eintragen
}

return SoundConfig
