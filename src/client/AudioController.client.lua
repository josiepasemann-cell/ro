--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: AudioController (LocalScript)
	Zuständigkeit:
		Hintergrundmusik + Unterwasser-Ambiente. Zwei geloopte `Sound`-
		Instanzen unter `SoundService`, deren Lautstärke live an die bereits
		bestehende "Musik-Lautstärke"-Option aus `MainMenuController`
		gebunden ist (`Workspace:GetAttribute("MusicVolume")`, 0..1, Default
		0.6 - siehe dortiger Kopfkommentar/Regler).

		WICHTIG zur Lautstärke-Verkettung: `MainMenuController`s
		"Sound-Lautstärke"-Regler setzt `SoundService.Volume` (Roblox-
		Master-Multiplikator für ALLE Sound-Instanzen im Spiel, inkl. dieser
		beiden hier UND aller UIKit-Klick-Sounds). Die hier gesetzte
		`Sound.Volume` ist also die MUSIK-eigene Lautstärke, die zusätzlich
		mit dem Master-Regler multipliziert wird (Roblox-Standardverhalten,
		nicht manuell nachgebaut) - beide Regler wirken dadurch sinnvoll
		zusammen, ohne dass dieses Skript `SoundService.Volume` selbst
		anfasst.

		KEINE ERFUNDENEN ASSET-IDS: `UIKit.SoundConfig.BackgroundMusic` /
		`UnderwaterAmbience` haben absichtlich eine LEERE `Id` (siehe
		Kopfkommentar dort). Dieses Skript prüft das und spielt in diesem
		Fall bewusst NICHTS ab (kein Fehler, kein Platzhalter-Katalogsound
		untergeschoben) - vor Launch trägt die Spiel-Autorin dort eigene,
		lizenzierte `rbxassetid://`-Werte ein, ohne dass dieses Skript
		nochmal angefasst werden muss.

		Reduzierte-Effekte-Einstellung (`UIKit.Settings`) betrifft nur
		visuelle FX/Partikel/Screen-Shake, NICHT Musik/Ambiente - beide
		spielen unabhängig davon normal weiter.

	Rojo-Einhängepunkt:
		src/client/AudioController.client.lua ->
		StarterPlayer.StarterPlayerScripts.AudioController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local SoundConfig = UIKit.SoundConfig

local player = Players.LocalPlayer

-- // Musik-Lautstärke-Attribut (von MainMenuController gepflegt) -------------------

local function getMusicVolume(): number
	local value = Workspace:GetAttribute("MusicVolume")
	if type(value) ~= "number" then
		return 0.6
	end
	return math.clamp(value, 0, 1)
end

-- // Sound-Aufbau -------------------------------------------------------------------

local function createLoopedSound(name: string, definition: { Id: string, Volume: number }): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = definition.Id
	sound.Looped = true
	sound.Volume = 0 -- startet stumm, wird von refreshVolumes() gesetzt (sanftes Einblenden)
	sound.Parent = SoundService
	return sound
end

local backgroundMusic = createLoopedSound("AbyssaraBackgroundMusic", SoundConfig.BackgroundMusic)
local underwaterAmbience = createLoopedSound("AbyssaraUnderwaterAmbience", SoundConfig.UnderwaterAmbience)

local function hasPlayableId(sound: Sound): boolean
	return sound.SoundId ~= nil and sound.SoundId ~= ""
end

local function startIfPlayable(sound: Sound)
	if hasPlayableId(sound) and not sound.IsPlaying then
		local ok = pcall(function()
			sound:Play()
		end)
		if not ok then
			warn(("[AudioController] Could not play %s (invalid SoundId?)."):format(sound.Name))
		end
	end
end

-- // Lautstärke-Bindung ---------------------------------------------------------

local musicBaseVolume = SoundConfig.BackgroundMusic.Volume
local ambienceBaseVolume = SoundConfig.UnderwaterAmbience.Volume

local function refreshVolumes(animated: boolean?)
	local musicSlider = getMusicVolume()
	local targetMusicVolume = musicBaseVolume * musicSlider
	local targetAmbienceVolume = ambienceBaseVolume * musicSlider

	if animated == false then
		backgroundMusic.Volume = targetMusicVolume
		underwaterAmbience.Volume = targetAmbienceVolume
	else
		TweenService:Create(backgroundMusic, TweenInfo.new(0.5), { Volume = targetMusicVolume }):Play()
		TweenService:Create(underwaterAmbience, TweenInfo.new(0.5), { Volume = targetAmbienceVolume }):Play()
	end
end

refreshVolumes(false)
startIfPlayable(backgroundMusic)
startIfPlayable(underwaterAmbience)

local attributeConnection = Workspace:GetAttributeChangedSignal("MusicVolume"):Connect(function()
	refreshVolumes(true)
end)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	attributeConnection:Disconnect()
	backgroundMusic:Destroy()
	underwaterAmbience:Destroy()
end)
