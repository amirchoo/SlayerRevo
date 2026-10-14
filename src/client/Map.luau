--!strict
-- The minimap and the world map (shared/Config/MapConfig).
--   Minimap (top right): a round window onto the world picture, centred on you, north up,
--     with an arrow for which way you're facing, dots for other players, and the name of the
--     place you're in underneath. Tap or click it to open the world map.
--   World map: the whole world, with place names, you and other players. M opens and closes
--     it (or tap the minimap / the X); it's a panel, so it closes the backpack and the like.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)
local HudStyle = require(script.Parent.HudStyle)
local Gamepad = require(script.Parent.Gamepad)
local Panels = require(script.Parent.Panels)

local COLORS = {
	Frame = Color3.fromRGB(70, 50, 35),
	Parchment = Color3.fromRGB(235, 220, 185),
	You = Color3.fromRGB(255, 225, 90),
	Others = Color3.fromRGB(120, 200, 255),
	Town = Color3.fromRGB(255, 225, 120),
	Area = Color3.fromRGB(255, 160, 130),
	Ruin = Color3.fromRGB(245, 240, 230),
	Dim = Color3.fromRGB(10, 10, 15),
}
local LABEL_HEIGHT = { town = 0.034, area = 0.03, ruin = 0.022 } -- of the map's height
local NEAR_LABEL = 70 -- studs from a ruin's label that count as being there
local MAP_SCREEN_FRACTION = 0.86 -- of the screen's height

local player = Players.LocalPlayer

local Map = {}

local worldSize = MapConfig.WorldMax - MapConfig.WorldMin

-- 0..1 across the map picture for a world X/Z.
local function uv(p: Vector2): Vector2
	return (p - MapConfig.WorldMin) / worldSize
end

local function flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

-- Degrees clockwise from north that a look direction faces (GUI Rotation).
local function heading(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

local function rootOf(target: Player): BasePart?
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- What the place you're standing in is called.
local function placeName(position: Vector3): string
	if TrainingArea.contains(position) then
		return "Training Grounds"
	end
	local p = flat(position)
	for _, label in MapConfig.Labels do
		if label.Kind == "ruin" and (p - label.Position).Magnitude < NEAR_LABEL then
			return label.Text
		end
	end
	if SafeZone.contains(position) then
		return "Beginning Town"
	elseif p.Y < -SafeZone.HALF_SIZE then
		return "Hunting Grounds"
	end
	return "The Wilds"
end

-- A "you are here" arrow: a round marker with a point at its top, turned by Rotation.
local function arrow(parent: Instance, size: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "You"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 5
	holder.Parent = parent

	local point = Instance.new("Frame")
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.18)
	point.Size = UDim2.fromScale(0.42, 0.42)
	point.Rotation = 45
	point.BackgroundColor3 = COLORS.You
	point.ZIndex = 5
	point.Parent = holder
	local pointStroke = Instance.new("UIStroke")
	pointStroke.Color = HudStyle.OUTLINE
	pointStroke.Thickness = 2
	pointStroke.Parent = point

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.55)
	dot.Size = UDim2.fromScale(0.7, 0.7)
	dot.BackgroundColor3 = COLORS.You
	dot.ZIndex = 6
	dot.Parent = holder
	HudStyle.chunky(dot, size, 2)
	return holder
end

local function dot(parent: Instance, size: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = color
	frame.ZIndex = 4
	frame.Parent = parent
	HudStyle.chunky(frame, size, 2)
	return frame
end

-- Keeps one dot per other player in `parent`, placed by `place(dot, worldXZ)`.
local function playerDots(parent: Instance, size: number): (place: (Frame, Vector2) -> ()) -> ()
	local dots: { [Player]: Frame } = {}
	Players.PlayerRemoving:Connect(function(gone)
		if dots[gone] then
			dots[gone]:Destroy()
			dots[gone] = nil
		end
	end)
	return function(place)
		for _, other in Players:GetPlayers() do
			local root = if other ~= player then rootOf(other) else nil
			local marker = dots[other]
			if root then
				if not marker then
					marker = dot(parent, size, COLORS.Others)
					dots[other] = marker
				end
				marker.Visible = true
				place(marker, flat(root.Position))
			elseif marker then
				marker.Visible = false
			end
		end
	end
end

local function buildMinimap(gui: ScreenGui, open: () -> ())
	local config = MapConfig.Minimap
	local size = config.Size
	local holder = HudStyle.holder(gui, Vector2.new(1, 0))

	local frame = Instance.new("Frame")
	frame.Name = "Minimap"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -config.Margin.X, 0, config.Margin.Y)
	frame.Size = UDim2.fromOffset(size, size + 30)
	frame.BackgroundTransparency = 1
	frame.Parent = holder

	local window = Instance.new("CanvasGroup") -- clips the map to the round frame
	window.Name = "Window"
	window.Size = UDim2.fromOffset(size, size)
	window.BackgroundColor3 = COLORS.Parchment
	window.Parent = frame
	HudStyle.chunky(window, size // 2, 4)

	local pixelsPerStud = (size / 2) / config.Range
	local mapPixels = worldSize * pixelsPerStud
	local image = Instance.new("ImageLabel")
	image.Name = "World"
	image.BackgroundTransparency = 1
	image.Image = MapConfig.Image
	image.Size = UDim2.fromOffset(mapPixels.X, mapPixels.Y)
	image.Parent = window

	local others = Instance.new("Frame")
	others.Size = UDim2.fromScale(1, 1)
	others.BackgroundTransparency = 1
	others.Parent = window
	local updateOthers = playerDots(others, 9)

	local you = arrow(window, 22)
	you.Position = UDim2.fromScale(0.5, 0.5)

	local north = HudStyle.caption(frame, "N", 18)
	north.AnchorPoint = Vector2.new(0.5, 0.5)
	north.Position = UDim2.fromOffset(size / 2, 4)
	north.Size = UDim2.fromOffset(20, 20)
	north.ZIndex = 6

	local place = HudStyle.caption(frame, "", 18)
	place.AnchorPoint = Vector2.new(0.5, 0)
	place.Position = UDim2.fromOffset(size / 2, size + 6)
	place.Size = UDim2.fromOffset(size + 60, 22)

	-- The key that opens the world map, on the minimap's lower left (not on touch screens).
	local keyHint = HudStyle.badge(frame, 30, COLORS.Frame, MapConfig.OpenKey.Name)
	local keyText = keyHint:FindFirstChildOfClass("TextLabel")
	if keyText then
		Gamepad.hint(keyText, MapConfig.OpenKey.Name, Enum.KeyCode.DPadLeft)
	end
	keyHint.AnchorPoint = Vector2.new(0.5, 0.5)
	keyHint.Position = UDim2.fromOffset(size * 0.15, size * 0.85)
	keyHint.ZIndex = 7
	for _, child in keyHint:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 7
		end
	end
	keyHint.Visible = not UserInputService.TouchEnabled
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.Touch then
			keyHint.Visible = false
		end
	end)

	local button = Instance.new("TextButton")
	button.Name = "Open"
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 8
	button.Parent = frame
	button.Activated:Connect(open)

	local lastPlaceCheck = 0
	RunService.RenderStepped:Connect(function()
		local root = rootOf(player)
		if not root then
			return
		end
		local here = uv(flat(root.Position))
		image.Position = UDim2.fromOffset(size / 2 - here.X * mapPixels.X, size / 2 - here.Y * mapPixels.Y)
		you.Rotation = heading(root.CFrame.LookVector)
		updateOthers(function(marker, at)
			local offset = (at - flat(root.Position)) * pixelsPerStud
			-- Players past the edge are pinned to the rim, so you can see which way they are.
			local limit = size / 2 - 8
			if offset.Magnitude > limit then
				offset = offset.Unit * limit
			end
			marker.Position = UDim2.fromOffset(size / 2 + offset.X, size / 2 + offset.Y)
		end)
		local now = os.clock()
		if now - lastPlaceCheck > 0.5 then
			lastPlaceCheck = now
			place.Text = placeName(root.Position)
		end
	end)
	return frame
end

local function buildWorldMap(gui: ScreenGui, close: () -> ()): Frame
	local screen = Instance.new("Frame")
	screen.Name = "WorldMap"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = COLORS.Dim
	screen.BackgroundTransparency = 0.45
	screen.Visible = false
	screen.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(MAP_SCREEN_FRACTION, MAP_SCREEN_FRACTION)
	panel.SizeConstraint = Enum.SizeConstraint.RelativeYY -- square, sized by the screen's height
	panel.BackgroundColor3 = COLORS.Frame
	panel.Parent = screen
	HudStyle.chunky(panel, 18, 4)
	Instance.new("UIScale").Parent = panel

	local map = Instance.new("ImageLabel")
	map.Name = "World"
	map.AnchorPoint = Vector2.new(0.5, 0.5)
	map.Position = UDim2.fromScale(0.5, 0.5)
	map.Size = UDim2.new(1, -16, 1, -16)
	map.Image = MapConfig.Image
	map.BackgroundColor3 = COLORS.Parchment
	map.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = map

	for _, label in MapConfig.Labels do
		local at = uv(label.Position)
		local text = Instance.new("TextLabel")
		text.Name = label.Text
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(at.X, at.Y)
		text.Size = UDim2.fromScale(0.4, LABEL_HEIGHT[label.Kind])
		text.BackgroundTransparency = 1
		text.Font = HudStyle.FONT
		text.TextScaled = true
		text.Text = label.Text
		text.TextColor3 = if label.Kind == "town" then COLORS.Town elseif label.Kind == "area" then COLORS.Area else COLORS.Ruin
		text.TextStrokeColor3 = HudStyle.OUTLINE
		text.TextStrokeTransparency = 0
		text.ZIndex = 3
		text.Parent = map
		if label.Kind ~= "area" then
			-- The place itself (and often you) is under the name; lift the name above it.
			local lift = if label.Kind == "town" then 0.075 else LABEL_HEIGHT.ruin * 1.4
			text.Position = UDim2.fromScale(at.X, at.Y - lift)
		end
	end

	local title = HudStyle.caption(panel, "World Map", 30)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromOffset(24, 0)
	title.Size = UDim2.fromOffset(200, 36)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 6

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	closeButton.Position = UDim2.new(1, -6, 0, 6)
	closeButton.Size = UDim2.fromOffset(44, 44)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 70, 60)
	closeButton.Font = HudStyle.FONT
	closeButton.TextSize = 24
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.ZIndex = 6
	closeButton.Parent = panel
	HudStyle.chunky(closeButton, 22, 3)
	closeButton.Activated:Connect(close)

	local others = Instance.new("Frame")
	others.Size = UDim2.fromScale(1, 1)
	others.BackgroundTransparency = 1
	others.ZIndex = 4
	others.Parent = map
	local updateOthers = playerDots(others, 12)
	local you = arrow(map, 26)

	RunService.RenderStepped:Connect(function()
		if not screen.Visible then
			return
		end
		local root = rootOf(player)
		if root then
			local here = uv(flat(root.Position))
			you.Visible = true
			you.Position = UDim2.fromScale(here.X, here.Y)
			you.Rotation = heading(root.CFrame.LookVector)
		else
			you.Visible = false
		end
		updateOthers(function(marker, at)
			local spot = uv(at)
			marker.Position = UDim2.fromScale(spot.X, spot.Y)
		end)
	end)
	return screen
end

function Map.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Map"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local fullGui = Instance.new("ScreenGui")
	fullGui.Name = "WorldMap"
	fullGui.ResetOnSpawn = false
	fullGui.IgnoreGuiInset = true
	fullGui.DisplayOrder = 5
	fullGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fullGui.Parent = player:WaitForChild("PlayerGui")

	local minimap: Frame
	local worldMap: Frame

	local function close()
		if worldMap.Visible then
			worldMap.Visible = false
			minimap.Visible = true
			Panels.closed("Map")
			Gamepad.unfocus(worldMap)
		end
	end
	local function open()
		if not worldMap.Visible then
			Panels.opened("Map") -- closes the backpack and the like
			worldMap.Visible = true
			minimap.Visible = false
			HudStyle.pop(worldMap:FindFirstChild("Panel") :: Frame, 0.9)
			Gamepad.focus(worldMap, close)
		end
	end

	minimap = buildMinimap(gui, open)
	worldMap = buildWorldMap(fullGui, close)
	Panels.register("Map", close)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.DPadLeft and (worldMap.Visible or not Gamepad.inMenu()) then
			if worldMap.Visible then -- the map's button on a controller
				close()
			else
				open()
			end
			return
		end
		if gameProcessed then
			return
		end
		if input.KeyCode == MapConfig.OpenKey then
			if worldMap.Visible then
				close()
			else
				open()
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)
end

return Map
