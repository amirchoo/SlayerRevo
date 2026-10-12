--!strict
-- Combat buttons for touch screens, around Roblox's jump button (bottom right):
--   Attack (big, left of jump): tap for a combo swing, hold for the heavy attack (the bow:
--     hold to draw, let go to fire)
--   Block (above Attack): hold to guard
--   Dash (above jump): tap to dash
--   Lock (left of Block): tap to lock onto an enemy, again to let go
-- They feed CombatInput, exactly like the mouse and keyboard do. Shown on touch screens, and
-- as soon as a touch is seen (some devices, and Studio's emulator, only report touch once
-- it's used); sized and placed like Roblox's own jump button (small on phones, bigger on
-- tablets).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CombatInput = require(script.Parent.CombatInput)
local HudStyle = require(script.Parent.HudStyle)

-- Where each button's centre goes, from the bottom-right corner, on a phone (scaled up on
-- bigger screens), and its size. Roblox's jump button is centred at about (-60, -55).
local LAYOUT: { { action: CombatInput.Action, icon: string, color: Color3, center: Vector2, size: number } } = {
	{ action = "Attack", icon = "Attack", color = Color3.fromRGB(220, 90, 70), center = Vector2.new(-160, -55), size = 78 },
	{ action = "Block", icon = "Shield", color = Color3.fromRGB(80, 150, 255), center = Vector2.new(-158, -150), size = 58 },
	{ action = "Dash", icon = "Dash", color = Color3.fromRGB(255, 200, 60), center = Vector2.new(-60, -145), size = 58 },
	{ action = "Lock", icon = "Target", color = Color3.fromRGB(150, 110, 220), center = Vector2.new(-240, -125), size = 48 },
}
local TABLET_SCALE = 1.6 -- Roblox's jump button grows on screens over 500 px on their short side
local PRESSED_TRANSPARENCY = 0.35

local player = Players.LocalPlayer

local TouchControls = {}

function TouchControls.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.Enabled = UserInputService.TouchEnabled
	gui.Parent = player:WaitForChild("PlayerGui")
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.Touch then
			gui.Enabled = true
		end
	end)

	local buttons: { { frame: Frame, entry: typeof(LAYOUT[1]) } } = {}
	for _, entry in LAYOUT do
		local badge = HudStyle.badge(gui, entry.size, entry.color, entry.icon)
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.BackgroundTransparency = 0.15
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 3
		button.Parent = badge
		table.insert(buttons, { frame = badge, entry = entry })

		-- Track the finger that pressed it, so sliding off and letting go anywhere releases it.
		local activeInput: InputObject? = nil
		button.InputBegan:Connect(function(input)
			local isPress = input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
			if not isPress or activeInput then
				return
			end
			HudStyle.pop(badge, 0.85)
			if entry.action == "Dash" or entry.action == "Lock" then
				CombatInput.press(entry.action) -- taps, not holds
				return
			end
			activeInput = input
			badge.BackgroundTransparency = PRESSED_TRANSPARENCY
			CombatInput.press(entry.action)
		end)
		UserInputService.InputEnded:Connect(function(input)
			if activeInput and input == activeInput then
				activeInput = nil
				badge.BackgroundTransparency = 0.15
				CombatInput.release(entry.action)
			end
		end)
	end

	-- Size and place them like the jump button: bigger on tablets.
	local function layout()
		local screen = workspace.CurrentCamera.ViewportSize
		local scale = if math.min(screen.X, screen.Y) > 500 then TABLET_SCALE else 1
		for _, item in buttons do
			local entry = item.entry
			item.frame.Size = UDim2.fromOffset(entry.size * scale, entry.size * scale)
			item.frame.Position = UDim2.new(1, entry.center.X * scale, 1, entry.center.Y * scale)
		end
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	layout()
end

return TouchControls
