--!strict
-- Dash: press DASH.Key (V) for a quick burst of speed in the direction you're moving (or
-- facing, if standing still). Up to DASH.MaxCharges are stored; spent charges refill one
-- at a time, each taking DASH.RechargeTime. A "DASH" meter on the left of the health bar's
-- top edge shows each charge, with the one refilling filling up as it charges.
-- Each client simulates its own character's movement, so the dash runs here and
-- replicates to others like normal movement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Push = require(script.Parent.Push)

local DASH = CombatConfig.Dash

local SEGMENT_SIZE = Vector2.new(44, 8)
local SEGMENT_GAP = 4
local READY_COLOR = Color3.fromRGB(130, 230, 140)
local CHARGING_COLOR = Color3.fromRGB(80, 140, 90)
local EMPTY_COLOR = Color3.fromRGB(35, 40, 38)

local player = Players.LocalPlayer

local Dash = {}

local charges = DASH.MaxCharges
local rechargeProgress = 0 -- 0..1 progress of the charge currently refilling
local lastDash = 0
local fills: { Frame } = {}

local function createMeter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DashDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Along the left half of the health bar's top edge (the bar is 300 wide at bottom
	-- center, see HealthBar); the block pips take the right half.
	local row = Instance.new("Frame")
	row.Name = "Meter"
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0.5, -150, 1, -118)
	row.Size = UDim2.fromOffset(150, 14)
	row.BackgroundTransparency = 1
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, SEGMENT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.LayoutOrder = 0
	label.Size = UDim2.fromOffset(34, 14)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "DASH"
	label.Parent = row

	for index = 1, DASH.MaxCharges do
		local segment = Instance.new("Frame")
		segment.Name = `Dash{index}`
		segment.LayoutOrder = index
		segment.Size = UDim2.fromOffset(SEGMENT_SIZE.X, SEGMENT_SIZE.Y)
		segment.BackgroundColor3 = EMPTY_COLOR
		segment.BorderSizePixel = 0
		segment.ClipsDescendants = true
		segment.Parent = row
		Instance.new("UICorner").Parent = segment
		local stroke = Instance.new("UIStroke")
		stroke.Transparency = 0.5
		stroke.Parent = segment

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.Parent = segment
		Instance.new("UICorner").Parent = fill
		table.insert(fills, fill)
	end
end

local function updateMeter()
	for index, fill in fills do
		if index <= charges then
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = READY_COLOR
		elseif index == charges + 1 then
			fill.Size = UDim2.fromScale(rechargeProgress, 1)
			fill.BackgroundColor3 = CHARGING_COLOR
		else
			fill.Size = UDim2.fromScale(0, 1)
		end
	end
end

local function tryDash()
	local now = os.clock()
	if charges <= 0 or now - lastDash < DASH.MinInterval then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	-- Where the player is steering, or straight ahead when standing still.
	local moving = humanoid.MoveDirection
	local direction = if moving.Magnitude > 0.1 then moving else root.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return
	end

	charges -= 1
	lastDash = now
	updateMeter()
	Push.apply(root, direction, DASH.Speed, DASH.Duration)
end

function Dash.start()
	createMeter()
	updateMeter()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed is true while typing in chat, so typing V there doesn't dash.
		if not gameProcessed and input.KeyCode == DASH.Key then
			tryDash()
		end
	end)

	-- Refill spent charges one at a time.
	RunService.Heartbeat:Connect(function(dt)
		if charges >= DASH.MaxCharges then
			rechargeProgress = 0
			return
		end
		rechargeProgress += dt / DASH.RechargeTime
		if rechargeProgress >= 1 then
			charges += 1
			rechargeProgress = 0
		end
		updateMeter()
	end)

	player.CharacterAdded:Connect(function()
		charges = DASH.MaxCharges
		rechargeProgress = 0
		updateMeter()
	end)
end

return Dash
