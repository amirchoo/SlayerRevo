--!strict
-- Total armor protection, shown as a shield and a percentage just left of the health bar
-- while any armor is worn. Display only: reads the "Protection" player attribute the server
-- sets (see ArmorService). Armor is put on and taken off in the backpack (see Backpack).

local Players = game:GetService("Players")

local HudStyle = require(script.Parent.HudStyle)

local player = Players.LocalPlayer

local ArmorReadout = {}

function ArmorReadout.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArmorReadout"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Just left of the health bar (420 wide, centered, bottom at -88).
	local shield = HudStyle.caption(gui, "", 18)
	shield.AnchorPoint = Vector2.new(1, 1)
	shield.Position = UDim2.new(0.5, -218, 1, -88)
	shield.Size = UDim2.fromOffset(70, 28)
	shield.TextXAlignment = Enum.TextXAlignment.Right

	local function update()
		local protection = player:GetAttribute("Protection")
		local total = if typeof(protection) == "number" then protection else 0
		shield.Text = `🛡 {math.round(total * 100)}%`
		shield.Visible = total > 0
	end
	player:GetAttributeChangedSignal("Protection"):Connect(update)
	update()
end

return ArmorReadout
