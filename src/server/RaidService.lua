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

	Guardians + co-op (docs/guardians-and-coop.md):
		Players deploy their saved guardian loadout (PlayerDataService.
		Get/SetGuardianLoadout, slots from RaidConfig.GetGuardianSlots) with
		RequestDeployGuardian. Guardians are creature models from
		Workspace.Assets.Creatures, simulated server-side inside the SAME shared
		tick loop as enemies/towers: they target the nearest enemy, deal damage
		on a cooldown scaled by rarity and the owner's level, and are knocked
		out (never lost) by enemy contact. Movement is published as
		TargetPosition attributes (tag RAID_GUARDIAN), ModelAnimator chases them.
		Reef Cluster members (ClusterService, required lazily) get an invite to
		join a raid on a cluster mate's plot as helpers: they deploy their own
		guardians and may use Depth Charges there, share the victory rewards and
		scale boss raids up (RaidConfig.COOP_*).

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
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local PlotRegistry = require(script.Parent:WaitForChild("PlotRegistry"))
local AssetTemplateSetup = require(script.Parent:WaitForChild("AssetTemplateSetup"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local ZoneEconomyConfig = require(ReplicatedStorage:WaitForChild("ZoneEconomyConfig"))
local ModelAnimationTags = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("ModelAnimationTags"))

local RaidService = {}

local rng = Random.new()

-- // Laufzeit-Typen (nur In-Memory, NICHT persistent) --------------------------

type EnemyRuntime = {
	EnemyId: RaidConfig.EnemyId,
	Model: Model,
	CurrentHP: number,
	MaxHP: number,
	MoveSpeed: number,
	-- Seamless-Animation-System (docs/animation-system.md): DIE serverseitige
	-- logische Position - ab jetzt die einzige Quelle der Wahrheit für
	-- Distanz-/Ziel-Berechnungen (Tower-Targeting, CoralBarrier-Slow-Radius,
	-- Center-Reach). Das Model selbst wird NICHT mehr jeden Tick per PivotTo
	-- bewegt (das verursachte sichtbares Ruckeln bei anchored Parts, siehe
	-- Auftrag) - stattdessen publiziert der Server diese Position nur noch
	-- als `ModelAnimationTags.ATTR_TARGET_POSITION`-Attribut, der Client
	-- (ModelAnimator.client.lua) interpoliert selbst dorthin.
	Position: Vector3,
}

type TowerRuntime = {
	PlacementId: string,
	Model: Model,
	Stats: RaidConfig.TowerCombatStats,
	LastFireTime: number,
}

type GuardianRuntime = {
	Owner: Player,
	OwnerUserId: number,
	InstanceId: string,
	CreatureId: string,
	Rarity: string,
	Model: Model?,
	Position: Vector3, -- server-side logical position, see EnemyRuntime.Position
	HomeOffset: Vector3,
	HP: number,
	MaxHP: number,
	Damage: number,
	CooldownSeconds: number,
	LastAttackAt: number,
	KnockedOut: boolean,
}

type HelperRuntime = {
	Player: Player,
	JoinedAt: number, -- os.clock()
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
	GuardiansFolder: Folder,
	Guardians: { GuardianRuntime },
	DeployedBy: { [number]: boolean }, -- UserIds that already deployed their loadout in this raid
	Helpers: { [number]: HelperRuntime }, -- co-op helpers (cluster mates), keyed by UserId
	GuardianDirty: boolean,
	LastGuardianSyncAt: number,
	Zone: string, -- Content Update 1, Abschnitt 3.1: ZoneEconomyConfig.GetZoneForLevel(Spieler-Level) zum Raid-Start, siehe RaidConfig.GetScaledEnemy
}

local activeRaids: { [number]: RaidRuntime } = {} -- keyed by UserId
local participantRaids: { [number]: RaidRuntime } = {} -- co-op helper UserId -> the raid they joined
local lastDeployAt: { [number]: number } = {}
local lastLoadoutAt: { [number]: number } = {}
local lastJoinAt: { [number]: number } = {}

local MAX_LOADOUT_PAYLOAD = 12 -- hard cap on ids read from a client payload
local MAX_CANDIDATES_SENT = 60

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

--- The raid `player` currently takes part in: their own, or a cluster mate's raid they joined.
local function getLiveRaidFor(player: Player): RaidRuntime?
	return activeRaids[player.UserId] or participantRaids[player.UserId]
end

--- Owner plus all helpers that are still in the server.
local function getRaidViewers(raid: RaidRuntime): { Player }
	local viewers: { Player } = {}
	if raid.Player.Parent == Players then
		table.insert(viewers, raid.Player)
	end
	for _, helper in pairs(raid.Helpers) do
		if helper.Player.Parent == Players then
			table.insert(viewers, helper.Player)
		end
	end
	return viewers
end

local function fireRaidClients(raid: RaidRuntime, remote: RemoteEvent, payload: { [string]: any })
	for _, viewer in ipairs(getRaidViewers(raid)) do
		remote:FireClient(viewer, payload)
	end
end

local function countHelpers(raid: RaidRuntime): number
	local count = 0
	for _ in pairs(raid.Helpers) do
		count += 1
	end
	return count
end

local function planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

--- Skaliert das geklonte Gegner-Modell gemäß der (ggf. bereits zonen-
--- skalierten, siehe RaidConfig.GetScaledEnemy) Gegnertyp-Definition und
--- setzt die Gameplay-Attribute.
---
--- GEÄNDERT (Content Update 1, Abschnitt 3): Body/Mantle/Eye1/Eye2 werden
--- NICHT MEHR fest auf definition.BodyColor/EyeColor eingefärbt. Das war nur
--- nötig, solange alle 4 Gegnertypen + Boss dasselbe ShadowKraken-Modell
--- wiederverwendet haben (siehe RaidConfig-Kopfkommentar zur früheren
--- MVP-Vereinfachung) - jetzt hat jeder EnemyId sein eigenes, bereits
--- passend eingefärbtes Modell (SpineDrifter/ThornSwarmer/IronMawBrute/
--- TrenchWardenBoss, siehe assets/models/enemies/*.lua), ein Overwrite
--- würde nur die absichtlich unterschiedliche Optik jedes Modells wieder
--- einebnen. RaidConfig.EnemyDefinition.BodyColor/EyeColor bleiben trotzdem
--- als Daten bestehen (Fallback-Referenzwerte, decken sich mit den
--- Modell-Farben, UND vorbereitet für künftige LiveEventService-
--- Farbvarianten wie "Venom-Slick"/"Wraith-Touched", die laut
--- Content-Update-Dokument Abschnitt 1.3 einen ZUSÄTZLICHEN, temporären
--- Farb-Override pro Event ergänzen sollen - das ist bewusst nicht Teil
--- dieses Auftrags/dieser Funktion).
--- `transparencyOverride`/`bodyColorOverride` sind die Live-Event-
--- Einhängepunkte, die der Kopfkommentar oben ankündigt (Abschnitt 1.3:
--- "Wraith-Touched" Transparency+10%HP, "Magma-Forged" Farb-Tönung+15%HP) -
--- modell-agnostisch umgesetzt (JEDER BasePart-Nachfahre, nicht feste
--- Part-Namen wie Eye1/Eye2), damit es unabhängig vom jeweiligen
--- Gegnermodell funktioniert. `nil` = kein Override (Normalfall).
local function applyEnemyVisual(
	model: Model,
	definition: RaidConfig.EnemyDefinition,
	transparencyOverride: number?,
	bodyColorOverride: Color3?
)
	local ok = pcall(function()
		model:ScaleTo(definition.ScaleMultiplier)
	end)
	if not ok then
		warn("[RaidService] Model:ScaleTo() failed (possibly an older engine version) - enemy stays unscaled.")
	end

	if type(transparencyOverride) == "number" then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Transparency = math.max(descendant.Transparency, transparencyOverride)
			end
		end
	end
	if typeof(bodyColorOverride) == "Color3" then
		local body = model:FindFirstChild("Body")
		if body and body:IsA("BasePart") then
			body.Color = bodyColorOverride
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

--- Gebäude-Upgrade-System (siehe docs/building-upgrades.md): liefert eine
--- STUFE-ANGEPASSTE Kopie von `baseStats` (RaidConfig.TowerCombatStats),
--- ausschließlich basierend auf BuildingConfig.GetTowerStageBonus. `stage`
--- kommt vom "Level"-Modell-Attribut - `nil`/kein Bonus liefert `baseStats`
--- unverändert zurück (Stufe 1, oder ein Turmtyp ohne konfigurierten Bonus).
--- Felder, die der jeweilige Turmtyp gar nicht besitzt (z. B. BlockRadius
--- bei AnglerfishTower), bleiben `nil` (kein Bonus "erfindet" ein Feld, das
--- RaidConfig.TOWER_STATS für diesen Turmtyp nie definiert hat).
local function applyTowerStageBonus(buildingId: string, baseStats: RaidConfig.TowerCombatStats, stage: any): RaidConfig.TowerCombatStats
	local numericStage = tonumber(stage) or 1
	local bonus = BuildingConfig.GetTowerStageBonus(buildingId, numericStage)
	if not bonus then
		return baseStats
	end

	return {
		Range = baseStats.Range + (bonus.RangeBonus or 0),
		Damage = baseStats.Damage * (bonus.DamageMultiplier or 1),
		FireRate = baseStats.FireRate * (bonus.FireRateMultiplier or 1),
		BlockRadius = baseStats.BlockRadius and (baseStats.BlockRadius + (bonus.BlockRadiusBonus or 0)) or nil,
		ChainCount = baseStats.ChainCount and (baseStats.ChainCount + (bonus.ChainCountBonus or 0)) or nil,
		ChainRadius = baseStats.ChainRadius and (baseStats.ChainRadius + (bonus.ChainRadiusBonus or 0)) or nil,
	}
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
					-- Seamless-Animation-System (docs/animation-system.md):
					-- idempotentes Tag - der Client-Renderer
					-- (ModelAnimator.client.lua) macht darüber jeden eigenen Turm
					-- idle-glow-pulsierend + Muzzle-Flash/Recoil bei Treffern,
					-- unabhängig davon ob gerade ein Raid läuft.
					CollectionService:AddTag(model, ModelAnimationTags.RAID_TOWER)
					table.insert(towers, {
						PlacementId = model:GetAttribute("PlacementId"),
						Model = model,
						-- Gebäude-Upgrade-System (siehe docs/building-upgrades.md): das
						-- "Level"-Modell-Attribut (1-3, siehe PlacementService.tagModel)
						-- wird hier auf die RaidConfig-Basiswerte angewendet - rein
						-- additiv/multiplikativ, NIEMALS in RaidConfig zurückgeschrieben
						-- (identisches Prinzip wie RaidConfig.GetScaledEnemy oben).
						Stats = applyTowerStageBonus(buildingId, stats, model:GetAttribute("Level")),
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

	-- Live-Event-Einhängepunkt (docs/content-update-1.md Abschnitt 1.3:
	-- Venom-Slick/Wraith-Touched/Magma-Forged-Gegnervarianten) - EINMAL pro
	-- Welle aufgelöst (nicht pro Gegner), BEWUSST ein LAZY require(),
	-- identische Begründung wie applyDoubleCoinsGamepass oben.
	local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))
	local enemyMoveSpeedMultiplier = LiveEventService.GetModifier("RaidEnemyMoveSpeedMultiplier", 1)
	local enemyMaxHPMultiplier = LiveEventService.GetModifier("RaidEnemyMaxHPMultiplier", 1)
	local enemyTransparencyOverride = LiveEventService.GetModifier("RaidEnemyTransparency", nil)
	local enemyBodyColorOverride = LiveEventService.GetModifier("RaidEnemyBodyColor", nil)

	local spawnedCount = 0
	local helperCount = countHelpers(raid)
	for _, spawnSpec in ipairs(wave.Enemies) do
		-- Content Update 1, Abschnitt 3.1: zonen-skalierte Definition statt
		-- der rohen Basis-Werte - raid.Zone wurde einmalig beim Raid-Start
		-- bestimmt (siehe startRaid), bleibt für die gesamte Raid-Dauer fix.
		local definition = RaidConfig.GetScaledEnemy(spawnSpec.EnemyId, raid.Zone)
		if definition then
			local template = AssetTemplateSetup.GetEnemyTemplate(definition.TemplateName)
			if template then
				-- Co-op scaling (RaidConfig.COOP_*): more helpers, tougher enemies,
				-- the boss most of all, and extra escorts in the boss wave.
				local hpScale = 1
					+ helperCount
						* (if definition.IsBoss
							then RaidConfig.COOP_BOSS_HP_PER_EXTRA
							else RaidConfig.COOP_ENEMY_HP_PER_EXTRA)
				local spawnCount = spawnSpec.Count
				if wave.IsBossWave and not definition.IsBoss then
					spawnCount += helperCount * RaidConfig.COOP_BOSS_ESCORT_PER_EXTRA
				end
				for _ = 1, spawnCount do
					local model = template:Clone()
					model.Name = definition.Id .. "_" .. tostring(spawnedCount + 1)
					applyEnemyVisual(model, definition, enemyTransparencyOverride, enemyBodyColorOverride)
					model.Parent = raid.EnemiesFolder

					local spawnPos = randomSpawnPosition(raid.CenterPosition)
					model:PivotTo(CFrame.new(spawnPos, raid.CenterPosition))

					-- Seamless-Animation-System (docs/animation-system.md): Tag +
					-- Startattribute für den Client-Renderer. Der Server bewegt
					-- dieses Model ab jetzt NIE MEHR direkt per PivotTo (siehe
					-- tickEnemyMovement) - nur noch ATTR_TARGET_POSITION-Updates,
					-- der Client interpoliert selbst (kein Ruckeln bei anchored
					-- Parts, siehe Auftrag).
					CollectionService:AddTag(model, ModelAnimationTags.RAID_ENEMY)
					model:SetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION, spawnPos)
					model:SetAttribute(ModelAnimationTags.ATTR_CENTER_POSITION, raid.CenterPosition)
					model:SetAttribute(ModelAnimationTags.ATTR_SPAWNED_AT, Workspace:GetServerTimeNow())

					local scaledMaxHP = definition.MaxHP * enemyMaxHPMultiplier * hpScale
					table.insert(raid.Enemies, {
						EnemyId = definition.Id,
						Model = model,
						CurrentHP = scaledMaxHP,
						MaxHP = scaledMaxHP,
						MoveSpeed = definition.MoveSpeed * enemyMoveSpeedMultiplier,
						Position = spawnPos,
					})
					spawnedCount += 1
				end
			else
				warn(
					("[RaidService] Enemy template '%s' is missing - spawn of '%s' skipped."):format(
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
	if raid.GuardiansFolder and raid.GuardiansFolder.Parent then
		raid.GuardiansFolder:Destroy()
	end
	raid.Enemies = {}
	raid.Guardians = {}
end

-- // Reef Cluster lookup (ClusterService is built by another feature, so it is
-- required lazily and everything falls back to solo when it is missing) --------

local clusterServiceModule: any? = nil

local function getClusterService(): any?
	if clusterServiceModule then
		return clusterServiceModule
	end
	local moduleScript = script.Parent:FindFirstChild("ClusterService")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if ok and type(result) == "table" and type((result :: any).GetClusterMembers) == "function" then
		clusterServiceModule = result
		return result
	end
	return nil
end

--- Online Reef Cluster mates of `player` (never including `player`), empty when
--- there is no ClusterService, no cluster, or the call fails.
local function getClusterMates(player: Player): { Player }
	local service = getClusterService()
	if not service then
		return {}
	end
	local ok, members = pcall(service.GetClusterMembers, player)
	if not ok or type(members) ~= "table" then
		return {}
	end
	local mates: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, member in ipairs(members) do
		if
			typeof(member) == "Instance"
			and member:IsA("Player")
			and member ~= player
			and member.Parent == Players
			and not seen[member]
		then
			seen[member] = true
			table.insert(mates, member)
		end
	end
	return mates
end

--- Persists one finished cluster raid for `player`. ClusterService.RecordClusterRaid
--- wraps PlayerDataService.RecordClusterRaid and also refreshes the Cluster
--- leaderboard; without ClusterService the PlayerDataService call is used directly.
local function recordClusterRaid(player: Player, wave: number, won: boolean)
	local service = getClusterService()
	if service and type(service.RecordClusterRaid) == "function" then
		local ok = pcall(service.RecordClusterRaid, player, wave, won)
		if ok then
			return
		end
	end
	PlayerDataService.RecordClusterRaid(player, wave, won)
end

-- // Co-op helpers: teleport + ability HUD refresh -----------------------------------

--- Puts the character of `player` on top of `plot`, offset from the center so
--- several helpers do not stand on each other.
local function teleportToPlot(player: Player, plot: Model, offset: Vector3): boolean
	local character = player.Character
	if not character or not character.PrimaryPart or not plot.PrimaryPart then
		return false
	end
	local approx = plot.PrimaryPart.Position + offset
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot.PrimaryPart :: Instance }
	local hit = Workspace:Raycast(approx + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
	local y = if hit then hit.Position.Y + 4 else plot.PrimaryPart.Position.Y + 6
	local center = plot.PrimaryPart.Position
	character:PivotTo(CFrame.new(Vector3.new(approx.X, y, approx.Z), Vector3.new(center.X, y, center.Z)))
	return true
end

local function returnHelperHome(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ownPlot = PlotRegistry.GetPlot(player)
	if ownPlot then
		teleportToPlot(player, ownPlot, Vector3.new(0, 0, 8))
	end
end

--- Refreshes the ability HUD (Depth Charge button follows raid membership).
--- Lazy require: AbilityService itself lazily requires RaidService.
local function pushAbilityStatus(player: Player)
	task.spawn(function()
		local ok, AbilityService = pcall(function()
			return require(script.Parent:WaitForChild("AbilityService"))
		end)
		if ok and AbilityService and player.Parent == Players then
			pcall(AbilityService.PushStatus, player)
		end
	end)
end

local function sendGuardianStatus(raid: RaidRuntime, onlyTo: Player?)
	local list = {}
	for _, guardian in ipairs(raid.Guardians) do
		table.insert(list, {
			OwnerUserId = guardian.OwnerUserId,
			InstanceId = guardian.InstanceId,
			CreatureId = guardian.CreatureId,
			Rarity = guardian.Rarity,
			HP = math.max(0, math.ceil(guardian.HP)),
			MaxHP = guardian.MaxHP,
			KnockedOut = guardian.KnockedOut,
		})
	end
	if onlyTo then
		RaidRemotes.GuardianStatus:FireClient(onlyTo, { Guardians = list })
	else
		fireRaidClients(raid, RaidRemotes.GuardianStatus, { Guardians = list })
	end
	raid.GuardianDirty = false
	raid.LastGuardianSyncAt = os.clock()
end

-- // Sieg/Niederlage-Auswertung (LIVE-Raid) ------------------------------------

local function finishRaid(raid: RaidRuntime, won: boolean)
	if raid.Finished then
		return
	end
	raid.Finished = true

	local player = raid.Player

	-- Co-op: freeze the helper list before the raid state is torn down.
	local helpers: { HelperRuntime } = {}
	local eligibleHelpers: { HelperRuntime } = {}
	local finishClock = os.clock()
	local clusterMates = if next(raid.Helpers) then getClusterMates(player) else {}
	for userId, helper in pairs(raid.Helpers) do
		table.insert(helpers, helper)
		participantRaids[userId] = nil
		if
			helper.Player.Parent == Players
			and PlayerDataService.IsDataLoaded(helper.Player)
			and table.find(clusterMates, helper.Player) ~= nil -- still a cluster mate (not kicked meanwhile)
			and finishClock - helper.JoinedAt >= RaidConfig.COOP_MIN_PRESENCE_SECONDS
		then
			table.insert(eligibleHelpers, helper)
		end
	end
	raid.Guardians = {}
	sendGuardianStatus(raid)
	destroyRaidWorkspaceState(raid)
	activeRaids[player.UserId] = nil

	-- Live-Event-Einhängepunkt (docs/content-update-1.md Abschnitt 1.3,
	-- Volcanic Vent "-30% Raid-Intervall") - BEWUSST ein LAZY require(),
	-- identische Begründung wie applyDoubleCoinsGamepass oben.
	local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))
	local raidIntervalMultiplier = LiveEventService.GetModifier("RaidIntervalMultiplier", 1)

	local now = os.time()
	local nextRaidAt = now + math.floor(RaidConfig.RAID_INTERVAL_SECONDS * raidIntervalMultiplier)
	PlayerDataService.SetNextRaidAt(player, nextRaidAt)

	local resultPayload: { [string]: any } = {
		Success = won,
		WavesCleared = if won then #RaidConfig.WAVES else math.max(0, raid.WaveIndex - 1),
		NextRaidAt = nextRaidAt,
	}

	local baseCoinReward = 0
	if won then
		-- Treasure Tide "Raid-Sieg-Tide-Coin-Belohnung ×1.5" (Abschnitt 1.3).
		baseCoinReward =
			math.floor(RaidConfig.VICTORY_REWARD_TIDE_COINS * LiveEventService.GetModifier("RaidVictoryCoinMultiplier", 1) + 0.5)
		local ownerBonus = 1 + RaidConfig.COOP_OWNER_BONUS_PER_HELPER * #eligibleHelpers
		local tideCoinReward = applyDoubleCoinsGamepass(player, math.floor(baseCoinReward * ownerBonus + 0.5))
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

		-- GameEvents-Einhängepunkt (Auftrag Punkt 1): QuestService zählt
		-- hierüber die "Überstehe N Raids"-Tagesquest.
		GameEvents.Fire(GameEvents.Events.RaidWon, player, {
			WavesCleared = resultPayload.WavesCleared,
			RewardTideCoins = tideCoinReward,
		})
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

		GameEvents.Fire(GameEvents.Events.RaidLost, player, {
			AbductedInstanceId = abducted and abducted.InstanceId or nil,
		})
	end

	resultPayload.HelperCount = if #eligibleHelpers > 0 then #eligibleHelpers else nil
	RaidRemotes.RaidResult:FireClient(player, resultPayload)

	-- Co-op: shared rewards, stats and the trip home for every helper. Helpers
	-- never lose a creature, even when the raid is lost.
	local wavesCleared = resultPayload.WavesCleared
	for _, helper in ipairs(helpers) do
		local helperPlayer = helper.Player
		if helperPlayer.Parent == Players then
			local helperPayload: { [string]: any } = {
				Success = won,
				Coop = true,
				OwnerName = player.DisplayName,
				WavesCleared = wavesCleared,
			}
			if won and table.find(eligibleHelpers, helper) then
				local helperCoins = applyDoubleCoinsGamepass(
					helperPlayer,
					math.floor(baseCoinReward * RaidConfig.COOP_HELPER_REWARD_FRACTION + 0.5)
				)
				PlayerDataService.AddCurrency(helperPlayer, "TideCoins", helperCoins)
				helperPayload.RewardTideCoins = helperCoins
				ProgressionService.AwardXP(helperPlayer, "RaidWon")
				if rng:NextNumber() <= RaidConfig.VICTORY_ABYSSAL_SHARD_CHANCE then
					PlayerDataService.AddCurrency(helperPlayer, "AbyssalShards", RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT)
					helperPayload.RewardAbyssalShards = RaidConfig.VICTORY_ABYSSAL_SHARD_AMOUNT
				end
				GameEvents.Fire(GameEvents.Events.RaidWon, helperPlayer, { WavesCleared = wavesCleared, RewardTideCoins = helperCoins })
			end
			RaidRemotes.RaidResult:FireClient(helperPlayer, helperPayload)
			pushAbilityStatus(helperPlayer)
			task.delay(RaidConfig.COOP_RETURN_DELAY_SECONDS, function()
				if not getLiveRaidFor(helperPlayer) then
					returnHelperHome(helperPlayer)
				end
			end)
		end
	end

	-- Cluster stats for everyone who really took part.
	if #eligibleHelpers > 0 then
		local reachedWave = if won then #RaidConfig.WAVES else raid.WaveIndex
		recordClusterRaid(player, reachedWave, won)
		for _, helper in ipairs(eligibleHelpers) do
			recordClusterRaid(helper.Player, reachedWave, won)
		end
	end
end

-- // Raid-Schutz fuer Neulinge ---------------------------------------------------
-- Raids beginnen erst, wenn der erste Verteidigungsturm (AnglerfishTower)
-- freigeschaltet ist - vorher haette ein neuer Spieler keine Chance zu
-- verteidigen und wuerde nach 25 Minuten eine Kreatur verlieren.
local function raidsAllowedFor(player: Player): boolean
	local tower = BuildingConfig.Get("AnglerfishTower")
	local minLevel = if tower then tower.UnlockLevel else 1
	return PlayerDataService.GetLevel(player) >= minLevel
end

--- A cluster mate's plot is under attack: ask the online mates to help.
local function inviteClusterMembers(raid: RaidRuntime)
	local owner = raid.Player
	local expiresAt = os.time() + RaidConfig.COOP_INVITE_SECONDS
	for _, mate in ipairs(getClusterMates(owner)) do
		if PlayerDataService.IsDataLoaded(mate) and not getLiveRaidFor(mate) then
			RaidRemotes.CoopRaidInvite:FireClient(mate, {
				OwnerUserId = owner.UserId,
				OwnerName = owner.DisplayName,
				ExpiresAt = expiresAt,
			})
		end
	end
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
	if not raidsAllowedFor(player) then
		-- Noch kein Verteidigungsturm freigeschaltet: ein Raid waere eine
		-- garantierte Niederlage (Entfuehrung). Timer einfach verlaengern.
		PlayerDataService.SetNextRaidAt(player, os.time() + RaidConfig.RAID_INTERVAL_SECONDS)
		return
	end

	local plot = PlotRegistry.GetPlot(player)
	if not plot or not plot.PrimaryPart then
		-- Kein Plot (noch) vorhanden (z. B. Buildscript-Vorlage fehlt, siehe
		-- AssetTemplateSetup-Warnung) - Timer trotzdem fortschreiben, damit
		-- nicht jeden Scheduler-Tick erneut versucht wird. Live-Event-
		-- Einhängepunkt siehe finishRaid oben (identischer Intervall-
		-- Multiplikator, BEWUSST ein LAZY require()).
		local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))
		local raidIntervalMultiplier = LiveEventService.GetModifier("RaidIntervalMultiplier", 1)
		PlayerDataService.SetNextRaidAt(player, os.time() + math.floor(RaidConfig.RAID_INTERVAL_SECONDS * raidIntervalMultiplier))
		return
	end

	local enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "RaidEnemies"
	enemiesFolder.Parent = plot

	local guardiansFolder = Instance.new("Folder")
	guardiansFolder.Name = "RaidGuardians"
	guardiansFolder.Parent = plot

	local raid: RaidRuntime = {
		Player = player,
		CenterPosition = plot.PrimaryPart.Position,
		EnemiesFolder = enemiesFolder,
		GuardiansFolder = guardiansFolder,
		Guardians = {},
		DeployedBy = {},
		Helpers = {},
		GuardianDirty = false,
		LastGuardianSyncAt = 0,
		Towers = collectTowerRuntimes(player),
		Enemies = {},
		WaveIndex = 1,
		EnemiesReachedCenter = 0,
		Finished = false,
		-- Content Update 1, Abschnitt 3.1 + ZoneEconomyConfig-Kopfkommentar:
		-- "Zone des Spielers" = tiefste per Level freigeschaltete Zone,
		-- einmalig beim Raid-Start bestimmt (bleibt für die gesamte
		-- Raid-Dauer stabil, auch falls der Spieler währenddessen levelt).
		Zone = ZoneEconomyConfig.GetZoneForLevel(PlayerDataService.GetLevel(player)),
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
	pushAbilityStatus(player)
	inviteClusterMembers(raid)
end

-- // Gemeinsamer Kampf-Tick-Loop (EIN Loop für ALLE Raids/Gegner/Türme) ---------

--- Liefert den Schuss-/Effekt-Ursprungspunkt eines Turm-Modells. Content
--- Update 1 führt 2 weitere Turmtypen ein, deren namensgebender "Muzzle"-Part
--- NICHT "LureOrb" heißt (CoralBarrier: "SlowPulseCore", ElectricEelTrap:
--- "EelHead") - alle 3 Turmmodelle tragen aber laut assets/models/README.md
--- einheitlich ein Attachment "MuzzlePoint" genau an diesem Part. Reihenfolge
--- daher bewusst generisch: 1) MuzzlePoint-Attachment (deckt alle 3 Türme +
--- künftige Turmtypen ab, ohne dass diese Funktion je wieder angepasst
--- werden muss), 2) bekannte Part-Namen als Fallback (ältere/unvollständige
--- Modelle), 3) Modell-Pivot als letzter Fallback.
local KNOWN_TOWER_ORIGIN_PART_NAMES = { "LureOrb", "SlowPulseCore", "EelHead" }

local function getTowerOriginPosition(model: Model): Vector3
	local muzzle = model:FindFirstChild("MuzzlePoint", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end

	for _, partName in ipairs(KNOWN_TOWER_ORIGIN_PART_NAMES) do
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part.Position
		end
	end

	return model:GetPivot().Position
end

--- Content Update 1, Abschnitt 4.1 (CoralBarrier): liefert den stärksten
--- (= niedrigsten) Geschwindigkeits-Multiplikator für einen Gegner an
--- `enemyPosition`, basierend auf allen eigenen CoralBarrier-Türmen, in
--- deren BlockRadius er gerade steht. Mehrere Barrieren stacken NICHT
--- (bewusste Vereinfachung - ein Gegner ist "verlangsamt" oder nicht, keine
--- kumulative Verlangsamung), da RaidConfig.CORAL_BARRIER_SLOW_FRACTION als
--- einzelner, fester Effekt dokumentiert ist. Rein lesend, keine
--- Zustandsänderung - billig genug, um pro Gegner/Tick zu laufen (kleine
--- Turm-/Gegner-Anzahl pro Raid, siehe Performance-Kopfkommentar).
local function computeSpeedMultiplier(raid: RaidRuntime, enemyPosition: Vector3): number
	local multiplier = 1
	for _, tower in ipairs(raid.Towers) do
		if tower.Model.Parent and tower.Stats.BlockRadius then
			local towerPosition = getTowerOriginPosition(tower.Model)
			if (enemyPosition - towerPosition).Magnitude <= tower.Stats.BlockRadius then
				multiplier = math.min(multiplier, 1 - RaidConfig.CORAL_BARRIER_SLOW_FRACTION)
			end
		end
	end
	return multiplier
end

--- Seamless-Animation-System (docs/animation-system.md): markiert `model` als
--- "stirbt gerade" (ATTR_DYING_AT-Zeitstempel, siehe ModelAnimationTags) und
--- zerstört es erst RaidConfig.DEATH_FX_SECONDS SPÄTER wirklich - der Client
--- (ModelAnimator.client.lua) spielt in dieser Karenzzeit eine Auflöse-/
--- Schrumpf-Animation statt eines sofortigen "Pop". Rein kosmetisch: der
--- Aufrufer hat das Model bereits VORHER aus `raid.Enemies`
--- entfernt/gameplay-seitig gewertet (Sieg/Wellen-Fortschritt), diese
--- Funktion beeinflusst also KEINE Gameplay-Zeitpunkte.
local function scheduleDeathDestroy(model: Model)
	model:SetAttribute(ModelAnimationTags.ATTR_DYING_AT, Workspace:GetServerTimeNow())
	task.delay(RaidConfig.DEATH_FX_SECONDS, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

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

		local currentPosition = enemy.Position
		local toCenter = raid.CenterPosition - currentPosition
		local distance = toCenter.Magnitude

		if distance <= RaidConfig.CENTER_REACH_RADIUS then
			scheduleDeathDestroy(enemy.Model)
			table.remove(raid.Enemies, i)
			raid.EnemiesReachedCenter += 1
			continue
		end

		local speedMultiplier = computeSpeedMultiplier(raid, currentPosition)
		local effectiveSpeed = enemy.MoveSpeed * speedMultiplier
		local step = math.min(distance, effectiveSpeed * deltaSeconds)
		local direction = toCenter.Unit
		local newPosition = currentPosition + direction * step
		enemy.Position = newPosition

		-- Seamless-Animation-System: NUR noch das Ziel-Attribut publizieren
		-- (kein PivotTo mehr) - der Client interpoliert selbst dorthin, siehe
		-- ModelAnimator.client.lua. `ATTR_SLOWED` treibt die sichtbare
		-- CoralBarrier-Verlangsamungs-Optik (trägere Idle-Wobble).
		enemy.Model:SetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION, newPosition)
		enemy.Model:SetAttribute(ModelAnimationTags.ATTR_SLOWED, speedMultiplier < 1)

		i += 1
	end
end

-- // ElectricEelTrap: "Ladezustand"-Blitz-Feedback (Content Update 1, Abschnitt 4.2) --
-- Rein visuell (ChargeCore/ChargeLight, siehe assets/models/buildings/
-- ElectricEelTrap.lua) - kein Gameplay-Effekt. Fail-soft: Modelle ohne
-- ChargeCore (AnglerfishTower/CoralBarrier, oder ein Fallback-Modell nach
-- AssetTemplateSetup-Fail-Soft) überspringen dies einfach.
local CHARGE_FLASH_SECONDS = 0.15
local CHARGE_FLASH_BRIGHTNESS = 4

local function flashChargeCore(model: Model)
	local core = model:FindFirstChild("ChargeCore")
	if not core or not core:IsA("BasePart") then
		return
	end

	local light = core:FindFirstChildWhichIsA("PointLight")
	local originalTransparency = core.Transparency
	local originalBrightness = light and light.Brightness or nil

	core.Transparency = 0
	if light then
		light.Brightness = CHARGE_FLASH_BRIGHTNESS
	end

	task.delay(CHARGE_FLASH_SECONDS, function()
		if core.Parent then
			core.Transparency = originalTransparency
		end
		if light and light.Parent and originalBrightness then
			light.Brightness = originalBrightness
		end
	end)
end

--- Entfernt alle Gegner mit CurrentHP <= 0 aus `raid.Enemies` (zerstört das
--- Modell, feuert kein Remote selbst - EnemyHit wurde bereits pro Treffer
--- gefeuert). Rückwärts iteriert, damit table.remove keine noch zu
--- prüfenden Indizes verschiebt.
local function removeDeadEnemies(raid: RaidRuntime)
	for index = #raid.Enemies, 1, -1 do
		local enemy = raid.Enemies[index]
		if enemy.CurrentHP <= 0 then
			if enemy.Model.Parent then
				scheduleDeathDestroy(enemy.Model)
			end
			table.remove(raid.Enemies, index)
		end
	end
end

--- WICHTIG: `now` muss `os.clock()` sein (hochauflösend, Sekunden als Float),
--- NICHT `os.time()` (nur ganzzahlige Sekunden-Auflösung) - bei FireRate-
--- Werten > 1 Schuss/Sekunde (siehe RaidConfig.TOWER_STATS) würde
--- `os.time()` jeden Turm faktisch auf maximal 1 Schuss/Sekunde deckeln, da
--- sich der Zeitstempel innerhalb einer Sekunde gar nicht ändert.
--- `os.clock()` wird hier rein für die Intra-Session-Taktung verwendet
--- (nicht persistiert), daher unproblematisch.
---
--- GEÄNDERT (Content Update 1, Abschnitt 4): bleibt EIN gemeinsamer Loop für
--- ALLE Türme/Raids (kein Loop pro Turm/Tower-Typ, siehe Performance-
--- Kopfkommentar) - CoralBarriers Slow-Effekt läuft komplett außerhalb
--- dieser Funktion (siehe computeSpeedMultiplier in tickEnemyMovement, kein
--- eigenes Feuerintervall nötig, da er kein "Schuss" ist). ElectricEelTraps
--- Kettenschaden hängt sich direkt in den bestehenden Ziel-/Feuer-Ablauf
--- dieser Funktion ein.
local function tickTowers(raid: RaidRuntime, now: number)
	for _, tower in ipairs(raid.Towers) do
		if tower.Model.Parent then
			local fireInterval = 1 / tower.Stats.FireRate
			if now - tower.LastFireTime >= fireInterval then
				local towerPosition = getTowerOriginPosition(tower.Model)

				local targetIndex: number? = nil
				local targetDistance = math.huge
				for index, enemy in ipairs(raid.Enemies) do
					if enemy.Model.Parent then
						local dist = (enemy.Position - towerPosition).Magnitude
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

					-- `Tower` (Content Update: seamless animation system, siehe
					-- ModelAnimator.client.lua) - zusätzliches, rein additives Feld
					-- (Instanz-Referenzen dürfen über RemoteEvents an Clients
					-- repliziert werden) für client-seitigen Muzzle-Flash/Recoil auf
					-- dem TATSÄCHLICH feuernden Turm-Modell, statt nur Positionen.
					fireRaidClients(raid, RaidRemotes.EnemyHit, {
						TowerPosition = towerPosition,
						EnemyPosition = target.Position,
						Tower = tower.Model,
					})

					-- Content Update 1, Abschnitt 4.2: ElectricEelTrap-Kettenschaden -
					-- bis zu ChainCount weitere, dem Hauptziel am nächsten stehende
					-- Gegner im ChainRadius erhalten CHAIN_DAMAGE_FRACTION Schaden.
					if tower.Stats.ChainCount and tower.Stats.ChainCount > 0 and tower.Stats.ChainRadius then
						local targetPosition = target.Position
						local candidates: { { Enemy: EnemyRuntime, Distance: number } } = {}
						for index, enemy in ipairs(raid.Enemies) do
							if index ~= targetIndex and enemy.Model.Parent then
								local dist = (enemy.Position - targetPosition).Magnitude
								if dist <= tower.Stats.ChainRadius then
									table.insert(candidates, { Enemy = enemy, Distance = dist })
								end
							end
						end
						table.sort(candidates, function(a, b)
							return a.Distance < b.Distance
						end)

						local chainDamage = tower.Stats.Damage * RaidConfig.CHAIN_DAMAGE_FRACTION
						for chainIndex = 1, math.min(tower.Stats.ChainCount, #candidates) do
							local chained = candidates[chainIndex].Enemy
							chained.CurrentHP -= chainDamage
							fireRaidClients(raid, RaidRemotes.EnemyHit, {
								TowerPosition = towerPosition,
								EnemyPosition = chained.Position,
								Tower = tower.Model,
							})
						end

						flashChargeCore(tower.Model)
					end

					removeDeadEnemies(raid)
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

		fireRaidClients(raid, RaidRemotes.WaveAdvanced, {
			WaveIndex = raid.WaveIndex,
			TotalWaves = #RaidConfig.WAVES,
			WaveEnemyCount = spawnedCount,
			IsBossWave = wave and wave.IsBossWave or false,
		})
	end
end

-- // Guardians: deploy, combat tick (same shared loop as enemies/towers) -------------

local warnedMissingGuardianTemplate: { [string]: boolean } = {}

--- Same lookup CreatureDisplayService/BuddyService use: the creature models
--- built by the Studio buildscripts live in Workspace.Assets.Creatures.
local function findCreatureTemplate(creatureId: string): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local creaturesFolder = assetsFolder and assetsFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	return nil
end

--- A creature can be a guardian when the player owns it in the inventory.
--- Abducted creatures live in RaidState.AbductedCreatures (not in the inventory)
--- and incubating eggs are not creature instances yet, but both are checked
--- explicitly so a future schema change cannot open a hole here.
local function checkGuardianEligibility(player: Player, instanceId: string): (PlayerDataService.CreatureInstance?, string?)
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		if abducted.InstanceId == instanceId then
			return nil, "Abducted"
		end
	end
	for _, incubation in ipairs(PlayerDataService.GetIncubations(player)) do
		if (incubation :: any).InstanceId == instanceId then
			return nil, "Incubating"
		end
	end
	local instance = PlayerDataService.GetCreatureInstance(player, instanceId)
	if not instance then
		return nil, "NotOwned"
	end
	return instance, nil
end

local function knockOutGuardian(raid: RaidRuntime, guardian: GuardianRuntime)
	guardian.KnockedOut = true
	guardian.HP = 0
	raid.GuardianDirty = true
	raid.LastGuardianSyncAt = 0 -- push the new state right away
	if guardian.Model and guardian.Model.Parent then
		scheduleDeathDestroy(guardian.Model) -- client fades it out (ATTR_DYING_AT)
	end
end

local function spawnGuardian(raid: RaidRuntime, owner: Player, instance: PlayerDataService.CreatureInstance)
	local stats = RaidConfig.GetGuardianCombatStats(instance.Rarity, PlayerDataService.GetLevel(owner))
	local homeAngle = #raid.Guardians * (math.pi / 3) + math.pi / 6
	local homeOffset = Vector3.new(
		math.cos(homeAngle) * RaidConfig.GUARDIAN_HOME_RADIUS,
		RaidConfig.GUARDIAN_HOVER_HEIGHT,
		math.sin(homeAngle) * RaidConfig.GUARDIAN_HOME_RADIUS
	)
	local position = raid.CenterPosition + homeOffset

	local model: Model? = nil
	local template = findCreatureTemplate(instance.CreatureId)
	if template then
		local clone = template:Clone()
		clone.Name = "Guardian_" .. instance.InstanceId
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") then
				descendant.Shadows = false
			end
		end
		clone:SetAttribute("OwnerUserId", owner.UserId)
		clone:SetAttribute("CreatureId", instance.CreatureId)
		clone:SetAttribute("GuardianRarity", instance.Rarity)
		clone:PivotTo(CFrame.new(position))
		clone:SetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION, position)
		clone:SetAttribute(ModelAnimationTags.ATTR_SPAWNED_AT, Workspace:GetServerTimeNow())
		CollectionService:AddTag(clone, ModelAnimationTags.RAID_GUARDIAN)
		clone.Parent = raid.GuardiansFolder
		model = clone
	elseif not warnedMissingGuardianTemplate[instance.CreatureId] then
		-- Fail soft: the guardian still fights, it just has no body to show.
		warnedMissingGuardianTemplate[instance.CreatureId] = true
		warn(
			("[RaidService] No Workspace.Assets.Creatures model for '%s' - guardian fights without a model."):format(
				instance.CreatureId
			)
		)
	end

	table.insert(raid.Guardians, {
		Owner = owner,
		OwnerUserId = owner.UserId,
		InstanceId = instance.InstanceId,
		CreatureId = instance.CreatureId,
		Rarity = instance.Rarity,
		Model = model,
		Position = position,
		HomeOffset = homeOffset,
		HP = stats.MaxHP,
		MaxHP = stats.MaxHP,
		Damage = stats.Damage,
		CooldownSeconds = stats.CooldownSeconds,
		LastAttackAt = 0,
		KnockedOut = false,
	})
end

local function tickGuardians(raid: RaidRuntime, now: number, deltaSeconds: number)
	for _, guardian in ipairs(raid.Guardians) do
		if guardian.KnockedOut then
			continue
		end

		-- Enemies touching the guardian knock it out for the rest of the raid.
		local contactDps = 0
		for _, enemy in ipairs(raid.Enemies) do
			if enemy.Model.Parent and planarDistance(enemy.Position, guardian.Position) <= RaidConfig.GUARDIAN_CONTACT_RADIUS then
				contactDps += RaidConfig.GUARDIAN_CONTACT_DPS_BY_ENEMY[enemy.EnemyId] or RaidConfig.GUARDIAN_CONTACT_DPS_DEFAULT
			end
		end
		if contactDps > 0 then
			guardian.HP -= contactDps * deltaSeconds
			raid.GuardianDirty = true
			if guardian.HP <= 0 then
				knockOutGuardian(raid, guardian)
				continue
			end
		end

		-- Nearest enemy that is still close enough to the plot.
		local target: EnemyRuntime? = nil
		local targetDistance = math.huge
		for _, enemy in ipairs(raid.Enemies) do
			if enemy.Model.Parent and planarDistance(enemy.Position, raid.CenterPosition) <= RaidConfig.GUARDIAN_ENGAGE_RADIUS then
				local dist = planarDistance(enemy.Position, guardian.Position)
				if dist < targetDistance then
					targetDistance = dist
					target = enemy
				end
			end
		end

		local goal = raid.CenterPosition + guardian.HomeOffset
		if target then
			if targetDistance <= RaidConfig.GUARDIAN_ATTACK_RANGE then
				goal = guardian.Position -- in range: hold position and fight
				if now - guardian.LastAttackAt >= guardian.CooldownSeconds then
					guardian.LastAttackAt = now
					target.CurrentHP -= guardian.Damage
					fireRaidClients(raid, RaidRemotes.GuardianAttack, {
						From = guardian.Position,
						To = target.Position + Vector3.new(0, RaidConfig.GUARDIAN_HOVER_HEIGHT * 0.5, 0),
						Rarity = guardian.Rarity,
					})
					if target.CurrentHP <= 0 then
						removeDeadEnemies(raid)
					end
				end
			else
				goal = Vector3.new(target.Position.X, guardian.Position.Y, target.Position.Z)
			end
		end

		local toGoal = goal - guardian.Position
		local distance = toGoal.Magnitude
		if distance > 0.05 then
			local newPosition = guardian.Position + toGoal.Unit * math.min(distance, RaidConfig.GUARDIAN_MOVE_SPEED * deltaSeconds)
			guardian.Position = newPosition
			if guardian.Model and guardian.Model.Parent then
				guardian.Model:SetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION, newPosition)
			end
		end
	end

	if raid.GuardianDirty and now - raid.LastGuardianSyncAt >= RaidConfig.GUARDIAN_STATUS_SYNC_SECONDS then
		sendGuardianStatus(raid)
	end
end

--- Deploys the caller's SAVED loadout into the raid they are in (own raid or a
--- cluster mate's). The client sends no ids: everything is read and
--- re-validated from server state.
function RaidService.RequestDeployGuardians(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	local now = os.clock()
	if now - (lastDeployAt[player.UserId] or -math.huge) < RaidConfig.GUARDIAN_DEPLOY_COOLDOWN_SECONDS then
		return { Success = false, Reason = "RateLimited" }
	end
	lastDeployAt[player.UserId] = now

	local raid = getLiveRaidFor(player)
	if not raid or raid.Finished then
		return { Success = false, Reason = "NoActiveRaid" }
	end
	if raid.DeployedBy[player.UserId] then
		return { Success = false, Reason = "AlreadyDeployed" }
	end

	local slots = RaidConfig.GetGuardianSlots(PlayerDataService.GetLevel(player))
	local deployed = 0
	for _, instanceId in ipairs(PlayerDataService.GetGuardianLoadout(player)) do
		if deployed >= slots then
			break
		end
		local instance = checkGuardianEligibility(player, instanceId)
		if instance then
			spawnGuardian(raid, player, instance)
			deployed += 1
		end
	end

	if deployed == 0 then
		-- Not marked as deployed: the player may fix the loadout and try again.
		return { Success = false, Reason = "NoGuardiansSelected" }
	end

	raid.DeployedBy[player.UserId] = true
	sendGuardianStatus(raid)
	return { Success = true, Count = deployed }
end

--- Loadout screen data: slots, saved loadout and every creature with its
--- guardian stats (or the reason it cannot be used).
function RaidService.GetGuardianLoadoutInfo(player: Player): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Slots = 1, SlotUnlockLevels = RaidConfig.GUARDIAN_SLOT_UNLOCK_LEVELS, Loadout = {}, Candidates = {}, Deployed = false, InRaid = false }
	end
	local level = PlayerDataService.GetLevel(player)
	local raid = getLiveRaidFor(player)

	local candidates = {}
	local inventory = table.clone(PlayerDataService.GetCreatureInventory(player))
	table.sort(inventory, function(a, b)
		local dpsA = (RaidConfig.GUARDIAN_RARITY_STATS[a.Rarity] or RaidConfig.GUARDIAN_RARITY_STATS.Common).Dps
		local dpsB = (RaidConfig.GUARDIAN_RARITY_STATS[b.Rarity] or RaidConfig.GUARDIAN_RARITY_STATS.Common).Dps
		if dpsA ~= dpsB then
			return dpsA > dpsB
		end
		return a.AcquiredAt > b.AcquiredAt
	end)
	for index = 1, math.min(#inventory, MAX_CANDIDATES_SENT) do
		local instance = inventory[index]
		local stats = RaidConfig.GetGuardianCombatStats(instance.Rarity, level)
		table.insert(candidates, {
			InstanceId = instance.InstanceId,
			CreatureId = instance.CreatureId,
			Rarity = instance.Rarity,
			Damage = math.floor(stats.Dps * 10 + 0.5) / 10, -- damage per second
			MaxHP = stats.MaxHP,
			Eligible = true,
		})
	end
	for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
		table.insert(candidates, {
			InstanceId = abducted.InstanceId,
			CreatureId = abducted.CreatureId,
			Rarity = abducted.Rarity,
			Damage = 0,
			MaxHP = 0,
			Eligible = false,
			Reason = "Abducted - rescue it first",
		})
	end

	return {
		Slots = RaidConfig.GetGuardianSlots(level),
		SlotUnlockLevels = RaidConfig.GUARDIAN_SLOT_UNLOCK_LEVELS,
		Loadout = PlayerDataService.GetGuardianLoadout(player),
		Candidates = candidates,
		Deployed = raid ~= nil and raid.DeployedBy[player.UserId] == true,
		InRaid = raid ~= nil,
	}
end

--- Saves a new loadout. `ids` comes from the client and is untrusted: capped,
--- type-checked, deduplicated, ownership/abduction-checked and trimmed to the
--- unlocked slot count before anything is persisted.
function RaidService.RequestSetGuardianLoadout(player: Player, ids: any): { [string]: any }
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded", Loadout = {}, Slots = 1 }
	end
	local slots = RaidConfig.GetGuardianSlots(PlayerDataService.GetLevel(player))
	local now = os.clock()
	if now - (lastLoadoutAt[player.UserId] or -math.huge) < RaidConfig.GUARDIAN_LOADOUT_COOLDOWN_SECONDS then
		return { Success = false, Reason = "RateLimited", Loadout = PlayerDataService.GetGuardianLoadout(player), Slots = slots }
	end
	lastLoadoutAt[player.UserId] = now

	if type(ids) ~= "table" then
		return { Success = false, Reason = "InvalidRequest", Loadout = PlayerDataService.GetGuardianLoadout(player), Slots = slots }
	end

	local cleaned: { string } = {}
	local seen: { [string]: boolean } = {}
	for index = 1, MAX_LOADOUT_PAYLOAD do
		local id = (ids :: { [any]: any })[index]
		if id == nil then
			break
		end
		if type(id) == "string" and #id <= 64 and not seen[id] then
			seen[id] = true
			if checkGuardianEligibility(player, id) and #cleaned < slots then
				table.insert(cleaned, id)
			end
		end
	end

	local stored = PlayerDataService.SetGuardianLoadout(player, cleaned)
	if not stored then
		return { Success = false, Reason = "PersistenceFailed", Loadout = PlayerDataService.GetGuardianLoadout(player), Slots = slots }
	end
	return { Success = true, Loadout = stored, Slots = slots }
end

-- // Co-op: join/leave ----------------------------------------------------------------

local function removeHelper(raid: RaidRuntime, helperPlayer: Player)
	raid.Helpers[helperPlayer.UserId] = nil
	if participantRaids[helperPlayer.UserId] == raid then
		participantRaids[helperPlayer.UserId] = nil
	end
	-- Their guardians leave with them.
	for index = #raid.Guardians, 1, -1 do
		local guardian = raid.Guardians[index]
		if guardian.OwnerUserId == helperPlayer.UserId then
			if guardian.Model and guardian.Model.Parent then
				guardian.Model:Destroy()
			end
			table.remove(raid.Guardians, index)
		end
	end
	raid.DeployedBy[helperPlayer.UserId] = nil
	sendGuardianStatus(raid)
end

--- A cluster mate asks to defend `ownerUserId`'s plot. Everything is checked
--- here: the owner has a running raid, the sender is in the owner's Reef
--- Cluster (ClusterService is the authority), capacity, not already busy.
function RaidService.RequestJoinCoopRaid(player: Player, ownerUserId: any): { [string]: any }
	if type(ownerUserId) ~= "number" or ownerUserId ~= ownerUserId or ownerUserId % 1 ~= 0 then
		return { Success = false, Reason = "InvalidRequest" }
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end
	local now = os.clock()
	if now - (lastJoinAt[player.UserId] or -math.huge) < RaidConfig.COOP_JOIN_COOLDOWN_SECONDS then
		return { Success = false, Reason = "RateLimited" }
	end
	lastJoinAt[player.UserId] = now

	local owner = Players:GetPlayerByUserId(ownerUserId)
	local raid = owner and activeRaids[owner.UserId]
	if not owner or not raid or raid.Finished then
		return { Success = false, Reason = "NoActiveRaid" }
	end
	if owner == player then
		return { Success = false, Reason = "OwnRaid" }
	end
	if getLiveRaidFor(player) then
		return { Success = false, Reason = "AlreadyInRaid" }
	end
	if not table.find(getClusterMates(owner), player) then
		return { Success = false, Reason = "NotInCluster" }
	end
	if countHelpers(raid) >= RaidConfig.COOP_MAX_PARTICIPANTS then
		return { Success = false, Reason = "RaidFull" }
	end

	local plot = PlotRegistry.GetPlot(owner)
	local helperIndex = countHelpers(raid)
	local angle = helperIndex * (math.pi / 2) + math.pi / 4
	if not plot or not teleportToPlot(player, plot, Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)) then
		return { Success = false, Reason = "CannotTeleport" }
	end

	raid.Helpers[player.UserId] = { Player = player, JoinedAt = os.clock() }
	participantRaids[player.UserId] = raid
	pushAbilityStatus(player)
	sendGuardianStatus(raid, player)

	local wave = RaidConfig.WAVES[raid.WaveIndex]
	return {
		Success = true,
		OwnerName = owner.DisplayName,
		WaveIndex = raid.WaveIndex,
		TotalWaves = #RaidConfig.WAVES,
		WaveEnemyCount = #raid.Enemies,
		IsBossWave = wave and wave.IsBossWave or false,
	}
end

--- Removes `player` from the co-op raid they joined. `teleportHome` is false
--- when the player is leaving the server anyway.
local function leaveCoopRaid(player: Player, reason: string, teleportHome: boolean)
	local raid = participantRaids[player.UserId]
	if not raid then
		return
	end
	removeHelper(raid, player)
	if player.Parent == Players then
		RaidRemotes.CoopRaidLeft:FireClient(player, { Reason = reason })
		RaidRemotes.GuardianStatus:FireClient(player, { Guardians = {} })
		pushAbilityStatus(player)
		if teleportHome then
			returnHelperHome(player)
		end
	end
end

function RaidService.RequestLeaveCoopRaid(player: Player)
	leaveCoopRaid(player, "Left", true)
end

local function runRaidTickLoop()
	while true do
		local deltaSeconds = RaidConfig.RAID_TICK_SECONDS
		task.wait(deltaSeconds)

		local now = os.clock() -- hochauflösend für Feuerraten-Cooldowns, siehe tickTowers-Kommentar
		for _, raid in pairs(activeRaids) do
			if not raid.Finished then
				tickEnemyMovement(raid, deltaSeconds)
				tickGuardians(raid, now, deltaSeconds)
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
			-- Gebäude-Upgrade-System: dieselbe Stufe-Anpassung wie im Live-Raid
			-- (collectTowerRuntimes), hier direkt aus placement.Level statt aus
			-- einem Modell-Attribut (siehe computeTowerDpsFromLayout-Kopfkommentar
			-- - läuft VOR PlacementService.RestorePlayerLayout, es gibt also noch
			-- gar keine Workspace-Modelle).
			local effectiveStats = applyTowerStageBonus(placement.BuildingId, stats, placement.Level)
			totalDps += effectiveStats.Damage * effectiveStats.FireRate
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

	if not raidsAllowedFor(player) then
		-- Neuling ohne Verteidigungsturm: verpasste Raids verfallen ersatzlos.
		PlayerDataService.SetNextRaidAt(player, now + RaidConfig.RAID_INTERVAL_SECONDS)
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

			-- GameEvents-Einhängepunkt (Auftrag Punkt 1), ein Fire je
			-- gewertetem verpasstem, aber gewonnenem Raid - identische
			-- Granularität wie oben.
			GameEvents.Fire(GameEvents.Events.RaidWon, player, { WavesCleared = 0, Offline = true })
		else
			local abducted = PlayerDataService.AbductRandomCreature(player)
			if abducted then
				table.insert(abductedCreatures, abducted)
				GameEvents.Fire(GameEvents.Events.RaidLost, player, {
					AbductedInstanceId = abducted.InstanceId,
					Offline = true,
				})
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

	-- Co-op helpers count as "in a raid" (wave bar, Depth Charge button).
	local liveRaid = raid or participantRaids[player.UserId]

	return {
		NextRaidAt = PlayerDataService.GetNextRaidAt(player),
		InRaid = liveRaid ~= nil,
		CoopHelper = raid == nil and liveRaid ~= nil,
		WaveIndex = liveRaid and liveRaid.WaveIndex or nil,
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

-- // EINHÄNGEPUNKT: Robux-"Depth Charge" (Entwicklerprodukt, purchasable ability) --
-- Applies heavy damage to every currently alive enemy in `player`'s OWN
-- active raid (charge-count/cooldown/"is there even an active raid on your
-- plot" gating is the CALLER's job, see AbilityService.RequestDepthCharge -
-- this function only knows raid combat, not purchasable-ability bookkeeping,
-- identical separation-of-concerns principle to
-- RaidService.RequestRescueWithToken vs. MonetizationService above).
-- Bosses (Model attribute "IsBoss", see applyEnemyVisual) take REDUCED
-- damage (a fraction of their OWN max HP) so a single charge never
-- trivializes a boss fight; regular enemies take `nonBossDamage` (a
-- deliberately huge flat value that always defeats them outright). Returns
-- (false, "NoActiveRaid") if there is no active, unfinished raid on the
-- player's plot, else (true, nil, raid.CenterPosition, enemiesHit) for the
-- caller to relay a client-side FX trigger.
function RaidService.ApplyDepthChargeDamage(player: Player, nonBossDamage: number, bossDamageFraction: number): (boolean, string?, Vector3?, number?)
	-- Co-op helpers may throw Depth Charges at the raid they joined.
	local raid = getLiveRaidFor(player)
	if not raid or raid.Finished then
		return false, "NoActiveRaid", nil, nil
	end

	local enemiesHit = 0
	for _, enemy in ipairs(raid.Enemies) do
		if enemy.Model.Parent then
			local isBoss = enemy.Model:GetAttribute("IsBoss") == true
			local damage = if isBoss then enemy.MaxHP * bossDamageFraction else nonBossDamage
			enemy.CurrentHP -= damage
			enemiesHit += 1

			fireRaidClients(raid, RaidRemotes.EnemyHit, {
				TowerPosition = raid.CenterPosition,
				EnemyPosition = enemy.Position,
			})
		end
	end

	removeDeadEnemies(raid)
	-- May advance the wave or finish the raid outright if this cleared all
	-- remaining enemies - identical progression path as regular tower kills.
	tickWaveProgress(raid)

	return true, nil, raid.CenterPosition, enemiesHit
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
	-- A helper leaving the server just drops out of the raid they joined.
	leaveCoopRaid(player, "Left", false)

	local raid = activeRaids[player.UserId]
	if raid then
		raid.Finished = true
		-- The owner is gone: send the helpers home, nobody gets rewards or penalties.
		for userId, helper in pairs(raid.Helpers) do
			participantRaids[userId] = nil
			if helper.Player.Parent == Players then
				RaidRemotes.CoopRaidLeft:FireClient(helper.Player, { Reason = "OwnerLeft" })
				RaidRemotes.GuardianStatus:FireClient(helper.Player, { Guardians = {} })
				pushAbilityStatus(helper.Player)
				returnHelperHome(helper.Player)
			end
		end
		raid.Helpers = {}
		destroyRaidWorkspaceState(raid)
		activeRaids[player.UserId] = nil
	end

	lastDeployAt[player.UserId] = nil
	lastLoadoutAt[player.UserId] = nil
	lastJoinAt[player.UserId] = nil
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
