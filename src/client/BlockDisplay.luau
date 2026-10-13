--!strict
-- Block charges HUD and feedback. Shows a shield badge and a row of chunky pips above the
-- right of the health bar (filled = charge ready; they pop back when they recharge). When the server says a block landed (GuardHit), pops "BLOCKED"
-- with a clang, shakes the camera a little, and shoves the character back away from the hit
-- (the client applies it because it controls its own character's movement).
-- A parry pops "PARRY!" instead, with no shove.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local DamageNumbers = require(script.Parent.DamageNumbers)
local HudStyle = require(script.Parent.HudStyle)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Push = require(script.Parent.Push)

local BLOCK = CombatConfig.Blocking

local PIP_SIZE = 26
local PIP_GAP = 6
local BADGE_SIZE = 40
local BADGE_COLOR = Color3.fromRGB(80, 150, 255)
local READY_COLOR = Color3.fromRGB(100, 190, 255)
local BLOCKED_COLOR = Color3.fromRGB(140, 200, 255)
local PARRY_COLOR = Color3.fromRGB(255, 225, 110)
local SHAKE_TIME = 0.15
local SHAKE_STRENGTH = 0.25 -- studs

local player = Players.LocalPlayer
local guardHitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GuardHit") :: RemoteEvent

local BlockDisplay = {}

local function createRow(): (Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlockDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Above the right half of the health bar (the bar is 420 wide at bottom center, see
	-- HealthBar); the dash meter takes the left half.
	local row = Instance.new("Frame")
	row.Name = "Pips"
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0.5, 232, 1, -22) -- right of the hotbar
	row.Size = UDim2.fromOffset(150, BADGE_SIZE)
	row.BackgroundTransparency = 1
	row.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PIP_GAP)
	layout.Parent = row

	-- A shield badge on the far right.
	local badge = HudStyle.badge(row, BADGE_SIZE, BADGE_COLOR, "Shield")
	badge.LayoutOrder = 1000
	return row, badge
end

local function createPip(row: Frame, index: number): Frame
	local pip = Instance.new("Frame")
	pip.Name = `Pip{index}`
	pip.LayoutOrder = index
	pip.Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE)
	pip.Parent = row
	HudStyle.chunky(pip, 7)
	HudStyle.gloss(pip)
	Instance.new("UIScale").Parent = pip
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

-- `parried`: the hit was parried (no shove; the clash itself is shown to everyone by HitEffects).
local function onGuardHit(direction: Vector3, parried: boolean?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if parried then
		if head and head:IsA("BasePart") then
			DamageNumbers.popup(head.Position + Vector3.new(0, 1.5, 0), "PARRY!", PARRY_COLOR)
		end
		if humanoid then
			shakeCamera(humanoid)
		end
		return
	end
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
	local row, badge = createRow()
	local pips: { Frame } = {}
	local shown: number? = nil -- charges last drawn

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
			pip.BackgroundColor3 = if index <= charges then READY_COLOR else HudStyle.EMPTY
		end
		-- Pop a charge that came back; squish one that was used.
		if shown and charges > shown and pips[charges] then
			HudStyle.pop(pips[charges], 1.35)
			HudStyle.pop(badge, 1.15)
		elseif shown and charges < shown and pips[charges + 1] then
			HudStyle.pop(pips[charges + 1], 0.7)
		end
		shown = charges
	end

	player:GetAttributeChangedSignal("BlockCharges"):Connect(update)
	player:GetAttributeChangedSignal("MaxBlockCharges"):Connect(update)
	update()

	guardHitRemote.OnClientEvent:Connect(onGuardHit)
end

return BlockDisplay
