--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.SoundConfig
	Zuständigkeit:
		Zentrale Sound-ID-Tabelle für alle UIKit-Klick-/Feedback-Sounds.

		WICHTIG - Platzhalter-IDs: Die rbxassetid-Werte unten sind
		funktionierende, öffentlich verwendbare Katalog-Sounds, die als
		neutrale UI-Klicks/Blips durchgehen, aber bewusst NICHT final
		kuratiert/lizenzgeprüft für Abyssara sind. Sie sind hier klar als
		PLATZHALTER markiert und sollten vor Launch durch final abgemischte,
		zum Biolumineszenz-Thema passende Sounds (z. B. Blasen/Sonar-Pings)
		ersetzt werden. Ersetzen reicht an genau dieser Stelle - kein
		anderes Modul referenziert Sound-IDs direkt.

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
	Click = { Id = "rbxassetid://6895079853", Volume = 0.45, PitchRange = NumberRange.new(0.97, 1.05) }, -- PLATZHALTER
	-- Leiser Hover-Blip, nur auf Geräten mit echtem Hover (Maus).
	Hover = { Id = "rbxassetid://6895079091", Volume = 0.2, PitchRange = NumberRange.new(1.0, 1.08) }, -- PLATZHALTER
	-- Bestätigungs-/Erfolgs-Sound (Kauf abgeschlossen, Dialog bestätigt).
	Confirm = { Id = "rbxassetid://6895079967", Volume = 0.5 }, -- PLATZHALTER
	-- Abbrechen/Schließen eines Panels oder Dialogs.
	Close = { Id = "rbxassetid://6895079659", Volume = 0.4 }, -- PLATZHALTER
	-- Fehler/nicht erlaubt (z. B. zu wenig Tide Coins).
	Error = { Id = "rbxassetid://6895080172", Volume = 0.5 }, -- PLATZHALTER
	-- Toast/Benachrichtigung erscheint.
	Toast = { Id = "rbxassetid://6895079310", Volume = 0.35 }, -- PLATZHALTER
	-- Großer Moment: Level-Up.
	LevelUp = { Id = "rbxassetid://6895081384", Volume = 0.6 }, -- PLATZHALTER
	-- Großer Moment: Mythic-Drop aus dem Gacha.
	MythicDrop = { Id = "rbxassetid://6895081760", Volume = 0.7 }, -- PLATZHALTER

	-- // Musik/Ambiente (AudioController.client.lua) ---------------------------
	-- BEWUSST LEERE Id: Anders als die Klick-/Feedback-Sounds oben (bestehende,
	-- funktionierende Platzhalter-Katalog-Sounds) wird hier KEINE erfundene
	-- Asset-ID eingetragen - eine falsche/erratene ID würde in Produktion
	-- entweder gar nichts oder (schlimmer) einen fremden/ungeeigneten Sound
	-- abspielen. Leere Id = AudioController spielt bewusst nichts ab, bis
	-- die Spiel-Autorin hier eine selbst hochgeladene/lizenzierte
	-- rbxassetid:// einträgt (Loop = true auf dem jeweiligen Sound-Objekt ist
	-- in AudioController bereits vorbereitet).
	BackgroundMusic = { Id = "", Volume = 0.5 }, -- PLATZHALTER: eigene Musik-Asset-ID hier eintragen
	UnderwaterAmbience = { Id = "", Volume = 0.35 }, -- PLATZHALTER: eigene Ambiente-Asset-ID hier eintragen
}

return SoundConfig
