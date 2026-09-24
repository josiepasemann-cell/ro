--[[
	CharacterAnimator.client.lua
	Ort: StarterPlayer.StarterPlayerScripts (via Rojo aus src/client)

	Orchestriert das prozedurale Animationssystem für "Abyssara – Deep Tide
	Tycoon": erstellt/entsorgt pro sichtbarem Spieler-Charakter einen
	ProceduralAnimator (ReplicatedStorage.CharacterAnimation), aktualisiert
	ihn jeden Frame mit Distanz-LOD, und kümmert sich um Sprint-Eingaben
	(Tastatur, Touch-Button, Gamepad) inkl. serverseitiger Bestätigung über
	SprintRemote.

	Jeder Client animiert JEDEN Charakter, den er sieht - Motor6D.Transform
	repliziert nicht über das Netzwerk, daher ist das die einzige performante
	Möglichkeit, Bewegung ohne hochgeladene Animation-Assets synchron
	aussehen zu lassen (siehe docs/animations.md).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAnimationFolder = ReplicatedStorage:WaitForChild("CharacterAnimation")
local ProceduralAnimator = require(CharacterAnimationFolder:WaitForChild("ProceduralAnimator"))
local AnimationConfig = require(CharacterAnimationFolder:WaitForChild("AnimationConfig"))
local EffectsPool = require(CharacterAnimationFolder:WaitForChild("EffectsPool"))

local localPlayer = Players.LocalPlayer

-- SprintRemote wird serverseitig unter ReplicatedStorage.CharacterAnimation angelegt (CharacterSetup.server.lua)
local sprintRemote = CharacterAnimationFolder:WaitForChild("SprintRemote") :: RemoteEvent

local effectsPool = EffectsPool.new()

type Entry = {
	Animator: ProceduralAnimator.ProceduralAnimatorT,
	Connections: { RBXScriptConnection },
}

local activeEntries: { [Model]: Entry } = {}
local lodTimer = 0
local lodUpdateInterval = 0.25

local function getCameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	return Vector3.new()
end

local function computeLOD(distance: number): ProceduralAnimator.LODLevel
	if distance <= AnimationConfig.LODFullDistance then
		return "Full"
	elseif distance <= AnimationConfig.LODReducedDistance then
		return "Reduced"
	end
	return "Off"
end

local function cleanupCharacter(character: Model)
	local entry = activeEntries[character]
	if not entry then
		return
	end
	for _, conn in ipairs(entry.Connections) do
		conn:Disconnect()
	end
	entry.Animator:Destroy()
	activeEntries[character] = nil
end

local function tryCreateAnimator(character: Model): boolean
	if activeEntries[character] then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return false
	end

	local animator = ProceduralAnimator.new(character, effectsPool)
	if not animator then
		-- Rig noch nicht vollständig repliziert; beim nächsten DescendantAdded erneut versuchen.
		return false
	end

	local connections: { RBXScriptConnection } = {}

	table.insert(
		connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				cleanupCharacter(character)
			end
		end)
	)

	table.insert(
		connections,
		humanoid.Died:Connect(function()
			cleanupCharacter(character)
		end)
	)

	activeEntries[character] = {
		Animator = animator,
		Connections = connections,
	}
	return true
end

local function onCharacterAdded(character: Model)
	-- Falls Rig-Teile asynchron nachladen (z.B. Custom-Avatare), mehrfach versuchen.
	if tryCreateAnimator(character) then
		return
	end

	local attempts = 0
	local conn: RBXScriptConnection
	conn = character.DescendantAdded:Connect(function()
		if activeEntries[character] then
			conn:Disconnect()
			return
		end
		attempts += 1
		tryCreateAnimator(character)
		if activeEntries[character] or attempts > 200 then
			conn:Disconnect()
		end
	end)
end

local function onCharacterRemoving(character: Model)
	cleanupCharacter(character)
end

local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end
Players.PlayerAdded:Connect(hookPlayer)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		cleanupCharacter(player.Character)
	end
end)

-- ===== Haupt-Update-Loop (physiksynchron, läuft VOR der Simulation) =====
RunService.PreSimulation:Connect(function(dt: number)
	lodTimer += dt
	local shouldRecomputeLOD = lodTimer >= lodUpdateInterval
	if shouldRecomputeLOD then
		lodTimer = 0
	end

	local camPos = shouldRecomputeLOD and getCameraPosition() or nil

	for character, entry in pairs(activeEntries) do
		if not character.Parent then
			cleanupCharacter(character)
			continue
		end

		if shouldRecomputeLOD and camPos then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local distance = (root.Position - camPos).Magnitude
				entry.Animator:SetLOD(computeLOD(distance))
			end
		end

		entry.Animator:Update(dt)
	end
end)

-- ===== Sprint-Eingabe: Tastatur (Shift), Touch-Button, Gamepad (L3) =====
local sprintActive = false

local function setSprint(active: boolean)
	if sprintActive == active then
		return
	end
	sprintActive = active

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Lokal sofort als Attribut setzen für responsives Gefühl der eigenen Animation;
		-- die tatsächliche WalkSpeed-Änderung erfolgt serverseitig-validiert.
		humanoid:SetAttribute("Sprinting", active)
	end

	sprintRemote:FireServer(active)
end

local function handleSprintAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		setSprint(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprint(false)
	end
	return Enum.ContextActionResult.Pass
end

-- ContextActionService erzeugt automatisch einen Touch-Button auf Mobile (3. Argument = true)
-- und bindet gleichzeitig Tastatur (LeftShift) sowie Gamepad (ButtonL3).
ContextActionService:BindAction(
	"AbyssaraSprint",
	handleSprintAction,
	true,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.ButtonL3
)
ContextActionService:SetTitle("AbyssaraSprint", "Sprint")
ContextActionService:SetPosition("AbyssaraSprint", UDim2.new(0.75, 0, 0.35, 0))

-- Sicherheitsnetz: falls das Fenster den Fokus verliert während Shift gehalten wird
UserInputService.WindowFocusReleased:Connect(function()
	setSprint(false)
end)

localPlayer.CharacterAdded:Connect(function()
	sprintActive = false
end)
