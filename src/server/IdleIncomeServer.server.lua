--[[
	Abyssara – Deep Tide Tycoon
	Skript: IdleIncomeServer (Script, kein ModuleScript)
	Zuständigkeit:
		Dünner Bootstrap für das Idle-Einkommen-/Produktionssystem: stellt
		sicher, dass IdleIncomeService.lua (Online-Tick-Loop + Offline-
		Progress-Berechnung, verdrahtet PlayerAdded bereits selbst beim
		require()) tatsächlich hochgeladen wird - identisches Muster zu
		GachaServer.server.lua/PlacementServer.server.lua, nur ohne eigene
		Remote-Verdrahtung: der Client sendet in diesem System nichts an den
		Server (siehe IdleIncomeRemotes.lua, reine Server->Client-Feedback-
		Events), es gibt also keinen OnServerEvent-Handler hier einzurichten.

	Rojo-Einhängepunkt:
		src/server/IdleIncomeServer.server.lua -> ServerScriptService.IdleIncomeServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)
]]

local IdleIncomeService = require(script.Parent:WaitForChild("IdleIncomeService"))

-- Referenz nur gehalten, damit ein künftiger Linter das require() nicht als
-- "ungenutzt" markiert - IdleIncomeService verdrahtet seinen Tick-Loop und
-- PlayerAdded-Hook bereits vollständig selbst beim require() oben.
local _ = IdleIncomeService

print("[Abyssara] IdleIncomeServer bereit (Online-Tick-Loop + Offline-Progress aktiv).")
