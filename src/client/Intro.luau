--!strict
-- The new-player intro. A player who hasn't picked a starter yet ("Starter" attribute "", see
-- server StarterService) sees:
--   1. The story: a letterboxed cutscene flown over the real world, a narrated line per shot
--      (IntroConfig.Shots), then the title card. Skippable.
--   2. The Hall of Oaths (server ClassHall): the camera swings between the statues, one per
--      starter class, while a panel on the left shows the class (name, gear, lore, stats,
--      playstyle) and crests on the right pick which one. Select, then confirm, fires
--      StarterChoose; the server checks and grants the pick.
--   3. Once the pick lands ("Starter" changes), a fade back to the player's character.
-- While it runs the rest of the HUD is hidden and the character can't move.
-- Streaming is on, so each shot's surroundings are requested before the camera goes there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local IntroConfig = require(ReplicatedStorage.Shared.Config.IntroConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local Starter = require(ReplicatedStorage.Shared.Starter)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local WeaponIcon = require(script.Parent.WeaponIcon)
local DayNight = require(script.Parent.DayNight)

local INTRO_CLOCK = 14.5 -- the intro is always shot in the afternoon, whatever the time

local chooseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StarterChoose") :: RemoteEvent

local player = Players.LocalPlayer

local DISPLAY_FONT = Enum.Font.Fondamento -- story text, titles, lore
local PANEL = Color3.fromRGB(36, 28, 22)
local GOLD = Color3.fromRGB(226, 188, 112)
local GOLD_DARK = Color3.fromRGB(140, 104, 56)
local MINT = Color3.fromRGB(176, 238, 218)
local TEXT = Color3.fromRGB(240, 228, 204)
local SOFT_TEXT = Color3.fromRGB(196, 178, 148)
local TRACK = Color3.fromRGB(70, 56, 42)
local CREST = Color3.fromRGB(62, 49, 37)
local CREST_SELECTED = Color3.fromRGB(104, 80, 50)
local DIFFICULTY_COLOR = Color3.fromRGB(226, 128, 92)
local BUTTON_DARK = Color3.fromRGB(30, 24, 20)

local PANEL_SIZE = Vector2.new(370, 600)
local CREST_SIZE = 74
local CREST_CELL = Vector2.new(88, 98)
local SHOT_FADE = 0.5 -- the dip to black between story shots
local TEXT_FADE = 0.8
local STREAM_TIMEOUT = 6
local CONFIRM_RETRY = 8 -- seconds before the oath button works again if the server never answered
local STAT_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Intro = {}

local function hasPicked(): boolean
	local value = player:GetAttribute("Starter")
	return typeof(value) == "string" and value ~= ""
end

local function fade(object: Instance, time: number, goal: { [string]: any }): Tween
	local tween = TweenService:Create(object, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	tween:Play()
	return tween
end

local function text(parent: Instance, font: Enum.Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function outline(label: TextLabel, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0.3
	stroke.Parent = label
end

-- A gold sheen across a title's letters.
local function goldText(label: TextLabel, top: Color3)
	label.TextColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(top, GOLD)
	gradient.Parent = label
end

local function corner(frame: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = frame
end

local function border(frame: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return stroke
end

-- The ornate frame of the info panel and the confirm box: a gold outer line, a thin inner
-- line, and a gold diamond at each corner.
local function ornate(frame: Frame)
	border(frame, GOLD, 3)
	corner(frame, UDim.new(0, 4))
	local inner = Instance.new("Frame")
	inner.Name = "InnerLine"
	inner.Position = UDim2.fromOffset(8, 8)
	inner.Size = UDim2.new(1, -16, 1, -16)
	inner.BackgroundTransparency = 1
	inner.Parent = frame
	border(inner, GOLD_DARK, 1.5)
	for _, at in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local diamond = Instance.new("Frame")
		diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		diamond.Position = UDim2.fromScale(at.X, at.Y)
		diamond.Size = UDim2.fromOffset(14, 14)
		diamond.Rotation = 45
		diamond.BackgroundColor3 = GOLD
		diamond.BorderSizePixel = 0
		diamond.ZIndex = 3
		diamond.Parent = frame
		border(diamond, PANEL, 2)
	end
end

local function pill(parent: Instance, label: string, color: Color3, size: Vector2): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = HudStyle.FONT
	b.TextSize = 20
	b.TextColor3 = TEXT
	b.Text = label
	b.Parent = parent
	corner(b, UDim.new(0.5, 0))
	border(b, GOLD, 2)
	Instance.new("UIScale").Parent = b
	return b
end

-- Loads the player's movement controls (PlayerModule), to switch them off and on.
local function getControls(): any
	local scripts = player:WaitForChild("PlayerScripts")
	local module = scripts:WaitForChild("PlayerModule", 10)
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require :: any)(module):GetControls()
	end)
	return if ok then result else nil
end

local function streamAround(position: Vector3)
	pcall(function()
		player:RequestStreamAround(position, STREAM_TIMEOUT)
	end)
end

-- What a shot needs streamed in: the land the camera looks at, some way ahead of it.
local function shotFocus(shot: IntroConfig.Shot): Vector3
	return shot.To.Position + shot.To.LookVector * 80
end

local function ease(alpha: number): number
	return (1 - math.cos(math.pi * math.clamp(alpha, 0, 1))) / 2
end

function Intro.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Intro"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30 -- over every other HUD piece
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Cutscene layer -----------------------------------------------------------------------
	local bars: { Frame } = {}
	for index, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, 0)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.ZIndex = 2
		bar.Parent = gui
		bars[index] = bar
	end

	local narration = text(gui, DISPLAY_FONT, 30, TEXT)
	narration.AnchorPoint = Vector2.new(0.5, 1)
	narration.Position = UDim2.new(0.5, 0, 1, -30)
	narration.Size = UDim2.new(0.8, 0, 0, 80)
	narration.TextYAlignment = Enum.TextYAlignment.Bottom
	narration.TextTransparency = 1
	narration.ZIndex = 3
	outline(narration, 2)
	local narrationScale = Instance.new("UITextSizeConstraint")
	narrationScale.MaxTextSize = 30
	narrationScale.MinTextSize = 16
	narrationScale.Parent = narration
	narration.TextScaled = true

	local skip = pill(gui, "Skip  ▸▸", BUTTON_DARK, Vector2.new(120, 40))
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -24, 0, 24)
	skip.TextSize = 18
	skip.ZIndex = 5
	skip.Visible = false

	local titleCard = Instance.new("Frame")
	titleCard.Size = UDim2.fromScale(1, 1)
	titleCard.BackgroundTransparency = 1
	titleCard.ZIndex = 11
	titleCard.Visible = false
	titleCard.Parent = gui
	local title = text(titleCard, DISPLAY_FONT, 96, Color3.new(1, 1, 1))
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.45)
	title.Size = UDim2.new(0.9, 0, 0, 110)
	title.TextScaled = true
	title.Text = IntroConfig.Title
	title.ZIndex = 11
	goldText(title, Color3.fromRGB(255, 244, 214))
	local subtitle = text(titleCard, DISPLAY_FONT, 28, SOFT_TEXT)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0.45, 66)
	subtitle.Size = UDim2.new(0.8, 0, 0, 34)
	subtitle.Text = IntroConfig.Subtitle
	subtitle.ZIndex = 11

	-- The black every scene change fades through (over everything but the title card).
	local blackout = Instance.new("Frame")
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.BackgroundColor3 = Color3.new(0, 0, 0)
	blackout.BorderSizePixel = 0
	blackout.ZIndex = 10
	blackout.Parent = gui

	local oathText = text(gui, DISPLAY_FONT, 40, Color3.new(1, 1, 1))
	oathText.AnchorPoint = Vector2.new(0.5, 0.5)
	oathText.Position = UDim2.fromScale(0.5, 0.46)
	oathText.Size = UDim2.new(0.9, 0, 0, 50)
	oathText.Text = IntroConfig.OathText
	oathText.TextTransparency = 1
	oathText.ZIndex = 11
	goldText(oathText, Color3.fromRGB(255, 244, 214))
	local afterText = text(gui, HudStyle.FONT, 20, SOFT_TEXT)
	afterText.AnchorPoint = Vector2.new(0.5, 0)
	afterText.Position = UDim2.new(0.5, 0, 0.46, 34)
	afterText.Size = UDim2.new(0.9, 0, 0, 26)
	afterText.Text = IntroConfig.AfterText
	afterText.TextTransparency = 1
	afterText.ZIndex = 11

	-- Hall layer ---------------------------------------------------------------------------
	local hallUi = Instance.new("Frame")
	hallUi.Size = UDim2.fromScale(1, 1)
	hallUi.BackgroundTransparency = 1
	hallUi.Visible = false
	hallUi.ZIndex = 4
	hallUi.Parent = gui

	-- Heading, top center.
	local top = HudStyle.holder(hallUi, Vector2.new(0.5, 0))
	local heading = text(top, DISPLAY_FONT, 40, Color3.new(1, 1, 1))
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Position = UDim2.new(0.5, 0, 0, 22)
	heading.Size = UDim2.fromOffset(600, 46)
	heading.Text = IntroConfig.ChooseHeading
	goldText(heading, Color3.fromRGB(255, 244, 214))
	outline(heading, 2, 0.5)

	-- The info panel, left.
	local left = HudStyle.holder(hallUi, Vector2.new(0, 0.5))
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 40, 0.5, 0)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.12
	panel.Parent = left
	ornate(panel)
	Instance.new("UIScale").Parent = panel

	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(26, 22)
	body.Size = UDim2.new(1, -52, 1, -100)
	body.BackgroundTransparency = 1
	body.Parent = panel
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.Parent = body

	local function row(order: number, label: TextLabel, height: number?)
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, height or 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		if not height then
			label.AutomaticSize = Enum.AutomaticSize.Y
		end
	end

	local className = text(body, DISPLAY_FONT, 50, Color3.new(1, 1, 1))
	row(1, className, 52)
	goldText(className, MINT)
	outline(className, 1.5, 0.6)
	local orderLine = text(body, DISPLAY_FONT, 18, SOFT_TEXT)
	row(2, orderLine, 22)
	local gearLine = text(body, HudStyle.FONT, 16, TEXT)
	row(3, gearLine, 20)
	gearLine.RichText = true

	local divider = Instance.new("Frame")
	divider.LayoutOrder = 4
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.BackgroundColor3 = GOLD_DARK
	divider.BorderSizePixel = 0
	divider.Parent = body

	local lore = text(body, DISPLAY_FONT, 17, TEXT)
	row(5, lore)

	-- Stat bars.
	local stats = Instance.new("Frame")
	stats.LayoutOrder = 6
	stats.Size = UDim2.new(1, 0, 0, 0)
	stats.AutomaticSize = Enum.AutomaticSize.Y
	stats.BackgroundTransparency = 1
	stats.Parent = body
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 5)
	statsLayout.Parent = stats
	local statsPad = Instance.new("UIPadding")
	statsPad.PaddingTop = UDim.new(0, 6)
	statsPad.PaddingBottom = UDim.new(0, 6)
	statsPad.Parent = stats

	local STAT_NAMES = { "Damage", "Speed", "Reach", "Defense", "Difficulty" }
	local fills: { [string]: Frame } = {}
	for order, name in STAT_NAMES do
		local line = Instance.new("Frame")
		line.LayoutOrder = order
		line.Size = UDim2.new(1, 0, 0, 18)
		line.BackgroundTransparency = 1
		line.Parent = stats
		local tag = text(line, HudStyle.FONT, 15, TEXT)
		tag.Size = UDim2.new(0, 96, 1, 0)
		tag.TextXAlignment = Enum.TextXAlignment.Left
		tag.Text = name
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, 100, 0.5, 0)
		track.Size = UDim2.new(1, -100, 0, 12)
		track.BackgroundColor3 = TRACK
		track.BorderSizePixel = 0
		track.Parent = line
		corner(track, UDim.new(0.5, 0))
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = if name == "Difficulty" then DIFFICULTY_COLOR else GOLD
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, UDim.new(0.5, 0))
		HudStyle.gloss(fill)
		fills[name] = fill
	end

	local playstyle = text(body, HudStyle.FONT, 15, SOFT_TEXT)
	row(7, playstyle)

	local selectButton = pill(panel, "SELECT", BUTTON_DARK, Vector2.new(170, 46))
	selectButton.AnchorPoint = Vector2.new(0.5, 1)
	selectButton.Position = UDim2.new(0.5, 0, 1, -26)
	selectButton.ZIndex = 2

	-- The crests, right: one per class.
	local right = HudStyle.holder(hallUi, Vector2.new(1, 0.5))
	local crests = Instance.new("Frame")
	crests.AnchorPoint = Vector2.new(1, 0.5)
	crests.Position = UDim2.new(1, -36, 0.5, 0)
	crests.BackgroundTransparency = 1
	crests.Parent = right
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CREST_CELL.X, CREST_CELL.Y)
	grid.CellPadding = UDim2.fromOffset(12, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = 2
	grid.Parent = crests

	-- Browse arrows and a counter, bottom center.
	local bottom = HudStyle.holder(hallUi, Vector2.new(0.5, 1))
	local browse = Instance.new("Frame")
	browse.AnchorPoint = Vector2.new(0.5, 1)
	browse.Position = UDim2.new(0.5, 0, 1, -26)
	browse.Size = UDim2.fromOffset(260, 46)
	browse.BackgroundTransparency = 1
	browse.Parent = bottom
	local prevButton = pill(browse, "◀", BUTTON_DARK, Vector2.new(56, 46))
	local nextButton = pill(browse, "▶", BUTTON_DARK, Vector2.new(56, 46))
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.fromScale(1, 0)
	local counter = text(browse, HudStyle.FONT, 18, TEXT)
	counter.Size = UDim2.fromScale(1, 1)
	outline(counter, 1.5)
	local keysHint = text(bottom, HudStyle.FONT, 14, SOFT_TEXT)
	keysHint.AnchorPoint = Vector2.new(0.5, 1)
	keysHint.Position = UDim2.new(0.5, 0, 1, -76)
	keysHint.Size = UDim2.fromOffset(500, 18)
	keysHint.Text = "A / D or arrow keys to browse  ·  Enter to choose"
	outline(keysHint, 1.5)

	-- Confirm box, center, over a dimmed screen.
	local dim = Instance.new("TextButton") -- swallows clicks behind the box
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Visible = false
	dim.ZIndex = 6
	dim.Parent = hallUi
	local middle = HudStyle.holder(dim, Vector2.new(0.5, 0.5))
	local confirmBox = Instance.new("Frame")
	confirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmBox.Position = UDim2.fromScale(0.5, 0.5)
	confirmBox.Size = UDim2.fromOffset(480, 250)
	confirmBox.BackgroundColor3 = PANEL
	confirmBox.Parent = middle
	ornate(confirmBox)
	Instance.new("UIScale").Parent = confirmBox
	local confirmTitle = text(confirmBox, DISPLAY_FONT, 30, Color3.new(1, 1, 1))
	confirmTitle.Position = UDim2.fromOffset(24, 22)
	confirmTitle.Size = UDim2.new(1, -48, 0, 36)
	goldText(confirmTitle, MINT)
	local confirmText = text(confirmBox, HudStyle.FONT, 16, TEXT)
	confirmText.Position = UDim2.fromOffset(32, 66)
	confirmText.Size = UDim2.new(1, -64, 0, 90)
	confirmText.TextYAlignment = Enum.TextYAlignment.Top
	confirmText.RichText = true
	local backButton = pill(confirmBox, "Back", Color3.fromRGB(70, 62, 54), Vector2.new(130, 46))
	backButton.AnchorPoint = Vector2.new(1, 1)
	backButton.Position = UDim2.new(0.5, -8, 1, -24)
	local oathButton = pill(confirmBox, "Swear the Oath", Color3.fromRGB(150, 112, 50), Vector2.new(190, 46))
	oathButton.AnchorPoint = Vector2.new(0, 1)
	oathButton.Position = UDim2.new(0.5, 8, 1, -24)

	-- State --------------------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local running = false
	local inHall = false
	local storyThread: thread? = nil
	local cameraDriver: (() -> CFrame)? = nil
	local choices: { Starter.Choice } = {}
	local selected = 1
	local shown = 1.0 -- the (fractional) statue the camera is on
	local turnFrom, turnDelta, turnStart = 1.0, 0.0, -math.huge
	local dollyStart = 0.0
	local crestButtons: { TextButton } = {}
	local sending = false
	local restore: (() -> ())? = nil

	local function setBars(open: boolean, time: number)
		for _, bar in bars do
			fade(bar, time, { Size = UDim2.fromScale(1, if open then IntroConfig.LetterboxHeight else 0) })
		end
	end

	local function black(on: boolean, time: number)
		if time <= 0 then
			blackout.BackgroundTransparency = if on then 0 else 1
			return
		end
		fade(blackout, time, { BackgroundTransparency = if on then 0 else 1 })
		task.wait(time)
	end

	-- Hides the HUD and stops the character; returns how to put it all back.
	local function takeOver(): () -> ()
		local hidden: { ScreenGui } = {}
		for _, child in player:WaitForChild("PlayerGui"):GetChildren() do
			if child:IsA("ScreenGui") and child ~= gui and child.Enabled then
				child.Enabled = false
				table.insert(hidden, child)
			end
		end
		Panels.opened("Intro")
		local listShown = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		local controls = getControls()
		if controls then
			controls:Disable()
		end
		local fieldOfView = camera.FieldOfView
		return function()
			for _, screen in hidden do
				screen.Enabled = true
			end
			Panels.opened("Intro") -- closes any panel a key opened meanwhile
			Panels.closed("Intro")
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, listShown)
			if controls then
				controls:Enable()
			end
			camera.FieldOfView = fieldOfView
		end
	end

	-- The camera on (fractional) statue `at`, pulled back `extra` studs.
	local function hallCamera(at: number, extra: number): CFrame
		local hall = IntroConfig.Hall
		local feet = Starter.statueFeet(at, #choices)
		local t = os.clock()
		local sway = Vector3.new(math.sin(t * 0.5) * 0.25, math.sin(t * 0.7) * 0.15, 0)
		local position = feet * (CFrame.new(hall.CameraShift, hall.CameraHeight, -(hall.CameraDistance + extra)) + sway)
		local look = feet * Vector3.new(hall.CameraShift, hall.LookHeight, 0)
		return CFrame.lookAt(position.Position, look)
	end

	RunService:BindToRenderStep("IntroCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local driver = cameraDriver
		if not driver then
			return
		end
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = driver()
	end)

	-- The info panel and crests for class `index`.
	local function showClass(index: number)
		local choice = choices[index]
		if not choice then
			return
		end
		local info = IntroConfig.Classes[choice.Weapon]
		local set = ArmorConfig.Sets[choice.ArmorSet]
		local weaponRarity = InventoryConfig.rarity(choice.Weapon)
		local setRarity = InventoryConfig.rarityById(set.Rarity)
		className.Text = string.upper(if info then info.Title else choice.Weapon)
		orderLine.Text = if info then info.Order else ""
		gearLine.Text = `<font color="#{weaponRarity.Color:ToHex()}">{choice.Weapon}</font>  ·  <font color="#{setRarity.Color:ToHex()}">{set.Name} Armor</font>`
		lore.Text = if info then info.Lore else ""
		local weaponInfo = InventoryConfig.weapon(choice.Weapon)
		playstyle.Text = if info then info.Playstyle elseif weaponInfo then weaponInfo.Description else ""

		local protection = 0
		for _, amount in set.Pieces do
			protection += amount
		end
		local values: { [string]: number } = {
			Damage = if info then info.Damage else 0.5,
			Speed = if info then info.Speed else 0.5,
			Reach = if info then info.Reach else 0.5,
			Defense = math.clamp(protection / IntroConfig.FullDefense, 0.05, 1),
			Difficulty = if info then info.Difficulty else 0.5,
		}
		for name, fill in fills do
			TweenService:Create(fill, STAT_TWEEN, { Size = UDim2.fromScale(math.clamp(values[name] or 0, 0.04, 1), 1) }):Play()
		end
		counter.Text = `{index} / {#choices}`
		HudStyle.pop(panel, 0.97)

		for i, crest in crestButtons do
			local circle = crest:FindFirstChild("Circle") :: Frame?
			local ring = circle and circle:FindFirstChildOfClass("UIStroke")
			local scale = circle and circle:FindFirstChildOfClass("UIScale")
			local isOn = i == index
			if circle and ring and scale then
				circle.BackgroundColor3 = if isOn then CREST_SELECTED else CREST
				ring.Color = if isOn then GOLD else GOLD_DARK
				ring.Thickness = if isOn then 4 else 2.5
				TweenService:Create(scale, STAT_TWEEN, { Scale = if isOn then 1.12 else 1 }):Play()
			end
			local name = crest:FindFirstChild("ClassName") :: TextLabel?
			if name then
				name.TextColor3 = if isOn then GOLD else SOFT_TEXT
			end
		end
	end

	local function browseTo(index: number)
		local count = #choices
		if count == 0 or dim.Visible then
			return
		end
		index = (index - 1) % count + 1
		if index == selected then
			return
		end
		-- Swing the shortest way round the ring from wherever the camera is now.
		local now = shown
		local delta = (index - now) % count
		if delta > count / 2 then
			delta -= count
		end
		turnFrom, turnDelta, turnStart = now, delta, os.clock()
		selected = index
		showClass(index)
	end

	local function buildCrests()
		for _, old in crestButtons do
			old:Destroy()
		end
		table.clear(crestButtons)
		local rows = math.ceil(#choices / 2)
		crests.Size = UDim2.fromOffset(CREST_CELL.X * 2 + 12, rows * CREST_CELL.Y + (rows - 1) * 6)
		for index, choice in choices do
			local info = IntroConfig.Classes[choice.Weapon]
			local crest = Instance.new("TextButton")
			crest.LayoutOrder = index
			crest.BackgroundTransparency = 1
			crest.Text = ""
			crest.Parent = crests
			local circle = Instance.new("Frame")
			circle.Name = "Circle"
			circle.AnchorPoint = Vector2.new(0.5, 0)
			circle.Position = UDim2.fromScale(0.5, 0)
			circle.Size = UDim2.fromOffset(CREST_SIZE, CREST_SIZE)
			circle.BackgroundColor3 = CREST
			circle.Parent = crest
			corner(circle, UDim.new(0.5, 0))
			border(circle, GOLD_DARK, 2.5)
			Instance.new("UIScale").Parent = circle
			local iconHolder = Instance.new("Frame")
			iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
			iconHolder.Position = UDim2.fromScale(0.5, 0.5)
			iconHolder.Size = UDim2.fromScale(0.68, 0.68)
			iconHolder.BackgroundTransparency = 1
			iconHolder.Parent = circle
			local viewport = WeaponIcon.viewport(iconHolder)
			if not WeaponIcon.show(viewport, choice.Weapon) then
				local connection: RBXScriptConnection
				connection = WeaponIcon.Previews.ChildAdded:Connect(function(child)
					if child.Name == choice.Weapon then
						connection:Disconnect()
						WeaponIcon.show(viewport, choice.Weapon)
					end
				end)
			end
			local name = text(crest, HudStyle.FONT, 14, SOFT_TEXT)
			name.Name = "ClassName"
			name.AnchorPoint = Vector2.new(0.5, 1)
			name.Position = UDim2.fromScale(0.5, 1)
			name.Size = UDim2.new(1, 8, 0, 18)
			name.Text = if info then info.Title else choice.Weapon
			outline(name, 1.5)
			crest.Activated:Connect(function()
				browseTo(index)
			end)
			table.insert(crestButtons, crest)
		end
	end

	local function openConfirm()
		local choice = choices[selected]
		if not inHall or not choice or dim.Visible then
			return
		end
		local info = IntroConfig.Classes[choice.Weapon]
		local set = ArmorConfig.Sets[choice.ArmorSet]
		confirmTitle.Text = `Swear the {if info then info.Title else choice.Weapon}'s oath?`
		confirmText.Text = `You'll begin with the <font color="#{GOLD:ToHex()}">{choice.Weapon}</font> and the full <font color="#{GOLD:ToHex()}">{set.Name}</font> armor set.\nYou can only choose once, but every weapon and armor can be bought in town later.`
		oathButton.Text = "Swear the Oath"
		backButton.Visible = true
		dim.Visible = true
		HudStyle.pop(confirmBox, 0.85)
	end

	local function closeConfirm()
		if not sending then
			dim.Visible = false
		end
	end

	-- Story ---------------------------------------------------------------------------------
	local function enterHall()
		if inHall then
			return
		end
		inHall = true
		skip.Visible = false
		if blackout.BackgroundTransparency > 0 then
			black(true, IntroConfig.FadeTime / 2)
		end
		titleCard.Visible = false
		narration.Visible = false -- a skip can leave its fade-in tween running
		setBars(false, 0.01)
		streamAround(IntroConfig.Hall.Center)

		choices = Starter.choices()
		buildCrests()
		selected, shown, turnDelta, turnStart = 1, 1, 0, -math.huge
		showClass(1)
		camera.FieldOfView = IntroConfig.Hall.FieldOfView
		dollyStart = os.clock()
		cameraDriver = function()
			local alpha = math.clamp((os.clock() - turnStart) / IntroConfig.Hall.TurnTime, 0, 1)
			shown = turnFrom + turnDelta * ease(alpha)
			if alpha >= 1 then
				turnDelta = 0
				shown = selected
			end
			local dolly = 1 - ease((os.clock() - dollyStart) / 2.5) -- a slow push in at the start
			return hallCamera(shown, dolly * 10)
		end
		hallUi.Visible = true
		black(false, IntroConfig.FadeTime)
	end

	local function playStory()
		local shots = IntroConfig.Shots
		if shots[1] then
			streamAround(shotFocus(shots[1]))
		end
		skip.Visible = true -- not before: skipping cancels this thread, best not mid-request
		setBars(true, 0.01)
		for index, shot in shots do
			local nextShot = shots[index + 1]
			if nextShot then
				task.spawn(streamAround, shotFocus(nextShot))
			end
			local start = os.clock()
			cameraDriver = function()
				return shot.From:Lerp(shot.To, ease((os.clock() - start) / shot.Duration))
			end
			narration.Text = shot.Text
			black(false, if index == 1 then IntroConfig.FadeTime else SHOT_FADE)
			fade(narration, TEXT_FADE, { TextTransparency = 0 })
			local fadeOutAt = shot.Duration - SHOT_FADE - (if index == 1 then IntroConfig.FadeTime else SHOT_FADE)
			task.wait(math.max(0, fadeOutAt - TEXT_FADE))
			fade(narration, TEXT_FADE, { TextTransparency = 1 })
			task.wait(TEXT_FADE)
			black(true, SHOT_FADE)
		end
		-- Title card.
		skip.Visible = false
		setBars(false, 0.01)
		title.TextTransparency, subtitle.TextTransparency = 1, 1
		titleCard.Visible = true
		fade(title, 1.2, { TextTransparency = 0 })
		task.wait(0.7)
		fade(subtitle, 1, { TextTransparency = 0 })
		task.wait(IntroConfig.TitleTime)
		fade(title, IntroConfig.FadeTime, { TextTransparency = 1 })
		fade(subtitle, IntroConfig.FadeTime, { TextTransparency = 1 })
		task.wait(IntroConfig.FadeTime)
		storyThread = nil
		enterHall()
	end

	local function finish()
		if not running then
			return
		end
		inHall = false
		dim.Visible = false
		sending = false
		black(true, IntroConfig.FadeTime)
		hallUi.Visible = false
		cameraDriver = nil
		fade(oathText, 1, { TextTransparency = 0 })
		task.wait(0.6)
		fade(afterText, 1, { TextTransparency = 0 })
		task.wait(2.6)

		local character = player.Character or player.CharacterAdded:Wait()
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
		if restore then
			restore()
			restore = nil
		end
		DayNight.hold(nil)
		fade(oathText, IntroConfig.FadeTime, { TextTransparency = 1 })
		fade(afterText, IntroConfig.FadeTime, { TextTransparency = 1 })
		black(false, IntroConfig.FadeTime)
		gui.Enabled = false
		running = false
	end

	local function run()
		if running or hasPicked() then
			return
		end
		running, inHall, sending = true, false, false
		black(true, 0)
		titleCard.Visible = false
		hallUi.Visible = false
		dim.Visible = false
		narration.TextTransparency = 1
		narration.Visible = true
		gui.Enabled = true
		restore = takeOver()
		DayNight.hold(INTRO_CLOCK) -- the flyover is always shot by day
		skip.Visible = false
		storyThread = task.spawn(playStory)
	end

	-- Input ---------------------------------------------------------------------------------
	skip.Activated:Connect(function()
		local thread = storyThread
		if not thread or inHall then
			return
		end
		storyThread = nil
		task.cancel(thread)
		task.spawn(enterHall)
	end)
	prevButton.Activated:Connect(function()
		browseTo(selected - 1)
	end)
	nextButton.Activated:Connect(function()
		browseTo(selected + 1)
	end)
	selectButton.Activated:Connect(function()
		HudStyle.pop(selectButton, 0.9)
		openConfirm()
	end)
	backButton.Activated:Connect(closeConfirm)
	oathButton.Activated:Connect(function()
		local choice = choices[selected]
		if not choice or sending then
			return
		end
		sending = true
		HudStyle.pop(oathButton, 0.9)
		oathButton.Text = "..."
		backButton.Visible = false
		chooseRemote:FireServer(choice.Weapon)
		task.delay(CONFIRM_RETRY, function()
			if sending and running and not hasPicked() then
				sending = false -- never answered: let them try again
				oathButton.Text = "Swear the Oath"
				backButton.Visible = true
			end
		end)
	end)

	local PREVIOUS = { Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.Up, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp, Enum.KeyCode.ButtonL1 }
	local NEXT = { Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.Down, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadDown, Enum.KeyCode.ButtonR1 }
	UserInputService.InputBegan:Connect(function(input)
		if not inHall then
			return
		end
		local key = input.KeyCode
		if dim.Visible then
			if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
				closeConfirm()
			end
		elseif table.find(PREVIOUS, key) then
			browseTo(selected - 1)
		elseif table.find(NEXT, key) then
			browseTo(selected + 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			openConfirm()
		end
	end)
	keysHint.Visible = not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled

	Panels.register("Intro", function() end) -- other panels can't close the intro

	-- Starts for a player who hasn't picked yet; ends once the server confirms the pick.
	local function check()
		if hasPicked() then
			if running and inHall then
				task.spawn(finish)
			end
		elseif player:GetAttribute("Starter") == "" then
			task.spawn(run)
		end
	end
	player:GetAttributeChangedSignal("Starter"):Connect(check)
	check()
end

return Intro
