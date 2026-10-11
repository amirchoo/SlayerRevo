--!strict
-- Block charges HUD and feedback. Shows a row of shield pips above the health bar
-- (filled = charge ready). When the server says a block landed (GuardHit), pops "BLOCKED"
-- with a clang, shakes the camera a little, and shoves the character back away from the hit
-- (the client applies it because it controls its own character's movement).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local DamageNumbers = require(script.Parent.DamageNumbers)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Push = require(script.Parent.Push)

local BLOCK = CombatConfig.Blocking

local PIP_SIZE = 16
local PIP_GAP = 6
local READY_COLOR = Color3.fromRGB(120, 190, 255)
local EMPTY_COLOR = Color3.fromRGB(45, 50, 60)
local BLOCKED_COLOR = Color3.fromRGB(140, 200, 255)
local SHAKE_TIME = 0.15
local SHAKE_STRENGTH = 0.25 -- studs

local player = Players.LocalPlayer
local guardHitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GuardHit") :: RemoteEvent

local BlockDisplay = {}

local function createRow(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlockDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Along the right half of the health bar's top edge (the bar is 300 wide at bottom
	-- center, see HealthBar); the dash meter takes the left half.
	local row = Instance.new("Frame")
	row.Name = "Pips"
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(0.5, 146, 1, -120)
	row.Size = UDim2.fromOffset(140, PIP_SIZE)
	row.BackgroundTransparency = 1
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, PIP_GAP)
	layout.Parent = row

	return row
end

local function createPip(row: Frame, index: number): Frame
	local pip = Instance.new("Frame")
	pip.Name = `Pip{index}`
	pip.LayoutOrder = index
	pip.Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE)
	pip.BorderSizePixel = 0
	pip.Rotation = 45 -- diamond, reads as a little shield
	pip.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.5
	stroke.Parent = pip
	return pip
end

local function shakeCamera(humanoid: Humanoid)
	local random = Random.new()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local remaining = 1 - (os.clock() - started) / SHAKE_TIME
		if remaining <= 0 then
			connection:Disconnect()
			humanoid.CameraOffset = Vector3.zero
			return
		end
		local strength = SHAKE_STRENGTH * remaining
		humanoid.CameraOffset = Vector3.new(random:NextNumber(-strength, strength), random:NextNumber(-strength, strength), 0)
	end)
end

local function onGuardHit(direction: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		DamageNumbers.popup(head.Position + Vector3.new(0, 1.5, 0), "BLOCKED", BLOCKED_COLOR)
	end
	Sounds.play("Block", workspace.CurrentCamera)
	if root and root:IsA("BasePart") then
		Push.apply(root, direction, BLOCK.KnockbackSpeed, BLOCK.KnockbackTime)
	end
	if humanoid then
		shakeCamera(humanoid)
	end
end

function BlockDisplay.start()
	local row = createRow()
	local pips: { Frame } = {}

	local function update()
		local charges = player:GetAttribute("BlockCharges")
		local maxCharges = player:GetAttribute("MaxBlockCharges")
		if typeof(charges) ~= "number" or typeof(maxCharges) ~= "number" then
			return
		end

		while #pips < maxCharges do
			table.insert(pips, createPip(row, #pips + 1))
		end
		for index, pip in pips do
			pip.Visible = index <= maxCharges
			pip.BackgroundColor3 = if index <= charges then READY_COLOR else EMPTY_COLOR
		end
	end

	player:GetAttributeChangedSignal("BlockCharges"):Connect(update)
	player:GetAttributeChangedSignal("MaxBlockCharges"):Connect(update)
	update()

	guardHitRemote.OnClientEvent:Connect(onGuardHit)
end

return BlockDisplay
