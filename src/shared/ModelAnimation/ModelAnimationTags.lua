--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: ModelAnimationTags
	Zuständigkeit:
		Zentrale `CollectionService`-Tag-Namen + Attribut-Namen für das
		gemeinsame client-seitige Bewegungs-/Idle-Animationssystem
		(siehe docs/animation-system.md). EIN Ort für diese Strings, damit
		Server-Publisher (CreatureDisplayService, RaidService) und der
		Client-Renderer (src/client/ModelAnimator.client.lua) nicht per
		Tippfehler auseinanderlaufen können.

	Rojo-Einhängepunkt:
		src/shared/ModelAnimation/ModelAnimationTags.lua ->
		ReplicatedStorage.ModelAnimation.ModelAnimationTags
]]

local ModelAnimationTags = {}

-- // CollectionService-Tags (Client-Discovery, siehe ModelAnimator.client.lua) --

-- Servergesteuerte, frei wandernde Plot-Anzeige-Kreaturen (CreatureDisplayService).
ModelAnimationTags.DISPLAY_CREATURE = "DisplayCreatureWander"

-- Servergesteuerte Raid-Gegner-Bewegung (RaidService).
ModelAnimationTags.RAID_ENEMY = "RaidEnemyMotion"

-- Platzierte Kampf-Türme (AnglerfishTower/CoralBarrier/ElectricEelTrap) -
-- rein kosmetischer Idle-Glow-Puls + Muzzle-Flash/Recoil bei Treffern,
-- unabhängig vom Raid-Status getaggt (idle-pulst auch außerhalb eines Raids).
ModelAnimationTags.RAID_TOWER = "RaidTower"

-- Weltpickups (Glow Spore/Toxic Spore/Frozen Spore/Sunken Chest, siehe
-- PickupSpawner) - rein kosmetischer Idle-Bob/Spin/Puls der DEKORATIVEN
-- Kind-Parts (NICHT des PrimaryPart "Body", der das serverseitig
-- angebrachte ProximityPrompt trägt - siehe IdleSway.ApplyStationary /
-- docs/animation-system.md "ProximityPrompt bleibt ortsfest").
ModelAnimationTags.PICKUP_IDLE = "PickupIdle"

-- Platzierte Gebäude (PlacementService) - Pop-in-Skalierung beim Platzieren,
-- Flash beim Upgrade-Modell-Tausch, Schrumpfen beim Verkauf.
ModelAnimationTags.BUILDING_PLACED = "BuildingPlacedAnim"

-- Mystery-Eggs an der Hub-Station (GachaServer) - sanftes Idle-Wobble.
ModelAnimationTags.HUB_EGG = "HubEggIdle"

-- // Attribut-Namen (auf dem jeweiligen Model gesetzt) -------------------------

-- Gemeinsam von DISPLAY_CREATURE + RAID_ENEMY: die aktuelle serverseitige
-- "Ziel"-Weltposition (Vector3, OHNE Bob/Idle-Layer - der Client rechnet
-- Idle-Bewegung on top). Der Client interpoliert (Chase/Lerp) dorthin statt
-- den Wert 1:1 zu übernehmen - siehe docs/animation-system.md.
ModelAnimationTags.ATTR_TARGET_POSITION = "TargetPosition"

-- RAID_ENEMY: Weltposition des Raid-Zentrums (einmalig pro Raid gesetzt) -
-- Blickrichtungs-Hinweis für den Client (siehe ModelAnimator).
ModelAnimationTags.ATTR_CENTER_POSITION = "CenterPosition"

-- RAID_ENEMY: Server-Zeitstempel (workspace:GetServerTimeNow()) des Spawns -
-- treibt die client-seitige Spawn-Einblend-/Einwachs-Animation.
ModelAnimationTags.ATTR_SPAWNED_AT = "SpawnedAt"

-- RAID_ENEMY: Server-Zeitstempel, ab dem das Modell "stirbt"/den Mittelpunkt
-- erreicht hat (nil/nicht gesetzt = lebt noch) - treibt die client-seitige
-- Auflöse-/Schrumpf-Animation, bevor der Server das Modell tatsächlich
-- zerstört (siehe RaidService.DEATH_FX_SECONDS).
ModelAnimationTags.ATTR_DYING_AT = "DyingAt"

-- RAID_ENEMY: true während der Gegner innerhalb einer CoralBarrier-
-- Verlangsamungszone steht (siehe RaidService.computeSpeedMultiplier) -
-- treibt eine sichtbar langsamere/"eingefrorenere" Idle-Wobble-Animation.
ModelAnimationTags.ATTR_SLOWED = "Slowed"

-- PICKUP_IDLE (Sunken Chest, Spore-Magnet-Auto-Collect): Server-Zeitstempel,
-- ab dem dieses Pickup bereits eingesammelt wurde (Belohnung schon
-- gewertet) - treibt die client-seitige "fliegt zum Sammler + schrumpft"-
-- Animation, bevor der Server das Modell nach HeldItemConfig.
-- CollectFxSeconds tatsächlich zerstört (siehe PickupSpawner/AbilityService
-- scheduleCollectDestroy).
ModelAnimationTags.ATTR_COLLECTED_AT = "CollectedAt"

-- PICKUP_IDLE: UserId des Spielers, zu dem das Pickup während der
-- Collect-Animation hinfliegt (der Client folgt live dessen Charakter-
-- Position, falls dieser sich währenddessen weiterbewegt).
ModelAnimationTags.ATTR_COLLECTOR_USER_ID = "CollectorUserId"

-- BUILDING_PLACED: Server-Zeitstempel des Platzierens/Upgrades - treibt die
-- client-seitige Pop-in-Skalierung bzw. den Upgrade-Flash.
ModelAnimationTags.ATTR_PLACED_AT = "PlacedAt"

-- BUILDING_PLACED: Server-Zeitstempel, ab dem das Gebäude verkauft wurde
-- (Modell soll noch kurz sichtbar schrumpfen, bevor der Server es nach
-- kurzer Karenzzeit zerstört) - identisches Karenzzeit-Prinzip wie
-- ATTR_DYING_AT/ATTR_COLLECTED_AT.
ModelAnimationTags.ATTR_SOLD_AT = "SoldAt"

return ModelAnimationTags
