--!strict
-- The skill tree screen: press K, or click the star icon on the left of the screen (its
-- outline glows gold while there are points to spend). Same look as the backpack (HudStyle,
-- world blurred behind). Tabs: GENERAL, then one per weapon.
-- Each tree is drawn as a tree: round skill nodes joined by crooked branches (thick near the
-- root, thinner toward the tips) that light up as you learn them.
--   General: five branches fan out and up from you at the root; rivals sit on opposite
--     sides, and a branch locked by its rival is darkened. It's bigger than the window:
--     drag the empty space to look around.
--   Weapons: grow up from the weapon at the root; the trunk splits into two branches and
--     ends in the two masteries (take one, the other locks).
-- Clicking a node selects it and the card on the right explains it; LEARN spends a point
-- (SkillSpend). RESET TAB (click twice) refunds the tab's points for free (SkillRespec).
-- All the rules come from SkillMath, the same ones the server enforces.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SkillTrees = require(ReplicatedStorage.Shared.Config.SkillTrees)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Icons = require(ReplicatedStorage.Shared.Icons)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local WeaponIcon = require(script.Parent.WeaponIcon)

local OPEN_KEY = Enum.KeyCode.K
local PANEL_SIZE = Vector2.new(1000, 620)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local GLOW_COLOR = Color3.fromRGB(255, 215, 90)
local GLOW_TWEEN = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local NODE_COLOR = Color3.fromRGB(58, 54, 74)
local LOCKED_COLOR = Color3.fromRGB(36, 34, 46)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local ACCENT = Color3.fromRGB(255, 210, 120)
local OWNED = Color3.fromRGB(110, 230, 140)
local MAXED = Color3.fromRGB(255, 205, 70)
local RED = Color3.fromRGB(215, 80, 75)
local LINE_DIM = Color3.fromRGB(80, 76, 96)
local LINE_LIT = Color3.fromRGB(255, 220, 140)

local CANVAS = { position = Vector2.new(40, 182), size = Vector2.new(640, 396) }
local INFO = { position = Vector2.new(700, 182), size = Vector2.new(260, 396) }
local NODE_SIZE = 58
local ROOT_SIZE = 72
local TAB_Y = 136
local TAB_TEXT_SIZE = 16
local TAB_GAP = 20
local ICON_SIZE = 52
local BLUR_SIZE = 14
local BLUR_TWEEN = TweenInfo.new(0.2)
local RESET_CONFIRM_TIME = 3

-- General tree shape: the root, how far out each tier sits, and each branch's direction
-- (degrees from straight up; rivals on opposite sides).
-- The General tree is drawn on a canvas bigger than the window (drag to pan around it).
local GENERAL_WORLD = Vector2.new(1150, 740)
local GENERAL_ROOT = Vector2.new(575, 660)
local GENERAL_TIER_DISTANCE = { 200, 345, 490 }
local GENERAL_BRANCH_WIDTH = { 13, 10, 7 } -- branch thickness into each tier
local DRAG_CLICK_SLOP = 6 -- a press that moves further than this is a drag, not a click
local GENERAL_BEND = 0.05 -- each tier leans this much further out, like a branch curling up
local BRANCH_ANGLES: { [string]: number } = { Mobility = -66, Vitality = -40, Endurance = -13, Arcana = 13, Might = 40, Guard = 66 }
-- The staff's Mage tree uses the same shape, one branch per element plus Arcane.
local STAFF_BRANCH_ANGLES: { [string]: number } = { Fire = -66, Water = -40, Earth = -13, Electric = 13, Faith = 40, Arcane = 66 }

-- Weapon tree shape: root, then each tier's height; tiers with two nodes split left/right.
local WEAPON_ROOT = Vector2.new(320, 352)
local WEAPON_TIER_Y = { 276, 200, 124, 44 }
local WEAPON_SPLIT_X = { 0, 120, 120, 150 }
local WEAPON_BRANCH_WIDTH = { 11, 9, 7, 6 }

-- Crooked branches: each link bends at a few points by up to this much of its length, with
-- a knot at each bend and, now and then, a short twig.
local BRANCH_BENDS = 3
local BRANCH_WOBBLE = 0.09
local TWIG_CHANCE = 0.5

-- Each skill's icon is the Icons entry named after it; these are named differently. Skills
-- without one show their branch's icon.
local NODE_ICONS: { [string]: string } = {
	FireUnlock = "Fire", WaterUnlock = "Water", EarthUnlock = "Earth", ElectricUnlock = "Electric", FaithUnlock = "Faith",
}

local function iconFor(nodeId: string, fallback: string): string
	return NODE_ICONS[nodeId] or (if Icons.has(nodeId) then nodeId else fallback)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spendRemote = remotes:WaitForChild("SkillSpend") :: RemoteEvent
local respecRemote = remotes:WaitForChild("SkillRespec") :: RemoteEvent

local player = Players.LocalPlayer

local SkillTree = {}

local function text(parent: Instance, value: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = value
	label.Parent = parent
	return label
end

type Line = { frames: { Frame }, from: string?, treeId: string }
type NodeView = {
	treeId: string,
	node: SkillTrees.Node,
	frame: Frame,
	stroke: UIStroke,
	icon: ImageLabel,
	rank: TextLabel,
	name: TextLabel,
}

function SkillTree.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillTree"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The always-on icon, under the backpack's, with a counter of unspent points.
	local icon = HudStyle.badge(HudStyle.holder(gui, Vector2.new(0, 0.5)), ICON_SIZE, Color3.fromRGB(150, 110, 220), "Skills")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 20, 0.5, 76)
	local keyHint = HudStyle.caption(icon, OPEN_KEY.Name, 16)
	keyHint.AnchorPoint = Vector2.new(0.5, 0.5)
	keyHint.Position = UDim2.new(0.5, 0, 1, 0)
	keyHint.Size = UDim2.fromOffset(20, 16)
	local pointsDot = HudStyle.caption(icon, "", 14)
	pointsDot.AnchorPoint = Vector2.new(0.5, 0.5)
	pointsDot.Position = UDim2.new(1, -4, 0, 4)
	pointsDot.Size = UDim2.fromOffset(22, 22)
	pointsDot.BackgroundColor3 = RED
	pointsDot.BackgroundTransparency = 0
	pointsDot.ZIndex = 3
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = pointsDot
	local iconButton = Instance.new("TextButton")
	iconButton.Size = UDim2.fromScale(1, 1)
	iconButton.BackgroundTransparency = 1
	iconButton.Text = ""
	iconButton.ZIndex = 4
	iconButton.Parent = icon
	-- While there are points to spend, the icon's outline glows gold on and off.
	local iconStroke = icon:FindFirstChildOfClass("UIStroke") :: UIStroke
	local glow: Tween? = nil
	local function setGlowing(on: boolean)
		if on == (glow ~= nil) then
			return
		end
		if glow then
			glow:Cancel()
			glow = nil
			iconStroke.Color = HudStyle.OUTLINE
		else
			local tween = TweenService:Create(iconStroke, GLOW_TWEEN, { Color = GLOW_COLOR })
			tween:Play()
			glow = tween
		end
	end

	-- The panel, in a holder that scales it down on small screens.
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local function refit()
		local screen = workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(1, (screen.X - 40) / PANEL_SIZE.X, (screen.Y - 40) / PANEL_SIZE.Y)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0
	panel.Visible = false
	panel.Parent = holder
	HudStyle.chunky(panel, 26, 4)
	local rim = panel:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(200, 200, 215)
	end
	Instance.new("UIScale").Parent = panel
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	-- Header: title, BACK, level and XP, unspent points, reset.
	local title = text(panel, "// SKILLS", 38)
	title.Position = UDim2.fromOffset(40, 28)
	title.Size = UDim2.fromOffset(300, 44)
	local back = Instance.new("TextButton")
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, -36, 0, 32)
	back.Size = UDim2.fromOffset(110, 36)
	back.BackgroundTransparency = 1
	back.Font = HudStyle.FONT
	back.TextSize = 22
	back.TextColor3 = Color3.new(1, 1, 1)
	back.TextXAlignment = Enum.TextXAlignment.Right
	back.Text = "BACK  →"
	back.Parent = panel

	local levelLabel = text(panel, "", 18)
	levelLabel.Position = UDim2.fromOffset(40, 92)
	levelLabel.Size = UDim2.fromOffset(90, 20)
	local xpBack = Instance.new("Frame")
	xpBack.Position = UDim2.fromOffset(136, 95)
	xpBack.Size = UDim2.fromOffset(250, 14)
	xpBack.BackgroundColor3 = HudStyle.EMPTY
	xpBack.Parent = panel
	HudStyle.chunky(xpBack, 7, 2)
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(150, 110, 220)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	local xpCorner = Instance.new("UICorner")
	xpCorner.CornerRadius = UDim.new(0, 5)
	xpCorner.Parent = xpFill
	HudStyle.gloss(xpFill)
	local xpLabel = text(panel, "", 15, SOFT_TEXT)
	xpLabel.Position = UDim2.fromOffset(398, 92)
	xpLabel.Size = UDim2.fromOffset(140, 20)

	local pointsLabel = text(panel, "", 22, ACCENT)
	pointsLabel.AnchorPoint = Vector2.new(1, 0)
	pointsLabel.Position = UDim2.new(1, -190, 0, 88)
	pointsLabel.Size = UDim2.fromOffset(260, 26)
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Right
	local reset = Instance.new("TextButton")
	reset.AnchorPoint = Vector2.new(1, 0)
	reset.Position = UDim2.new(1, -40, 0, 86)
	reset.Size = UDim2.fromOffset(136, 32)
	reset.BackgroundColor3 = Color3.fromRGB(95, 95, 110)
	reset.Font = HudStyle.FONT
	reset.TextSize = 15
	reset.TextColor3 = Color3.new(1, 1, 1)
	reset.Text = "RESET TAB"
	reset.Parent = panel
	HudStyle.chunky(reset, 8, 2.5)
	HudStyle.gloss(reset)

	-- Tabs.
	type Tab = { id: string, button: TextButton, x: number, width: number }
	local tabs: { Tab } = {}
	local tabIds = { "General" }
	for _, weapon in SkillTrees.WeaponOrder do
		table.insert(tabIds, weapon)
	end
	local tabX = 40
	for _, id in tabIds do
		local label = id:upper()
		local width = math.ceil(TextService:GetTextSize(label, TAB_TEXT_SIZE, HudStyle.FONT, Vector2.new(400, 40)).X)
		local tab = Instance.new("TextButton")
		tab.BackgroundTransparency = 1
		tab.Font = HudStyle.FONT
		tab.TextSize = TAB_TEXT_SIZE
		tab.Text = label
		tab.Position = UDim2.fromOffset(tabX, TAB_Y)
		tab.Size = UDim2.fromOffset(width, 28)
		tab.Parent = panel
		table.insert(tabs, { id = id, button = tab, x = tabX, width = width })
		tabX += width + TAB_GAP
	end
	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(40, TAB_Y + 36)
	divider.Size = UDim2.fromOffset(920, 2)
	divider.BackgroundColor3 = LINE_DIM
	divider.BorderSizePixel = 0
	divider.Parent = panel
	local underline = Instance.new("Frame")
	underline.BackgroundColor3 = Color3.new(1, 1, 1)
	underline.BorderSizePixel = 0
	underline.ZIndex = 2
	underline.Parent = panel
	local underlineCorner = Instance.new("UICorner")
	underlineCorner.CornerRadius = UDim.new(0, 2)
	underlineCorner.Parent = underline

	-- The info card on the right.
	local info = Instance.new("Frame")
	info.Position = UDim2.fromOffset(INFO.position.X, INFO.position.Y)
	info.Size = UDim2.fromOffset(INFO.size.X, INFO.size.Y)
	info.BackgroundColor3 = NODE_COLOR
	info.BackgroundTransparency = 0.25
	info.Parent = panel
	HudStyle.chunky(info, 16, 3)
	local infoIcon = Icons.image(info, nil)
	infoIcon.AnchorPoint = Vector2.new(0, 0)
	infoIcon.Position = UDim2.fromOffset(16, 14)
	infoIcon.Size = UDim2.fromOffset(56, 56)
	local infoName = text(info, "", 22)
	infoName.Position = UDim2.fromOffset(80, 16)
	infoName.Size = UDim2.new(1, -92, 0, 26)
	infoName.TextWrapped = true
	local infoTree = text(info, "", 13, SOFT_TEXT)
	infoTree.Position = UDim2.fromOffset(80, 44)
	infoTree.Size = UDim2.new(1, -92, 0, 16)
	local infoRank = text(info, "", 17, ACCENT)
	infoRank.Position = UDim2.fromOffset(16, 82)
	infoRank.Size = UDim2.new(1, -32, 0, 20)
	local infoBody = text(info, "", 15)
	infoBody.Position = UDim2.fromOffset(16, 110)
	infoBody.Size = UDim2.new(1, -32, 0, 170)
	infoBody.TextWrapped = true
	infoBody.TextYAlignment = Enum.TextYAlignment.Top
	local infoStatus = text(info, "", 14, SOFT_TEXT)
	infoStatus.AnchorPoint = Vector2.new(0, 1)
	infoStatus.Position = UDim2.new(0, 16, 1, -66)
	infoStatus.Size = UDim2.new(1, -32, 0, 34)
	infoStatus.TextWrapped = true
	infoStatus.TextYAlignment = Enum.TextYAlignment.Bottom
	local learn = Instance.new("TextButton")
	learn.AnchorPoint = Vector2.new(0.5, 1)
	learn.Position = UDim2.new(0.5, 0, 1, -16)
	learn.Size = UDim2.new(1, -32, 0, 42)
	learn.Font = HudStyle.FONT
	learn.TextSize = 20
	learn.TextColor3 = Color3.new(1, 1, 1)
	learn.Parent = info
	HudStyle.chunky(learn, 10, 3)
	HudStyle.gloss(learn)
	Instance.new("UIScale").Parent = learn

	-- The trees -----------------------------------------------------------------------------

	local pages: { [string]: Frame } = {}
	local nodeViews: { NodeView } = {}
	local lines: { Line } = {}
	local branchLocks: { { branch: SkillTrees.Branch, label: TextLabel, icon: ImageLabel, views: { NodeView } } } = {}
	local selected: NodeView? = nil
	local selectedTab = "General"
	local dragMoved = 0 -- how far the current (or last) press has dragged the canvas
	local refresh: () -> ()

	-- The trees are drawn inside a clipped window over the canvas area; a tree bigger than
	-- the window (General) can be dragged around inside it.
	local canvasBack = Instance.new("Frame")
	canvasBack.Position = UDim2.fromOffset(CANVAS.position.X, CANVAS.position.Y)
	canvasBack.Size = UDim2.fromOffset(CANVAS.size.X, CANVAS.size.Y)
	canvasBack.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
	canvasBack.Parent = panel
	HudStyle.chunky(canvasBack, 14, 2)
	local window = Instance.new("Frame")
	window.Position = UDim2.fromOffset(CANVAS.position.X, CANVAS.position.Y)
	window.Size = UDim2.fromOffset(CANVAS.size.X, CANVAS.size.Y)
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.Parent = panel
	local dragHint = HudStyle.caption(panel, "drag to look around", 13)
	dragHint.AnchorPoint = Vector2.new(0, 1)
	dragHint.Position = UDim2.fromOffset(CANVAS.position.X + 10, CANVAS.position.Y + CANVAS.size.Y - 6)
	dragHint.Size = UDim2.fromOffset(170, 16)
	dragHint.TextXAlignment = Enum.TextXAlignment.Left
	dragHint.TextColor3 = SOFT_TEXT
	dragHint.ZIndex = 6

	type PageInfo = { frame: Frame, size: Vector2, pannable: boolean }
	local pageInfo: { [string]: PageInfo } = {}

	local function setPan(info: PageInfo, offset: Vector2)
		local x = math.clamp(offset.X, math.min(CANVAS.size.X - info.size.X, 0), 0)
		local y = math.clamp(offset.Y, math.min(CANVAS.size.Y - info.size.Y, 0), 0)
		info.frame.Position = UDim2.fromOffset(x, y)
	end

	-- A tree's canvas; `size` bigger than the window makes it draggable, starting with `focus`
	-- (a point on it) at the bottom centre of the window.
	local function makePage(id: string, size: Vector2?, focus: Vector2?): Frame
		local worldSize = size or CANVAS.size
		local page = Instance.new("Frame")
		page.Size = UDim2.fromOffset(worldSize.X, worldSize.Y)
		page.BackgroundTransparency = 1
		page.Visible = false
		page.Parent = window
		pages[id] = page
		local info: PageInfo = { frame = page, size = worldSize, pannable = worldSize ~= CANVAS.size }
		pageInfo[id] = info
		local start = if focus then Vector2.new(CANVAS.size.X / 2 - focus.X, CANVAS.size.Y - focus.Y - 70) else Vector2.zero
		setPan(info, start)
		return page
	end

	-- A stable pseudo-random seed from text, so each branch bends the same way every time.
	local function seedOf(textValue: string): number
		local seed = 0
		for index = 1, #textValue do
			seed = (seed * 31 + string.byte(textValue, index)) % 2147483647
		end
		return seed
	end

	local function segment(page: Frame, a: Vector2, b: Vector2, width: number, frames: { Frame })
		local delta = b - a
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		frame.Size = UDim2.fromOffset(delta.Magnitude + width * 0.5, width)
		frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		frame.BackgroundColor3 = LINE_DIM
		frame.BorderSizePixel = 0
		frame.Parent = page
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		table.insert(frames, frame)
	end

	-- A crooked branch between two node centres, `width` thick; lit once `fromNode` (in
	-- `treeId`) is learned (or always, from the root, when `fromNode` is nil).
	local function branchLine(page: Frame, a: Vector2, b: Vector2, treeId: string, fromNode: string?, width: number)
		local random = Random.new(seedOf(`{treeId}:{fromNode or "root"}:{math.floor(b.X)}:{math.floor(b.Y)}`))
		local delta = b - a
		local normal = Vector2.new(-delta.Y, delta.X).Unit
		local points = { a }
		for bend = 1, BRANCH_BENDS - 1 do
			local along = bend / BRANCH_BENDS + random:NextNumber(-0.07, 0.07)
			local wobble = random:NextNumber(-1, 1) * delta.Magnitude * BRANCH_WOBBLE
			table.insert(points, a + delta * along + normal * wobble)
		end
		table.insert(points, b)

		local frames: { Frame } = {}
		for index = 1, #points - 1 do
			-- A little thinner toward the far end of each link.
			local taper = width * (1 - 0.12 * (index - 1))
			segment(page, points[index], points[index + 1], taper, frames)
		end
		-- Knots at the bends, so the joins look like bark rather than gaps.
		for index = 2, #points - 1 do
			local knot = Instance.new("Frame")
			knot.AnchorPoint = Vector2.new(0.5, 0.5)
			knot.Position = UDim2.fromOffset(points[index].X, points[index].Y)
			knot.Size = UDim2.fromOffset(width + 3, width + 3)
			knot.BackgroundColor3 = LINE_DIM
			knot.BorderSizePixel = 0
			knot.Parent = page
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = knot
			table.insert(frames, knot)
		end
		-- Now and then a short twig off one of the bends.
		if random:NextNumber() < TWIG_CHANCE and #points > 2 then
			local from = points[random:NextInteger(2, #points - 1)]
			local direction = delta.Unit
			local side = if random:NextNumber() < 0.5 then -1 else 1
			local angle = math.rad(random:NextNumber(35, 60)) * side
			local twigDirection = Vector2.new(
				direction.X * math.cos(angle) - direction.Y * math.sin(angle),
				direction.X * math.sin(angle) + direction.Y * math.cos(angle)
			)
			segment(page, from, from + twigDirection * random:NextNumber(16, 28), math.max(width * 0.45, 3), frames)
		end
		table.insert(lines, { frames = frames, from = fromNode, treeId = treeId })
	end

	local function makeNode(page: Frame, treeId: string, node: SkillTrees.Node, center: Vector2, fallbackIcon: string): NodeView
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(center.X, center.Y)
		frame.Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE)
		frame.BackgroundColor3 = NODE_COLOR
		frame.ZIndex = 3
		frame.Parent = page
		HudStyle.chunky(frame, NODE_SIZE // 2, 3)
		Instance.new("UIScale").Parent = frame
		local iconLabel = Icons.image(frame, iconFor(node.Id, fallbackIcon), 9)
		iconLabel.ZIndex = 3
		local rank = HudStyle.caption(frame, "", 13)
		rank.AnchorPoint = Vector2.new(0.5, 0.5)
		rank.Position = UDim2.new(0.5, 0, 1, 0)
		rank.Size = UDim2.fromOffset(36, 16)
		rank.BackgroundColor3 = HudStyle.OUTLINE
		rank.BackgroundTransparency = 0
		rank.ZIndex = 4
		local rankCorner = Instance.new("UICorner")
		rankCorner.CornerRadius = UDim.new(1, 0)
		rankCorner.Parent = rank
		local name = HudStyle.caption(page, node.Name, 12)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.fromOffset(center.X, center.Y + NODE_SIZE / 2 + 10)
		name.Size = UDim2.fromOffset(110, 14)
		name.ZIndex = 3
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 5
		button.Parent = frame
		local view: NodeView = {
			treeId = treeId,
			node = node,
			frame = frame,
			stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke,
			icon = iconLabel,
			rank = rank,
			name = name,
		}
		button.Activated:Connect(function()
			if dragMoved > DRAG_CLICK_SLOP then
				return -- that was a drag across the canvas, not a click on this node
			end
			selected = view
			HudStyle.pop(frame, 1.12)
			refresh()
		end)
		table.insert(nodeViews, view)
		return view
	end

	local function makeRoot(page: Frame, center: Vector2, label: string): Frame
		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromOffset(center.X, center.Y)
		root.Size = UDim2.fromOffset(ROOT_SIZE, ROOT_SIZE)
		root.BackgroundColor3 = Color3.fromRGB(90, 70, 140)
		root.ZIndex = 3
		root.Parent = page
		HudStyle.chunky(root, ROOT_SIZE // 2, 4)
		HudStyle.gloss(root)
		local caption = HudStyle.caption(page, label, 14)
		caption.AnchorPoint = Vector2.new(0.5, 0)
		caption.Position = UDim2.fromOffset(center.X, center.Y + ROOT_SIZE / 2 + 4)
		caption.Size = UDim2.fromOffset(120, 16)
		caption.TextColor3 = ACCENT
		return root
	end

	-- A tree drawn as branches fanning out and up from a root (the General tree, and the
	-- staff's Mage tree): each branch climbs node by node in its own direction (`angles`, by
	-- branch id), with its name past its tip. Links from the root light up once `rootNode` is
	-- learned (or always, with no root node).
	local function radialTree(page: Frame, treeId: string, branches: { SkillTrees.Branch }, angles: { [string]: number }, rootNode: string?)
		local function along(angle: number, distance: number): Vector2
			local radians = math.rad(angle)
			return GENERAL_ROOT + Vector2.new(math.sin(radians) * distance, -math.cos(radians) * distance)
		end
		for _, branch in branches do
			local angle = angles[branch.Id] or 0
			local previous = GENERAL_ROOT
			local previousNode: string? = rootNode
			local views: { NodeView } = {}
			local last = GENERAL_ROOT
			for step, node in branch.Nodes do
				local center = along(angle * (1 + GENERAL_BEND * (step - 1)), GENERAL_TIER_DISTANCE[step] or 300)
				branchLine(page, previous, center, treeId, previousNode, GENERAL_BRANCH_WIDTH[step] or 6)
				table.insert(views, makeNode(page, treeId, node, center, branch.Icon))
				previous, previousNode, last = center, node.Id, center
			end
			-- The branch's name past its tip.
			local tipDirection = (last - GENERAL_ROOT).Unit
			local labelPosition = last + tipDirection * 72
			local label = HudStyle.caption(page, branch.Name:upper(), 15)
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromOffset(math.clamp(labelPosition.X, 80, GENERAL_WORLD.X - 80), math.max(labelPosition.Y, 20))
			label.Size = UDim2.fromOffset(150, 34)
			label.TextColor3 = ACCENT
			label.TextWrapped = true
			local icon = HudStyle.iconBeside(label, branch.Icon, 20)
			table.insert(branchLocks, { branch = branch, label = label, icon = icon, views = views })
		end
	end

	-- General: branches fanning out and up from you.
	do
		local page = makePage("General", GENERAL_WORLD, GENERAL_ROOT)
		local root = makeRoot(page, GENERAL_ROOT, "YOU")
		local star = Icons.image(root, "Star", 10)
		star.ZIndex = 3
		radialTree(page, "General", SkillTrees.General, BRANCH_ANGLES, nil)
	end

	-- Staff: the Mage class. The Mage node is the root; each element's branch grows from it.
	do
		local page = makePage("Staff", GENERAL_WORLD, GENERAL_ROOT)
		makeNode(page, "Staff", SkillTrees.StaffClassNode, GENERAL_ROOT, "Mage")
		radialTree(page, "Staff", SkillTrees.StaffBranches, STAFF_BRANCH_ANGLES, SkillTrees.StaffClass)
	end

	-- Weapons: a trunk from the weapon that splits into two branches and ends in the masteries.
	for _, weapon in SkillTrees.WeaponOrder do
		if weapon == "Staff" then
			continue -- drawn as the Mage tree, above
		end
		local page = makePage(weapon)
		local root = makeRoot(page, WEAPON_ROOT, weapon:upper())
		local viewport = WeaponIcon.viewport(root)
		viewport.ZIndex = 3
		WeaponIcon.show(viewport, weapon)
		WeaponIcon.Previews.ChildAdded:Connect(function(child)
			if child.Name == weapon then
				WeaponIcon.show(viewport, weapon)
			end
		end)

		-- Lay each tier's nodes out side by side, then join each to the tier below.
		local byTier: { { SkillTrees.Node } } = {}
		for _, node in SkillTrees.Weapons[weapon] do
			byTier[node.Tier] = byTier[node.Tier] or {}
			table.insert(byTier[node.Tier], node)
		end
		local below: { { center: Vector2, id: string? } } = { { center = WEAPON_ROOT, id = nil } }
		for tier = 1, #WEAPON_TIER_Y do
			local nodes = byTier[tier] or {}
			local here: { { center: Vector2, id: string? } } = {}
			for index, node in nodes do
				local offset = if #nodes == 1 then 0 elseif index == 1 then -WEAPON_SPLIT_X[tier] else WEAPON_SPLIT_X[tier]
				local center = Vector2.new(WEAPON_ROOT.X + offset, WEAPON_TIER_Y[tier])
				-- Join to the node below on the same side (or the single node below).
				local parent = if #below == 1 then below[1] elseif #nodes == 1 then below[1] else below[math.min(index, #below)]
				branchLine(page, parent.center, center, weapon, parent.id, WEAPON_BRANCH_WIDTH[tier] or 6)
				if #below == 2 and #nodes == 1 then
					branchLine(page, below[2].center, center, weapon, below[2].id, WEAPON_BRANCH_WIDTH[tier] or 6)
				end
				makeNode(page, weapon, node, center, "Sparkles")
				table.insert(here, { center = center, id = node.Id })
			end
			if tier == #WEAPON_TIER_Y and #nodes == 2 then
				local orLabel = HudStyle.caption(page, "OR", 20)
				orLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				orLabel.Position = UDim2.fromOffset(WEAPON_ROOT.X, WEAPON_TIER_Y[tier])
				orLabel.Size = UDim2.fromOffset(40, 24)
				orLabel.TextColor3 = ACCENT
				orLabel.ZIndex = 4
			end
			if #here > 0 then
				below = here
			end
		end
	end

	-- Updating -----------------------------------------------------------------------------

	refresh = function()
		local alloc = SkillMath.allocations(player)
		local level = SkillMath.level(player)
		local points = SkillMath.availablePoints(alloc, level)

		-- Header.
		local xp = player:GetAttribute("XP")
		local toNext = player:GetAttribute("XPToNext")
		levelLabel.Text = `LEVEL {level}`
		if typeof(xp) == "number" and typeof(toNext) == "number" and toNext > 0 then
			xpFill.Size = UDim2.fromScale(math.clamp(xp / toNext, 0, 1), 1)
			xpLabel.Text = `{math.floor(xp)} / {toNext} XP`
		else
			xpFill.Size = UDim2.fromScale(1, 1)
			xpLabel.Text = "MAX LEVEL"
		end
		pointsLabel.Text = `SKILL POINTS: {points}`
		pointsDot.Text = tostring(points)
		pointsDot.Visible = points > 0
		setGlowing(points > 0)

		-- Tabs (trees with points in them are tinted gold).
		for _, tab in tabs do
			local isSelected = tab.id == selectedTab
			tab.button.TextColor3 = if isSelected then Color3.new(1, 1, 1) elseif SkillMath.spent(alloc, tab.id) > 0 then ACCENT else SOFT_TEXT
			pages[tab.id].Visible = isSelected
			if isSelected then
				underline.Position = UDim2.fromOffset(tab.x - 6, TAB_Y + 33)
				underline.Size = UDim2.fromOffset(tab.width + 12, 4)
			end
		end

		-- Nodes.
		for _, view in nodeViews do
			local rank = SkillMath.rank(alloc, view.treeId, view.node.Id)
			local ok = SkillMath.check(alloc, level, view.treeId, view.node.Id)
			view.rank.Text = `{rank}/{view.node.MaxRank}`
			local color, border, iconFade
			if rank >= view.node.MaxRank then
				color, border, iconFade = Color3.fromRGB(96, 80, 44), MAXED, 0
			elseif rank > 0 then
				color, border, iconFade = Color3.fromRGB(46, 84, 60), OWNED, 0
			elseif ok then
				color, border, iconFade = NODE_COLOR, Color3.new(1, 1, 1), 0
			else
				color, border, iconFade = LOCKED_COLOR, HudStyle.OUTLINE, 0.6
			end
			view.frame.BackgroundColor3 = color
			view.stroke.Color = if view == selected then ACCENT else border
			view.stroke.Thickness = if view == selected then 5 else 3
			view.icon.ImageTransparency = iconFade
			view.name.TextColor3 = if rank > 0 then Color3.new(1, 1, 1) else SOFT_TEXT
		end

		-- Branch lines light up from learned nodes (and from the root).
		for _, line in lines do
			local lit = line.from == nil or SkillMath.rank(alloc, line.treeId, line.from) > 0
			for _, frame in line.frames do
				frame.BackgroundColor3 = if lit then LINE_LIT else LINE_DIM
			end
		end
		dragHint.Visible = pageInfo[selectedTab].pannable

		-- General branches locked by their rival.
		for _, entry in branchLocks do
			local rival = entry.branch.Rival
			local lockedBy = rival and SkillMath.spentInBranch(alloc, rival) > 0
			entry.label.Text = if lockedBy then `{entry.branch.Name:upper()}\nlocked by {rival}` else entry.branch.Name:upper()
			Icons.set(entry.icon, if lockedBy then "Lock" else entry.branch.Icon)
			entry.label.TextColor3 = if lockedBy then SOFT_TEXT else ACCENT
			for _, view in entry.views do
				view.frame.BackgroundTransparency = if lockedBy then 0.55 else 0
			end
		end

		-- The info card.
		local view = selected
		if view and view.treeId ~= selectedTab then
			view = nil
		end
		if view then
			local node = view.node
			local rank = SkillMath.rank(alloc, view.treeId, node.Id)
			local ok, reason = SkillMath.check(alloc, level, view.treeId, node.Id)
			local branch = SkillMath.branchOf(node.Id)
			infoIcon.Image = view.icon.Image
			infoIcon.ImageRectOffset = view.icon.ImageRectOffset
			infoIcon.ImageRectSize = view.icon.ImageRectSize
			infoName.Text = node.Name
			infoTree.Text = if view.treeId == "General" and branch then `{branch.Name} · tier {node.Tier}` else `{view.treeId} · tier {node.Tier}`
			infoRank.Text = `RANK {rank} / {node.MaxRank}`
			local extra = ""
			if node.Exclusive then
				local other = SkillMath.node(view.treeId, node.Exclusive)
				extra = `\n\nMastery: can't be taken with {if other then other.Name else node.Exclusive}.`
			end
			infoBody.Text = `{node.Description}{if node.MaxRank > 1 then " (per rank)" else ""}{extra}`
			if rank >= node.MaxRank then
				infoStatus.Text = "Fully learned."
				learn.Text = "MAXED"
				learn.BackgroundColor3 = MAXED
				learn.Active = false
			elseif ok then
				infoStatus.Text = "Costs 1 skill point."
				learn.Text = if rank > 0 then "UPGRADE" else "LEARN"
				learn.BackgroundColor3 = OWNED
				learn.Active = true
			else
				infoStatus.Text = reason or "Locked"
				learn.Text = "LOCKED"
				learn.BackgroundColor3 = Color3.fromRGB(80, 78, 92)
				learn.Active = false
			end
			learn.Visible = true
		else
			Icons.set(infoIcon, if selectedTab == "General" then "Star" elseif selectedTab == "Staff" then "Mage" else "Swords")
			infoName.Text = if selectedTab == "General" then "General" elseif selectedTab == "Staff" then "Mage" else selectedTab
			infoTree.Text = `{SkillMath.spent(alloc, selectedTab)} points spent here`
			infoRank.Text = ""
			infoBody.Text = if selectedTab == "General"
				then "Grow the branches you want. Points are shared by every tree, and spending in a branch locks its rival on the other side (Mobility ↔ Guard, Vitality ↔ Might, Endurance ↔ Arcana) until you reset.\n\nClick a skill to see it."
				elseif selectedTab == "Staff" then "The staff's magic. Unlock the Mage class (the root) to cast at all, then unlock each element's branch to use that element, and grow its upgrades.\n\nClick a skill to see it."
				else `Make the {selectedTab} hit harder and handle better. Higher tiers need points spent in this tree. The masteries at the top are a choice: take one and the other locks.\n\nClick a skill to see it.`
			infoStatus.Text = ""
			learn.Visible = false
		end
	end

	-- Dragging the canvas (mouse or touch) pans a tree that's bigger than the window.
	type Drag = { input: InputObject?, start: Vector2, pan: Vector2, info: PageInfo }
	local drag: Drag? = nil
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	window.InputBegan:Connect(function(input)
		local info = pageInfo[selectedTab]
		if not isPress(input) or not info or not info.pannable then
			return
		end
		dragMoved = 0
		local position = info.frame.Position
		drag = {
			input = if input.UserInputType == Enum.UserInputType.Touch then input else nil,
			start = Vector2.new(input.Position.X, input.Position.Y),
			pan = Vector2.new(position.X.Offset, position.Y.Offset),
			info = info,
		}
	end)
	UserInputService.InputChanged:Connect(function(input)
		local current = drag
		if not current then
			return
		end
		local moving = input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and (current.input == nil or input == current.input))
		if moving then
			-- Screen pixels to canvas pixels (the panel is scaled down on small screens).
			local delta = (Vector2.new(input.Position.X, input.Position.Y) - current.start) / fit.Scale
			dragMoved = math.max(dragMoved, delta.Magnitude)
			setPan(current.info, current.pan + delta)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if drag and isPress(input) then
			drag = nil
			-- Forget the drag once this release's click (if any) has been ignored.
			task.delay(0.05, function()
				if not drag then
					dragMoved = 0
				end
			end)
		end
	end)

	learn.Activated:Connect(function()
		local view = selected
		if not view then
			return
		end
		local ok = SkillMath.check(SkillMath.allocations(player), SkillMath.level(player), view.treeId, view.node.Id)
		if ok then
			spendRemote:FireServer(view.treeId, view.node.Id)
			HudStyle.pop(learn, 1.1)
			HudStyle.pop(view.frame, 1.25)
		else
			HudStyle.pop(learn, 0.9)
		end
	end)

	-- Opening, closing, resetting.
	local blur = Instance.new("BlurEffect")
	blur.Name = "SkillTreeBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	local function setOpen(open: boolean)
		if open == panel.Visible then
			return
		end
		panel.Visible = open
		if open then
			Panels.opened("SkillTree")
			refresh()
			HudStyle.pop(panel, 0.92)
			blur.Enabled = true
			TweenService:Create(blur, BLUR_TWEEN, { Size = BLUR_SIZE }):Play()
		else
			Panels.closed("SkillTree")
			local fade = TweenService:Create(blur, BLUR_TWEEN, { Size = 0 })
			fade.Completed:Connect(function()
				if not panel.Visible then
					blur.Enabled = false
				end
			end)
			fade:Play()
		end
	end
	local function toggle()
		setOpen(not panel.Visible)
		HudStyle.pop(icon, if panel.Visible then 1.2 else 0.85)
	end
	Panels.register("SkillTree", function()
		setOpen(false)
	end)

	for _, tab in tabs do
		tab.button.Activated:Connect(function()
			selectedTab = tab.id
			selected = nil
			dragMoved = 0
			refresh()
		end)
	end

	local confirmUntil = 0
	local function resetButtonIdle()
		reset.Text = "RESET TAB"
		reset.BackgroundColor3 = Color3.fromRGB(95, 95, 110)
	end
	reset.Activated:Connect(function()
		if os.clock() < confirmUntil then
			confirmUntil = 0
			respecRemote:FireServer(selectedTab)
			resetButtonIdle()
		else
			confirmUntil = os.clock() + RESET_CONFIRM_TIME
			reset.Text = "CLICK AGAIN"
			reset.BackgroundColor3 = RED
			task.delay(RESET_CONFIRM_TIME, function()
				if os.clock() >= confirmUntil then
					resetButtonIdle()
				end
			end)
		end
	end)

	iconButton.Activated:Connect(toggle)
	back.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == OPEN_KEY then
			toggle()
		end
	end)

	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Skills" or attribute == "SkillPoints" or attribute == "Level" or attribute == "XP" or attribute == "XPToNext" then
			refresh()
		end
	end)
	refresh()
end

return SkillTree
