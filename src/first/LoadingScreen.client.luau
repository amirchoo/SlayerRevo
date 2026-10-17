--!strict
-- The loading screen (ReplicatedFirst, so it runs before anything else has arrived): the game's
-- title over a dark panel, in the intro's colours, while the world streams in. It replaces
-- Roblox's default one and fades out once the game has loaded, your character has spawned and
-- the area round it has streamed in (or after MAX_WAIT, whatever's still missing). Self-contained:
-- ReplicatedStorage's modules may not have arrived when it starts.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local MIN_SHOW = 1 -- seconds, so it doesn't just flash
local MAX_WAIT = 20 -- seconds before it gives up waiting and fades out anyway
local STREAM_TIMEOUT = 8 -- seconds to wait for the area round the character
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Sine)

local PANEL = Color3.fromRGB(24, 19, 15)
local GOLD = Color3.fromRGB(226, 188, 112)
local GOLD_DARK = Color3.fromRGB(140, 104, 56)
local TEXT = Color3.fromRGB(205, 190, 165)
local TITLE_FONT = Enum.Font.Fondamento

local player = Players.LocalPlayer
local started = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000 -- over everything, the intro included
gui.ScreenInsets = Enum.ScreenInsets.None

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = PANEL
background.BorderSizePixel = 0
background.Parent = gui

local vignette = Instance.new("UIGradient")
vignette.Rotation = 90 -- darker at the top and bottom edges
vignette.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 11, 9)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 31, 24)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 11, 9)),
})
vignette.Parent = background

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.44)
title.Size = UDim2.fromScale(0.8, 0.14)
title.BackgroundTransparency = 1
title.Font = TITLE_FONT
title.Text = "Slayer Revo"
title.TextColor3 = GOLD
title.TextScaled = true
title.Parent = background
local titleSize = Instance.new("UITextSizeConstraint")
titleSize.MaxTextSize = 96
titleSize.Parent = title
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(10, 8, 6)
titleStroke.Thickness = 2
titleStroke.Parent = title

-- A thin gold line under the title with a glint sweeping along it while it waits.
local rule = Instance.new("Frame")
rule.AnchorPoint = Vector2.new(0.5, 0.5)
rule.Position = UDim2.fromScale(0.5, 0.535)
rule.Size = UDim2.new(0.3, 0, 0, 2)
rule.BackgroundColor3 = GOLD_DARK
rule.BorderSizePixel = 0
rule.Parent = background
local glint = Instance.new("UIGradient")
glint.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD_DARK),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 190)),
	ColorSequenceKeypoint.new(1, GOLD_DARK),
})
glint.Offset = Vector2.new(-1, 0)
glint.Parent = rule

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.58)
status.Size = UDim2.fromScale(0.8, 0.04)
status.BackgroundTransparency = 1
status.Font = TITLE_FONT
status.Text = "Loading the world"
status.TextColor3 = TEXT
status.TextScaled = true
status.Parent = background
local statusSize = Instance.new("UITextSizeConstraint")
statusSize.MaxTextSize = 28
statusSize.Parent = status

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local glintTween = TweenService:Create(glint, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) })
glintTween:Play()

local function remaining(): number
	return math.max(MAX_WAIT - (os.clock() - started), 0)
end

-- Waits until `ready()` or the overall time runs out.
local function waitFor(ready: () -> boolean)
	while not ready() and remaining() > 0 do
		task.wait(0.1)
	end
end

-- 1. The game itself.
waitFor(function()
	return game:IsLoaded()
end)

-- 2. Your character.
status.Text = "Finding your way"
waitFor(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end)

-- 3. The area round it (streaming).
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
if root and root:IsA("BasePart") and remaining() > 0 then
	status.Text = "Gathering your surroundings"
	local done = false
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(root.Position, math.min(STREAM_TIMEOUT, remaining()))
		end)
		done = true
	end)
	waitFor(function()
		return done
	end)
end

local shown = os.clock() - started
if shown < MIN_SHOW then
	task.wait(MIN_SHOW - shown)
end

-- Fade everything out, then clean up.
for _, object in gui:GetDescendants() do
	if object:IsA("Frame") then
		TweenService:Create(object, FADE, { BackgroundTransparency = 1 }):Play()
	elseif object:IsA("TextLabel") then
		TweenService:Create(object, FADE, { TextTransparency = 1 }):Play()
	elseif object:IsA("UIStroke") then
		TweenService:Create(object, FADE, { Transparency = 1 }):Play()
	end
end
task.wait(FADE.Time)
glintTween:Cancel()
gui:Destroy()
