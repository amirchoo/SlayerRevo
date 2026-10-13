--!strict
-- NPC shop panel. Merchant sells consumables, Blacksmith sells weapons, Armorer sells armor.
-- The server checks the seller, spends coins, and grants the item.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CurrencyConfig = require(ReplicatedStorage.Shared.Config.CurrencyConfig)
local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Icons = require(ReplicatedStorage.Shared.Icons)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local WeaponIcon = require(script.Parent.WeaponIcon)

local PANEL_SIZE = Vector2.new(760, 500)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local TAB_COLOR = Color3.fromRGB(58, 54, 74)
local TAB_SELECTED = Color3.fromRGB(205, 150, 60)
local CARD_COLOR = Color3.fromRGB(46, 43, 60)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local BUTTON_ACTIVE = Color3.fromRGB(80, 190, 110)
local BUTTON_DONE = Color3.fromRGB(70, 68, 85)
local BUTTON_LOCKED = Color3.fromRGB(120, 68, 62)
local TAB_WIDTH = 170
local CARD_HEIGHT = 96

local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopBuy") :: RemoteEvent
local player = Players.LocalPlayer

local ShopPanel = {}

type Category = { Id: string, Icon: string }

local isStarted = false
local openPanel: ((Vector3, string) -> ())? = nil

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

local function ownsWeapon(name: string): boolean
	local owned = player:GetAttribute("OwnedWeapons")
	return typeof(owned) == "string" and table.find(string.split(owned, ","), name) ~= nil
end

local function ownsArmor(setId: string): boolean
	return player:GetAttribute(`OwnsArmor{setId}`) == true
end

local function consumableCount(itemId: string): number
	local value = player:GetAttribute("Consumables")
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

local function coins(): number
	local value = player:GetAttribute("Coins")
	return if typeof(value) == "number" then value else 0
end

local function categories(sellerId: string): { Category }
	local used: { [string]: boolean } = {}
	local list: { Category } = {}
	for _, item in ShopConfig.Items do
		if item.Seller == sellerId and not used[item.Category] then
			used[item.Category] = true
		end
	end
	for _, class in InventoryConfig.Classes do
		if used[class.Id] then
			table.insert(list, { Id = class.Id, Icon = class.Icon })
		end
	end
	if used[ShopConfig.ConsumableCategory] then
		table.insert(list, { Id = ShopConfig.ConsumableCategory, Icon = "Backpack" })
	end
	if used[ShopConfig.ArmorCategory] then
		table.insert(list, { Id = ShopConfig.ArmorCategory, Icon = "Shield" })
	end
	return list
end

local function armorDetail(setId: string): string
	local set = ArmorConfig.Sets[setId]
	if not set then
		return "Armor set."
	end
	local total = 0
	for _, slot in ArmorConfig.Slots do
		total += set.Pieces[slot] or 0
	end
	return `{math.round(math.min(total, ArmorConfig.MaxProtection) * 100)}% full-set protection.`
end

function ShopPanel.open(position: Vector3, sellerId: string)
	if openPanel then
		openPanel(position, sellerId)
	end
end

function ShopPanel.start()
	if isStarted then
		return
	end
	isStarted = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponShop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

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
		rim.Color = Color3.fromRGB(230, 180, 60)
	end
	Instance.new("UIScale").Parent = panel
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	local title = label(panel, "Shop", 30)
	title.Position = UDim2.fromOffset(70, 20)
	title.Size = UDim2.fromOffset(360, 36)
	local titleIcon = HudStyle.iconBeside(title, "Backpack", 36)
	local subtitle = label(panel, "", 15, SOFT_TEXT)
	subtitle.Position = UDim2.fromOffset(32, 56)
	subtitle.Size = UDim2.fromOffset(560, 20)

	local coinLabel = label(panel, "", 18, CurrencyConfig.TextColor)
	coinLabel.AnchorPoint = Vector2.new(1, 0)
	coinLabel.Position = UDim2.new(1, -76, 0, 28)
	coinLabel.Size = UDim2.fromOffset(180, 24)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Right

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

	local tabList = Instance.new("Frame")
	tabList.Position = UDim2.fromOffset(24, 96)
	tabList.Size = UDim2.fromOffset(TAB_WIDTH, PANEL_SIZE.Y - 120)
	tabList.BackgroundTransparency = 1
	tabList.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabList

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

	local activeSeller = ShopConfig.MerchantNpc
	local categoryList = categories(activeSeller)
	local selected = if categoryList[1] then categoryList[1].Id else ""
	local tabs: { [string]: TextButton } = {}
	local distanceWatch: RBXScriptConnection? = nil
	local sellerPosition: Vector3? = nil
	local refreshList: () -> ()

	local function setOpen(open: boolean)
		if panel.Visible == open then
			return
		end
		panel.Visible = open
		if open then
			Panels.opened("WeaponShop")
			HudStyle.pop(panel, 0.9)
			distanceWatch = RunService.Heartbeat:Connect(function()
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if sellerPosition and root and root:IsA("BasePart") and (root.Position - sellerPosition).Magnitude > 18 then
					setOpen(false)
				end
			end)
		else
			Panels.closed("WeaponShop")
			if distanceWatch then
				distanceWatch:Disconnect()
				distanceWatch = nil
			end
		end
	end

	local function card(order: number, item: ShopConfig.Item)
		local info = if item.Weapon then InventoryConfig.weapon(item.Weapon) else nil
		local owned = item.Weapon ~= nil and ownsWeapon(item.Weapon)
		if item.ArmorSet then
			owned = ownsArmor(item.ArmorSet)
		end
		local balance = coins()
		local canBuy = not owned and balance >= item.Price
		local buttonText = if owned then "Owned" elseif canBuy then "Buy" else "Need coins"

		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		frame.BackgroundColor3 = CARD_COLOR
		frame.Parent = list
		HudStyle.chunky(frame, 14, 3)

		local rarity = if item.Weapon then InventoryConfig.rarity(item.Weapon) else InventoryConfig.Rarities[1]
		if item.Weapon and rarity ~= InventoryConfig.Rarities[1] then
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
		if item.Weapon then
			WeaponIcon.show(WeaponIcon.viewport(iconFrame), item.Weapon)
		else
			local icon = Icons.image(iconFrame, item.Icon, 12)
			icon.ImageColor3 = if item.ArmorSet then Color3.fromRGB(150, 205, 255) elseif item.ManaPercent then Color3.fromRGB(120, 170, 255) else Color3.fromRGB(120, 235, 145)
		end

		local nameLabel = label(frame, item.Name, 20, rarity.Color)
		nameLabel.Position = UDim2.fromOffset(CARD_HEIGHT + 4, 12)
		nameLabel.Size = UDim2.new(1, -CARD_HEIGHT - 150, 0, 24)
		local detail = item.Description
		if info then
			detail = `{rarity.Id}  ·  {info.Description}`
		elseif item.ArmorSet then
			local set = ArmorConfig.Sets[item.ArmorSet]
			detail = `{InventoryConfig.rarityById(set and set.Rarity).Id}  ·  {armorDetail(item.ArmorSet)}`
		elseif ShopConfig.consumable(item.Id) then
			detail = `{item.Description}  ·  You own {consumableCount(item.Id)}`
		end
		local detailLabel = label(frame, `{detail}\nCost: {CurrencyConfig.format(item.Price)} coins`, 13, SOFT_TEXT)
		detailLabel.Position = UDim2.fromOffset(CARD_HEIGHT + 4, 38)
		detailLabel.Size = UDim2.new(1, -CARD_HEIGHT - 150, 0, 50)
		detailLabel.TextWrapped = true
		detailLabel.TextYAlignment = Enum.TextYAlignment.Top

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -14, 0.5, 0)
		button.Size = UDim2.fromOffset(118, 40)
		button.BackgroundColor3 = if owned then BUTTON_DONE elseif canBuy then BUTTON_ACTIVE else BUTTON_LOCKED
		button.AutoButtonColor = canBuy
		button.Font = HudStyle.FONT
		button.TextSize = 17
		button.TextColor3 = if canBuy then Color3.new(1, 1, 1) else SOFT_TEXT
		button.Text = buttonText
		button.Parent = frame
		HudStyle.chunky(button, 10, 3)
		Instance.new("UIScale").Parent = button
		if canBuy then
			button.Activated:Connect(function()
				HudStyle.pop(button, 0.88)
				buyRemote:FireServer(activeSeller, item.Id)
			end)
		end
	end

	local function rebuildTabs()
		for _, child in tabList:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		tabs = {}
		categoryList = categories(activeSeller)
		selected = if categoryList[1] then categoryList[1].Id else ""
		for order, category in categoryList do
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
	end

	refreshList = function()
		coinLabel.Text = `{CurrencyConfig.format(coins())} coins`
		for id, tab in tabs do
			tab.BackgroundColor3 = if id == selected then TAB_SELECTED else TAB_COLOR
		end
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local order = 0
		for _, item in ShopConfig.Items do
			if item.Seller == activeSeller and item.Category == selected then
				order += 1
				card(order, item)
			end
		end
	end

	openPanel = function(position: Vector3, sellerId: string)
		sellerPosition = position
		activeSeller = sellerId
		local shop = ShopConfig.shop(activeSeller)
		title.Text = if shop then shop.Title else "Shop"
		subtitle.Text = if shop then shop.Subtitle else ""
		Icons.set(titleIcon, if shop then shop.Icon else "Backpack")
		rebuildTabs()
		refreshList()
		setOpen(true)
	end

	close.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and panel.Visible and input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if panel.Visible then
			refreshList()
		end
	end)
	player:GetAttributeChangedSignal("OwnedWeapons"):Connect(function()
		if panel.Visible then
			refreshList()
		end
	end)
	player:GetAttributeChangedSignal("Consumables"):Connect(function()
		if panel.Visible then
			refreshList()
		end
	end)
	for setId in ArmorConfig.Sets do
		player:GetAttributeChangedSignal(`OwnsArmor{setId}`):Connect(function()
			if panel.Visible then
				refreshList()
			end
		end)
	end
	player:GetAttributeChangedSignal("Mana"):Connect(function()
		if panel.Visible then
			refreshList()
		end
	end)
	local function watchCharacter(character: Model)
		character:GetAttributeChangedSignal("Health"):Connect(function()
			if panel.Visible then
				refreshList()
			end
		end)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	Panels.register("WeaponShop", function()
		setOpen(false)
	end)
	rebuildTabs()
	refreshList()
end

return ShopPanel
