--!strict
-- Shared look for the chunky, cartoonish HUD pieces (dash and block meters): thick dark
-- outlines, rounded corners, a glossy top highlight, the FredokaOne font, and a bouncy pop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Icons = require(ReplicatedStorage.Shared.Icons)

local HudStyle = {}

HudStyle.FONT = Enum.Font.FredokaOne
HudStyle.OUTLINE = Color3.fromRGB(20, 18, 28)
HudStyle.EMPTY = Color3.fromRGB(55, 55, 70)

local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Rounded corners and a thick outline.
function HudStyle.chunky(frame: GuiObject, radius: number, outline: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = outline or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

-- A glossy look: lighter at the top, a little darker at the bottom (tints the frame's color).
function HudStyle.gloss(frame: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)),
	})
	gradient.Parent = frame
end

-- A round icon badge: a colored circle with an icon in it (an Icons name; any other text is
-- shown as text).
function HudStyle.badge(parent: Instance, size: number, color: Color3, icon: string): Frame
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(size, size)
	badge.BackgroundColor3 = color
	badge.Parent = parent
	HudStyle.chunky(badge, size // 2)
	HudStyle.gloss(badge)
	Instance.new("UIScale").Parent = badge

	if Icons.has(icon) then
		Icons.image(badge, icon, math.floor(size * 0.14))
		return badge
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextScaled = true
	label.Text = icon
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = badge
	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0, math.floor(size * 0.18))
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = inset, inset, inset, inset
	padding.Parent = label
	return badge
end

-- A small caption in the HUD font with a dark outline.
function HudStyle.caption(parent: Instance, text: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

-- Keeps icon `name` just left of `label`'s text (wherever its alignment puts the text), as tall
-- as `size` pixels. Returns the icon, e.g. to fade it with the label.
function HudStyle.iconBeside(label: TextLabel, name: string, size: number): ImageLabel
	local icon = Icons.image(label, name)
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	local function place()
		local width, bounds = label.AbsoluteSize.X, label.TextBounds.X
		local left = if label.TextXAlignment == Enum.TextXAlignment.Left
			then 0
			elseif label.TextXAlignment == Enum.TextXAlignment.Right then width - bounds
			else (width - bounds) / 2
		icon.Position = UDim2.new(if width > 0 then left / width else 0, -4, 0.5, 0)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(place)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	return icon
end

-- A short name tag ("HP", "STA") just outside a bar's left end, so the bars read at a glance.
function HudStyle.barTag(bar: GuiObject, text: string, color: Color3): TextLabel
	local tag = HudStyle.caption(bar, text, 12)
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(0, -6, 0.5, 0)
	tag.Size = UDim2.fromOffset(40, 14)
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.TextColor3 = color
	return tag
end

-- Celebrates a bar's maximum going up (a skill, armor): "+N" rises off its right end and
-- the bar pops (it needs a UIScale).
local GAIN_RISE = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
function HudStyle.maxGain(bar: GuiObject, amount: number, color: Color3)
	local label = HudStyle.caption(bar, `+{amount}`, 16)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(1, 8, 0.5, 0)
	label.Size = UDim2.fromOffset(50, 18)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.ZIndex = 4
	local stroke = label:FindFirstChildOfClass("UIStroke")
	TweenService:Create(label, GAIN_RISE, { Position = UDim2.new(1, 8, 0.5, -22), TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, GAIN_RISE, { Transparency = 1 }):Play()
	end
	task.delay(GAIN_RISE.Time, function()
		label:Destroy()
	end)
	HudStyle.pop(bar, 1.1)
end

-- HUD scale: the HUD is laid out for a 1280x720 screen and shrinks on smaller ones, so it
-- never covers the game; never grows past 1. Phones (a short side under PHONE_SIZE) shrink
-- it further, so the small screen isn't crowded.
local REFERENCE_SCREEN = Vector2.new(1280, 720)
local MIN_HUD_SCALE = 0.55
local PHONE_SIZE = 500
local PHONE_FACTOR = 0.85 -- extra shrink on phones...
local PHONE_RANGE = Vector2.new(0.36, 0.6) -- ...kept within this
local hudScales: { UIScale } = {}

function HudStyle.isPhone(): boolean
	local screen = workspace.CurrentCamera.ViewportSize
	return screen.X > 2 and math.min(screen.X, screen.Y) < PHONE_SIZE
end

local function hudScale(): number
	local screen = workspace.CurrentCamera.ViewportSize
	if screen.X < 2 or screen.Y < 2 then
		return 1 -- the camera isn't ready yet
	end
	local fit = math.min(screen.X / REFERENCE_SCREEN.X, screen.Y / REFERENCE_SCREEN.Y)
	if HudStyle.isPhone() then
		return math.clamp(fit * PHONE_FACTOR, PHONE_RANGE.X, PHONE_RANGE.Y)
	end
	return math.clamp(fit, MIN_HUD_SCALE, 1)
end

local watchingScreen = false
local function watchScreen()
	if watchingScreen then
		return
	end
	watchingScreen = true
	local function update()
		local scale = hudScale()
		for _, uiScale in hudScales do
			uiScale.Scale = scale
		end
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(update)
end

-- A full-screen frame in `gui` that scales its contents with the HUD scale, around `anchor`
-- (0..1 across the screen: e.g. (0.5, 1) is the bottom centre). Put HUD pieces in this
-- instead of the ScreenGui, and they shrink toward their own corner or edge.
function HudStyle.holder(gui: Instance, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = "HudScale"
	frame.AnchorPoint = anchor
	frame.Position = UDim2.fromScale(anchor.X, anchor.Y)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = hudScale()
	scale.Parent = frame
	table.insert(hudScales, scale)
	watchScreen()
	return frame
end

-- Bounces `frame` (it needs a UIScale): `from` above 1 pops it, below 1 squishes it.
function HudStyle.pop(frame: GuiObject, from: number)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		return
	end
	scale.Scale = from
	TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
end

return HudStyle
