--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.CountUp
	Zuständigkeit:
		Zahlen-Hochzähl-Animation für Währungsanzeigen (Tide Coins, XP, ...).
		Tweent einen internen NumberValue-Proxy und aktualisiert dabei live
		den Text eines TextLabels, mit optionalem Zahlenformat (z. B.
		Tausendertrennzeichen).

	Rojo-Einhängepunkt:
		src/shared/UIKit/CountUp.lua -> ReplicatedStorage.UIKit.CountUp
]]

local TweenService = game:GetService("TweenService")

local CountUp = {}

-- Formatiert eine Zahl mit deutschem Tausenderpunkt (z. B. 12345 -> "12.345").
local function defaultFormat(value: number): string
	local rounded = math.floor(value + 0.5)
	local isNegative = rounded < 0
	local digits = tostring(math.abs(rounded))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	grouped = grouped:gsub("^%.", "")
	return (isNegative and "-" or "") .. grouped
end

CountUp.DefaultFormat = defaultFormat

-- Animiert label.Text von `fromValue` nach `toValue` über `duration`
-- Sekunden. `formatFn` erhält den aktuellen Zwischenwert und liefert den
-- anzuzeigenden String (Default: Tausenderpunkt-Formatierung, gerundet).
-- Gibt die Tween-Instanz zurück, falls der Aufrufer sie abbrechen möchte.
function CountUp.Animate(
	label: TextLabel,
	fromValue: number,
	toValue: number,
	duration: number?,
	formatFn: ((number) -> string)?
): Tween
	local format = formatFn or defaultFormat
	local proxy = Instance.new("NumberValue")
	proxy.Value = fromValue
	label.Text = format(fromValue)

	local connection: RBXScriptConnection
	connection = proxy.Changed:Connect(function(value: number)
		label.Text = format(value)
	end)

	local tween = TweenService:Create(
		proxy,
		TweenInfo.new(duration or 0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Value = toValue }
	)
	tween:Play()
	tween.Completed:Connect(function()
		label.Text = format(toValue)
		connection:Disconnect()
		proxy:Destroy()
	end)
	return tween
end

return CountUp
