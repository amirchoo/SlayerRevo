--!strict
-- Dash: press DASH.Key (V) for a quick burst of speed in the direction you're moving (or
-- facing, if standing still). Up to DASH.MaxCharges are stored; spent charges refill one
-- at a time, each taking DASH.RechargeTime. A meter above the left of the health bar (a
-- lightning badge and one bar per charge) shows each charge, with the one refilling filling
-- up as it charges; bars pop when they refill and squish when spent.
-- Each client simulates its own character's movement, so the dash runs here and
-- replicates to others like normal movement.
-- Each dash is reported to the server (DashStart), which grants a moment of i-frames
-- (see DashService); a hit dodged that way pops "DODGE".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HudStyle = require(script.Parent.HudStyle)
local DamageNumbers = require(script.Parent.DamageNumbers)
local Push = require(script.Parent.Push)

local DASH = CombatConfig.Dash

local SEGMENT_SIZE = Vector2.new(46, 22)
local SEGMENT_GAP = 6
local BADGE_SIZE = 40
local BADGE_COLOR = Color3.fromRGB(255, 200, 60)
local READY_COLOR = Color3.fromRGB(90, 230, 120)
local CHARGING_COLOR = Color3.fromRGB(60, 150, 95)
local DODGE_COLOR = Color3.fromRGB(150, 255, 200)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dashRemote = remotes:WaitForChild("DashStart") :: RemoteEvent
local dodgedRemote = remotes:WaitForChild("Dodged") :: RemoteEvent

local Dash = {}

local charges = DASH.MaxCharges
local rechargeProgress = 0 -- 0..1 progress of the charge currently refilling
local lastDash = 0
local segments: { Frame } = {}
local fills: { Frame } = {}
local badge: Frame? = nil

local function createMeter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DashDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Above the left half of the health bar (the bar is 300 wide at bottom center, see
	-- HealthBar); the block meter takes the right half.
	local row = Instance.new("Frame")
	row.Name = "Meter"
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0.5, -150, 1, -148)
	row.Size = UDim2.fromOffset(150, BADGE_SIZE)
	row.BackgroundTransparency = 1
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, SEGMENT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	-- A lightning badge, with the key under it.
	badge = HudStyle.badge(row, BADGE_SIZE, BADGE_COLOR, "⚡")
	local key = HudStyle.caption(badge :: Frame, DASH.Key.Name, 14)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.new(0.5, 0, 1, 0)
	key.Size = UDim2.fromOffset(20, 14)
	key.ZIndex = 2

	for index = 1, DASH.MaxCharges do
		local segment = Instance.new("Frame")
		segment.Name = `Dash{index}`
		segment.LayoutOrder = index
		segment.Size = UDim2.fromOffset(SEGMENT_SIZE.X, SEGMENT_SIZE.Y)
		segment.BackgroundColor3 = HudStyle.EMPTY
		segment.Parent = row
		HudStyle.chunky(segment, 8)
		Instance.new("UIScale").Parent = segment

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BorderSizePixel = 0
		fill.Parent = segment
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = fill
		HudStyle.gloss(fill)
		table.insert(segments, segment)
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
	HudStyle.pop(segments[charges + 1], 0.75) -- squish the one just spent
	Push.apply(root, direction, DASH.Speed, DASH.Duration)
	dashRemote:FireServer() -- the server grants the dash's i-frames
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
			HudStyle.pop(segments[charges], 1.3) -- pop the one just refilled
			if badge then
				HudStyle.pop(badge, 1.2)
			end
		end
		updateMeter()
	end)

	-- A hit dodged during the dash's i-frames.
	dodgedRemote.OnClientEvent:Connect(function()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			DamageNumbers.popup(head.Position + Vector3.new(0, 1.5, 0), "DODGE", DODGE_COLOR)
		end
	end)

	player.CharacterAdded:Connect(function()
		charges = DASH.MaxCharges
		rechargeProgress = 0
		updateMeter()
	end)
end

return Dash
