--!strict
-- Ammo counter in the top-right corner, shown only while you're holding a ranged weapon:
-- arrows for the bow, bolts for the crossbow, shells for the blunderbuss. Display only: reads the ammo attributes the
-- server keeps on the player (Arrows/MaxArrows, Bolts/MaxBolts, Shells/MaxShells).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HudStyle = require(script.Parent.HudStyle)

type Ammo = { count: string, max: string, title: string }

-- Per weapon (by ToolName): which attributes hold its ammo, and what it's called.
local AMMO: { [string]: Ammo } = {
	[CombatConfig.Bow.ToolName] = { count = "Arrows", max = "MaxArrows", title = "ARROWS" },
	[CombatConfig.Crossbow.ToolName] = { count = "Bolts", max = "MaxBolts", title = "BOLTS" },
	[CombatConfig.Blunderbuss.ToolName] = { count = "Shells", max = "MaxShells", title = "SHELLS" },
}

local NORMAL_COLOR = Color3.new(1, 1, 1)
local LOW_COLOR = Color3.fromRGB(255, 200, 90)
local EMPTY_COLOR = Color3.fromRGB(235, 90, 80)
local LOW_THRESHOLD = 0.25

local player = Players.LocalPlayer

local AmmoDisplay = {}

local function createGui(): (Frame, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "AmmoDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local corner = Vector2.new(1, 0) -- top right
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = corner
	panel.Position = UDim2.new(1, -20, 0, 10)
	panel.Visible = false
	panel.Size = UDim2.fromOffset(190, 64)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.Parent = HudStyle.holder(gui, corner)
	Instance.new("UICorner").Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextColor3 = Color3.fromRGB(190, 190, 190)
	title.TextXAlignment = Enum.TextXAlignment.Right
	title.Parent = panel

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.fromOffset(12, 22)
	count.Size = UDim2.new(1, -24, 0, 36)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextSize = 30
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = panel

	return panel, title, count
end

function AmmoDisplay.start()
	local panel, title, count = createGui()

	local shown: Ammo? = nil -- the ammo of the weapon in hand, if it has any

	local function update()
		if not shown then
			return
		end
		local ammo = player:GetAttribute(shown.count)
		local maxAmmo = player:GetAttribute(shown.max)
		if typeof(ammo) ~= "number" or typeof(maxAmmo) ~= "number" or maxAmmo <= 0 then
			count.Text = "-- / --"
			title.Text = shown.title
			return
		end

		count.Text = `{ammo} / {maxAmmo}`
		if ammo <= 0 then
			count.TextColor3 = EMPTY_COLOR
			title.Text = "EMPTY · REFILL IN HUB"
		else
			count.TextColor3 = if ammo / maxAmmo <= LOW_THRESHOLD then LOW_COLOR else NORMAL_COLOR
			title.Text = shown.title
		end
	end

	player.AttributeChanged:Connect(function(attribute)
		if shown and (attribute == shown.count or attribute == shown.max) then
			update()
		end
	end)

	-- Only while a ranged weapon is in hand (equipping moves a tool into the character).
	local function watch(character: Model)
		local function refresh()
			local tool = character:FindFirstChildOfClass("Tool")
			shown = if tool then AMMO[tool.Name] else nil
			panel.Visible = shown ~= nil
			update()
		end
		character.ChildAdded:Connect(refresh)
		character.ChildRemoved:Connect(refresh)
		refresh()
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

return AmmoDisplay
