--[[
	CharacterSetup.server.lua
	Ort: ServerScriptService (via Rojo aus src/server)

	Serverseitige Grundlage für das prozedurale Animationssystem:
	- Erzwingt R15-Rigs (Hauptziel des Animators; R6 wird vom Client zwar
	  vereinfacht unterstützt, aber R15 liefert die beste Qualität).
	- Entfernt das automatisch von Roblox eingefügte "Animate"-LocalScript,
	  damit es nicht mit den client-seitig gesetzten Motor6D.C0-Werten
	  konkurriert (sonst "kämpfen" zwei Systeme um dieselben Gelenke).
	- Legt das SprintRemote unter ReplicatedStorage.CharacterAnimation an
	  und validiert Sprint-Anfragen serverseitig (kein Vertrauen in Client-
	  Werte; WalkSpeed wird ausschließlich server-seitig gesetzt und
	  gedeckelt).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAnimationFolder = ReplicatedStorage:WaitForChild("CharacterAnimation")

-- Alle neu erstellten Avatare als R15 laden (best-effort; falls die API in
-- der jeweiligen Roblox-Version nicht existiert, wird es sauber übersprungen
-- und der Client fällt für betroffene Charaktere auf die vereinfachte
-- R6-Animation zurück, siehe RigJoints.lua / docs/animations.md).
pcall(function()
	(Players :: any):SetDefaultRigType(Enum.HumanoidRigType.R15)
end)

-- ===== SprintRemote =====
local sprintRemote = CharacterAnimationFolder:FindFirstChild("SprintRemote")
if not sprintRemote then
	sprintRemote = Instance.new("RemoteEvent")
	sprintRemote.Name = "SprintRemote"
	sprintRemote.Parent = CharacterAnimationFolder
end

local BASE_WALK_SPEED = 16
local SPRINT_SPEED = 26
local SPRINT_SPEED_CAP = 34 -- harte Obergrenze, auch falls Buff-Systeme künftig BASE_WALK_SPEED erhöhen
local SPRINT_REQUEST_COOLDOWN = 0.15

local lastRequestAt: { [Player]: number } = {}

local function disableDefaultAnimateScript(character: Model)
	-- "Animate" wird von Roblox automatisch beim Avatar-Laden eingefügt.
	-- Es lädt Standard-Animationen über den Animator, was sich mit unseren
	-- direkt gesetzten Motor6D.C0-Werten beißen würde.
	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript:Destroy()
	end
end

local function setupHumanoid(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = BASE_WALK_SPEED
	humanoid:SetAttribute("Sprinting", false)
	humanoid:SetAttribute("BaseWalkSpeed", BASE_WALK_SPEED)
	humanoid:SetAttribute("SprintSpeed", SPRINT_SPEED)
end

local function onCharacterAdded(player: Player, character: Model)
	disableDefaultAnimateScript(character)
	setupHumanoid(character)
end

local function onPlayerAdded(player: Player)
	lastRequestAt[player] = 0
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)

sprintRemote.OnServerEvent:Connect(function(player: Player, wantsSprintRaw: any)
	if typeof(wantsSprintRaw) ~= "boolean" then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player] or 0
	if now - last < SPRINT_REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Nur ein Boolean wird vom Client entgegengenommen; die tatsächliche
	-- Geschwindigkeit wird ausschließlich hier server-seitig bestimmt.
	local targetSpeed = wantsSprintRaw and SPRINT_SPEED or BASE_WALK_SPEED
	humanoid.WalkSpeed = math.min(targetSpeed, SPRINT_SPEED_CAP)
	humanoid:SetAttribute("Sprinting", wantsSprintRaw)
end)
