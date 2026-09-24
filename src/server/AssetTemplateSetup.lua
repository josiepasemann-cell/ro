--[[
	Abyssara – Deep Tide Tycoon
	Modul: AssetTemplateSetup
	Zuständigkeit:
		Schließt eine Lücke zwischen den 3D-Buildscripts
		(assets/models/**/*.lua) und dem Bauplatzierungs-System: Die
		Buildscripts sind laut assets/models/README.md bewusst EINMALIGE
		Aufbau-Skripte, die ihre Modelle live unter
		Workspace.Assets.<Kategorie>.<Name> an einer fest im Skript
		codierten ORIGIN-Position erzeugen (z. B. BroodPool_Basic immer bei
		CFrame.new(20, 2, 20)). Sie existieren NICHT als fertige,
		wiederverwendbare Instanzen in ReplicatedStorage.

		Für Platzierung (PlacementService) UND Client-Vorschau
		(PlacementPreviewController) wird aber genau das gebraucht: eine
		stabile, beliebig oft klonbare Modell-VORLAGE pro Gebäude/Plot-Typ,
		die nicht an der (für mehrere Spieler ungeeigneten, sich
		überlappenden) Buildscript-ORIGIN-Position im offenen Workspace
		herumsteht.

	PRAGMATISCHE ENTSCHEIDUNG (siehe Auftrag zu diesem System):
		Dieses Modul räumt das automatisch auf, sobald der Server startet
		bzw. sobald es zum ersten Mal requiret wird:
			1) Sucht die vom 3D-Artist-Agent einmalig in Studio ausgeführten
			   Buildscript-Ergebnisse unter Workspace.Assets.Terrain /
			   Workspace.Assets.Buildings / Workspace.Assets.Enemies (siehe
			   README, Abschnitt "Wie man die Skripte in Roblox Studio
			   ausführt"). Enemies wurde für das Trench-Raid-System
			   (RaidService) ergänzt - identisches Prinzip wie Terrain/
			   Buildings, siehe RaidConfig-Kopfkommentar zur bewussten
			   MVP-Vereinfachung "ein Gegnermodell (ShadowKraken) für alle
			   Gegnertypen, unterschieden über RaidConfig-Daten".
			2) Klont jedes gefundene Modell nach
			   ReplicatedStorage.AssetTemplates.<Terrain|Buildings|Enemies>.<Name>
			   (idempotent - ein vorhandenes Template wird ersetzt, falls
			   der Artist ein Buildscript erneut/aktualisiert ausgeführt
			   hat).
			3) Entfernt das Workspace-Original wieder, da es nur als
			   Bau-Nebenprodukt an der ORIGIN-Position existiert und sonst
			   dauerhaft sichtbar/kollidierbar im offenen Meeresboden
			   herumstehen würde (überlappt z. B. mit jedem Spieler-Plot,
			   siehe PlotRegistry).

		Fehlt ein Buildscript-Ergebnis (Buildscript wurde in Studio noch
		nicht ausgeführt), wird das klar per warn() gemeldet statt den
		Server hart abstürzen zu lassen - PlotRegistry/PlacementService
		lehnen betroffene Anfragen dann sauber mit einem Fehlergrund
		("TemplateMissing"/"NoPlot") ab, statt mit nil-Referenzen zu
		crashen.

		ALTERNATIVE, die bewusst NICHT gewählt wurde: die Buildscripts
		selbst zu Server-Startskripten machen, die bei jedem Server-Start
		neu ausführen. Das würde funktionieren, aber pro Server-Start
		unnötig CSG-Operationen wiederholen (teuer) und würde die
		Buildscripts entgegen ihrer dokumentierten Zweckbestimmung
		("einmalig, von Hand in Studio") zu Laufzeit-Code machen. Der hier
		gewählte Weg (einmal bauen, danach nur noch klonen) ist sowohl
		performanter als auch näher am dokumentierten Workflow.

	Rojo-Einhängepunkt:
		src/server/AssetTemplateSetup.lua -> ServerScriptService.AssetTemplateSetup
		(reines Server-Modul; wird per require() von PlotRegistry und
		PlacementServer.server.lua angestoßen - läuft dank Luaus
		Modul-Caching garantiert nur einmal pro Server, unabhängig davon,
		wer zuerst requiret.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TERRAIN_TEMPLATE_NAMES = { "HabitatPlotBase" }
-- Content Update 1, Abschnitt 4/7b: CoralBarrier + ElectricEelTrap ergänzt
-- (siehe BuildingConfig.DEFINITIONS/RaidConfig.TOWER_STATS). ShadowKraken
-- bleibt bewusst NICHT in dieser Liste (es ist kein Gebäude) - siehe
-- ENEMY_TEMPLATE_NAMES unten.
local BUILDING_TEMPLATE_NAMES =
	{ "BroodPool_Basic", "GlowBuoyStation", "FilterPlant", "AnglerfishTower", "CoralBarrier", "ElectricEelTrap" }
-- Trench-Raid-System (RaidService): Content Update 1, Abschnitt 3 ersetzt
-- den früheren "ein Modell für alle Gegnertypen"-Platzhalter durch 4 eigene
-- Modelle (siehe RaidConfig.ENEMIES.*.TemplateName). ShadowKraken bleibt
-- zusätzlich in der Liste (nicht mehr von RaidConfig referenziert, aber
-- weiterhin der Fail-Soft-Fallback für GetEnemyTemplate unten, falls ein
-- neues Gegnermodell zur Laufzeit fehlt).
local ENEMY_TEMPLATE_NAMES = { "ShadowKraken", "SpineDrifter", "ThornSwarmer", "IronMawBrute", "TrenchWardenBoss" }

-- Fail-Soft-Fallback-Namen (siehe Auftrag: "warn + fall back to ShadowKraken
-- / AnglerfishTower template", falls ein spezifisches Template zur Laufzeit
-- fehlt, z. B. weil das entsprechende Buildscript noch nicht in Studio
-- ausgeführt wurde). Nur EINMAL pro fehlendem Namen gewarnt (siehe
-- warnedMissingTemplate unten), damit ein dauerhaft fehlendes Template
-- nicht bei jedem Raid-/Bau-Aufruf erneut spammt.
local ENEMY_TEMPLATE_FALLBACK_NAME = "ShadowKraken"
local BUILDING_TEMPLATE_FALLBACK_NAME = "AnglerfishTower"
local warnedMissingTemplate: { [string]: boolean } = {}

-- // Gebäude-Upgrade-System (siehe docs/building-upgrades.md) -----------------
-- Stufe-2/3-Modelle sind laut Auftrag OPTIONAL: der 3D-Agent liefert sie
-- ggf. erst später unter Workspace.Assets.Buildings.<BuildingId>_Stage2 /
-- _Stage3 (Namensschema bewusst über die BuildingId, NICHT über
-- BuildingConfig.TemplateName, da beide beim BroodPool auseinanderlaufen -
-- TemplateName ist "BroodPool_Basic", die BuildingId aber "BroodPool").
-- Fehlt ein Stufe-Modell, bleibt PlacementService beim Stufe-1-Modell und
-- ergänzt stattdessen einen einfachen Glow-Akzent (siehe dortige
-- applyStageAccent-Funktion) - deshalb wird hier bewusst NICHT gewarnt, wenn
-- ein Stufe-Template fehlt (anders als bei den verpflichtenden Stufe-1-
-- Templates oben), das ist der erwartete Normalfall, bis der 3D-Agent
-- liefert.
local BUILDING_IDS_WITH_STAGES = { "BroodPool", "GlowBuoyStation", "FilterPlant", "AnglerfishTower", "CoralBarrier", "ElectricEelTrap" }
local UPGRADE_STAGE_LEVELS = { 2, 3 }

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Folder
end

local templatesRoot = getOrCreateFolder(ReplicatedStorage, "AssetTemplates")
local terrainTemplatesFolder = getOrCreateFolder(templatesRoot, "Terrain")
local buildingTemplatesFolder = getOrCreateFolder(templatesRoot, "Buildings")
local enemyTemplatesFolder = getOrCreateFolder(templatesRoot, "Enemies")

local assetsFolder = Workspace:FindFirstChild("Assets")
local workspaceTerrainFolder: Instance? = assetsFolder and assetsFolder:FindFirstChild("Terrain")
local workspaceBuildingsFolder: Instance? = assetsFolder and assetsFolder:FindFirstChild("Buildings")
local workspaceEnemiesFolder: Instance? = assetsFolder and assetsFolder:FindFirstChild("Enemies")

--- Klont `name` aus `sourceFolder` (Workspace-Buildscript-Ergebnis) nach
--- `destFolder` (ReplicatedStorage-Template) und entfernt danach das
--- Workspace-Original. Ist `name` im Workspace nicht (mehr) vorhanden,
--- bleibt ein bereits vorhandenes Template unangetastet (z. B. weil dieses
--- Modul in derselben Studio-Session schon einmal gelaufen ist) - nur wenn
--- WEDER Workspace-Original NOCH Template existieren, wird gewarnt.
local function promoteToTemplate(sourceFolder: Instance?, name: string, destFolder: Folder)
	local source = sourceFolder and sourceFolder:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		if not destFolder:FindFirstChild(name) then
			warn(
				("[AssetTemplateSetup] '%s' fehlt unter Workspace.Assets - bitte das passende Buildscript unter assets/models/**/%s.lua einmal in Studio ausführen (siehe assets/models/README.md)."):format(
					name,
					name
				)
			)
		end
		return
	end

	local clone = source:Clone()
	clone.Name = name

	local existingTemplate = destFolder:FindFirstChild(name)
	if existingTemplate then
		existingTemplate:Destroy()
	end
	clone.Parent = destFolder

	source:Destroy()

	print(("[AssetTemplateSetup] Template '%s' bereit unter %s."):format(name, destFolder:GetFullName()))
end

--- Wie promoteToTemplate, aber OHNE Warnung, falls `name` weder im
--- Workspace NOCH bereits als Template existiert - für optionale Stufe-2/3-
--- Gebäude-Modelle (siehe BUILDING_IDS_WITH_STAGES oben), deren Fehlen der
--- erwartete Normalfall ist (Fail-Soft-Akzent-Fallback in PlacementService),
--- nicht ein zu meldender Konfigurationsfehler wie bei den Stufe-1-Basis-
--- Templates.
local function promoteOptionalToTemplate(sourceFolder: Instance?, name: string, destFolder: Folder)
	local source = sourceFolder and sourceFolder:FindFirstChild(name)
	if not source or not source:IsA("Model") then
		return
	end

	local clone = source:Clone()
	clone.Name = name

	local existingTemplate = destFolder:FindFirstChild(name)
	if existingTemplate then
		existingTemplate:Destroy()
	end
	clone.Parent = destFolder

	source:Destroy()

	print(("[AssetTemplateSetup] Stufe-Template '%s' bereit unter %s."):format(name, destFolder:GetFullName()))
end

for _, name in ipairs(TERRAIN_TEMPLATE_NAMES) do
	promoteToTemplate(workspaceTerrainFolder, name, terrainTemplatesFolder)
end

for _, name in ipairs(BUILDING_TEMPLATE_NAMES) do
	promoteToTemplate(workspaceBuildingsFolder, name, buildingTemplatesFolder)
end

for _, name in ipairs(ENEMY_TEMPLATE_NAMES) do
	promoteToTemplate(workspaceEnemiesFolder, name, enemyTemplatesFolder)
end

for _, buildingId in ipairs(BUILDING_IDS_WITH_STAGES) do
	for _, stage in ipairs(UPGRADE_STAGE_LEVELS) do
		promoteOptionalToTemplate(workspaceBuildingsFolder, buildingId .. "_Stage" .. tostring(stage), buildingTemplatesFolder)
	end
end

local AssetTemplateSetup = {}

--- Liefert die Plot-Basis-Vorlage, oder nil, falls das HabitatPlotBase-
--- Buildscript nie in Studio ausgeführt wurde (siehe warn() oben).
function AssetTemplateSetup.GetPlotTemplate(): Model?
	local model = terrainTemplatesFolder:FindFirstChild("HabitatPlotBase")
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

--- Warnt höchstens EINMAL pro `templateName`, dass auf `fallbackName`
--- ausgewichen wird (siehe warnedMissingTemplate oben).
local function warnFallbackOnce(kind: string, templateName: string, fallbackName: string)
	local key = kind .. ":" .. templateName
	if warnedMissingTemplate[key] then
		return
	end
	warnedMissingTemplate[key] = true
	warn(
		("[AssetTemplateSetup] %s-Vorlage '%s' fehlt - weiche auf Fallback '%s' aus (siehe assets/models/README.md, betroffenes Buildscript einmal in Studio ausführen, um den echten Look zu bekommen)."):format(
			kind,
			templateName,
			fallbackName
		)
	)
end

--- Liefert die Gebäude-Vorlage für `templateName`
--- (siehe BuildingConfig.TemplateName je Gebäude). Fail-soft: fehlt das
--- spezifische Template (z. B. CoralBarrier/ElectricEelTrap-Buildscript noch
--- nicht in Studio ausgeführt), wird EINMALIG gewarnt und auf
--- BUILDING_TEMPLATE_FALLBACK_NAME ("AnglerfishTower") ausgewichen, statt
--- die Platzierung mit "TemplateMissing" hart abzulehnen. Liefert nil nur,
--- wenn selbst der Fallback fehlt (z. B. ganz frischer Server ohne jedes
--- Buildscript-Ergebnis).
function AssetTemplateSetup.GetBuildingTemplate(templateName: string): Model?
	local model = buildingTemplatesFolder:FindFirstChild(templateName)
	if model and model:IsA("Model") then
		return model
	end

	if templateName ~= BUILDING_TEMPLATE_FALLBACK_NAME then
		local fallback = buildingTemplatesFolder:FindFirstChild(BUILDING_TEMPLATE_FALLBACK_NAME)
		if fallback and fallback:IsA("Model") then
			warnFallbackOnce("Gebäude", templateName, BUILDING_TEMPLATE_FALLBACK_NAME)
			return fallback
		end
	end

	return nil
end

--- Liefert die Stufe-2/3-Gebäude-Vorlage für `buildingId` bei `stage`, oder
--- nil, wenn `stage` <= 1 ist ODER (der erwartete Normalfall, bis der
--- 3D-Agent liefert - siehe BUILDING_IDS_WITH_STAGES-Kommentar oben) das
--- Modell schlicht noch nicht existiert. Liefert BEWUSST KEINEN
--- AnglerfishTower-Fallback wie GetBuildingTemplate unten - ein "falsches"
--- Turmmodell für z. B. ein Stufe-2-Brutbecken wäre irreführender als gar
--- kein Modellwechsel. Aufrufer (PlacementService) behandelt `nil` als
--- "Stufe-1-Modell beibehalten, stattdessen Glow-Akzent ergänzen".
function AssetTemplateSetup.GetBuildingStageTemplate(buildingId: string, stage: number): Model?
	if stage <= 1 then
		return nil
	end
	local model = buildingTemplatesFolder:FindFirstChild(buildingId .. "_Stage" .. tostring(stage))
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

--- Liefert die Raid-Gegner-Vorlage für `templateName` (siehe
--- RaidConfig.EnemyDefinition.TemplateName, z. B. "SpineDrifter"). Fail-
--- soft: fehlt das spezifische Gegnermodell, wird EINMALIG gewarnt und auf
--- ENEMY_TEMPLATE_FALLBACK_NAME ("ShadowKraken") ausgewichen, statt den
--- betroffenen Spawn zu überspringen (siehe RaidService.spawnWave). Liefert
--- nil nur, wenn selbst der Fallback fehlt.
function AssetTemplateSetup.GetEnemyTemplate(templateName: string): Model?
	local model = enemyTemplatesFolder:FindFirstChild(templateName)
	if model and model:IsA("Model") then
		return model
	end

	if templateName ~= ENEMY_TEMPLATE_FALLBACK_NAME then
		local fallback = enemyTemplatesFolder:FindFirstChild(ENEMY_TEMPLATE_FALLBACK_NAME)
		if fallback and fallback:IsA("Model") then
			warnFallbackOnce("Gegner", templateName, ENEMY_TEMPLATE_FALLBACK_NAME)
			return fallback
		end
	end

	return nil
end

return AssetTemplateSetup
