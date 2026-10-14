--!strict
-- The backpack: press InventoryConfig.OpenKey (B) or ArmorConfig.PanelKey (G), the View
-- button on a controller, or click the backpack icon on the left of the screen. On a
-- controller the D-pad moves between its buttons (selecting a tile shows its details, like
-- hovering), Cross / A clicks, Circle / B closes. Laid out like a game inventory screen, in the
-- cartoon HUD style (HudStyle), with the world blurred behind it:
--   left:  title, your health, category tabs, and a grid of weapon/consumable/material slots.
--          Ones in your hotbar are highlighted with their hotbar number. Clicking an item moves
--          it between the hotbar and storage (InventoryMove remote); a weapon moved in swaps
--          out the one in its category's slot (Primary, Magic, Ranged). Materials (meat, ...)
--          just show how many you have.
--   right: your character facing you, with the five armor slots around it, each linked by a
--          line to where it's worn, showing the worn piece's model and its protection. Clicking one puts the piece
--          on or takes it off (ArmorEquip remote). A sixth slot holds a shield, put on or
--          taken off the same way (ShieldEquip remote).
-- Display and requests only: the server decides what you own, wear, and carry (see
-- InventoryService, ArmorService, and ShieldService) and publishes it as player attributes,
-- which this reads.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local ShieldConfig = require(ReplicatedStorage.Shared.Config.ShieldConfig)
local CurrencyConfig = require(ReplicatedStorage.Shared.Config.CurrencyConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Panels = require(script.Parent.Panels)
local HudStyle = require(script.Parent.HudStyle)
local Gamepad = require(script.Parent.Gamepad)
local Icons = require(ReplicatedStorage.Shared.Icons)
local WeaponIcon = require(script.Parent.WeaponIcon)

local PANEL_SIZE = Vector2.new(1000, 620)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local TILE_COLOR = Color3.fromRGB(58, 54, 74)
local EMPTY_COLOR = Color3.fromRGB(42, 40, 54)
local HOTBAR_BORDER = Color3.fromRGB(110, 230, 140)
local WORN_BORDER = Color3.fromRGB(110, 175, 255)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local LINE_COLOR = Color3.fromRGB(235, 235, 245)
local PROTECTION_COLOR = Color3.fromRGB(150, 205, 255)
local ICON_SIZE = 60

local GRID_COLUMNS = 5
local GRID_SLOTS = 20 -- the rest of the grid shows empty slots, filled as you get more
local TILE = 80
local TILE_GAP = 10
local GRID_ORIGIN = Vector2.new(40, 212)
local GRID_WIDTH = GRID_COLUMNS * TILE + (GRID_COLUMNS - 1) * TILE_GAP

local TAB_TEXT_SIZE = 16
local TAB_GAP = 24
local TAB_Y = 132
-- The Primary tab's filter pills, between the tabs and the grid.
local FILTER_Y = 176
local FILTER_HEIGHT = 24
local FILTER_TEXT_SIZE = 13
local FILTER_GAP = 8
local FILTER_SELECTED = Color3.fromRGB(52, 66, 110)

local BLUR_SIZE = 14
local BLUR_TWEEN = TweenInfo.new(0.2)

-- Armor slots around the character: where the tile sits (in the panel) and the point on the
-- character view the line runs to (as a fraction of the view: 0,0 top left, 1,1 bottom right).
local CHARACTER_VIEW = { position = Vector2.new(640, 70), size = Vector2.new(250, 520) }
local ARMOR_LAYOUT: { [string]: { tile: Vector2, body: Vector2, icon: string } } = {
	Helmet = { tile = Vector2.new(890, 90), body = Vector2.new(0.5, 0.1), icon = "Helmet" },
	Chestplate = { tile = Vector2.new(545, 150), body = Vector2.new(0.45, 0.3), icon = "Chestplate" },
	Armwear = { tile = Vector2.new(900, 280), body = Vector2.new(0.75, 0.42), icon = "Armwear" },
	Leggings = { tile = Vector2.new(545, 380), body = Vector2.new(0.42, 0.66), icon = "Leggings" },
	Boots = { tile = Vector2.new(900, 460), body = Vector2.new(0.6, 0.84), icon = "Boots" },
}
-- The shield's slot, below the chestplate; its line runs to the left forearm.
local SHIELD_LAYOUT = { tile = Vector2.new(545, 265), body = Vector2.new(0.72, 0.55), icon = "Shield" }
local SHIELD_WORN_BACKGROUND = Color3.fromRGB(52, 66, 110)
local PROTECTION_SEGMENTS = 6
local PROTECTION_PER_SEGMENT = 0.025 -- a 12% chestplate fills 5 of 6
-- How worn pieces are turned in their tiles: from the front, a little from the side and above.
local PIECE_TURN = CFrame.Angles(math.rad(15), 0, 0) * CFrame.Angles(0, math.rad(180 + 30), 0)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local moveRemote = remotes:WaitForChild("InventoryMove") :: RemoteEvent
local armorRemote = remotes:WaitForChild("ArmorEquip") :: RemoteEvent
local shieldRemote = remotes:WaitForChild("ShieldEquip") :: RemoteEvent

local player = Players.LocalPlayer

local Backpack = {}

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

local function outlined(label: TextLabel)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = 1.5
	stroke.Parent = label
end

local function hotbarList(): { string }
	local value = player:GetAttribute("Hotbar")
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
end

-- How many of `itemId` the player has, from a count list attribute ("Id=3,Other=1").
local function countIn(attribute: string, itemId: string): number
	local value = player:GetAttribute(attribute)
	if typeof(value) ~= "string" or value == "" then
		return 0
	end
	for _, part in string.split(value, ",") do
		local split = string.split(part, "=")
		if split[1] == itemId then
			local count = tonumber(split[2])
			return if count then count else 0
		end
	end
	return 0
end

local function consumableCount(itemId: string): number
	return countIn("Consumables", itemId)
end

local function materialCount(itemId: string): number
	return countIn("Materials", itemId)
end

-- A straight line between two points in `parent` (offset pixels), with a dot at `to`.
local function line(parent: Instance, from: Vector2, to: Vector2)
	local delta = to - from
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
	bar.Size = UDim2.fromOffset(delta.Magnitude, 2)
	bar.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	bar.BackgroundColor3 = LINE_COLOR
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.ZIndex = 3
	bar.Parent = parent
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromOffset(to.X, to.Y)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BackgroundColor3 = LINE_COLOR
	dot.ZIndex = 4
	dot.Parent = parent
	HudStyle.chunky(dot, 5, 2)
end

-- The character view: returns a function that copies the current character into it.
local function buildCharacterView(panel: Frame): () -> ()
	local viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.fromOffset(CHARACTER_VIEW.position.X, CHARACTER_VIEW.position.Y)
	viewport.Size = UDim2.fromOffset(CHARACTER_VIEW.size.X, CHARACTER_VIEW.size.Y)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 165, 180)
	viewport.LightColor = Color3.fromRGB(255, 245, 230)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Parent = panel

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local copy: Model? = nil
	return function()
		if copy then
			copy:Destroy()
			copy = nil
		end
		local character = player.Character
		if not character then
			return
		end
		local wasArchivable = character.Archivable
		character.Archivable = true
		local clone = character:Clone()
		character.Archivable = wasArchivable
		if not clone then
			return
		end
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") or descendant:IsA("Tool") then
				descendant:Destroy() -- (no weapon in hand: the weapons are on the left)
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		clone:PivotTo(CFrame.new()) -- facing -Z, toward the camera
		clone.Parent = world
		copy = clone

		-- Fit the whole body in the (tall) view.
		local boxCFrame, size = clone:GetBoundingBox()
		local aspect = CHARACTER_VIEW.size.X / CHARACTER_VIEW.size.Y
		local halfHeight = math.max(size.Y, size.X / aspect) / 2 * 1.04
		local distance = halfHeight / math.tan(math.rad(camera.FieldOfView / 2)) + size.Z / 2
		local center = boxCFrame.Position
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, -distance), center)
	end
end

function Backpack.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Backpack"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The always-on icon, left side of the screen.
	local icon = HudStyle.badge(HudStyle.holder(gui, Vector2.new(0, 0.5)), ICON_SIZE, Color3.fromRGB(190, 120, 60), "Backpack")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	local keyHint = HudStyle.caption(icon, InventoryConfig.OpenKey.Name, 16)
	Gamepad.hint(keyHint, InventoryConfig.OpenKey.Name, Enum.KeyCode.ButtonSelect)
	keyHint.AnchorPoint = Vector2.new(0.5, 0.5)
	keyHint.Position = UDim2.new(0.5, 0, 1, 0)
	keyHint.Size = UDim2.fromOffset(20, 16)
	local iconButton = Instance.new("TextButton")
	iconButton.Size = UDim2.fromScale(1, 1)
	iconButton.BackgroundTransparency = 1
	iconButton.Text = ""
	iconButton.ZIndex = 3
	iconButton.Parent = icon

	-- The panel sits in a full-screen holder that scales it down on small screens.
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local function refit()
		fit.Scale = HudStyle.panelScale(PANEL_SIZE)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = holder
	HudStyle.chunky(panel, 26, 4)
	local rim = panel:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(200, 200, 215) -- a light rim, like a device frame
	end
	Instance.new("UIScale").Parent = panel -- for the open pop
	-- A modal button frees the mouse while it's open (even in shift lock).
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	-- Header: title, BACK, and health.
	local title = text(panel, "// BACKPACK", 38)
	title.Position = UDim2.fromOffset(40, 28)
	title.Size = UDim2.fromOffset(420, 44)
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

	-- Currency widget: coin pill on the top right, to the left of BACK.
	local coinPill = Instance.new("Frame")
	coinPill.Name = "CoinPill"
	coinPill.AnchorPoint = Vector2.new(1, 0)
	coinPill.Position = UDim2.new(1, -165, 0, 30)
	coinPill.Size = UDim2.fromOffset(130, 38)
	coinPill.BackgroundColor3 = Color3.fromRGB(42, 40, 54)
	coinPill.Parent = panel
	HudStyle.chunky(coinPill, 19, 2.5)
	local coinStroke = coinPill:FindFirstChildOfClass("UIStroke")
	if coinStroke then
		coinStroke.Color = Color3.fromRGB(230, 180, 60)
	end
	HudStyle.gloss(coinPill)
	Instance.new("UIScale").Parent = coinPill

	local coinDisc = Instance.new("Frame")
	coinDisc.Name = "CoinDisc"
	coinDisc.AnchorPoint = Vector2.new(0, 0.5)
	coinDisc.Position = UDim2.new(0, 6, 0.5, 0)
	coinDisc.Size = UDim2.fromOffset(26, 26)
	coinDisc.BackgroundColor3 = Color3.fromRGB(245, 190, 45)
	coinDisc.Parent = coinPill
	HudStyle.chunky(coinDisc, 13, 1.5)
	local discStroke = coinDisc:FindFirstChildOfClass("UIStroke")
	if discStroke then
		discStroke.Color = Color3.fromRGB(160, 110, 20)
	end
	HudStyle.gloss(coinDisc)

	local coinSymbol = Instance.new("TextLabel")
	coinSymbol.Size = UDim2.fromScale(1, 1)
	coinSymbol.BackgroundTransparency = 1
	coinSymbol.Font = HudStyle.FONT
	coinSymbol.TextSize = 17
	coinSymbol.TextColor3 = Color3.fromRGB(255, 245, 180)
	coinSymbol.Text = "¢"
	coinSymbol.Parent = coinDisc
	local symbolStroke = Instance.new("UIStroke")
	symbolStroke.Color = Color3.fromRGB(140, 95, 20)
	symbolStroke.Thickness = 1.2
	symbolStroke.Parent = coinSymbol

	local coinLabel = text(coinPill, "0", 20, Color3.fromRGB(255, 230, 110))
	coinLabel.AnchorPoint = Vector2.new(0, 0.5)
	coinLabel.Position = UDim2.new(0, 38, 0.5, 0)
	coinLabel.Size = UDim2.new(1, -44, 1, 0)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Center
	outlined(coinLabel)

	local healthLabel = text(panel, "HEALTH", 18)
	healthLabel.Position = UDim2.fromOffset(40, 92)
	healthLabel.Size = UDim2.fromOffset(80, 20)
	local healthBack = Instance.new("Frame")
	healthBack.Position = UDim2.fromOffset(124, 95)
	healthBack.Size = UDim2.fromOffset(250, 14)
	healthBack.BackgroundColor3 = HudStyle.EMPTY
	healthBack.Parent = panel
	HudStyle.chunky(healthBack, 7, 2)
	local healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(235, 70, 60)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = healthFill
	HudStyle.gloss(healthFill)
	local healthValue = text(panel, "", 22)
	healthValue.Position = UDim2.fromOffset(386, 88)
	healthValue.Size = UDim2.fromOffset(80, 26)

	-- Tabs: ALL, each hotbar weapon slot (Primary, Magic, Ranged), then consumables and
	-- materials, with an underline under the selected one. The text shrinks to fit the grid's width.
	type Tab = { id: string?, button: TextButton, x: number, width: number }
	local tabs: { Tab } = {}
	local tabEntries: { { id: string?, name: string } } = { { id = nil, name = "ALL" } }
	for _, slot in InventoryConfig.WeaponSlots do
		table.insert(tabEntries, { id = slot.Id, name = slot.Id:upper() })
	end
	table.insert(tabEntries, { id = ShopConfig.ConsumableCategory, name = ShopConfig.ConsumableCategory:upper() })
	table.insert(tabEntries, { id = MaterialConfig.Category, name = MaterialConfig.Category:upper() })
	local function tabWidth(name: string, size: number): number
		return math.ceil(TextService:GetTextSize(name, size, HudStyle.FONT, Vector2.new(400, 40)).X)
	end
	local tabTextSize = TAB_TEXT_SIZE
	while tabTextSize > 11 do
		local total = (#tabEntries - 1) * TAB_GAP
		for _, entry in tabEntries do
			total += tabWidth(entry.name, tabTextSize)
		end
		if total <= GRID_WIDTH then
			break
		end
		tabTextSize -= 1
	end
	local tabX = GRID_ORIGIN.X
	for _, entry in tabEntries do
		local width = tabWidth(entry.name, tabTextSize)
		local tab = Instance.new("TextButton")
		tab.BackgroundTransparency = 1
		tab.Font = HudStyle.FONT
		tab.TextSize = tabTextSize
		tab.Text = entry.name
		tab.Position = UDim2.fromOffset(tabX, TAB_Y)
		tab.Size = UDim2.fromOffset(width, 28)
		tab.Parent = panel
		table.insert(tabs, { id = entry.id, button = tab, x = tabX, width = width })
		tabX += width + TAB_GAP
	end
	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(GRID_ORIGIN.X, TAB_Y + 36)
	divider.Size = UDim2.fromOffset(GRID_WIDTH, 2)
	divider.BackgroundColor3 = Color3.fromRGB(80, 76, 96)
	divider.BorderSizePixel = 0
	divider.Parent = panel
	local underline = Instance.new("Frame")
	underline.Size = UDim2.fromOffset(40, 4)
	underline.BackgroundColor3 = Color3.new(1, 1, 1)
	underline.BorderSizePixel = 0
	underline.ZIndex = 2
	underline.Parent = panel
	local underlineCorner = Instance.new("UICorner")
	underlineCorner.CornerRadius = UDim.new(0, 2)
	underlineCorner.Parent = underline

	-- The Primary tab's filters (ALL, then PrimaryFilters), shown only while it's selected.
	type Filter = { id: string?, button: TextButton, stroke: UIStroke }
	local filters: { Filter } = {}
	local filterRow = Instance.new("Frame")
	filterRow.BackgroundTransparency = 1
	filterRow.Position = UDim2.fromOffset(GRID_ORIGIN.X, FILTER_Y)
	filterRow.Size = UDim2.fromOffset(GRID_WIDTH, FILTER_HEIGHT)
	filterRow.Visible = false
	filterRow.Parent = panel
	local filterEntries: { string? } = { nil }
	for _, filter in InventoryConfig.PrimaryFilters do
		table.insert(filterEntries, filter.Id)
	end
	local filterX = 0
	for index = 1, #InventoryConfig.PrimaryFilters + 1 do
		local id = filterEntries[index]
		local name = if id then id:upper() else "ALL"
		local width = math.ceil(TextService:GetTextSize(name, FILTER_TEXT_SIZE, HudStyle.FONT, Vector2.new(400, 40)).X) + 24
		local pill = Instance.new("TextButton")
		pill.Font = HudStyle.FONT
		pill.TextSize = FILTER_TEXT_SIZE
		pill.Text = name
		pill.AutoButtonColor = false
		pill.Position = UDim2.fromOffset(filterX, 0)
		pill.Size = UDim2.fromOffset(width, FILTER_HEIGHT)
		pill.Parent = filterRow
		HudStyle.chunky(pill, FILTER_HEIGHT // 2, 2)
		table.insert(filters, { id = id, button = pill, stroke = pill:FindFirstChildOfClass("UIStroke") :: UIStroke })
		filterX += width + FILTER_GAP
	end

	-- The item grid.
	type Tile = { frame: Frame, stroke: UIStroke, viewport: ViewportFrame, icon: ImageLabel, name: TextLabel, badge: TextLabel, item: string? }
	local tiles: { Tile } = {}
	local hovered: string? = nil
	local updateItems: () -> ()
	for index = 1, GRID_SLOTS do
		local column = (index - 1) % GRID_COLUMNS
		local row = (index - 1) // GRID_COLUMNS
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(GRID_ORIGIN.X + column * (TILE + TILE_GAP), GRID_ORIGIN.Y + row * (TILE + TILE_GAP))
		frame.Size = UDim2.fromOffset(TILE, TILE)
		frame.BackgroundColor3 = TILE_COLOR
		frame.Parent = panel
		HudStyle.chunky(frame, 14, 3)
		Instance.new("UIScale").Parent = frame
		local viewport = WeaponIcon.viewport(frame)
		local iconLabel = Icons.image(frame, nil, 18)
		iconLabel.Visible = false
		local name = text(frame, "", 12)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -3)
		name.Size = UDim2.new(1, -6, 0, 14)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 2
		outlined(name)
		local badge = HudStyle.caption(frame, "", 15)
		badge.Position = UDim2.fromOffset(8, 4)
		badge.Size = UDim2.fromOffset(16, 16)
		badge.TextColor3 = HOTBAR_BORDER
		badge.ZIndex = 2
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 3
		button.Parent = frame
		local tile: Tile = {
			frame = frame,
			stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke,
			viewport = viewport,
			icon = iconLabel,
			name = name,
			badge = badge,
			item = nil,
		}
		tiles[index] = tile
		button.Activated:Connect(function()
			local item = tile.item
			if item and not MaterialConfig.item(item) then
				local inHotbar = table.find(hotbarList(), item) ~= nil
				moveRemote:FireServer(item, not inHotbar)
				HudStyle.pop(frame, 0.88)
			end
		end)
		local function hover()
			hovered = tile.item
			updateItems()
		end
		local function unhover()
			if hovered == tile.item then
				hovered = nil
				updateItems()
			end
		end
		button.MouseEnter:Connect(hover)
		button.MouseLeave:Connect(unhover)
		button.SelectionGained:Connect(hover) -- a controller's selection works like the mouse
		button.SelectionLost:Connect(unhover)
	end
	local detail = text(panel, "", 15, SOFT_TEXT)
	detail.Position = UDim2.fromOffset(GRID_ORIGIN.X, GRID_ORIGIN.Y + (GRID_SLOTS // GRID_COLUMNS) * (TILE + TILE_GAP))
	detail.Size = UDim2.fromOffset(GRID_WIDTH, 34)
	detail.TextWrapped = true
	detail.TextYAlignment = Enum.TextYAlignment.Top

	-- The character, and the armor slots around it.
	local refreshCharacter = buildCharacterView(panel)
	type ArmorTile = { slot: string, frame: Frame, stroke: UIStroke, icon: ImageLabel, viewport: ViewportFrame, shown: Model?, segments: { Frame }, name: TextLabel }
	-- One equipment tile, linked by a line to `layout.body` on the character, with a
	-- protection bar under it if `bar`; `onClick` runs when it's pressed.
	local function equipmentTile(slot: string, layout: { tile: Vector2, body: Vector2, icon: string }, bar: boolean, onClick: () -> ()): ArmorTile
		local body = CHARACTER_VIEW.position + CHARACTER_VIEW.size * layout.body
		local tileCenter = layout.tile + Vector2.new(TILE / 2, TILE / 2)
		-- The line leaves from the tile's side facing the character.
		local side = if tileCenter.X < body.X then Vector2.new(TILE / 2, 0) else Vector2.new(-TILE / 2, 0)
		line(panel, tileCenter + side, body)

		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(layout.tile.X, layout.tile.Y)
		frame.Size = UDim2.fromOffset(TILE, TILE)
		frame.BackgroundColor3 = TILE_COLOR
		frame.ZIndex = 5
		frame.Parent = panel
		HudStyle.chunky(frame, 14, 3)
		Instance.new("UIScale").Parent = frame
		local iconLabel = Icons.image(frame, layout.icon, 20)
		iconLabel.Position = UDim2.new(0.5, 0, 0.5, -6) -- above the name
		iconLabel.ZIndex = 5
		-- The worn piece's model, in place of the icon (see showPiece).
		local viewport = WeaponIcon.viewport(frame)
		viewport.Position = UDim2.fromOffset(4, 3)
		viewport.Size = UDim2.new(1, -8, 1, -19)
		viewport.ZIndex = 5
		viewport.Visible = false
		local name = text(frame, "", 11)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -3)
		name.Size = UDim2.new(1, -6, 0, 13)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 6
		outlined(name)

		-- Protection bar under the tile.
		local segments: { Frame } = {}
		local segmentWidth = (TILE - (PROTECTION_SEGMENTS - 1) * 3) / PROTECTION_SEGMENTS
		for index = 1, if bar then PROTECTION_SEGMENTS else 0 do
			local segment = Instance.new("Frame")
			segment.Position = UDim2.fromOffset(layout.tile.X + (index - 1) * (segmentWidth + 3), layout.tile.Y + TILE + 8)
			segment.Size = UDim2.fromOffset(segmentWidth, 8)
			segment.BackgroundColor3 = HudStyle.EMPTY
			segment.BorderSizePixel = 0
			segment.Parent = panel
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 2)
			corner.Parent = segment
			table.insert(segments, segment)
		end

		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 7
		button.Parent = frame
		button.Activated:Connect(function()
			HudStyle.pop(frame, 0.88)
			onClick()
		end)
		return {
			slot = slot,
			frame = frame,
			stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke,
			icon = iconLabel,
			viewport = viewport,
			shown = nil,
			segments = segments,
			name = name,
		}
	end

	-- Clicking cycles through what's owned for the slot, then takes it off (nil past the last one).
	local function nextOption(options: { string }, worn: unknown): string?
		local index = if typeof(worn) == "string" then table.find(options, worn) else nil
		return options[if index then index + 1 else 1]
	end
	local armorTiles: { ArmorTile } = {}
	for _, slot in ArmorConfig.Slots do
		table.insert(armorTiles, equipmentTile(slot, ARMOR_LAYOUT[slot], true, function()
			local options: { string } = {}
			for _, setId in ArmorConfig.SetOrder do
				if ArmorConfig.Sets[setId].Pieces[slot] and player:GetAttribute(`OwnsArmor{setId}`) == true then
					table.insert(options, setId)
				end
			end
			armorRemote:FireServer(slot, nextOption(options, player:GetAttribute(`Armor{slot}`)))
		end))
	end
	local function ownedShields(): { string }
		local options: { string } = {}
		for _, id in ShieldConfig.Order do
			if player:GetAttribute(`OwnsShield{id}`) == true then
				table.insert(options, id)
			end
		end
		return options
	end
	local shieldTile = equipmentTile("Shield", SHIELD_LAYOUT, false, function()
		shieldRemote:FireServer(nextOption(ownedShields(), player:GetAttribute("Shield")))
	end)
	local protectionLabel = text(panel, "", 16, PROTECTION_COLOR)
	protectionLabel.AnchorPoint = Vector2.new(0.5, 0)
	protectionLabel.Position = UDim2.fromOffset(CHARACTER_VIEW.position.X + CHARACTER_VIEW.size.X / 2, PANEL_SIZE.Y - 34)
	protectionLabel.Size = UDim2.fromOffset(240, 20)
	protectionLabel.TextXAlignment = Enum.TextXAlignment.Center
	HudStyle.iconBeside(protectionLabel, "Shield", 18)

	-- Updating ---------------------------------------------------------------------------

	local selectedTab: string? = nil -- nil = ALL; else a WeaponSlots Id, or the consumable or material category
	local selectedFilter: string? = nil -- nil = ALL; else a PrimaryFilters Id
	local shownPreview: { [Tile]: string } = {}
	local modelShown: { [Tile]: boolean } = {} -- the tile's consumable or material shows its model, not its icon
	local primaryTab = InventoryConfig.WeaponSlots[1].Id

	local function updateTabs()
		for _, tab in tabs do
			local selected = tab.id == selectedTab
			tab.button.TextColor3 = if selected then Color3.new(1, 1, 1) else SOFT_TEXT
			if selected then
				underline.Position = UDim2.fromOffset(tab.x - 6, TAB_Y + 33)
				underline.Size = UDim2.fromOffset(tab.width + 12, 4)
			end
		end
		filterRow.Visible = selectedTab == primaryTab
		for _, filter in filters do
			local selected = filter.id == selectedFilter
			filter.button.BackgroundColor3 = if selected then FILTER_SELECTED else EMPTY_COLOR
			filter.button.TextColor3 = if selected then Color3.new(1, 1, 1) else SOFT_TEXT
			filter.stroke.Color = if selected then WORN_BORDER else HudStyle.OUTLINE
		end
	end

	-- Whether a weapon shows under the selected tab (and, under Primary, the selected filter).
	local function weaponShown(name: string): boolean
		if selectedTab == nil then
			return true
		end
		local slot = InventoryConfig.weaponSlot(name)
		if not slot or InventoryConfig.WeaponSlots[slot].Id ~= selectedTab then
			return false
		end
		if selectedTab ~= primaryTab or selectedFilter == nil then
			return true
		end
		for _, filter in InventoryConfig.PrimaryFilters do
			if filter.Id == selectedFilter then
				return table.find(filter.Weapons, name) ~= nil
			end
		end
		return false
	end

	updateItems = function()
		local hotbar = hotbarList()
		local filled = 0
		for _, item in hotbar do
			if item ~= "" then
				filled += 1
			end
		end
		local potionFree = table.find(hotbar, "", #InventoryConfig.WeaponSlots + 1) ~= nil
		local ownedValue = player:GetAttribute("OwnedWeapons")
		local owned = if typeof(ownedValue) == "string" and ownedValue ~= "" then string.split(ownedValue, ",") else {}
		local shown: { string } = {}
		for _, info in InventoryConfig.Weapons do
			if table.find(owned, info.Name) and weaponShown(info.Name) then
				table.insert(shown, info.Name)
			end
		end
		if selectedTab == nil or selectedTab == ShopConfig.ConsumableCategory then
			for _, item in ShopConfig.Items do
				if ShopConfig.consumable(item.Id) and consumableCount(item.Id) > 0 then
					table.insert(shown, item.Id)
				end
			end
		end
		if selectedTab == nil or selectedTab == MaterialConfig.Category then
			for _, item in MaterialConfig.Items do
				if materialCount(item.Id) > 0 then
					table.insert(shown, item.Id)
				end
			end
		end
		for index, tile in tiles do
			local itemId = shown[index]
			local consumable = if itemId then ShopConfig.consumable(itemId) else nil
			local material = if itemId then MaterialConfig.item(itemId) else nil
			tile.item = itemId
			tile.frame.BackgroundColor3 = if itemId then TILE_COLOR else EMPTY_COLOR
			if shownPreview[tile] ~= itemId then
				if consumable or material then
					local model = if consumable then consumable.Model else (material :: MaterialConfig.Material).Model
					local icon = if consumable then consumable.Icon else (material :: MaterialConfig.Material).Icon
					modelShown[tile] = WeaponIcon.showItem(tile.viewport, model)
					Icons.set(tile.icon, icon)
					shownPreview[tile] = itemId
				else
					tile.icon.Visible = false
					tile.viewport.Visible = true
					shownPreview[tile] = if WeaponIcon.show(tile.viewport, itemId) then itemId else nil
				end
			end
			local iconShown = (consumable ~= nil or material ~= nil) and not modelShown[tile]
			tile.icon.Visible = iconShown
			tile.viewport.Visible = not iconShown
			if consumable then
				tile.icon.ImageColor3 = if consumable.ManaPercent then Color3.fromRGB(120, 170, 255) else Color3.fromRGB(120, 235, 145)
			elseif material then
				tile.icon.ImageColor3 = Color3.new(1, 1, 1)
			end
			local hotbarIndex = if itemId then table.find(hotbar, itemId) else nil
			local rarity = if itemId and not consumable and not material then InventoryConfig.rarity(itemId) else nil
			local special = rarity ~= nil and rarity ~= InventoryConfig.Rarities[1]
			tile.name.Text = if consumable then consumable.Name elseif material then material.Name else itemId or ""
			tile.name.TextColor3 = if rarity and special then rarity.Color else Color3.new(1, 1, 1)
			tile.badge.Text = if consumable
				then `x{consumableCount(consumable.Id)}`
				elseif material then `x{materialCount(material.Id)}`
				elseif hotbarIndex then tostring(hotbarIndex)
				else ""
			tile.badge.TextColor3 = if consumable and hotbarIndex then HOTBAR_BORDER else if consumable or material then SOFT_TEXT else HOTBAR_BORDER
			tile.stroke.Color = if hotbarIndex then HOTBAR_BORDER elseif rarity and special then rarity.Color else HudStyle.OUTLINE
			tile.stroke.Thickness = if hotbarIndex then 3.5 else 3
		end

		local info = if hovered then InventoryConfig.weapon(hovered) else nil
		local consumable = if hovered then ShopConfig.consumable(hovered) else nil
		local material = if hovered then MaterialConfig.item(hovered) else nil
		local count = `Hotbar {filled}/{InventoryConfig.HotbarSlots}`
		if info then
			local inHotbar = table.find(hotbar, info.Name) ~= nil
			local slot = InventoryConfig.weaponSlot(info.Name)
			local current = if slot then hotbar[slot] else nil
			local hint = if inHotbar
				then "click to store"
				elseif current and current ~= "" then `click to swap with {current}`
				else `click to add to the {if slot then InventoryConfig.WeaponSlots[slot].Id else ""} slot`
			local rarity = InventoryConfig.rarity(info.Name)
			detail.Text = `{info.Name} ({rarity.Id})  ·  {info.Description}  ({hint})`
		elseif consumable then
			local inHotbar = table.find(hotbar, consumable.Id) ~= nil
			local hint = if inHotbar then "click to remove from hotbar" elseif not potionFree then "potion slots full" else "click to add to hotbar"
			detail.Text = `{consumable.Name} x{consumableCount(consumable.Id)}  ·  {consumable.Description}  ({hint})`
		elseif material then
			detail.Text = `{material.Name} x{materialCount(material.Id)}  ·  {material.Description}`
		else
			detail.Text = `{count}  ·  one Primary, Magic and Ranged weapon at a time; click an item to move it between your hotbar and backpack`
		end
	end

	-- Shows `preview` (a worn piece's look-only model) in the tile in place of its icon, or the
	-- icon again if there's none.
	local function showPiece(tile: ArmorTile, preview: Instance?)
		local model = if preview and preview:IsA("Model") then preview else nil
		if model ~= tile.shown then
			tile.shown = model
			if model then
				WeaponIcon.showModel(tile.viewport, model, PIECE_TURN)
			else
				tile.viewport:ClearAllChildren()
			end
		end
		tile.viewport.Visible = model ~= nil
		tile.icon.Visible = model == nil
	end

	local function updateArmor()
		local protection = player:GetAttribute("Protection")
		local total = if typeof(protection) == "number" then protection else 0
		protectionLabel.Text = `{math.round(total * 100)}% protection`
		for _, tile in armorTiles do
			local worn = player:GetAttribute(`Armor{tile.slot}`)
			local set = if typeof(worn) == "string" then ArmorConfig.Sets[worn] else nil
			local amount = if set then set.Pieces[tile.slot] or 0 else 0
			local owned = false
			for setId, ownedSet in ArmorConfig.Sets do
				owned = owned or (ownedSet.Pieces[tile.slot] ~= nil and player:GetAttribute(`OwnsArmor{setId}`) == true)
			end
			tile.stroke.Color = if set then WORN_BORDER else HudStyle.OUTLINE
			tile.frame.BackgroundColor3 = if set then Color3.fromRGB(52, 66, 110) elseif owned then TILE_COLOR else EMPTY_COLOR
			tile.icon.ImageTransparency = if set then 0 else 0.6
			local previews = ReplicatedStorage:FindFirstChild("ArmorPreviews")
			local setPreviews = if previews and set then previews:FindFirstChild(worn :: string) else nil
			showPiece(tile, if setPreviews then setPreviews:FindFirstChild(tile.slot) else nil)
			tile.name.Text = if set then set.Name elseif owned then "Wear" else tile.slot
			local rarity = if set then InventoryConfig.rarityById(set.Rarity) else nil
			tile.name.TextColor3 = if rarity and rarity ~= InventoryConfig.Rarities[1] then rarity.Color else Color3.new(1, 1, 1)
			local filled = math.clamp(math.round(amount / PROTECTION_PER_SEGMENT), if amount > 0 then 1 else 0, PROTECTION_SEGMENTS)
			for index, segment in tile.segments do
				segment.BackgroundColor3 = if index <= filled then PROTECTION_COLOR else HudStyle.EMPTY
			end
		end

		local wornShield = player:GetAttribute("Shield")
		local shield = if typeof(wornShield) == "string" then ShieldConfig.Shields[wornShield] else nil
		local ownsShield = #ownedShields() > 0
		shieldTile.stroke.Color = if shield then WORN_BORDER else HudStyle.OUTLINE
		shieldTile.frame.BackgroundColor3 = if shield then SHIELD_WORN_BACKGROUND elseif ownsShield then TILE_COLOR else EMPTY_COLOR
		shieldTile.icon.ImageTransparency = if shield then 0 else 0.6
		local shieldPreviews = ReplicatedStorage:FindFirstChild("ShieldPreviews")
		showPiece(shieldTile, if shieldPreviews and shield then shieldPreviews:FindFirstChild(wornShield :: string) else nil)
		shieldTile.name.Text = if shield then shield.Name elseif ownsShield then "Wear" else "Shield"
		local shieldRarity = if shield then InventoryConfig.rarityById(shield.Rarity) else nil
		shieldTile.name.TextColor3 = if shieldRarity and shieldRarity ~= InventoryConfig.Rarities[1] then shieldRarity.Color else Color3.new(1, 1, 1)
	end

	local function updateHealth()
		local character = player.Character
		local health = character and character:GetAttribute("Health")
		local maxHealth = character and character:GetAttribute("MaxHealth")
		if typeof(health) == "number" and typeof(maxHealth) == "number" and maxHealth > 0 then
			healthFill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
			healthValue.Text = tostring(math.ceil(health))
		end
	end

	local lastCoins = -1
	local function updateCoins(animate: boolean?)
		local coins = player:GetAttribute("Coins")
		local amount = if typeof(coins) == "number" then math.max(0, math.floor(coins)) else 0
		local formatted = CurrencyConfig.format(amount)
		coinLabel.Text = formatted
		local textWidth = TextService:GetTextSize(formatted, 20, HudStyle.FONT, Vector2.new(500, 38)).X
		coinPill.Size = UDim2.fromOffset(math.max(120, textWidth + 56), 38)
		if animate and lastCoins >= 0 and amount > lastCoins then
			HudStyle.pop(coinPill, 1.18)
		end
		lastCoins = amount
	end

	-- Opening, closing, and keeping it up to date.
	local blur = Instance.new("BlurEffect")
	blur.Name = "BackpackBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	local function setOpen(open: boolean)
		if open == panel.Visible then
			return
		end
		panel.Visible = open
		if open then
			Panels.opened("Backpack") -- closes the skills screen, hides the hotbar
			Gamepad.focus(panel, function()
				setOpen(false)
			end)
		else
			Panels.closed("Backpack")
			Gamepad.unfocus(panel)
		end
		if open then
			updateTabs()
			updateItems()
			updateArmor()
			updateHealth()
			updateCoins(false)
			refreshCharacter()
			HudStyle.pop(panel, 0.92)
			blur.Enabled = true
			TweenService:Create(blur, BLUR_TWEEN, { Size = BLUR_SIZE }):Play()
		else
			hovered = nil
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

	for _, tab in tabs do
		tab.button.Activated:Connect(function()
			selectedTab = tab.id
			selectedFilter = nil
			updateTabs()
			updateItems()
		end)
	end
	for _, filter in filters do
		filter.button.Activated:Connect(function()
			selectedFilter = filter.id
			updateTabs()
			updateItems()
		end)
	end
	WeaponIcon.Previews.ChildAdded:Connect(function()
		table.clear(shownPreview) -- a weapon's look arrived: redraw the tiles
		if panel.Visible then
			updateItems()
		end
	end)

	Panels.register("Backpack", function()
		setOpen(false)
	end)
	iconButton.Activated:Connect(toggle)
	back.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.ButtonSelect then
			toggle() -- (even while a menu has the controller)
			return
		end
		if gameProcessed then
			return
		end
		if input.KeyCode == InventoryConfig.OpenKey or input.KeyCode == ArmorConfig.PanelKey then
			toggle()
		end
	end)

	local refreshQueued = false
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Hotbar" or attribute == "HotbarSlots" or attribute == "OwnedWeapons" then
			updateItems()
		elseif attribute == "Coins" then
			updateCoins(true)
		elseif attribute == "Consumables" or attribute == "Materials" then
			updateItems()
		elseif
			attribute == "Protection"
			or attribute == "Shield"
			or string.sub(attribute, 1, 5) == "Armor"
			or string.sub(attribute, 1, 9) == "OwnsArmor"
			or string.sub(attribute, 1, 10) == "OwnsShield"
		then
			updateArmor()
			-- Re-copy the character once the armor change has reached it.
			if panel.Visible and not refreshQueued then
				refreshQueued = true
				task.delay(0.3, function()
					refreshQueued = false
					if panel.Visible then
						refreshCharacter()
					end
				end)
			end
		end
	end)
	local function watchHealth(character: Model)
		character:GetAttributeChangedSignal("Health"):Connect(updateHealth)
		updateHealth()
		if panel.Visible then
			task.delay(1, refreshCharacter)
		end
	end
	player.CharacterAdded:Connect(watchHealth)
	if player.Character then
		watchHealth(player.Character)
	end
	updateTabs()
	updateItems()
	updateArmor()
	updateCoins(false)
end

return Backpack
