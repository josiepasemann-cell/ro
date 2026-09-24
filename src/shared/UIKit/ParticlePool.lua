--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.ParticlePool
	Zuständigkeit:
		Objekt-Pool für die kleinen Frame-"Partikel", die beim
		Klick-Burst der Button-Factory nach außen fliegen. Vermeidet
		ständiges Instance.new()/Destroy() bei häufigen Klicks (Performance
		+ keine GC-Spitzen), indem fertige Frames wiederverwendet werden.

	Rojo-Einhängepunkt:
		src/shared/UIKit/ParticlePool.lua -> ReplicatedStorage.UIKit.ParticlePool
]]

local POOL_MAX_SIZE = 64

local ParticlePool = {}

-- Partikel sind einfache, abgerundete Frames statt ImageLabel mit
-- externer Textur-Asset-ID - garantiert sichtbares Rendering ohne
-- Abhängigkeit von einer (potenziell ungültigen) Bild-Asset-Referenz.
local freeList: { Frame } = {}

local function createParticle(): Frame
	local particle = Instance.new("Frame")
	particle.Name = "FXParticle"
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.BorderSizePixel = 0
	particle.Size = UDim2.fromOffset(8, 8)
	particle.Visible = false
	particle.ZIndex = 50
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = particle
	return particle
end

-- Holt ein freies Partikel-Frame aus dem Pool (oder erzeugt ein neues,
-- falls der Pool leer ist), parentet es und macht es sichtbar.
function ParticlePool.Acquire(parent: Instance): Frame
	local particle = table.remove(freeList)
	if not particle then
		particle = createParticle()
	end
	particle.Visible = true
	particle.BackgroundTransparency = 0
	particle.Rotation = 0
	particle.Parent = parent
	return particle
end

-- Gibt ein Partikel-Frame an den Pool zurück statt es zu zerstören.
function ParticlePool.Release(particle: Frame)
	particle.Visible = false
	particle.Parent = nil
	if #freeList < POOL_MAX_SIZE then
		table.insert(freeList, particle)
	else
		particle:Destroy()
	end
end

return ParticlePool
