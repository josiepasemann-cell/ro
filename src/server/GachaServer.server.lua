--[[
	Abyssara – Deep Tide Tycoon
	Skript: GachaServer (Script, kein ModuleScript)
	Zuständigkeit:
		Bootstrap/Verdrahtung des Mystery-Egg-Gacha-Systems auf Server-Seite:
		verbindet die RemoteEvent/RemoteFunction-Kanäle aus GachaRemotes mit
		der reinen Logik in GachaService. Enthält selbst KEINE Gacha-Logik
		(Roll/Pity/Duplikat) - das bleibt vollständig in GachaService, damit
		dieses Skript austauschbar/dünn bleibt.

	Rojo-Einhängepunkt:
		src/server/GachaServer.server.lua  ->  ServerScriptService.GachaServer
		(".server.lua"-Suffix signalisiert Rojo, hieraus ein normales
		Server-`Script` zu machen statt eines `ModuleScript`)

	Sicherheitsprinzip (kein Client-Trust):
		RequestOpenEgg wird ohne jegliche Payload vom Client entgegen-
		genommen. Der einzige vertrauenswürdige Wert aus dem Event ist der
		`player`, den die Roblox-Engine selbst als ersten Parameter von
		OnServerEvent liefert (vom Client nicht fälschbar). Alles andere
		(Rarity, Kreatur, Pity-Stand) wird ausschließlich von GachaService
		serverseitig bestimmt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GachaService = require(script.Parent:WaitForChild("GachaService"))
local GachaConfig = require(script.Parent:WaitForChild("GachaConfig"))
local GachaRemotes = require(ReplicatedStorage:WaitForChild("GachaRemotes"))

-- Die Ei-Buildscripts bauen die Eier nebeneinander nahe dem Weltursprung.
-- Klickbar sollen sie aber an der Mystery-Egg-Station im Hub stehen: drei
-- Schau-Eier auf den drei EggDisplaySlots, die übrigen wandern als Vorlagen
-- aus der Welt. Der Preis steht als Attribut am Ei, damit der Client ihn
-- anzeigen kann, ohne ihn selbst zu kennen.
local SHOWCASE_EGGS = { "MysteryEgg_Common", "MysteryEgg_Epic", "MysteryEgg_Mythic" }

local function arrangeEggsAtStation()
	local assets = Workspace:FindFirstChild("Assets")
	local gachaFolder = assets and assets:FindFirstChild("Gacha")
	local hubFolder = assets and assets:FindFirstChild("Hub")
	local hub = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	local station = hub and hub:FindFirstChild("GachaStation", true)
	if not gachaFolder then
		return
	end

	for _, child in ipairs(gachaFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("EggTier") ~= nil then
			child:SetAttribute("EggCostTideCoins", GachaConfig.EGG_COST_TIDE_COINS)
		end
	end

	if not station then
		warn("[GachaServer] Hub/GachaStation fehlt - Eier bleiben an ihrer Bau-Position.")
		return
	end

	local templates = ReplicatedStorage:FindFirstChild("AssetTemplates")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "AssetTemplates"
		templates.Parent = ReplicatedStorage
	end
	local gachaTemplates = templates:FindFirstChild("Gacha")
	if not gachaTemplates then
		gachaTemplates = Instance.new("Folder")
		gachaTemplates.Name = "Gacha"
		gachaTemplates.Parent = templates
	end

	for _, child in ipairs(gachaFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("EggTier") ~= nil then
			local slotIndex = table.find(SHOWCASE_EGGS, child.Name)
			local slot = slotIndex and station:FindFirstChild("EggDisplaySlot" .. slotIndex, true)
			if slot and slot:IsA("Attachment") then
				local height = child:GetExtentsSize().Y
				child:PivotTo(CFrame.new(slot.WorldPosition + Vector3.new(0, height / 2, 0)))
			else
				child.Parent = gachaTemplates
			end
		end
	end
end

arrangeEggsAtStation()

GachaRemotes.RequestOpenEgg.OnServerEvent:Connect(function(player: Player)
	local result, failure = GachaService.OpenEgg(player)

	if not result then
		-- z. B. "OnCooldown" bei zu schneller Wiederholungs-Anfrage
		-- (Anti-Spam-Schutz, siehe GachaConfig.MIN_SECONDS_BETWEEN_ROLLS).
		-- Kein hartes Kick/Ban hier - eine zu schnelle Doppel-Anfrage kann
		-- auch durch Netzwerk-Jitter/Doppelklick entstehen.
		GachaRemotes.OpenEggResult:FireClient(player, {
			Success = false,
			Failure = failure,
		})
		return
	end

	GachaRemotes.OpenEggResult:FireClient(player, {
		Success = true,
		Result = result,
	})
end)

GachaRemotes.GetGachaOdds.OnServerInvoke = function(_player: Player)
	return GachaService.GetOddsTable()
end

print("[Abyssara] GachaServer bereit (RequestOpenEgg / GetGachaOdds verdrahtet).")
