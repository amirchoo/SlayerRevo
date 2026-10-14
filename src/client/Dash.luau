--!strict
-- Dash: press DASH.Key (V) for a quick burst of speed in the direction you're moving (or
-- facing, if standing still). Up to DASH.MaxCharges are stored (more with skills); spent
-- charges refill one at a time, each taking DASH.RechargeTime (less with skills; almost none
-- in the training camp, TutorialConfig.DashRecharge). A meter above the left of the health bar (a
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
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local HudStyle = require(script.Parent.HudStyle)
local Gamepad = require(script.Parent.Gamepad)
local DamageNumbers = require(script.Parent.DamageNumbers)
local CombatInput = require(script.Parent.CombatInput)
local Push = require(script.Parent.Push)

local DASH = CombatConfig.Dash

local METER_WIDTH = 150 -- the badge plus the charge bars fit in this
local SEGMENT_HEIGHT = 22
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

-- Dash charges and recharge time, with the player's skill bonuses and the training camp's
-- fast recharge (matches DashService).
local function maxCharges(): number
	return DASH.MaxCharges + SkillMath.general(player, "DashCharges")
end
local function rechargeTime(): number
	return TutorialConfig.dashRecharge(player, DASH.RechargeTime * (1 - SkillMath.general(player, "DashRecharge")))
end

local charges = DASH.MaxCharges
local meterRow: Frame? = nil
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

	-- Above the left half of the health bar (the bar is 420 wide at bottom center, see
	-- HealthBar); the block meter takes the right half.
	local row = Instance.new("Frame")
	row.Name = "Meter"
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(0.5, -232, 1, -22) -- left of the hotbar
	row.Size = UDim2.fromOffset(METER_WIDTH, BADGE_SIZE)
	row.BackgroundTransparency = 1
	row.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, SEGMENT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	-- A lightning badge, with the key under it.
	badge = HudStyle.badge(row, BADGE_SIZE, BADGE_COLOR, "Dash")
	local key = HudStyle.caption(badge :: Frame, DASH.Key.Name, 14)
	Gamepad.hint(key, DASH.Key.Name, Enum.KeyCode.ButtonB)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.new(0.5, 0, 1, 0)
	key.Size = UDim2.fromOffset(20, 14)
	key.ZIndex = 2

	meterRow = row
end

-- Makes the meter show `count` charge bars (more with the Extra Dash skill), sized to fit.
local function setSegmentCount(count: number)
	local row = meterRow
	if not row then
		return
	end
	while #segments > count do
		(table.remove(segments) :: Frame):Destroy()
		table.remove(fills)
	end
	while #segments < count do
		local index = #segments + 1
		local segment = Instance.new("Frame")
		segment.Name = `Dash{index}`
		segment.LayoutOrder = index
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
	local width = math.floor((METER_WIDTH - BADGE_SIZE - SEGMENT_GAP * count) / count)
	for _, segment in segments do
		segment.Size = UDim2.fromOffset(width, SEGMENT_HEIGHT)
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
	setSegmentCount(maxCharges())
	charges = maxCharges()
	updateMeter()
	-- Skills can add a charge: rebuild the meter (a new charge comes ready).
	local shownMax = maxCharges()
	player:GetAttributeChangedSignal("Skills"):Connect(function()
		local max = maxCharges()
		if max ~= shownMax then
			charges = math.clamp(charges + (max - shownMax), 0, max)
			shownMax = max
			setSegmentCount(max)
			updateMeter()
		end
	end)

	CombatInput.Dash:Connect(tryDash) -- the dash key, or the touch Dash button

	-- Refill spent charges one at a time.
	RunService.Heartbeat:Connect(function(dt)
		if charges >= maxCharges() then
			rechargeProgress = 0
			return
		end
		rechargeProgress += dt / rechargeTime()
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
		charges = maxCharges()
		rechargeProgress = 0
		updateMeter()
	end)
end

return Dash
