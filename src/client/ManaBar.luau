--!strict
-- Mana bar: a slim blue bar (HudStyle) just above the stamina bar. Display only: reads the
-- Mana/MaxMana attributes the server sets (see ManaService). Flashes red and wobbles when a
-- spell is refused for lack of mana, and pops with "+N" when a skill raises max mana.
-- Shown only once the Mage class is unlocked, and then while the staff is in hand or mana is
-- still refilling, so it doesn't clutter the HUD for fighters who never cast.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HudStyle = require(script.Parent.HudStyle)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Stamina = require(ReplicatedStorage.Shared.Stamina)

local WIDTH = 420 -- as wide as the health bar
local HEIGHT = 10
local BOTTOM = -140 -- just above the stamina bar (which spans -122 to -136)
local FULL_COLOR = Color3.fromRGB(80, 150, 255)
local LOW_COLOR = Color3.fromRGB(120, 100, 230)
local EMPTY_FLASH_COLOR = Color3.fromRGB(230, 60, 60)
local LOW_THRESHOLD = 0.25
local FILL_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Linear)
local FLASH_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STAFF_NAME = CombatConfig.Staff.ToolName

local player = Players.LocalPlayer

local ManaBar = {}

local function staffInHand(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool.Name == STAFF_NAME
end

function ManaBar.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ManaBar"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.AnchorPoint = Vector2.new(0.5, 1)
	background.Position = UDim2.new(0.5, 0, 1, BOTTOM)
	background.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	background.BackgroundColor3 = HudStyle.EMPTY
	background.Visible = false
	background.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))
	HudStyle.chunky(background, 5, 2)
	Instance.new("UIScale").Parent = background
	HudStyle.barTag(background, "MANA", FULL_COLOR)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FULL_COLOR
	fill.Parent = background
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = fill
	HudStyle.gloss(fill)

	local lastMax: number? = nil
	local function update()
		local mana = player:GetAttribute("Mana")
		local maxMana = player:GetAttribute("MaxMana")
		if typeof(mana) ~= "number" or typeof(maxMana) ~= "number" or maxMana <= 0 then
			background.Visible = false
			return
		end
		local ratio = math.clamp(mana / maxMana, 0, 1)
		background.Visible = SkillMath.staffUnlocked(player) and (staffInHand() or ratio < 1)
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		fill.BackgroundColor3 = if ratio > LOW_THRESHOLD then FULL_COLOR else LOW_COLOR
		if lastMax and maxMana > lastMax and background.Visible then
			HudStyle.maxGain(background, math.round(maxMana - lastMax), FULL_COLOR) -- e.g. Wellspring
		end
		lastMax = maxMana
	end
	for _, attribute in { "Mana", "MaxMana", "Skills" } do
		player:GetAttributeChangedSignal(attribute):Connect(update)
	end
	-- Equipping moves a tool into the character; watch it come and go.
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				update()
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				update()
			end
		end)
		update()
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	update()

	Stamina.NotEnough:Connect(function(resource: string?)
		if resource ~= "Mana" then
			return
		end
		background.BackgroundColor3 = EMPTY_FLASH_COLOR
		TweenService:Create(background, FLASH_TWEEN, { BackgroundColor3 = HudStyle.EMPTY }):Play()
		HudStyle.pop(background, 1.08)
	end)
end

return ManaBar
