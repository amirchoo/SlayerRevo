--!strict
-- Player health bar, bottom center: a chunky cartoon bar (see HudStyle).
-- Display only: reads the Health/MaxHealth attributes the server sets. Green, turning red
-- when low; damage leaves a pale chunk that drains away after a moment.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local HudStyle = require(script.Parent.HudStyle)

local WIDTH = 300
local HEIGHT = 28
local BOTTOM = -90 -- offset of the bar's bottom edge from the bottom of the screen (above the hotbar)
local HIGH_COLOR = Color3.fromRGB(90, 220, 90)
local LOW_COLOR = Color3.fromRGB(235, 65, 60)
local TRAIL_COLOR = Color3.fromRGB(255, 240, 220)
local LOW_THRESHOLD = 0.3
local FILL_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_DELAY = 0.4
local TRAIL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local player = Players.LocalPlayer

local HealthBar = {}

local function createGui(): (Frame, Frame, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HealthBar"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.AnchorPoint = Vector2.new(0.5, 1)
	background.Position = UDim2.new(0.5, 0, 1, BOTTOM)
	background.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	background.BackgroundColor3 = HudStyle.EMPTY
	background.Parent = gui
	HudStyle.chunky(background, 10)

	-- The pale chunk that lingers after damage, under the fill.
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = TRAIL_COLOR
	trail.Parent = background
	local trailCorner = Instance.new("UICorner")
	trailCorner.CornerRadius = UDim.new(0, 8)
	trailCorner.Parent = trail

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HIGH_COLOR
	fill.ZIndex = 2
	fill.Parent = background
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill
	HudStyle.gloss(fill)

	local label = HudStyle.caption(background, "", 18)
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3

	return fill, trail, label
end

function HealthBar.start()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	local fill, trail, label = createGui()
	local lastRatio = 1
	local trailToken = 0

	local function update(character: Model)
		local health = character:GetAttribute("Health")
		local maxHealth = character:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			return
		end

		local ratio = math.clamp(health / maxHealth, 0, 1)
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		fill.BackgroundColor3 = if ratio > LOW_THRESHOLD then HIGH_COLOR else LOW_COLOR
		label.Text = string.format("%d / %d", math.ceil(health), math.ceil(maxHealth))

		if ratio < lastRatio then
			-- Took damage: the lost chunk lingers, then drains.
			trailToken += 1
			local token = trailToken
			task.delay(TRAIL_DELAY, function()
				if token == trailToken then
					TweenService:Create(trail, TRAIL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
				end
			end)
		else
			trail.Size = UDim2.fromScale(ratio, 1) -- healing: no trail
		end
		lastRatio = ratio
	end

	local function onCharacterAdded(character: Model)
		lastRatio = 1
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
