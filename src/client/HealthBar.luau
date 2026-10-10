--!strict
-- Player health bar. Display only: reads the Health/MaxHealth attributes the server sets.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local HIGH_COLOR = Color3.fromRGB(90, 200, 90)
local LOW_COLOR = Color3.fromRGB(220, 60, 60)
local LOW_THRESHOLD = 0.3
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer

local HealthBar = {}

local function createGui(): (Frame, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HealthBar"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Name = "Background"
	-- Bottom center, just above the default hotbar.
	background.AnchorPoint = Vector2.new(0.5, 1)
	background.Position = UDim2.new(0.5, 0, 1, -90)
	background.Size = UDim2.fromOffset(300, 22)
	background.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	background.BorderSizePixel = 0
	background.Parent = gui
	Instance.new("UICorner").Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HIGH_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = background
	Instance.new("UICorner").Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.ZIndex = 2
	label.Parent = background

	return fill, label
end

function HealthBar.start()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	local fill, label = createGui()

	local function update(character: Model)
		local health = character:GetAttribute("Health")
		local maxHealth = character:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			return
		end

		local ratio = math.clamp(health / maxHealth, 0, 1)
		TweenService:Create(fill, TWEEN_INFO, { Size = UDim2.fromScale(ratio, 1) }):Play()
		fill.BackgroundColor3 = if ratio > LOW_THRESHOLD then HIGH_COLOR else LOW_COLOR
		label.Text = string.format("%d / %d", math.ceil(health), math.ceil(maxHealth))
	end

	local function onCharacterAdded(character: Model)
		-- The server may set the attributes after we see the character, so listen and also check now.
		character:GetAttributeChangedSignal("Health"):Connect(function()
			update(character)
		end)
		character:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			update(character)
		end)
		update(character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return HealthBar
