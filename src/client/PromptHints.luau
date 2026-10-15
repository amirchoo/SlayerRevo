--!strict
-- Every interact prompt in the HUD's style (the one Bonnie's "Pet" started), in place of
-- Roblox's popup: a key chip ([E], or the controller's button picture) and the action, in
-- FredokaOne with a dark outline. Townsfolk and pets show it under their nameplate (Nameplates
-- hands those over with `attach`); anything else (chests, the campfire, the quest board, armor
-- stands...) gets it floating over the object, with the object's name above it in gold.
-- A prompt that must be held fills a bar under the hint while it's held. The hint can be
-- tapped or clicked too (touch screens have no key to press).

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HudStyle = require(script.Parent.HudStyle)
local Gamepad = require(script.Parent.Gamepad)

local NAME_SIZE = 17
local HINT_SIZE = 15
local KEY_COLOR = Color3.fromRGB(58, 54, 74)
local NAME_COLOR = Color3.fromRGB(255, 226, 150)
local HOLD_COLOR = Color3.fromRGB(255, 210, 90)
local HOLD_HEIGHT = 4
local FLOAT_WIDTH = 220
local FLOAT_ABOVE = 1.2 -- studs over the top of the prompt's part
local FLOAT_DISTANCE = 30

local player = Players.LocalPlayer

local PromptHints = {}

-- A built hint: show/hide it, and the frame it lives in.
type Hint = { frame: TextButton, show: () -> (), hide: () -> () }
-- Prompts whose hint lives somewhere else (a nameplate), by prompt.
local attached: { [ProximityPrompt]: Hint } = setmetatable({}, { __mode = "k" }) :: any
-- Floating hints currently up, by prompt.
local floating: { [ProximityPrompt]: { gui: BillboardGui, hint: Hint } } = {}

local function outlined(parent: Instance, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.TextColor3 = color
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

-- Builds "[key] Action" for `prompt` inside `parent`, its top centred at `y` (hidden until shown).
local function build(parent: GuiObject, y: number, prompt: ProximityPrompt): Hint
	local textWidth = game:GetService("TextService"):GetTextSize(prompt.ActionText, HINT_SIZE, HudStyle.FONT, Vector2.new(400, 100)).X
	local width = HINT_SIZE + 10 + textWidth + 4

	local frame = Instance.new("TextButton")
	frame.Name = "PromptHint"
	frame.BackgroundTransparency = 1
	frame.Text = ""
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, y)
	frame.Size = UDim2.fromOffset(width, HINT_SIZE + 4 + HOLD_HEIGHT + 4)
	frame.Visible = false
	frame.Parent = parent
	Instance.new("UIScale").Parent = frame

	local key = outlined(frame, HINT_SIZE - 2, Color3.new(1, 1, 1))
	key.BackgroundTransparency = 0
	key.BackgroundColor3 = KEY_COLOR
	key.Size = UDim2.fromOffset(HINT_SIZE + 4, HINT_SIZE + 4)
	key.Text = prompt.KeyboardKeyCode.Name
	HudStyle.chunky(key, 5, 1.5)
	Gamepad.hint(key, prompt.KeyboardKeyCode.Name, prompt.GamepadKeyCode)

	local action = outlined(frame, HINT_SIZE, Color3.new(1, 1, 1))
	action.Position = UDim2.fromOffset(HINT_SIZE + 10, 0)
	action.Size = UDim2.new(1, -(HINT_SIZE + 10), 0, HINT_SIZE + 4)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.Text = prompt.ActionText

	-- Hold progress (only for prompts with a HoldDuration).
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(0, HINT_SIZE + 8)
	track.Size = UDim2.new(1, 0, 0, HOLD_HEIGHT)
	track.BackgroundColor3 = HudStyle.EMPTY
	track.Visible = false
	track.Parent = frame
	HudStyle.chunky(track, 2, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = HOLD_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillTween: Tween? = nil

	local connections = {
		prompt.PromptButtonHoldBegan:Connect(function()
			if prompt.HoldDuration <= 0 then
				return
			end
			track.Visible = true
			fill.Size = UDim2.fromScale(0, 1)
			fillTween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
			;(fillTween :: Tween):Play()
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if fillTween then
				fillTween:Cancel()
				fillTween = nil
			end
			track.Visible = false
		end),
		frame.Activated:Connect(function()
			if not prompt.Enabled then
				return
			end
			prompt:InputHoldBegin()
			if prompt.HoldDuration > 0 then
				task.delay(prompt.HoldDuration + 0.05, function()
					prompt:InputHoldEnd()
				end)
			else
				prompt:InputHoldEnd()
			end
		end),
	}
	frame.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	return {
		frame = frame,
		show = function()
			frame.Visible = true
			HudStyle.pop(frame, 0.8)
		end,
		hide = function()
			frame.Visible = false
			track.Visible = false
		end,
	}
end

-- Shows `prompt`'s hint inside `parent` (e.g. a nameplate), its top at `y`, instead of floating.
function PromptHints.attach(parent: GuiObject, y: number, prompt: ProximityPrompt)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	local old = attached[prompt]
	if old then
		old.frame:Destroy()
	end
	attached[prompt] = build(parent, y, prompt)
end

-- Where a floating hint hangs: the prompt's part (or attachment), just over its top.
local function anchorOf(prompt: ProximityPrompt): (Instance?, Vector3)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent, Vector3.new(0, parent.Size.Y / 2 + FLOAT_ABOVE, 0)
	elseif parent and parent:IsA("Attachment") then
		return parent, Vector3.new(0, FLOAT_ABOVE, 0)
	elseif parent and parent:IsA("Model") then
		local _, size = parent:GetBoundingBox()
		return parent.PrimaryPart, Vector3.new(0, size.Y / 2 + FLOAT_ABOVE, 0)
	end
	return nil, Vector3.zero
end

local function showFloating(prompt: ProximityPrompt)
	local adornee, offset = anchorOf(prompt)
	if not adornee then
		return
	end
	local hasName = prompt.ObjectText ~= ""
	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptHint"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(FLOAT_WIDTH, (if hasName then NAME_SIZE + 6 else 0) + HINT_SIZE + HOLD_HEIGHT + 12)
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = true
	gui.MaxDistance = FLOAT_DISTANCE
	gui.LightInfluence = 0
	gui.Active = true -- the hint can be clicked
	gui.Parent = player:WaitForChild("PlayerGui")
	if hasName then
		local name = outlined(gui, NAME_SIZE, NAME_COLOR)
		name.Size = UDim2.new(1, 0, 0, NAME_SIZE + 2)
		name.Text = prompt.ObjectText
	end
	local hint = build(gui :: any, if hasName then NAME_SIZE + 6 else 0, prompt)
	hint.show()
	floating[prompt] = { gui = gui, hint = hint }
end

local function hideFloating(prompt: ProximityPrompt)
	local entry = floating[prompt]
	if entry then
		floating[prompt] = nil
		entry.gui:Destroy()
	end
end

-- Takes over a prompt's look (locally: the server's prompt still works the same).
local function adopt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptHints.start()
	workspace.DescendantAdded:Connect(adopt)
	for _, descendant in workspace:GetDescendants() do
		adopt(descendant)
	end

	ProximityPromptService.PromptShown:Connect(function(prompt)
		local hint = attached[prompt]
		if hint then
			hint.show()
		else
			showFloating(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local hint = attached[prompt]
		if hint then
			hint.hide()
		end
		hideFloating(prompt)
	end)
end

return PromptHints
