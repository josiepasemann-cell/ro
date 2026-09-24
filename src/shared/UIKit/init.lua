--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit (Einstiegspunkt)
	Zuständigkeit:
		Aggregiert alle UIKit-Bausteine unter einem einzigen require. Ist
		die Fassade, die alle künftigen Menü-Umstellungen nutzen sollen:

			local UIKit = require(ReplicatedStorage.UIKit)
			local button = UIKit.Button.new({ ... })

		Siehe docs/ui-kit.md für die vollständige API-Doku.

	Rojo-Einhängepunkt:
		src/shared/UIKit/ (Ordner mit init.lua)
			-> ReplicatedStorage.UIKit (ModuleScript)
			-> Kind-Module (Device, Theme, Button, Panel, ...) werden von
			   Rojo automatisch als Kind-ModuleScripts von
			   ReplicatedStorage.UIKit eingehängt (Standardverhalten für
			   Ordner mit init.lua).
]]

local UIKit = {}

UIKit.Signal = require(script:WaitForChild("Signal"))
UIKit.Device = require(script:WaitForChild("Device"))
UIKit.Theme = require(script:WaitForChild("Theme"))
UIKit.Settings = require(script:WaitForChild("Settings"))
UIKit.SoundConfig = require(script:WaitForChild("SoundConfig"))
UIKit.ParticlePool = require(script:WaitForChild("ParticlePool"))
UIKit.Layout = require(script:WaitForChild("Layout"))
UIKit.Button = require(script:WaitForChild("Button"))
UIKit.Panel = require(script:WaitForChild("Panel"))
UIKit.Tabs = require(script:WaitForChild("Tabs"))
UIKit.Toast = require(script:WaitForChild("Toast"))
UIKit.CountUp = require(script:WaitForChild("CountUp"))
UIKit.ProgressBar = require(script:WaitForChild("ProgressBar"))
UIKit.RarityBadge = require(script:WaitForChild("RarityBadge"))
UIKit.ConfirmDialog = require(script:WaitForChild("ConfirmDialog"))
UIKit.ScreenFX = require(script:WaitForChild("ScreenFX"))

return UIKit
