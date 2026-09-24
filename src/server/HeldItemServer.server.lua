--[[
	Abyssara – Deep Tide Tycoon
	Skript: HeldItemServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des "Items in der Hand"-Systems auf
		Server-Seite: verbindet den RemoteEvent-Kanal aus HeldItemRemotes mit
		HeldItemService, und orchestriert den Join-/Leave-Ablauf für
		PickupSpawner (Glow-Spore-Spawn-Loop pro Plot). Enthält selbst KEINE
		Halte-/Spawn-/Abgabe-Logik - die bleibt vollständig in
		HeldItemService/PickupSpawner, identisches Muster zu
		PlacementService/PlacementServer.server.lua.

	Rojo-Einhängepunkt:
		src/server/HeldItemServer.server.lua -> ServerScriptService.HeldItemServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestDropHeld wird ohne jegliche Payload vom Client entgegen-
		genommen - der einzige vertrauenswürdige Wert ist `player`, den die
		Roblox-Engine selbst als ersten Parameter von OnServerEvent liefert.
		HeldItemService.DropHeld legt IMMER nur das Item DES ANFRAGENDEN
		Spielers ab, niemals ein fremdes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeldItemService = require(script.Parent:WaitForChild("HeldItemService"))
local PickupSpawner = require(script.Parent:WaitForChild("PickupSpawner"))
local HeldItemRemotes = require(ReplicatedStorage:WaitForChild("HeldItemRemotes"))

HeldItemRemotes.RequestDropHeld.OnServerEvent:Connect(function(player: Player)
	HeldItemService.DropHeld(player)
end)

Players.PlayerAdded:Connect(PickupSpawner.OnPlayerAdded)
Players.PlayerRemoving:Connect(PickupSpawner.OnPlayerRemoving)

-- Falls dieses Skript erst nach PlayerAdded-Events hochläuft (z. B.
-- Studio-Playtest-Timing), bereits verbundene Spieler nachträglich
-- einbuchen - gleiche Absicherung wie in PlacementServer.server.lua.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(PickupSpawner.OnPlayerAdded, existingPlayer)
end

print("[Abyssara] HeldItemServer ready (RequestDropHeld wired up, PickupSpawner active).")
