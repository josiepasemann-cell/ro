--[[
	Abyssara – Deep Tide Tycoon
	Modul: RaidService
	Zuständigkeit:
		Kernlogik des Trench-Raid-Systems (GDD Abschnitt 3 "Session-zu-
		Session" + Abschnitt 9, Punkt 5 + Abschnitt 10 MVP-Scope): Raid-Timer
		je Spieler (absoluter os.time()-Zeitstempel, persistiert über
		PlayerDataService.Get/SetNextRaidAt - identisches Prinzip wie
		BreedingService/IdleIncomeService), Online-Raid-Ablauf (Gegner spawnen
		am Plot-Rand, bewegen sich serverseitig linear zum Plot-Zentrum,
		platzierte AnglerfishTower zielen/schießen serverseitig), Sieg-/
		Niederlage-Auswertung, Entführungs-/Lösegeld-Mechanik sowie eine
		deterministische Offline-Raid-Auswertung beim Login.

		Reine Logik + eigener Tick-Loop/PlayerAdded-Hook, keine
		Remote-Verdrahtung außer dem direkten Feuern der Ergebnis-/HUD-Events
		aus RaidRemotes - die Client-Request-Handler (RequestRescueCreature
		etc.) übernimmt RaidServer.server.lua (identisches Muster wie
		BreedingService/BreedingServer.server.lua).

	MVP-Scope-Auslassung (siehe Auftrag, explizit hier dokumentiert):
		Der im GDD (Abschnitt 3 + 9 Punkt 5) erwähnte "Wächter-Einsatz"
		(Spieler setzt während des Raids aktiv eigene Kreaturen als
		Verteidiger ein) ist bewusst NICHT Teil dieses MVP - GDD Abschnitt 10
		nennt für den MVP-Scope explizit nur "Solo, 3 Gegnertypen, 1 Boss"
		ohne Wächter-Mechanik. Verteidigung läuft im MVP ausschließlich über
		platzierte AnglerfishTower. Ein künftiger Ausbau würde einen eigenen
		Remote-Kanal ("RequestDeployGuardian") + eine Kreaturen-Kampfwert-
		Tabelle brauchen, ohne den bestehenden Turm-/Wellen-Ablauf hier zu
		verändern.

	Performance (Auftrag: "ein Heartbeat-Loop für alle Gegner statt einer
	Schleife pro Gegner"):
		EIN gemeinsamer Server-Loop (runRaidTickLoop, task.wait-basiert,
		RaidConfig.RAID_TICK_SECONDS) iteriert über ALLE aktiven Raids
		(activeRaids) und darin über alle lebenden Gegner/Türme - es gibt
		KEINEN separaten Loop/keine eigene Coroutine pro Gegner oder Turm.
		Bewegung ist bewusst simple lineare Interpolation Richtung
		Plot-Zentrum (kein Pathfinding, siehe Auftrag - MVP-Plots sind flache,
		offene Plattformen ohne Hindernisse).

	Sicherheitsprinzip (kein Client-Trust):
		Der Client liefert für den Raid-ABLAUF selbst NICHTS ein (Spawns,
		Bewegung, Turm-Schaden, Sieg/Niederlage laufen 1:1 serverseitig,
		Modelle replizieren nur ihre bereits server-berechnete Position).
		Einzige Client-Eingabe ist `RequestRescueCreature(instanceId)` - wird
		hier komplett neu gegen die EIGENE, bereits persistente
		AbductedCreatures-Liste des anfragenden Spielers validiert (Lookup
		ausschließlich im eigenen RaidState, siehe PlayerDataService.
		RescueAbductedCreature), inkl. erneuter Kontostandsprüfung.

	Offline-Auswertung (deterministische Formel, GDD: "auch offline zählend
	mit Cap"):
		KEIN Simulieren des eigentlichen Wellenablaufs offline (zu teuer/
		komplex für MVP) - stattdessen ein einfacher, rein deterministischer
		Vergleich pro verpasstem Raid (siehe evaluateOfflineRaidWin):

			TurmDPS = Summe(Damage * FireRate) aller platzierten
			          AnglerfishTower im aktuellen HabitatLayout
			TurmSchadenBudget = TurmDPS * RaidConfig.OFFLINE_ASSUMED_RAID_SECONDS
			GegnerGesamt-HP = RaidConfig.GetTotalEnemyHP()
			                  * RaidConfig.OFFLINE_DIFFICULTY_MULTIPLIER

			Sieg, wenn TurmSchadenBudget >= GegnerGesamt-HP, sonst Niederlage.

		Diese Formel ist bewusst simpel und ausschließlich von der (bereits
		serverseitig persistenten, nicht vom Client beeinflussbaren)
		Turmanzahl/-stärke abhängig - kein Zufall. Sie wird höchstens
		RaidConfig.MAX_OFFLINE_RAIDS_EVALUATED mal angewendet (zusätzlich zur
		OFFLINE_CAP_SECONDS-Zeitdeckelung), um zu verhindern, dass eine sehr
		lange Abwesenheit auf einen Schlag übermäßig viele Belohnungen ODER
		Entführungen anhäuft (Soft-Loss-Prinzip). Jeder ausgewertete verpasste
		Raid kann höchstens EINE Kreatur entführen (limitiert zusätzlich durch
		die tatsächliche Inventargröße).

	Rojo-Einhängepunkt:
		src/server/RaidService.lua -> ServerScriptService.RaidService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local AssetTemplateSetup = require(script.Parent:WaitForChild("AssetTemplateSetup"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))

local RaidService = {}

local rng = Random.new()

-- // Laufzeit-Typen (nur In-Memory, NICHT persistent) --------------------------

type EnemyRuntime = {
	EnemyId: RaidConfig.EnemyId,
	Model: Model,
	CurrentHP: number,
	MaxHP: number,
	MoveSpeed: number,
}

type TowerRuntime = {
	PlacementId: string,
	Model: Model,
	Stats: RaidConfig.TowerCombatStats,
	LastFireTime: number,
}

type RaidRuntime = {
	Player: Player,
	CenterPosition: Vector3,
	EnemiesFolder: Folder,
	Towers: { TowerRuntime },
	Enemies: { EnemyRuntime },
	WaveIndex: number,
	EnemiesReachedCenter: number,
	Finished: boolean,
}

local activeRaids: { [number]: RaidRuntime } = {} -- keyed by UserId

-- // Hilfsfunktionen ------------------------------------------------------------

--- GDD Abschnitt 5: "2x Tide Coins - Dauerhaft doppelte Währung" gilt laut
--- Gamepass-Beschreibung fürs Idle-Einkommen UND fürs Raid-Sieg-Coin-
--- Belohnung (siehe MonetizationService-Kopfkommentar für die Herleitung,
--- warum beide Systeme diesen Effekt tragen). BEWUSST ein LAZY require()
--- (Funktionskörper statt Modul-Kopf) - RaidService wird selbst NICHT von
--- MonetizationService benötigt, aber die allgemeine Konvention in diesem
--- Auftrag ist, jeden MonetizationService-Zugriff aus Gameplay-Services
--- konsequent lazy zu halten (siehe identischer Kommentar in
--- BreedingService.RequestStartBreeding) - vermeidet zukünftige
--- Zyklusprobleme, falls RaidService selbst einmal zu einem
--- MonetizationService-Abhängigkeitsziel wird.
local function applyDoubleCoinsGamepass(player: Player, baseAmount: number): number
	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	if MonetizationService.PlayerOwnsGamepass(player, "DoubleCoins") then
		return math.floor(baseAmount * MonetizationService.GetDoubleCoinsMultiplier() + 0.5)
	end
	return baseAmount
end

--- Färbt/skaliert das (einzige, wiederverwendete) ShadowKraken-Modell gemäß
--- der Gegnertyp-Definition ein - siehe RaidConfig-Kopfkommentar zur
--- bewussten MVP-Vereinfachung "ein Gegnermodell für alle Typen".
local function applyEnemyVisual(model: Model, definition: RaidConfig.EnemyDefinition)
	local ok = pcall(function()
		model:ScaleTo(definition.ScaleMultiplier)
	end)
	if not ok then
		warn("[RaidService] Model:ScaleTo() fehlgeschlagen (evtl. ältere Engine-Version) - Gegner bleibt unskaliert.")
	end

	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.Color = definition.BodyColor
	end
	local mantle = model:FindFirstChild("Mantle")
	if mantle and mantle:IsA("BasePart") then
		mantle.Color = definition.BodyColor
	end
	for i = 1, 2 do
		local eye = model:FindFirstChild("Eye" .. i)
		if eye and eye:IsA("BasePart") then
			eye.Color = definition.EyeColor
		end
	end

	model:SetAttribute("EnemyId", definition.Id)
	model:SetAttribute("IsBoss", definition.IsBoss)
end

--- Liefert einen zufälligen Punkt auf dem Spawn-Ring um `center` (siehe
--- RaidConfig.SPAWN_RING_RADIUS), auf derselben Höhe wie `center`.
local function randomSpawnPosition(center: Vector3): Vector3
	local angle = rng:NextNumber() * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * RaidConfig.SPAWN_RING_RADIUS
	return center + offset
end

--- Sammelt alle eigenen, aktuell im Workspace stehenden AnglerfishTower-
--- Modelle eines Spielers als TowerRuntime (Kampfwerte aus RaidConfig,
--- Feuerbereitschaft sofort - kein "Aufwärmen" nötig).
local function collectTowerRuntimes(player: Player): { TowerRuntime }
	local towers: { TowerRuntime } = {}
	local buildingsFolder = PlotRegistry.GetBuildingsFolder(player)
	if not buildingsFolder then
		return towers
	end

	for _, model in ipairs(buildingsFolder:GetChildren()) do
		if model:IsA("Model") then
			local buildingId = model:GetAttribute("BuildingId")
			if type(buildingId) == "string" then
				local stats = RaidConfig.GetTowerStats(buildingId)
				if stats then
					table.insert(towers, {
						PlacementId = model:GetAttribute("PlacementId"),
						Model = model,
						Stats = stats,
						LastFireTime = 0,
					})
				end
			end
		end
	end

	return towers
end

--- Erzeugt die lebenden Gegner-Instanzen einer Welle im Workspace (siehe
--- RaidRuntime.EnemiesFolder) und hängt sie an `raid.Enemies` an.
local function spawnWave(raid: RaidRuntime, waveIndex: number): number
	local wave = RaidConfig.WAVES[waveIndex]
	if not wave then
		return 0
	end

	local spawnedCount = 0
	for _, spawnSpec in ipairs(wave.Enemies) do
		local definition = RaidConfig.GetEnemy(spawnSpec.EnemyId)
		if definition then
			local template = AssetTemplateSetup.GetEnemyTemplate(definition.TemplateName)
			if template then
				for _ = 1, spawnSpec.Count do
					local model = template:Clone()
					model.Name = definition.Id .. "_" .. tostring(spawnedCount + 1)
					applyEnemyVisual(model, definition)
					model.Parent = raid.EnemiesFolder

					local spawnPos = randomSpawnPosition(raid.CenterPosition)
					model:PivotTo(CFrame.new(spawnPos, raid.CenterPosition))

					table.insert(raid.Enemies, {
						EnemyId = definition.Id,
						Model = model,
						CurrentHP = definition.MaxHP,
						MaxHP = definition.MaxHP,
						MoveSpeed = definition.MoveSpeed,
					})
					spawnedCount += 1
				end
			else
				warn(
					("[RaidService] Gegner-Vorlage '%s' fehlt - Spawn von '%s' übersprungen."):format(
						definition.TemplateName,
						definition.Id
					)
				)
			end
		end
	end

	return spawnedCount
end

local function destroyRaidWorkspaceState(raid: RaidRuntime)
	if raid.EnemiesFolder and raid.EnemiesFolder.Parent then
		raid.EnemiesFolder:Destroy()
	end
	raid.Enemies = {}
end

-- // Sieg/Niederlage-Auswertung (LIVE-Raid) ------------------------------------

local function finishRaid(raid: RaidRuntime, won: boolean)
	if raid.Finished then
		return
	end
	raid.Finished = true

	local player = raid.Player
	destroyRaidWorkspaceState(raid)
	activeRaids[player.UserId] = nil

	local now = os.time()
	local nextRaidAt = now + RaidConfig.RAID_INTERVAL_SECONDS
	PlayerDataService.SetNextRaidAt(player, nextRaidAt)

	local resultPayload: { [string]: any } = {
		Success = won,
		WavesCleared = if won then #RaidConfig.WAVES else math.max(0, raid.WaveIndex - 1),
		NextRaidAt = nextRaidAt,
	}

	if won then
		local tideCoinReward = applyDoubleCoinsGamepass(player, RaidConfig.VICTORY_REWARD_TIDE_COINS)
		local _, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", tideCoinReward)
		resultPayload.RewardTideCoins = tideCoinReward
		resultPayload.NewTideCoinBalance = newBalance

		-- Progression-Einhängepunkt: NACH erfolgreichem Sieg (nicht beim
		-- Raid-Start), siehe ProgressionService-Kopfkommentar.
		ProgressionService.AwardXP(player, "RaidWon")

		if rng:NextNumber() <= RaidConfig.VICTORY_ABYSSAL_SHARD_CHANCE then
			local _, shardBalance =
				PlayerDataService.AddCurrency(player, "AbyssalShards", RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT)
			resultPayload.RewardAbyssalShards = RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT
			resultPayload.NewAbyssalShardBalance = shardBalance
		end
	else
		local abducted = PlayerDataService.AbductRandomCreature(player)
		if abducted then
			resultPayload.AbductedCreature = {
				InstanceId = abducted.InstanceId,
				CreatureId = abducted.CreatureId,
				Rarity = abducted.Rarity,
				RansomCost = abducted.RansomCost,
			}
		end
	end

	RaidRemotes.RaidResult:FireClient(player, resultPayload)
end

-- // Live-Raid-Start -------------------------------------------------------------

--- Startet einen Raid auf dem Plot von `player`, sofern dieser gerade nicht
--- bereits in einem läuft und ein Plot zugewiesen ist. Rein server-seitig
--- ausgelöst (siehe runSchedulerLoop) - der Client fordert dies NICHT an.
local function startRaid(player: Player)
	if activeRaids[player.UserId] then
		return
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		-- Kein Plot (noch) vorhanden (z. B. Buildscript-Vorlage fehlt, siehe
		-- AssetTemplateSetup-Warnung) - Timer trotzdem fortschreiben, damit
		-- nicht jeden Scheduler-Tick erneut versucht wird.
		PlayerDataService.SetNextRaidAt(player, os.time() + RaidConfig.RAID_INTERVAL_SECONDS)
		return
	end

	local enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "RaidEnemies"
	enemiesFolder.Parent = plot

	local raid: RaidRuntime = {
		Player = player,
		CenterPosition = plot.PrimaryPart.Position,
		EnemiesFolder = enemiesFolder,
		Towers = collectTowerRuntimes(player),
		Enemies = {},
		WaveIndex = 1,
		EnemiesReachedCenter = 0,
		Finished = false,
	}

	activeRaids[player.UserId] = raid
	local spawnedCount = spawnWave(raid, 1)

	local firstWave = RaidConfig.WAVES[1]
	RaidRemotes.RaidStarted:FireClient(player, {
		TotalWaves = #RaidConfig.WAVES,
		WaveIndex = 1,
		WaveEnemyCount = spawnedCount,
		IsBossWave = firstWave and firstWave.IsBossWave or false,
	})
end

-- // Gemeinsamer Kampf-Tick-Loop (EIN Loop für ALLE Raids/Gegner/Türme) ---------

local function tickEnemyMovement(raid: RaidRuntime, deltaSeconds: number)
	local i = 1
	while i <= #raid.Enemies do
		local enemy = raid.Enemies[i]
		if not enemy.Model.Parent then
			-- Modell wurde extern zerstört (z. B. Server-Shutdown-Race) -
			-- defensiv aus der Liste entfernen statt darauf weiterzurechnen.
			table.remove(raid.Enemies, i)
			continue
		end

		local currentPosition = enemy.Model:GetPivot().Position
		local toCenter = raid.CenterPosition - currentPosition
		local distance = toCenter.Magnitude

		if distance <= RaidConfig.CENTER_REACH_RADIUS then
			enemy.Model:Destroy()
			table.remove(raid.Enemies, i)
			raid.EnemiesReachedCenter += 1
			continue
		end

		local step = math.min(distance, enemy.MoveSpeed * deltaSeconds)
		local direction = toCenter.Unit
		local newPosition = currentPosition + direction * step
		enemy.Model:PivotTo(CFrame.new(newPosition, raid.CenterPosition))

		i += 1
	end
end

--- WICHTIG: `now` muss `os.clock()` sein (hochauflösend, Sekunden als Float),
--- NICHT `os.time()` (nur ganzzahlige Sekunden-Auflösung) - bei FireRate-
--- Werten > 1 Schuss/Sekunde (siehe RaidConfig.TOWER_STATS, aktuell 1.5)
--- würde `os.time()` jeden Turm faktisch auf maximal 1 Schuss/Sekunde
--- deckeln, da sich der Zeitstempel innerhalb einer Sekunde gar nicht
--- ändert. `os.clock()` wird hier rein für die Intra-Session-Taktung
--- verwendet (nicht persistiert), daher unproblematisch.
local function tickTowers(raid: RaidRuntime, now: number)
	for _, tower in ipairs(raid.Towers) do
		if tower.Model.Parent then
			local fireInterval = 1 / tower.Stats.FireRate
			if now - tower.LastFireTime >= fireInterval then
				local lureOrb = tower.Model:FindFirstChild("LureOrb")
				local towerPosition = if lureOrb and lureOrb:IsA("BasePart")
					then lureOrb.Position
					else tower.Model:GetPivot().Position

				local targetIndex: number? = nil
				local targetDistance = math.huge
				for index, enemy in ipairs(raid.Enemies) do
					if enemy.Model.Parent then
						local dist = (enemy.Model:GetPivot().Position - towerPosition).Magnitude
						if dist <= tower.Stats.Range and dist < targetDistance then
							targetDistance = dist
							targetIndex = index
						end
					end
				end

				if targetIndex then
					tower.LastFireTime = now
					local target = raid.Enemies[targetIndex]
					target.CurrentHP -= tower.Stats.Damage

					RaidRemotes.EnemyHit:FireClient(raid.Player, {
						TowerPosition = towerPosition,
						EnemyPosition = target.Model:GetPivot().Position,
					})

					if target.CurrentHP <= 0 then
						target.Model:Destroy()
						table.remove(raid.Enemies, targetIndex)
					end
				end
			end
		end
	end
end

local function tickWaveProgress(raid: RaidRuntime)
	if raid.Finished then
		return
	end

	if raid.EnemiesReachedCenter >= RaidConfig.DEFEAT_ENEMY_REACH_COUNT then
		finishRaid(raid, false)
		return
	end

	if #raid.Enemies == 0 then
		if raid.WaveIndex >= #RaidConfig.WAVES then
			finishRaid(raid, true)
			return
		end

		raid.WaveIndex += 1
		local spawnedCount = spawnWave(raid, raid.WaveIndex)
		local wave = RaidConfig.WAVES[raid.WaveIndex]

		RaidRemotes.WaveAdvanced:FireClient(raid.Player, {
			WaveIndex = raid.WaveIndex,
			TotalWaves = #RaidConfig.WAVES,
			WaveEnemyCount = spawnedCount,
			IsBossWave = wave and wave.IsBossWave or false,
		})
	end
end

local function runRaidTickLoop()
	while true do
		local deltaSeconds = RaidConfig.RAID_TICK_SECONDS
		task.wait(deltaSeconds)

		local now = os.clock() -- hochauflösend für Feuerraten-Cooldowns, siehe tickTowers-Kommentar
		for _, raid in pairs(activeRaids) do
			if not raid.Finished then
				tickEnemyMovement(raid, deltaSeconds)
				tickTowers(raid, now)
				tickWaveProgress(raid)
			end
		end
	end
end

-- // Scheduler: löst fällige Raids für Online-Spieler aus ------------------------

local SCHEDULER_INTERVAL_SECONDS = 15 -- grob genug für Performance, fein genug gegen "verpasste" Fälligkeit

local function runSchedulerLoop()
	while true do
		task.wait(SCHEDULER_INTERVAL_SECONDS)

		local now = os.time()
		for _, player in ipairs(Players:GetPlayers()) do
			if PlayerDataService.IsDataLoaded(player) and not activeRaids[player.UserId] then
				if now >= PlayerDataService.GetNextRaidAt(player) then
					task.spawn(startRaid, player)
				end
			end
		end
	end
end

-- // Offline-Auswertung (deterministisch, siehe Kopfkommentar) -------------------

--- Summiert die Turm-DPS (Damage * FireRate) aller aktuell im HabitatLayout
--- gespeicherten AnglerfishTower - bewusst über das PERSISTENTE Layout (NICHT
--- über Workspace-Modelle), da diese Auswertung direkt beim Login läuft,
--- bevor PlacementService das Layout überhaupt wiederhergestellt hat.
local function computeTowerDpsFromLayout(player: Player): number
	local totalDps = 0
	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		local stats = RaidConfig.GetTowerStats(placement.BuildingId)
		if stats then
			totalDps += stats.Damage * stats.FireRate
		end
	end
	return totalDps
end

--- Reine, deterministische Sieg-Entscheidung für EINEN verpassten Raid (siehe
--- Formel im Kopfkommentar) - kein Zufall, ausschließlich abhängig von der
--- übergebenen Turm-DPS.
local function evaluateOfflineRaidWin(towerDps: number): boolean
	local damageBudget = towerDps * RaidConfig.OFFLINE_ASSUMED_RAID_SECONDS
	local requiredDamage = RaidConfig.GetTotalEnemyHP() * RaidConfig.OFFLINE_DIFFICULTY_MULTIPLIER
	return damageBudget >= requiredDamage
end

--- Wertet beim Login alle seit dem letzten Besuch fällig gewordenen, aber
--- verpassten Raids deterministisch aus (siehe Kopfkommentar: KEINE
--- Wellensimulation, gedeckelt über RaidConfig.OFFLINE_CAP_SECONDS UND
--- RaidConfig.MAX_OFFLINE_RAIDS_EVALUATED). Schreibt NextRaidAt immer sauber
--- auf `now + Intervall` fort, unabhängig vom Ergebnis.
local function evaluateOfflineRaids(player: Player)
	local now = os.time()
	local nextRaidAt = PlayerDataService.GetNextRaidAt(player)

	if now < nextRaidAt then
		-- Kein Raid verpasst - nichts zu tun.
		return
	end

	local elapsedSinceFirstMiss = math.min(now - nextRaidAt, RaidConfig.OFFLINE_CAP_SECONDS)
	local missedRaids = 1 + math.floor(elapsedSinceFirstMiss / RaidConfig.RAID_INTERVAL_SECONDS)
	missedRaids = math.min(missedRaids, RaidConfig.MAX_OFFLINE_RAIDS_EVALUATED)

	local towerDps = computeTowerDpsFromLayout(player)
	local won = evaluateOfflineRaidWin(towerDps)

	local totalTideCoins = 0
	local totalShards = 0
	local abductedCreatures = {}

	for _ = 1, missedRaids do
		if won then
			totalTideCoins += applyDoubleCoinsGamepass(player, RaidConfig.VICTORY_REWARD_TIDE_COINS)
			if rng:NextNumber() <= RaidConfig.VICTORY_ABYSSAL_SHARD_CHANCE then
				totalShards += RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT
			end

			-- Progression-Einhängepunkt: NACH erfolgreichem (verpasstem, aber
			-- gewonnenem) Raid, ein AwardXP je gewertetem Sieg - identische
			-- "pro Raid"-Granularität wie die Tide-Coin-/Shard-Gutschrift
			-- oben, siehe ProgressionService-Kopfkommentar.
			ProgressionService.AwardXP(player, "RaidWon")
		else
			local abducted = PlayerDataService.AbductRandomCreature(player)
			if abducted then
				table.insert(abductedCreatures, abducted)
			else
				-- Inventar bereits leer - weitere Entführungsversuche dieser
				-- Offline-Auswertung würden ohnehin nichts mehr finden.
				break
			end
		end
	end

	if totalTideCoins > 0 then
		PlayerDataService.AddCurrency(player, "TideCoins", totalTideCoins)
	end
	if totalShards > 0 then
		PlayerDataService.AddCurrency(player, "AbyssalShards", totalShards)
	end

	PlayerDataService.SetNextRaidAt(player, now + RaidConfig.RAID_INTERVAL_SECONDS)

	RaidRemotes.RaidResult:FireClient(player, {
		Success = won,
		Offline = true,
		RaidsEvaluated = missedRaids,
		RewardTideCoins = if totalTideCoins > 0 then totalTideCoins else nil,
		RewardAbyssalShards = if totalShards > 0 then totalShards else nil,
		AbductedCreatures = if #abductedCreatures > 0
			then (function()
				local list = {}
				for _, abducted in ipairs(abductedCreatures) do
					table.insert(list, {
						InstanceId = abducted.InstanceId,
						CreatureId = abducted.CreatureId,
						Rarity = abducted.Rarity,
						RansomCost = abducted.RansomCost,
					})
				end
				return list
			end)()
			else nil,
		NextRaidAt = now + RaidConfig.RAID_INTERVAL_SECONDS,
	})
end

-- // Öffentliche API --------------------------------------------------------------

--- Liefert den aktuellen Raid-Status eines Spielers für den initialen
--- HUD-Sync (siehe RaidRemotes.GetRaidStatus).
function RaidService.GetStatus(player: Player): { [string]: any }
	local raid = activeRaids[player.UserId]

	local abductedList = {}
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		table.insert(abductedList, {
			InstanceId = abducted.InstanceId,
			CreatureId = abducted.CreatureId,
			Rarity = abducted.Rarity,
			RansomCost = abducted.RansomCost,
			AbductedAt = abducted.AbductedAt,
		})
	end

	return {
		NextRaidAt = PlayerDataService.GetNextRaidAt(player),
		InRaid = raid ~= nil,
		WaveIndex = raid and raid.WaveIndex or nil,
		TotalWaves = #RaidConfig.WAVES,
		AbductedCreatures = abductedList,
	}
end

--- Validiert und führt eine Rettungs-/Lösegeld-Anfrage vollständig
--- serverseitig aus. `instanceId` ist ein unvertrauter, angeblicher
--- Client-Wert - wird komplett neu gegen die eigene AbductedCreatures-Liste
--- geprüft, bevor irgendetwas verändert wird.
function RaidService.RequestRescue(player: Player, instanceId: any): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	if type(instanceId) ~= "string" then
		return { Success = false, Reason = "InvalidInstance" }
	end

	local target = nil
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		if abducted.InstanceId == instanceId then
			target = abducted
			break
		end
	end

	if not target then
		return { Success = false, Reason = "NotAbducted" }
	end

	local balance = PlayerDataService.GetCurrency(player, "TideCoins")
	if balance < target.RansomCost then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	local chargeOk, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", -target.RansomCost)
	if not chargeOk then
		return { Success = false, Reason = "ChargeFailed" }
	end

	local rescued = PlayerDataService.RescueAbductedCreature(player, instanceId)
	if not rescued then
		-- Sollte praktisch nie eintreten (Ziel wurde oben gerade erst
		-- gefunden) - defensiv Lösegeld zurückerstatten statt Geld zu
		-- verschwenden.
		PlayerDataService.AddCurrency(player, "TideCoins", target.RansomCost)
		return { Success = false, Reason = "PersistenceFailed" }
	end

	return {
		Success = true,
		InstanceId = instanceId,
		RansomCost = target.RansomCost,
		NewBalance = newBalance,
	}
end

-- // EINHÄNGEPUNKT: Robux-"Rettungs-Token" (Entwicklerprodukt) ------------------
-- GDD Abschnitt 5: "Rettungs-Token (entführte Kreatur sofort zurückholen),
-- 49 Robux - Umgeht Rettungsmission". Aufgerufen ausschließlich von
-- MonetizationService.ProcessReceipt NACH erfolgreich verifiziertem Kauf
-- (Robux bereits abgebucht) - identischer Rettungs-Flow wie RequestRescue,
-- ABER ohne Lösegeld-Abbuchung (das hat der Robux-Kauf bereits ersetzt).
-- "NotAbducted" ist für MonetizationService NICHT retry-würdig (siehe
-- ShopConfig.DEV_PRODUCTS.RescueToken.FallbackCompensationTideCoins).
function RaidService.RequestRescueWithToken(player: Player, instanceId: any): (boolean, string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded"
	end
	if type(instanceId) ~= "string" then
		return false, "InvalidInstance"
	end

	local exists = false
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		if abducted.InstanceId == instanceId then
			exists = true
			break
		end
	end
	if not exists then
		return false, "NotAbducted"
	end

	local rescued = PlayerDataService.RescueAbductedCreature(player, instanceId)
	if not rescued then
		return false, "PersistenceFailed"
	end
	return true, nil
end

-- // EINHÄNGEPUNKT: Robux-"Raid-Skip" (Entwicklerprodukt) -----------------------
-- GDD Abschnitt 5: "Raid-Skip (aktueller Raid wird automatisch 'gewonnen'
-- gewertet, 1x/Tag), 59 Robux - Zeitersparnis". Die "1x/Tag"-Begrenzung gilt
-- laut GDD-Wortlaut für das PRODUKT selbst (nicht nur für einen separaten
-- Gratis-Weg) - siehe PlayerDataService.Get/SetLastRaidSkipDate. Aufgerufen
-- ausschließlich von MonetizationService.ProcessReceipt NACH erfolgreich
-- verifiziertem Kauf. "NoActiveRaid"/"AlreadyUsedToday" sind für
-- MonetizationService NICHT retry-würdig (Fallback-Kompensation greift).
function RaidService.RequestRaidSkip(player: Player): (boolean, string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded"
	end

	local today = PlayerDataService.GetUtcDateString()
	if PlayerDataService.GetLastRaidSkipDate(player) == today then
		return false, "AlreadyUsedToday"
	end

	local raid = activeRaids[player.UserId]
	if not raid or raid.Finished then
		return false, "NoActiveRaid"
	end

	PlayerDataService.SetLastRaidSkipDate(player, today)
	finishRaid(raid, true)
	return true, nil
end

--- Räumt den rein transienten Laufzeit-Zustand eines Spielers auf
--- (PlayerRemoving). Ein aktiver Raid wird dabei bewusst NEUTRAL abgebrochen
--- (kein Sieg/keine Niederlage gewertet, keine Belohnung/Entführung) - ein
--- Verbindungsabbruch mitten im Raid soll den Spieler nicht bestrafen. Der
--- Raid-Timer bleibt unverändert stehen (nicht sofort neu fällig), sodass
--- beim nächsten Login entweder direkt ein neuer Raid startet (falls die
--- Zeit inzwischen abgelaufen ist) oder der bisherige Countdown normal
--- weiterläuft.
function RaidService.CleanupPlayer(player: Player)
	local raid = activeRaids[player.UserId]
	if raid then
		raid.Finished = true
		destroyRaidWorkspaceState(raid)
		activeRaids[player.UserId] = nil
	end
end

--- Wird beim Login NACH erfolgreichem PlayerDataService.WaitForData
--- aufgerufen (siehe RaidServer.server.lua) - wertet verpasste Raids
--- deterministisch aus (siehe evaluateOfflineRaids oben). Der eigentliche
--- Live-Scheduler (runSchedulerLoop) übernimmt danach alle künftig
--- fälligen Raids dieser Session.
function RaidService.HandlePlayerLogin(player: Player)
	evaluateOfflineRaids(player)
end

-- // Bootstrap --------------------------------------------------------------------

task.spawn(runRaidTickLoop)
task.spawn(runSchedulerLoop)

return RaidService
