--!strict
-- Stamina bar: a chunky cartoon bar (see HudStyle) just above the health bar. Display only:
-- reads the Stamina/MaxStamina attributes the server sets (see StaminaService). Golden,
-- turning orange when low; when an attack is refused for lack of stamina, the bar flashes
-- red and wobbles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudStyle = require(script.Parent.HudStyle)
local Stamina = require(ReplicatedStorage.Shared.Stamina)

local WIDTH = 420 -- as wide as the health bar
local HEIGHT = 14
local BOTTOM = -122 -- just above the health bar (which spans -88 to -116)
local FULL_COLOR = Color3.fromRGB(255, 205, 60)
local LOW_COLOR = Color3.fromRGB(255, 140, 50)
local EMPTY_FLASH_COLOR = Color3.fromRGB(230, 60, 60)
local LOW_THRESHOLD = 0.25
local FILL_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Linear)
local FLASH_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer

local StaminaBar = {}

local function createGui(): (Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "StaminaBar"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.AnchorPoint = Vector2.new(0.5, 1)
	background.Position = UDim2.new(0.5, 0, 1, BOTTOM)
	background.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	background.BackgroundColor3 = HudStyle.EMPTY
	background.Parent = gui
	HudStyle.chunky(background, 7, 2.5)
	Instance.new("UIScale").Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FULL_COLOR
	fill.Parent = background
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = fill
	HudStyle.gloss(fill)

	return background, fill
end

function StaminaBar.start()
	local background, fill = createGui()

	local function update()
		local stamina = player:GetAttribute("Stamina")
		local maxStamina = player:GetAttribute("MaxStamina")
		if typeof(stamina) ~= "number" or typeof(maxStamina) ~= "number" or maxStamina <= 0 then
			return
		end
		local ratio = math.clamp(stamina / maxStamina, 0, 1)
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		fill.BackgroundColor3 = if ratio > LOW_THRESHOLD then FULL_COLOR else LOW_COLOR
	end

	player:GetAttributeChangedSignal("Stamina"):Connect(update)
	player:GetAttributeChangedSignal("MaxStamina"):Connect(update)
	update()

	-- Not enough for that attack: flash the empty part red and wobble the bar.
	Stamina.NotEnough:Connect(function()
		background.BackgroundColor3 = EMPTY_FLASH_COLOR
		TweenService:Create(background, FLASH_TWEEN, { BackgroundColor3 = HudStyle.EMPTY }):Play()
		HudStyle.pop(background, 1.08)
	end)
end

return StaminaBar
