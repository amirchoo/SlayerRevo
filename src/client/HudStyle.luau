--!strict
-- Shared look for the chunky, cartoonish HUD pieces (dash and block meters): thick dark
-- outlines, rounded corners, a glossy top highlight, the FredokaOne font, and a bouncy pop.

local TweenService = game:GetService("TweenService")

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

-- A round icon badge: a colored circle with an outlined emoji/text in it.
function HudStyle.badge(parent: Instance, size: number, color: Color3, icon: string): Frame
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(size, size)
	badge.BackgroundColor3 = color
	badge.Parent = parent
	HudStyle.chunky(badge, size // 2)
	HudStyle.gloss(badge)
	Instance.new("UIScale").Parent = badge

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
