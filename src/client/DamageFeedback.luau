--!strict
-- How it feels to get hurt, on your own screen:
--   * when you take damage: the camera shakes and the screen's edges flash red, both
--     stronger for bigger hits (relative to your max health)
--   * while your health is low: a red vignette pulses at the edges, the world's colours
--     drain toward grey, and a heartbeat thumps, faster the closer you are to death
-- Display only: watches your character's Health attribute (see HealthService).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local FEEDBACK = CombatConfig.DamageFeedback
local RED = Color3.fromRGB(200, 20, 25)
local EDGE_DEPTH = 0.28 -- how far in from each screen edge the vignette reaches

local player = Players.LocalPlayer

local DamageFeedback = {}

-- One edge of the vignette: red at the screen edge, fading to clear toward the middle.
-- Starts invisible (its BackgroundTransparency is the vignette's overall strength).
local function edge(parent: Instance, anchor: Vector2, position: UDim2, size: UDim2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = RED
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation -- points from the opaque edge toward the clear middle
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	return frame
end

function DamageFeedback.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DamageFeedback"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1 -- under the HUD
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The vignette: four edges, each faded directly. (A CanvasGroup would fade them together,
	-- but Roblox skips its fade when short on graphics memory, leaving them fully red.)
	local edges = {
		edge(gui, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, EDGE_DEPTH), 90),
		edge(gui, Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, EDGE_DEPTH), -90),
		edge(gui, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(EDGE_DEPTH, 1), 0),
		edge(gui, Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(EDGE_DEPTH, 1), 180),
	}
	local shown = -1
	local function setStrength(strength: number)
		strength = math.clamp(strength, 0, 1)
		if math.abs(strength - shown) < 0.005 then
			return
		end
		shown = strength
		for _, frame in edges do
			frame.BackgroundTransparency = 1 - strength
			frame.Visible = strength > 0
		end
	end
	setStrength(0)

	-- Colours drain while hurt (only on this screen).
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "LowHealthGrade"
	grade.Parent = Lighting

	local flash = 0 -- 0..1, the red flash from the last hit, fading out
	local shake = 0 -- studs of camera shake, fading out
	local ratio = 1 -- current health / max health
	local nextBeat = 0
	local random = Random.new()

	local function onHealthChanged(character: Model, previous: number?)
		local health = character:GetAttribute("Health")
		local maxHealth = character:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			return
		end
		ratio = math.clamp(health / maxHealth, 0, 1)
		if previous and health < previous and health > 0 then
			local hurt = (previous - health) / maxHealth -- share of max health lost
			flash = math.max(flash, math.clamp(FEEDBACK.FlashMin + hurt * FEEDBACK.FlashPerHealth, 0, 1))
			shake = math.max(shake, math.clamp(FEEDBACK.ShakeMin + hurt * FEEDBACK.ShakePerHealth, 0, FEEDBACK.ShakeMax))
		end
	end

	local function watch(character: Model)
		ratio, flash, shake = 1, 0, 0
		local last = character:GetAttribute("Health")
		character:GetAttributeChangedSignal("Health"):Connect(function()
			onHealthChanged(character, if typeof(last) == "number" then last else nil)
			last = character:GetAttribute("Health")
		end)
		character:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			onHealthChanged(character, nil)
		end)
		onHealthChanged(character, nil)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end

	local gradedLow = -1 -- the `low` the grade was last set for
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local alive = ratio > 0
		-- How deep into low health we are: 0 at the threshold, 1 at zero health.
		local low = if alive and ratio < FEEDBACK.LowHealth then 1 - ratio / FEEDBACK.LowHealth else 0
		local pulse = 0.5 + 0.5 * math.sin(now * (3 + 4 * low))
		local lowStrength = if low > 0 then 0.35 + 0.35 * low + 0.15 * pulse else 0
		setStrength(math.max(lowStrength, flash))
		if low ~= gradedLow then -- only while it changes (not every frame at full health)
			gradedLow = low
			grade.Saturation = -FEEDBACK.LowHealthDesaturate * low
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 205, 205), low)
		end

		-- A heartbeat while low, quickening as health drops.
		if low > 0 and now >= nextBeat then
			nextBeat = now + 1.1 - 0.5 * low
			Sounds.play("Heartbeat", workspace.CurrentCamera)
		end

		-- The hit's shake and flash fade out.
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if shake > 0.01 and humanoid then
			humanoid.CameraOffset = Vector3.new(random:NextNumber(-shake, shake), random:NextNumber(-shake, shake), 0)
			shake = math.max(shake - dt * shake / FEEDBACK.ShakeTime * 3, 0)
			if shake <= 0.01 then
				humanoid.CameraOffset = Vector3.zero
			end
		end
		flash = math.max(flash - dt / FEEDBACK.FlashTime, 0)
	end)
end

return DamageFeedback
