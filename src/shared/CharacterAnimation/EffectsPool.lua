--[[
	EffectsPool.lua
	Ort: ReplicatedStorage.CharacterAnimation.EffectsPool

	Client-seitiges, gepooltes Partikelsystem für Schritt-/Landungs-Staub.
	Es werden keine Instanzen pro Emit erzeugt/zerstört (wichtig auf Mobile) -
	stattdessen wird ein fester Pool aus unsichtbaren, anker­baren Parts mit
	ParticleEmitter wiederverwendet (round-robin).

	Nur für den Client gedacht (require nur aus CharacterAnimator.client.lua).
]]

local AnimationConfig = require(script.Parent:WaitForChild("AnimationConfig"))

export type Preset = "Footstep" | "Landing"

local EffectsPool = {}
EffectsPool.__index = EffectsPool

export type EffectsPoolT = typeof(setmetatable(
	{} :: {
		_parts: { BasePart },
		_emitters: { ParticleEmitter },
		_cursor: number,
		_folder: Folder,
	},
	EffectsPool
))

local PRESETS: { [Preset]: { [string]: any } } = {
	Footstep = {
		Color = ColorSequence.new(Color3.fromRGB(196, 186, 158)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1.2),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(35, 35),
		Rate = 0,
		Count = 6,
	},
	Landing = {
		Color = ColorSequence.new(Color3.fromRGB(210, 200, 175)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 2.4),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.4, 0.85),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(60, 60),
		Rate = 0,
		Count = 14,
	},
}

function EffectsPool.new(): EffectsPoolT
	local self = setmetatable({}, EffectsPool) :: any

	local folder = Instance.new("Folder")
	folder.Name = "CharacterAnimationFX"
	folder.Parent = workspace

	self._parts = {}
	self._emitters = {}
	self._cursor = 1
	self._folder = folder

	for i = 1, AnimationConfig.FXPoolSize do
		local part = Instance.new("Part")
		part.Name = "FXPoint" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Massless = true
		part.Parent = folder

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds" -- Platzhalter: eigene Textur-ID in AnimationConfig/hier ersetzbar
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.4, 0.6)
		emitter.Acceleration = Vector3.new(0, -12, 0)
		emitter.LightEmission = 0
		emitter.Parent = part

		self._parts[i] = part
		self._emitters[i] = emitter
	end

	return self
end

function EffectsPool.EmitAt(self: EffectsPoolT, position: Vector3, preset: Preset)
	local cfg = PRESETS[preset]
	if not cfg then
		return
	end

	local index = self._cursor
	self._cursor = (self._cursor % #self._parts) + 1

	local part = self._parts[index]
	local emitter = self._emitters[index]

	part.CFrame = CFrame.new(position)
	emitter.Color = cfg.Color
	emitter.Size = cfg.Size
	emitter.Transparency = cfg.Transparency
	emitter.Lifetime = cfg.Lifetime
	emitter.Speed = cfg.Speed
	emitter.SpreadAngle = cfg.SpreadAngle

	emitter:Emit(cfg.Count)
end

function EffectsPool.Destroy(self: EffectsPoolT)
	self._folder:Destroy()
	table.clear(self._parts)
	table.clear(self._emitters)
end

return EffectsPool
