--[[
	Abyssara – Deep Tide Tycoon
	Skript: GachaOpenClient (LocalScript)
	Zuständigkeit:
		Client-seitiger Öffnungs-Flow für die bereits in der Welt platzierten
		Mystery-Egg-Modelle (assets/models/gacha/MysteryEgg_*.lua, unter
		Workspace.Assets.Gacha). Reagiert AUSSCHLIESSLICH auf das
		Server-Ergebnis (RemoteEvent "OpenEggResult") - trifft selbst keine
		Rarity-/Kreaturen-Entscheidung.

		Bei Klick auf ein Ei:
			1) Fordert per RemoteEvent "RequestOpenEgg" (ohne Payload) eine
			   Öffnung beim Server an.
			2) Sobald der Server antwortet: aktiviert das GachaEggOpenVFX-Rig
			   (assets/models/gacha/GachaEggOpenVFX.lua) für die Dauer der
			   Öffnungs-Zeremonie (Enabled = true), setzt die Rarity-Farbe,
			   und räumt das geklonte Rig danach wieder auf (Destroy).
			3) Zeigt kurz (per BillboardGui) die gewonnene Kreatur inkl.
			   Rarity und - im Duplikat-Fall - den Tide-Coin-Ausgleich an.

	GEÄNDERT (UIKit-Umstellung): Die Rarity-Farbe wird nicht mehr aus dem
	DOM-Baum des alten, manuell gebauten Odds-Panels ausgelesen (dieses
	Panel entsteht jetzt komplett per Code, siehe
	GachaOddsUIController.client.lua), sondern direkt aus
	UIKit.Theme.Rarity - laut docs/ui-kit.md 1:1 mit GachaConfig.DROP_TABLE
	synchron gehalten, also strikt äquivalent, aber ohne fragile
	Abhängigkeit von einer fremden UI-Instanzstruktur. Die Reveal-Anzeige
	nutzt jetzt UIKit.RarityBadge/Theme-Styling, und bei Legendary/Mythic-
	Drops spielt UIKit.ScreenFX.BigMoment (Flash + Kamera-Shake) plus ein
	UIKit.Toast fuer den "grossen Moment".

	Rojo-Einhängepunkt:
		src/client/GachaOpenClient.client.lua
			->  StarterPlayerScripts.GachaOpenClient
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen)

	Design-Entscheidung (Mapping Ei-Modell <-> Drop-Tabelle):
		Laut assets/models/README.md sind die sechs MysteryEgg_<Tier>-
		Modelle rein visuelle "Rarity-Erwartungsstufen" (Schalen-Design),
		KEIN separater Gacha-Pool pro Modell - es gibt laut GDD nur EIN
		Mystery-Egg-Produkt mit EINER Drop-Tabelle (siehe GachaConfig auf
		Server-Seite). Jedes platzierte Ei-Modell ist deshalb hier ein
		gleichwertiger Interaktionspunkt für dieselbe Drop-Tabelle; die
		Öffnungs-Zeremonie spielt unabhängig vom angeklickten Ei-Modell an
		dessen Position ab. Das angeklickte Modell wird zudem NICHT an den
		Server geschickt (kein Client-Trust) - der Server kennt nur den
		anfragenden `player`.

		Da es noch kein Kauf-/Bestandssystem gibt, ist jedes Ei-Modell ein
		wiederverwendbarer Test-Interaktionspunkt (kein Verbrauchsgut) - die
		Anbindung an einen echten Kauf-Flow (Developer Product/Robux via
		ProcessReceipt) ist bewusst nicht Teil dieses Bausteins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local GachaRemotes = require(ReplicatedStorage:WaitForChild("GachaRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX
local RarityBadge = UIKit.RarityBadge

local localPlayer = Players.LocalPlayer

local CLICK_MAX_DISTANCE = 20
local CRACK_TWEEN_TIME = 0.35
local VFX_ACTIVE_TIME = 1.1
local REVEAL_DISPLAY_TIME = 2.75

-- Fallback-Farbe, falls der Tier-String aus irgendeinem Grund nicht Teil
-- von Theme.RarityOrder ist (sollte praktisch nie vorkommen, da Server und
-- Theme dieselben Tier-Strings verwenden).
local FALLBACK_RARITY_COLOR = Color3.fromRGB(120, 235, 255)

-- Tiers, bei denen ein "großer Moment" (Flash + Kamera-Shake) gespielt wird.
local BIG_MOMENT_TIERS = { Legendary = true, Mythic = true }

local isOpeningEgg = false -- lokaler Debounce, verhindert Doppel-Klicks
local pendingEggModel: Model? = nil -- zuletzt angeklicktes Ei, für die VFX-Position

-- // Hilfsfunktionen ----------------------------------------------------------

--- Liest die Rarity-Farbe direkt aus UIKit.Theme.Rarity (siehe
--- docs/ui-kit.md: 1:1 synchron zu GachaConfig.DROP_TABLE gehalten).
local function getRarityColor(rarityTier: string): Color3
	local key = (rarityTier :: any) :: Theme.Rarity
	if table.find(Theme.RarityOrder, key) then
		return Theme.Rarity[key]
	end
	return FALLBACK_RARITY_COLOR
end

--- Fügt einem Ei-Modell (falls noch nicht vorhanden) einen ClickDetector
--- an seinem PrimaryPart ("Shell", siehe Namenskonvention in
--- assets/models/README.md) hinzu.
local function ensureClickDetector(eggModel: Model)
	local shell = eggModel.PrimaryPart
	if not shell then
		return
	end
	if shell:FindFirstChildOfClass("ClickDetector") then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = CLICK_MAX_DISTANCE
	clickDetector.Parent = shell

	clickDetector.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= localPlayer then
			return
		end
		if isOpeningEgg then
			return
		end
		isOpeningEgg = true
		pendingEggModel = eggModel
		GachaRemotes.RequestOpenEgg:FireServer()
	end)
end

--- Durchsucht Workspace.Assets.Gacha nach allen MysteryEgg_*-Modellen
--- (erkennbar am Attribut "EggTier", siehe assets/models/README.md) und
--- stattet sie mit einem ClickDetector aus. Läuft einmalig beim Start und
--- reagiert zusätzlich auf später hinzugefügte Eier (ChildAdded).
local function setupEggInteractions(gachaFolder: Folder)
	for _, child in ipairs(gachaFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("EggTier") ~= nil then
			ensureClickDetector(child)
		end
	end

	gachaFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child:GetAttribute("EggTier") ~= nil then
			ensureClickDetector(child)
		end
	end)
end

--- Spielt die Öffnungs-Zeremonie (Schalenriss + VFX-Rig) an der Position
--- des übergebenen Ei-Modells ab. Räumt sich danach vollständig selbst auf.
local function playOpenCeremony(eggModel: Model, rarityColor: Color3)
	local shell = eggModel.PrimaryPart
	if not shell then
		return
	end

	local vfxTemplate = Workspace
		:FindFirstChild("Assets")
	vfxTemplate = vfxTemplate and vfxTemplate:FindFirstChild("Gacha")
	vfxTemplate = vfxTemplate and vfxTemplate:FindFirstChild("GachaEggOpenVFX")

	-- 1) Schale kurz "knacken" lassen (Scale/Transparency-Tween statt
	--    aufwendiger Geometrie-Manipulation, siehe Asset-Kommentar in
	--    MysteryEgg_*.lua: PrimaryPart "Shell" ist der Ansatzpunkt dafür).
	local originalSize = shell.Size
	local originalTransparency = shell.Transparency

	local crackTween = TweenService:Create(
		shell,
		TweenInfo.new(CRACK_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Size = originalSize * 1.15, Transparency = 1 }
	)
	crackTween:Play()
	crackTween.Completed:Wait()

	-- 2) VFX-Rig klonen, an der Ei-Position andocken, rarity-farbig
	--    einfärben und für die Dauer der Zeremonie aktivieren.
	if vfxTemplate and vfxTemplate:IsA("Model") then
		local vfxClone = vfxTemplate:Clone()
		vfxClone.Parent = Workspace
		if vfxClone.PrimaryPart then
			vfxClone:PivotTo(shell.CFrame)
		end

		local shellCrackEmitter = vfxClone:FindFirstChild("ShellCrackPoint", true)
		shellCrackEmitter = shellCrackEmitter and shellCrackEmitter:FindFirstChildOfClass("ParticleEmitter")
		local lightBurstEmitter = vfxClone:FindFirstChild("LightBurstPoint", true)
		lightBurstEmitter = lightBurstEmitter and lightBurstEmitter:FindFirstChildOfClass("ParticleEmitter")
		local shineBurst = vfxClone:FindFirstChild("ShineBurst", true) :: PointLight?
		local rarityBeam = vfxClone:FindFirstChild("RarityBeam", true) :: Beam?

		if shellCrackEmitter then
			local emitter = shellCrackEmitter :: ParticleEmitter
			emitter.Color = ColorSequence.new(rarityColor)
			emitter.Enabled = true
			emitter:Emit(30)
		end
		if lightBurstEmitter then
			local emitter = lightBurstEmitter :: ParticleEmitter
			emitter.Color = ColorSequence.new(rarityColor)
			emitter.Enabled = true
			emitter:Emit(45)
		end
		if shineBurst then
			shineBurst.Color = rarityColor
			shineBurst.Enabled = true
		end
		if rarityBeam then
			rarityBeam.Color = ColorSequence.new(rarityColor)
			rarityBeam.Enabled = true
		end

		task.wait(VFX_ACTIVE_TIME)

		if shellCrackEmitter then
			(shellCrackEmitter :: ParticleEmitter).Enabled = false
		end
		if lightBurstEmitter then
			(lightBurstEmitter :: ParticleEmitter).Enabled = false
		end
		if shineBurst then
			shineBurst.Enabled = false
		end
		if rarityBeam then
			rarityBeam.Enabled = false
		end

		vfxClone:Destroy()
	else
		warn("[GachaOpenClient] GachaEggOpenVFX-Template nicht gefunden unter Workspace.Assets.Gacha.")
		task.wait(VFX_ACTIVE_TIME)
	end

	-- 3) Ei-Modell zurücksetzen - es ist (mangels echtem Bestandssystem)
	--    ein wiederverwendbarer Interaktionspunkt, kein Verbrauchsgut.
	local resetTween = TweenService:Create(
		shell,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = originalSize, Transparency = originalTransparency }
	)
	resetTween:Play()
end

--- Zeigt kurz per BillboardGui die gewonnene Kreatur (Name + Rarity, im
--- Duplikat-Fall zusätzlich den Tide-Coin-Ausgleich) über dem Ei an.
local function showRevealBillboard(eggModel: Model, resultPayload: { [string]: any })
	local shell = eggModel.PrimaryPart
	if not shell then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaRevealBillboard"
	billboard.Size = UDim2.fromOffset(240, 100)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = shell

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.Background.Panel
	background.BackgroundTransparency = 0.1
	background.BorderSizePixel = 0
	background.Parent = billboard
	Theme.ApplyCorner(background, UDim.new(0, 10))
	Theme.ApplyGradient(background, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

	local rarityColor = getRarityColor(resultPayload.Rarity)
	local stroke = Theme.ApplyStroke(background, rarityColor, 2)
	stroke.Transparency = 0.1

	local rarityKey = (resultPayload.Rarity :: any) :: Theme.Rarity
	if table.find(Theme.RarityOrder, rarityKey) then
		RarityBadge.new({
			Parent = background,
			Rarity = rarityKey,
			Size = UDim2.fromOffset(110, 24),
			Position = UDim2.new(0.5, -55, 0, 8),
		})
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -12, 0, 30)
	nameLabel.Position = UDim2.new(0, 6, 0, 36)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = resultPayload.CreatureName
	nameLabel.TextColor3 = Theme.Text.Primary
	nameLabel.Font = Theme.Font.BodyBold
	nameLabel.TextScaled = true
	nameLabel.Parent = background
	Theme.ApplyStroke(nameLabel, Theme.Text.Stroke, 1)

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -12, 0, 24)
	subLabel.Position = UDim2.new(0, 6, 0, 68)
	subLabel.BackgroundTransparency = 1
	subLabel.TextColor3 = rarityColor
	subLabel.Font = Theme.Font.Body
	subLabel.TextScaled = true
	local toastText: string
	if resultPayload.ResultType == "Duplicate" then
		subLabel.Text = ("Duplikat, +%d Tide Coins"):format(resultPayload.CompensationTideCoins)
		toastText = ("%s (Duplikat) +%d Tide Coins"):format(resultPayload.CreatureName, resultPayload.CompensationTideCoins)
	else
		subLabel.Text = if resultPayload.PityForced then "Pity!" else ""
		toastText = ("Neu: %s (%s)"):format(resultPayload.CreatureName, Theme.RarityLabel[rarityKey] or resultPayload.Rarity)
	end
	subLabel.Parent = background

	-- // Große Momente: Legendary/Mythic bekommen Flash + Kamera-Shake ---------
	if BIG_MOMENT_TIERS[resultPayload.Rarity] then
		ScreenFX.BigMoment(rarityColor)
		Toast.Show({ Text = toastText, Type = "Success", Duration = 4.5 })
	else
		Toast.Show({ Text = toastText, Type = "Info", Duration = 3 })
	end

	task.delay(REVEAL_DISPLAY_TIME, function()
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	end)
end

-- // Server-Ergebnis entgegennehmen -------------------------------------------

GachaRemotes.OpenEggResult.OnClientEvent:Connect(function(payload: { [string]: any })
	local eggModel = pendingEggModel
	pendingEggModel = nil

	if not payload.Success then
		isOpeningEgg = false
		if payload.Failure == "OnCooldown" then
			-- Kein UI-Fehlerdialog nötig fürs MVP - einfache Konsole-Warnung
			-- reicht, da es sich um einen reinen Anti-Spam-Schutz handelt.
			warn("[GachaOpenClient] Anfrage zu schnell wiederholt, bitte kurz warten.")
		elseif payload.Failure == "DataNotLoaded" then
			-- Spielerdaten (PlayerDataService) sind serverseitig noch nicht
			-- fertig geladen (z. B. Anfrage sehr kurz nach dem Join). Kein
			-- Datenverlust-Risiko, einfach erneut versuchen.
			warn("[GachaOpenClient] Spielerdaten werden noch geladen, bitte kurz warten und erneut versuchen.")
		end
		return
	end

	local result = payload.Result
	local rarityColor = getRarityColor(result.Rarity)

	if eggModel and eggModel.Parent then
		task.spawn(function()
			local ok, err = pcall(playOpenCeremony, eggModel, rarityColor)
			if not ok then
				warn("[GachaOpenClient] Fehler in der Öffnungs-Zeremonie:", err)
			end
			showRevealBillboard(eggModel, result)
			isOpeningEgg = false
		end)
	else
		-- Ei-Modell nicht mehr vorhanden (z. B. aus der Welt entfernt) -
		-- Ergebnis trotzdem nicht verschlucken.
		print(("[GachaOpenClient] Ergebnis: %s (%s)"):format(result.CreatureName, result.Rarity))
		isOpeningEgg = false
	end
end)

-- // Setup ---------------------------------------------------------------------

local assetsFolder = Workspace:WaitForChild("Assets", 10)
if assetsFolder then
	local gachaFolder = assetsFolder:WaitForChild("Gacha", 10)
	if gachaFolder and gachaFolder:IsA("Folder") then
		setupEggInteractions(gachaFolder)
	else
		warn("[GachaOpenClient] Workspace.Assets.Gacha nicht gefunden - wurden die Gacha-Buildscripts ausgeführt?")
	end
else
	warn("[GachaOpenClient] Workspace.Assets nicht gefunden - wurden die Asset-Buildscripts ausgeführt?")
end
