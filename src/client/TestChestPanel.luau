--!strict
-- The Test Chest's panel (see server TestChest): opens when the server says the player used
-- the chest (TestChestOpen), and lists every item by category: a tab per weapon class, and
-- one for armor (and shields). Each item has a button that asks the server for it (TestChestTake):
-- weapons are given (or moved to the hotbar if owned), armor sets and shields are given and put on.
-- Closes with its X, Escape, or by walking away from the chest.
-- Display and requests only: the server checks and decides; this reads what the player has
-- from their attributes (Hotbar, HotbarSlots, OwnsArmor<Set>, Armor<Slot>, OwnsShield<Id>, Shield).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local ShieldConfig = require(ReplicatedStorage.Shared.Config.ShieldConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local Icons = require(ReplicatedStorage.Shared.Icons)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local WeaponIcon = require(script.Parent.WeaponIcon)

local PANEL_SIZE = Vector2.new(780, 520)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local TAB_COLOR = Color3.fromRGB(58, 54, 74)
local TAB_SELECTED = Color3.fromRGB(205, 150, 60)
local CARD_COLOR = Color3.fromRGB(46, 43, 60)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local BUTTON_ACTIVE = Color3.fromRGB(80, 190, 110)
local BUTTON_DONE = Color3.fromRGB(70, 68, 85)
local TAB_WIDTH = 170
local CARD_HEIGHT = 96
local CLOSE_DISTANCE = 18 -- studs from the chest before the panel closes itself

local ARMOR_CATEGORY = { Id = "Armor", Icon = "Shield" }
local CURRENCY_CATEGORY = { Id = "Coins", Icon = "Sparkles" }

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = remotes:WaitForChild("TestChestOpen") :: RemoteEvent
local takeRemote = remotes:WaitForChild("TestChestTake") :: RemoteEvent

local player = Players.LocalPlayer

local TestChestPanel = {}

type Category = { Id: string, Icon: string }

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = HudStyle.FONT
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function hotbarList(): { string }
	local value = player:GetAttribute("Hotbar")
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
end

local function categories(): { Category }
	local list: { Category } = {}
	for _, class in InventoryConfig.Classes do
		table.insert(list, { Id = class.Id, Icon = class.Icon })
	end
	table.insert(list, ARMOR_CATEGORY)
	table.insert(list, CURRENCY_CATEGORY)
	return list
end

-- What an item's button says, and whether pressing it does anything.
local function weaponButton(name: string): (string, boolean)
	local owned = player:GetAttribute("OwnedWeapons")
	if typeof(owned) ~= "string" or not table.find(string.split(owned, ","), name) then
		return "Take", true
	end
	local hotbar = hotbarList()
	if table.find(hotbar, name) then
		return "In hotbar", false
	end
	-- Moving it in swaps out the weapon in its category's slot.
	local slot = InventoryConfig.weaponSlot(name)
	local current = if slot then hotbar[slot] else nil
	return if current and current ~= "" then "Swap in" else "To hotbar", true
end

local function armorButton(setId: string): (string, boolean)
	local set = ArmorConfig.Sets[setId]
	if player:GetAttribute(`OwnsArmor{setId}`) ~= true then
		return "Take", true
	end
	for slot in set.Pieces do
		if player:GetAttribute(`Armor{slot}`) ~= setId then
			return "Wear set", true
		end
	end
	return "Wearing", false
end

local function shieldButton(id: string): (string, boolean)
	if player:GetAttribute(`OwnsShield{id}`) ~= true then
		return "Take", true
	end
	if player:GetAttribute("Shield") == id then
		return "Wearing", false
	end
	return "Wear", true
end

-- "20% full set · Helmet 4% · Chestplate 7% · ...", in the backpack's slot order.
local function armorDetail(set: ArmorConfig.ArmorSet): string
	local parts: { string } = {}
	local total = 0
	for _, slot in ArmorConfig.Slots do
		local amount = set.Pieces[slot]
		if amount then
			table.insert(parts, `{slot} {math.round(amount * 100)}%`)
			total += amount
		end
	end
	return `{math.round(math.min(total, ArmorConfig.MaxProtection) * 100)}% full set  ·  {table.concat(parts, " · ")}`
end

function TestChestPanel.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TestChest"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Scales the panel down on small screens, like the backpack.
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
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = holder
	HudStyle.chunky(panel, 26, 4)
	local rim = panel:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(230, 180, 60) -- a gold rim, like the chest
	end
	Instance.new("UIScale").Parent = panel -- for the open pop
	local modal = Instance.new("TextButton") -- frees the mouse while open (even in shift lock)
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	local title = label(panel, "Test Chest", 30)
	title.Position = UDim2.fromOffset(70, 20)
	title.Size = UDim2.fromOffset(400, 36)
	HudStyle.iconBeside(title, "Chest", 36)
	local subtitle = label(panel, "Every item in the game, for testing. Take what you need.", 15, SOFT_TEXT)
	subtitle.Position = UDim2.fromOffset(32, 56)
	subtitle.Size = UDim2.fromOffset(600, 20)

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -20, 0, 20)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
	close.Font = HudStyle.FONT
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = panel
	HudStyle.chunky(close, 12, 3)

	-- Category tabs down the left.
	local tabList = Instance.new("Frame")
	tabList.Position = UDim2.fromOffset(24, 96)
	tabList.Size = UDim2.fromOffset(TAB_WIDTH, PANEL_SIZE.Y - 120)
	tabList.BackgroundTransparency = 1
	tabList.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabList

	-- The items, in a scrolling list on the right.
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(TAB_WIDTH + 44, 96)
	list.Size = UDim2.fromOffset(PANEL_SIZE.X - TAB_WIDTH - 68, PANEL_SIZE.Y - 120)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = list
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop, listPadding.PaddingLeft, listPadding.PaddingRight = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 14)
	listPadding.Parent = list

	local selected = categories()[1].Id
	local tabs: { [string]: TextButton } = {}
	local refreshList: () -> ()

	for order, category in categories() do
		local tab = Instance.new("TextButton")
		tab.LayoutOrder = order
		tab.Size = UDim2.new(1, 0, 0, 44)
		tab.BackgroundColor3 = TAB_COLOR
		tab.Font = HudStyle.FONT
		tab.TextSize = 18
		tab.TextColor3 = Color3.new(1, 1, 1)
		tab.TextXAlignment = Enum.TextXAlignment.Left
		tab.Text = category.Id
		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, 48)
		tabPadding.Parent = tab
		local tabIcon = Icons.image(tab, category.Icon)
		tabIcon.AnchorPoint = Vector2.new(0, 0.5)
		tabIcon.Position = UDim2.new(0, -38, 0.5, 0)
		tabIcon.Size = UDim2.fromOffset(28, 28)
		tab.Parent = tabList
		HudStyle.chunky(tab, 12, 3)
		tab.Activated:Connect(function()
			selected = category.Id
			refreshList()
		end)
		tabs[category.Id] = tab
	end

	-- One item card: icon, name (tinted by rarity), detail line, and the action button.
	local function card(order: number, name: string, rarity: InventoryConfig.Rarity, detail: string, buttonText: string, enabled: boolean, onPress: () -> (), drawIcon: (Frame) -> ())
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		frame.BackgroundColor3 = CARD_COLOR
		frame.Parent = list
		HudStyle.chunky(frame, 14, 3)
		local special = rarity ~= InventoryConfig.Rarities[1]
		if special then
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = rarity.Color
			end
		end

		local iconFrame = Instance.new("Frame")
		iconFrame.Position = UDim2.fromOffset(10, 10)
		iconFrame.Size = UDim2.fromOffset(CARD_HEIGHT - 20, CARD_HEIGHT - 20)
		iconFrame.BackgroundColor3 = TAB_COLOR
		iconFrame.Parent = frame
		HudStyle.chunky(iconFrame, 10, 2)
		drawIcon(iconFrame)

		local nameLabel = label(frame, name, 20, if special then rarity.Color else Color3.new(1, 1, 1))
		nameLabel.Position = UDim2.fromOffset(CARD_HEIGHT + 4, 12)
		nameLabel.Size = UDim2.new(1, -CARD_HEIGHT - 150, 0, 24)
		local detailLabel = label(frame, `{rarity.Id}  ·  {detail}`, 13, SOFT_TEXT)
		detailLabel.Position = UDim2.fromOffset(CARD_HEIGHT + 4, 38)
		detailLabel.Size = UDim2.new(1, -CARD_HEIGHT - 150, 0, 50)
		detailLabel.TextWrapped = true
		detailLabel.TextYAlignment = Enum.TextYAlignment.Top

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -14, 0.5, 0)
		button.Size = UDim2.fromOffset(118, 40)
		button.BackgroundColor3 = if enabled then BUTTON_ACTIVE else BUTTON_DONE
		button.AutoButtonColor = enabled
		button.Font = HudStyle.FONT
		button.TextSize = 17
		button.TextColor3 = if enabled then Color3.new(1, 1, 1) else SOFT_TEXT
		button.Text = buttonText
		button.Parent = frame
		HudStyle.chunky(button, 10, 3)
		Instance.new("UIScale").Parent = button
		if enabled then
			button.Activated:Connect(function()
				HudStyle.pop(button, 0.88)
				onPress()
			end)
		end
	end

	refreshList = function()
		for id, tab in tabs do
			tab.BackgroundColor3 = if id == selected then TAB_SELECTED else TAB_COLOR
		end
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if selected == ARMOR_CATEGORY.Id then
			for order, setId in ArmorConfig.SetOrder do
				local set = ArmorConfig.Sets[setId]
				local text, enabled = armorButton(setId)
				local detail = if set.StarterFor then `{set.StarterFor} starter  ·  {armorDetail(set)}` else armorDetail(set)
				card(order, `{set.Name} Armor`, InventoryConfig.rarityById(set.Rarity), detail, text, enabled, function()
					takeRemote:FireServer("Armor", setId)
				end, function(iconFrame)
					iconFrame.BackgroundColor3 = set.Color
					Icons.image(iconFrame, "Chestplate", 10)
				end)
			end
			for order, id in ShieldConfig.Order do
				local shield = ShieldConfig.Shields[id]
				local text, enabled = shieldButton(id)
				local bonus = `+{shield.BlockBonus} block, +{shield.ExtraCharges} charge with Sword, Emberfang, Mace, Axe, or Rapier`
				local detail = if shield.StarterFor then `{shield.StarterFor} set  ·  {bonus}` else bonus
				card(#ArmorConfig.SetOrder + order, shield.Name, InventoryConfig.rarityById(shield.Rarity), detail, text, enabled, function()
					takeRemote:FireServer("Shield", id)
				end, function(iconFrame)
					iconFrame.BackgroundColor3 = shield.Color
					Icons.image(iconFrame, "Shield", 10)
				end)
			end
		elseif selected == CURRENCY_CATEGORY.Id then
			card(1, "100 Coins", InventoryConfig.Rarities[5], "Add 100 coins for testing.", "TAKE", true, function()
				takeRemote:FireServer("Coins", "100")
			end, function(iconFrame)
				iconFrame.BackgroundColor3 = Color3.fromRGB(220, 170, 50)
				local dot = Instance.new("TextLabel")
				dot.Size = UDim2.fromScale(1, 1)
				dot.BackgroundTransparency = 1
				dot.Font = HudStyle.FONT
				dot.TextSize = 28
				dot.TextColor3 = Color3.fromRGB(255, 235, 140)
				dot.Text = "¢"
				dot.Parent = iconFrame
			end)
			card(2, "500 Coins", InventoryConfig.Rarities[5], "Add 500 coins for testing.", "TAKE", true, function()
				takeRemote:FireServer("Coins", "500")
			end, function(iconFrame)
				iconFrame.BackgroundColor3 = Color3.fromRGB(220, 170, 50)
				local dot = Instance.new("TextLabel")
				dot.Size = UDim2.fromScale(1, 1)
				dot.BackgroundTransparency = 1
				dot.Font = HudStyle.FONT
				dot.TextSize = 28
				dot.TextColor3 = Color3.fromRGB(255, 235, 140)
				dot.Text = "¢"
				dot.Parent = iconFrame
			end)
		else
			local order = 0
			for _, info in InventoryConfig.Weapons do
				if info.Class == selected then
					order += 1
					local text, enabled = weaponButton(info.Name)
					card(order, info.Name, InventoryConfig.rarity(info.Name), info.Description, text, enabled, function()
						takeRemote:FireServer("Weapon", info.Name)
					end, function(iconFrame)
						WeaponIcon.show(WeaponIcon.viewport(iconFrame), info.Name)
					end)
				end
			end
		end
	end

	-- Opening and closing.
	local chestPosition: Vector3? = nil
	local distanceWatch: RBXScriptConnection? = nil

	local function setOpen(open: boolean)
		if open == panel.Visible then
			return
		end
		panel.Visible = open
		if open then
			Panels.opened("TestChest")
			refreshList()
			HudStyle.pop(panel, 0.92)
			distanceWatch = RunService.Heartbeat:Connect(function()
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if chestPosition and root and root:IsA("BasePart") and (root.Position - chestPosition).Magnitude > CLOSE_DISTANCE then
					setOpen(false)
				end
			end)
		else
			Panels.closed("TestChest")
			if distanceWatch then
				distanceWatch:Disconnect()
				distanceWatch = nil
			end
		end
	end

	Panels.register("TestChest", function()
		setOpen(false)
	end)
	openRemote.OnClientEvent:Connect(function(position: unknown)
		chestPosition = if typeof(position) == "Vector3" then position else nil
		setOpen(true)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
			setOpen(false)
		end
	end)

	-- Keep the buttons right as the server answers (hotbar moves, armor given/worn).
	local refreshQueued = false
	player.AttributeChanged:Connect(function(attribute)
		if not panel.Visible or refreshQueued then
			return
		end
		if attribute == "Hotbar" or attribute == "HotbarSlots" or attribute == "OwnedWeapons" or string.sub(attribute, 1, 5) == "Armor" or string.sub(attribute, 1, 9) == "OwnsArmor" or attribute == "Shield" or string.sub(attribute, 1, 10) == "OwnsShield" then
			refreshQueued = true
			task.defer(function()
				refreshQueued = false
				if panel.Visible then
					refreshList()
				end
			end)
		end
	end)
	WeaponIcon.Previews.ChildAdded:Connect(function()
		if panel.Visible then
			refreshList() -- a weapon's look arrived
		end
	end)
end

return TestChestPanel
