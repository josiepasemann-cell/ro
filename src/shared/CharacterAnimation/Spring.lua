--!strict
--[[
	Spring.lua
	Ort: ReplicatedStorage.CharacterAnimation.Spring (via Rojo aus src/shared/CharacterAnimation)

	Generische, kritisch gedämpfte Feder für weiches Blending von Zahlen und
	Vector3-Werten (Gewichte, Lean, Squash/Stretch, Bob, ...).
	Nutzt semi-implizite Euler-Integration, stabil bei variablen dt.
]]

export type Spring = {
	Position: number,
	Velocity: number,
	Target: number,
	Speed: number,
	Damping: number,
	SetTarget: (self: Spring, target: number) -> (),
	Update: (self: Spring, dt: number) -> number,
	Snap: (self: Spring, value: number) -> (),
}

local Spring = {}
Spring.__index = Spring

-- speed: wie "steif" die Feder ist (höher = schneller); damping: 1 = kritisch gedämpft (kein Überschwingen)
function Spring.new(initial: number?, speed: number?, damping: number?): Spring
	local self = setmetatable({}, Spring) :: any
	self.Position = initial or 0
	self.Velocity = 0
	self.Target = initial or 0
	self.Speed = speed or 12
	self.Damping = damping or 1
	return self
end

function Spring.SetTarget(self: Spring, target: number)
	self.Target = target
end

function Spring.Snap(self: Spring, value: number)
	self.Position = value
	self.Target = value
	self.Velocity = 0
end

function Spring.Update(self: Spring, dt: number): number
	-- Clamp dt gegen Spikes (Teleports/Lag), verhindert Instabilität der Integration.
	if dt > 0.25 then
		dt = 0.25
	end

	local speed = self.Speed
	local damping = self.Damping

	local displacement = self.Position - self.Target
	local springForce = -speed * speed * displacement
	local dampingForce = -2 * speed * damping * self.Velocity

	self.Velocity += (springForce + dampingForce) * dt
	self.Position += self.Velocity * dt

	return self.Position
end

return Spring
