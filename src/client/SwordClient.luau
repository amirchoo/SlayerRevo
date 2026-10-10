--!strict
-- Sword input and visuals. Plays the swing animation and tells the server we swung;
-- the server decides whether anything was hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

local SWORD = CombatConfig.Sword

type Keyframe = {
	tilt: number, -- degrees the blade tilts around the hand; positive = back, negative = forward
	time: number,
	style: Enum.EasingStyle,
	trail: boolean,
}

-- Procedural overhead slash: wind up, slash down, recover. Animates the tool's Grip,
-- so it works on any rig (R6, R15, new avatar joints). Runs on the local client only,
-- so other players won't see it yet; swap for an Animation asset made in Studio's
-- Animation Editor once we have one.
local SWING_KEYFRAMES: { Keyframe } = {
	{ tilt = 70, time = 0.12, style = Enum.EasingStyle.Quad, trail = false },
	{ tilt = -110, time = 0.1, style = Enum.EasingStyle.Quint, trail = true },
	{ tilt = 0, time = 0.2, style = Enum.EasingStyle.Sine, trail = false },
}

local player = Players.LocalPlayer
local swingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SwordSwing") :: RemoteEvent

local SwordClient = {}

local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local baseGrips: { [Tool]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local lastSwing = 0
local swingId = 0

local function playSwing(tool: Tool)
	local baseGrip = baseGrips[tool] or tool.Grip
	baseGrips[tool] = baseGrip

	-- The default Animate script plays its arm slash when it finds this value on the tool.
	local toolAnim = Instance.new("StringValue")
	toolAnim.Name = "toolanim"
	toolAnim.Value = "Slash"
	toolAnim.Parent = tool

	local trail = tool:FindFirstChild("SwingTrail", true)
	local sound = tool:FindFirstChild("SlashSound", true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end

	swingId += 1
	local thisSwing = swingId
	for _, keyframe in SWING_KEYFRAMES do
		if thisSwing ~= swingId then
			return -- a newer swing took over
		end
		if trail and trail:IsA("Trail") then
			trail.Enabled = keyframe.trail
		end
		-- Rotating the Grip by -tilt pivots the sword around the hand by +tilt.
		local tween = TweenService:Create(tool, TweenInfo.new(keyframe.time, keyframe.style, Enum.EasingDirection.Out), {
			Grip = baseGrip * CFrame.Angles(math.rad(-keyframe.tilt), 0, 0),
		})
		tween:Play()
		tween.Completed:Wait()
	end
end

local function onActivated(tool: Tool)
	-- Local cooldown is just to avoid spamming the server; the server enforces the real one.
	local now = os.clock()
	if now - lastSwing < SWORD.Cooldown then
		return
	end
	lastSwing = now

	task.spawn(playSwing, tool)
	swingRemote:FireServer()
end

local function hookTool(child: Instance)
	if child:IsA("Tool") and child.Name == SWORD.ToolName and not hookedTools[child] then
		hookedTools[child] = true
		child.Activated:Connect(function()
			onActivated(child)
		end)
	end
end

function SwordClient.start()
	local function onCharacterAdded(character: Model)
		-- Tools move into the character when equipped.
		character.ChildAdded:Connect(hookTool)
		for _, child in character:GetChildren() do
			hookTool(child)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return SwordClient
