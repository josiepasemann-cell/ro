--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.ConfirmDialog
	Zuständigkeit:
		Bestätigungsdialog (z. B. "Wirklich für 500 Tide Coins kaufen?"),
		gebaut auf UIKit.Panel + UIKit.Button. Nutzt Layout.ResponsiveRow
		für die Bestätigen/Abbrechen-Buttons, damit sie auf Phone
		übereinander (volle Breite) statt nebeneinander erscheinen.

	Rojo-Einhängepunkt:
		src/shared/UIKit/ConfirmDialog.lua -> ReplicatedStorage.UIKit.ConfirmDialog
]]

local Theme = require(script.Parent:WaitForChild("Theme"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local Button = require(script.Parent:WaitForChild("Button"))
local Layout = require(script.Parent:WaitForChild("Layout"))

export type ConfirmDialogProps = {
	Title: string,
	Message: string,
	ConfirmText: string?,
	CancelText: string?,
	Danger: boolean?,
	OnConfirm: (() -> ())?,
	OnCancel: (() -> ())?,
}

local ConfirmDialog = {}

-- Baut, öffnet und zeigt einen Bestätigungsdialog an. Der Dialog zerstört
-- sich nach einer Entscheidung automatisch selbst.
function ConfirmDialog.Show(props: ConfirmDialogProps)
	local suppressCancel = false

	local panel = Panel.new({
		Title = props.Title,
		Closable = true,
		CenteredSize = UDim2.fromOffset(460, 260),
		OnClose = function()
			if not suppressCancel and props.OnCancel then
				props.OnCancel()
			end
		end,
	})

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.BackgroundTransparency = 1
	message.Size = UDim2.new(1, 0, 0, 90)
	message.Font = Theme.Font.Body
	message.TextColor3 = Theme.Text.Secondary
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top
	message.TextScaled = true
	message.Text = props.Message
	message.Parent = panel.Content
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 14
	constraint.MaxTextSize = 20
	constraint.Parent = message

	local buttonHost = Instance.new("Frame")
	buttonHost.Name = "Buttons"
	buttonHost.BackgroundTransparency = 1
	buttonHost.Size = UDim2.new(1, 0, 0, 100)
	buttonHost.Position = UDim2.new(0, 0, 1, -100)
	buttonHost.Parent = panel.Content

	local row = Layout.ResponsiveRow({
		Parent = buttonHost,
		Padding = 12,
	})
	row.Frame.Size = UDim2.fromScale(1, 1)

	local cancelButton = Button.new({
		Parent = row.Frame,
		Text = props.CancelText or "Abbrechen",
		Variant = "Ghost",
		Size = UDim2.new(0.48, 0, 0, 48),
	})

	local confirmButton = Button.new({
		Parent = row.Frame,
		Text = props.ConfirmText or "Bestätigen",
		Variant = if props.Danger then "Danger" else "Success",
		Important = true,
		Size = UDim2.new(0.48, 0, 0, 48),
	})

	local function teardown()
		row:Destroy()
		cancelButton:Destroy()
		confirmButton:Destroy()
		panel:Destroy()
	end

	panel.Closed:Connect(teardown)

	cancelButton.Clicked:Connect(function()
		panel:Close()
	end)

	confirmButton.Clicked:Connect(function()
		suppressCancel = true
		if props.OnConfirm then
			props.OnConfirm()
		end
		panel:Close()
	end)

	panel:Open()
end

return ConfirmDialog
