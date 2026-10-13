--!strict
-- Our hotbar, replacing Roblox's: an ornate bar at the bottom of the screen (between the dash
-- and block meters) with a fixed slot per weapon category and two potion slots
-- (InventoryConfig.WeaponSlots / PotionSlots):
--   [4 potion] [2 Magic] ( 1 Primary ) [3 Ranged] [5 potion]
-- The Primary weapon sits in the big ring in the middle, under a red gem; the others in
-- metal-framed squares on a stone panel, with a navy band across the top naming the weapon in
-- hand. Number keys or clicking a slot equip that weapon or use that potion; using an equipped
-- weapon again puts it away. The equipped slot glows gold, and a star in the corner counts
-- the skill points spent in that weapon's tree (SkillMath). Names above Common are tinted
-- their rarity's color. The slots come from the server's "Hotbar" player attribute (see
-- InventoryService; an empty slot is blank); the tools themselves are in the Backpack.
-- The backpack hides it while it's open (Hotbar.setHidden).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local Icons = require(ReplicatedStorage.Shared.Icons)
local HudStyle = require(script.Parent.HudStyle)
local WeaponIcon = require(script.Parent.WeaponIcon)

-- The bar's layout, in pixels from its top-left corner (it's WIDTH x HEIGHT, bottom-centered).
local WIDTH, HEIGHT = 440, 112
local BOTTOM = -8 -- the bar's bottom edge, from the bottom of the screen
local CENTER_X = WIDTH / 2
local PANEL_Y, PANEL_HEIGHT = 78, 68 -- the stone panel's middle and height
local BAND_Y, BAND_HEIGHT = 34, 26 -- the navy band behind the ring
local RING_Y, RING_SIZE = 62, 98 -- the big Primary ring
local SQUARE = 56 -- a square slot's metal frame
local INNER_X, OUTER_X = 89, 153 -- square slots' distance from the middle

local STONE = Color3.fromRGB(74, 70, 66)
local METAL = Color3.fromRGB(200, 190, 168)
local METAL_DARK = Color3.fromRGB(105, 98, 86)
local BONE = Color3.fromRGB(225, 214, 192)
local BAND = Color3.fromRGB(46, 52, 92)
local WELL = Color3.fromRGB(30, 29, 34) -- a slot's inside
local GEM = Color3.fromRGB(220, 40, 40)
local EQUIPPED_GLOW = Color3.fromRGB(255, 205, 70)
local SKILL_STAR_COLOR = Color3.fromRGB(255, 215, 90)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local player = Players.LocalPlayer
local useRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ConsumableUse") :: RemoteEvent

local Hotbar = {}

local bar: Frame? = nil

-- Hides the hotbar (e.g. while the backpack is open) or shows it again.
function Hotbar.setHidden(hidden: boolean)
	if bar then
		bar.Visible = not hidden
	end
end

-- The hotbar's slots, in order ("" for an empty one).
local function hotbarList(): { string }
	local value = player:GetAttribute("Hotbar")
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
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

local function findTool(name: string): Tool?
	for _, place in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		local tool = place and place:FindFirstChild(name)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end
	return nil
end

local function equippedName(): string?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if tool then tool.Name else nil
end

-- Equips the weapon in slot `index`, uses the consumable there, or puts away the equipped weapon.
local function useSlot(index: number)
	local name = hotbarList()[index]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not name or name == "" or not humanoid or humanoid.Health <= 0 then
		return
	end
	if ShopConfig.consumable(name) then
		useRemote:FireServer(name)
		return
	end
	if equippedName() == name then
		humanoid:UnequipTools()
		return
	end
	local tool = findTool(name)
	if tool then
		humanoid:EquipTool(tool)
	end
end

-- Drawing --------------------------------------------------------------------------------

-- A plain block centered on (x, y), turned `rotation` degrees.
local function block(parent: Instance, x: number, y: number, width: number, height: number, color: Color3, rotation: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Rotation = rotation or 0
	frame.Parent = parent
	return frame
end

local function corner(frame: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = frame
end

local function stroke(frame: GuiObject, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = frame
	return s
end

-- Shading across a frame (tints its color): `points` are (position, brightness 0..255).
local function shade(frame: GuiObject, rotation: number, points: { { number } })
	local keys: { ColorSequenceKeypoint } = {}
	for _, point in points do
		local v = point[2]
		table.insert(keys, ColorSequenceKeypoint.new(point[1], Color3.fromRGB(v, v, v)))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = frame
end

-- Polished metal: bright at the top-left, dark at the bottom-right.
local function metal(frame: GuiObject)
	shade(frame, 45, { { 0, 255 }, { 0.45, 215 }, { 0.55, 180 }, { 1, 120 } })
end

-- A small metal diamond (a rivet on a slot's corner).
local function rivet(parent: Instance, x: number, y: number)
	local r = block(parent, x, y, 9, 9, METAL, 45)
	r.ZIndex = 4
	metal(r)
	stroke(r, HudStyle.OUTLINE, 1)
end

-- A horn or claw: a rounded, bone-colored spike, shaded across its width (curves are built
-- from two of them, the tip thinner).
local function spike(parent: Instance, x: number, y: number, width: number, height: number, rotation: number, zIndex: number)
	local s = block(parent, x, y, width, height, BONE, rotation)
	s.ZIndex = zIndex
	corner(s, UDim.new(0.5, 0))
	shade(s, 0, { { 0, 150 }, { 0.4, 255 }, { 1, 170 } })
	stroke(s, METAL_DARK, 1)
end

type Slot = {
	scale: GuiObject, -- popped when equipped
	glow: UIStroke, -- the inner edge, gold when equipped
	viewport: ViewportFrame,
	icon: ImageLabel,
	name: TextLabel,
	skill: TextLabel,
	empty: TextLabel, -- the slot's category, while it's empty
	shown: string?,
}

-- Fills a slot's dark well with its contents and a click target.
local function fillWell(well: Frame, index: number, keyPosition: UDim2, emptyText: string, scale: GuiObject, glow: UIStroke): Slot
	local viewport = WeaponIcon.viewport(well)
	viewport.ZIndex = 5
	local itemIcon = Icons.image(well, nil, 10)
	itemIcon.ZIndex = 5
	itemIcon.Visible = false
	local key = HudStyle.caption(well, tostring(index), 14)
	key.Position = keyPosition
	key.Size = UDim2.fromOffset(14, 16)
	key.ZIndex = 7
	local name = HudStyle.caption(well, "", 10)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -1)
	name.Size = UDim2.new(1, 8, 0, 12)
	name.ZIndex = 7
	local skill = HudStyle.caption(well, "", 11)
	skill.AnchorPoint = Vector2.new(1, 0)
	skill.Position = UDim2.new(1, -3, 0, 2)
	skill.Size = UDim2.fromOffset(28, 13)
	skill.TextXAlignment = Enum.TextXAlignment.Right
	skill.TextColor3 = SKILL_STAR_COLOR
	skill.ZIndex = 7
	local empty = HudStyle.caption(well, emptyText, 9)
	empty.Size = UDim2.fromScale(1, 1)
	empty.TextColor3 = SOFT_TEXT
	empty.TextTransparency = 0.35
	empty.ZIndex = 6
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 8
	button.Parent = well
	button.Activated:Connect(function()
		useSlot(index)
	end)
	return { scale = scale, glow = glow, viewport = viewport, icon = itemIcon, name = name, skill = skill, empty = empty, shown = nil }
end

-- A square slot: a riveted metal frame around a dark well, centered at (x, PANEL_Y).
local function squareSlot(parent: Instance, x: number, index: number, emptyText: string): Slot
	local frame = block(parent, x, PANEL_Y, SQUARE, SQUARE, METAL)
	frame.ZIndex = 3
	metal(frame)
	stroke(frame, HudStyle.OUTLINE, 1.5)
	Instance.new("UIScale").Parent = frame
	local well = block(frame, SQUARE / 2, SQUARE / 2, SQUARE - 10, SQUARE - 10, WELL)
	well.ZIndex = 4
	shade(well, 90, { { 0, 150 }, { 1, 255 } })
	local glow = stroke(well, METAL_DARK, 1.5)
	local half = SQUARE / 2
	for _, offset in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		rivet(parent, x + offset.X * (half - 1), PANEL_Y + offset.Y * (half - 1))
	end
	return fillWell(well, index, UDim2.fromOffset(4, 1), emptyText, frame, glow)
end

-- The big ring in the middle: a metal ring with claws around its top and a red gem on it,
-- around a round dark well.
local function ringSlot(parent: Instance, index: number, emptyText: string): Slot
	-- Claws curling up around the top of the ring (behind it, so only their tips show).
	for _, angle in { -62, -34, 34, 62 } do
		local radians = math.rad(angle)
		local reach = RING_SIZE / 2 + 2
		spike(parent, CENTER_X + math.sin(radians) * reach, RING_Y - math.cos(radians) * reach, 11, 24, angle * 0.8, 2)
	end
	local ring = block(parent, CENTER_X, RING_Y, RING_SIZE, RING_SIZE, METAL)
	ring.ZIndex = 3
	corner(ring, UDim.new(0.5, 0))
	metal(ring)
	stroke(ring, HudStyle.OUTLINE, 2)
	Instance.new("UIScale").Parent = ring
	local groove = block(ring, RING_SIZE / 2, RING_SIZE / 2, RING_SIZE - 12, RING_SIZE - 12, METAL_DARK)
	groove.ZIndex = 3
	corner(groove, UDim.new(0.5, 0))
	local wellSize = RING_SIZE - 20
	local well = block(ring, RING_SIZE / 2, RING_SIZE / 2, wellSize, wellSize, WELL)
	well.ZIndex = 4
	corner(well, UDim.new(0.5, 0))
	shade(well, 90, { { 0, 150 }, { 1, 255 } })
	local glow = stroke(well, METAL_DARK, 2)

	-- The gem: a red diamond in a metal setting, on top of the ring.
	local setting = block(parent, CENTER_X, RING_Y - RING_SIZE / 2 - 4, 30, 30, METAL, 45)
	setting.ZIndex = 9
	metal(setting)
	stroke(setting, HudStyle.OUTLINE, 1.5)
	local gem = block(setting, 15, 15, 17, 17, GEM)
	gem.ZIndex = 10
	shade(gem, 45, { { 0, 255 }, { 0.35, 230 }, { 1, 110 } })
	local shine = block(gem, 5, 5, 4, 4, Color3.fromRGB(255, 210, 200))
	shine.ZIndex = 11

	local slot = fillWell(well, index, UDim2.new(0.5, -7, 0, 6), emptyText, ring, glow)
	slot.name.Position = UDim2.new(0.5, 0, 1, -6)
	slot.skill.Position = UDim2.new(1, -10, 0, 12)
	return slot
end

-- A horn curling up and out of one end of the panel (`side` -1 left, 1 right).
local function horn(parent: Instance, side: number)
	local x = CENTER_X + side * (WIDTH / 2 - 12)
	spike(parent, x, PANEL_Y - 6, 12, 46, side * 16, 1)
	spike(parent, x + side * 9, PANEL_Y - 34, 8, 24, side * 38, 1)
	-- And a claw hooking in over the panel's top edge.
	spike(parent, x - side * 26, PANEL_Y - PANEL_HEIGHT / 2 - 2, 7, 26, side * -62, 3)
end

local function buildBar(parent: Instance): (Frame, { Slot }, TextLabel, TextLabel)
	local root = Instance.new("Frame")
	root.Name = "Slots"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, BOTTOM)
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- The navy band across the top, with the weapon in hand named on it.
	local band = block(root, CENTER_X, BAND_Y, WIDTH - 100, BAND_HEIGHT, BAND)
	band.ZIndex = 1
	stroke(band, METAL, 2)
	shade(band, 90, { { 0, 200 }, { 0.5, 255 }, { 1, 170 } })
	local held = HudStyle.caption(band, "", 13)
	held.Position = UDim2.fromOffset(10, 0)
	held.Size = UDim2.new(0.5, -(RING_SIZE / 2) - 14, 1, 0)
	held.TextXAlignment = Enum.TextXAlignment.Left
	held.TextTruncate = Enum.TextTruncate.AtEnd
	held.ZIndex = 2
	local heldClass = HudStyle.caption(band, "", 11)
	heldClass.AnchorPoint = Vector2.new(1, 0)
	heldClass.Position = UDim2.new(1, -10, 0, 0)
	heldClass.Size = UDim2.new(0.5, -(RING_SIZE / 2) - 14, 1, 0)
	heldClass.TextXAlignment = Enum.TextXAlignment.Right
	heldClass.TextColor3 = SOFT_TEXT
	heldClass.ZIndex = 2

	-- The stone panel the squares sit in.
	local panel = block(root, CENTER_X, PANEL_Y, WIDTH - 20, PANEL_HEIGHT, STONE)
	panel.ZIndex = 2
	corner(panel, UDim.new(0, 4))
	stroke(panel, METAL, 2)
	shade(panel, 8, { { 0, 150 }, { 0.15, 205 }, { 0.3, 160 }, { 0.5, 215 }, { 0.68, 150 }, { 0.85, 200 }, { 1, 140 } })
	local lip = block(panel, (WIDTH - 20) / 2, 2, WIDTH - 24, 3, METAL)
	lip.ZIndex = 2
	metal(lip)

	horn(root, -1)
	horn(root, 1)

	local slots: { Slot } = {}
	local weaponSlots = InventoryConfig.WeaponSlots
	slots[1] = ringSlot(root, 1, string.upper(weaponSlots[1].Id))
	slots[2] = squareSlot(root, CENTER_X - INNER_X, 2, string.upper(weaponSlots[2].Id))
	slots[3] = squareSlot(root, CENTER_X + INNER_X, 3, string.upper(weaponSlots[3].Id))
	slots[4] = squareSlot(root, CENTER_X - OUTER_X, 4, "POTION")
	slots[5] = squareSlot(root, CENTER_X + OUTER_X, 5, "POTION")
	return root, slots, held, heldClass
end

function Hotbar.start()
	-- Turn off Roblox's hotbar (it can take a moment to be allowed at startup).
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
				break
			end
			task.wait(0.5)
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hotbar"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local root, slots, held, heldClass = buildBar(HudStyle.holder(gui, Vector2.new(0.5, 1)))
	bar = root
	local count = #slots

	local lastEquipped: string? = nil
	local function update()
		local list = hotbarList()
		local equipped = equippedName()
		local alloc = SkillMath.allocations(player)
		for index, slot in slots do
			local listed = list[index]
			local item = if listed and listed ~= "" then listed else nil
			local consumable = if item then ShopConfig.consumable(item) else nil
			if consumable then
				if slot.shown ~= item then
					slot.viewport:ClearAllChildren()
					Icons.set(slot.icon, consumable.Icon)
					slot.shown = item
				end
				slot.viewport.Visible = false
				slot.icon.Visible = true
				slot.icon.ImageColor3 = if consumable.ManaPercent then Color3.fromRGB(120, 170, 255) else Color3.fromRGB(120, 235, 145)
			elseif slot.shown ~= item then
				slot.icon.Visible = false
				slot.viewport.Visible = true
				slot.shown = if WeaponIcon.show(slot.viewport, item) then item else nil
			end
			slot.empty.Visible = item == nil
			slot.name.Text = if consumable then consumable.Name else item or ""
			local spent = if item and not consumable then SkillMath.spent(alloc, SkillMath.treeOf(item)) else 0
			slot.skill.Text = if consumable then `x{consumableCount(consumable.Id)}` elseif spent > 0 then `★{spent}` else ""
			local isEquipped = item ~= nil and not consumable and item == equipped
			local rarity = if item and not consumable then InventoryConfig.rarity(item) else nil
			local special = rarity ~= nil and rarity ~= InventoryConfig.Rarities[1]
			slot.name.TextColor3 = if consumable then SOFT_TEXT elseif rarity and special then rarity.Color else Color3.new(1, 1, 1)
			slot.glow.Color = if isEquipped then EQUIPPED_GLOW elseif rarity and special then rarity.Color else METAL_DARK
			slot.glow.Thickness = if isEquipped then 3 elseif rarity and special then 2 else 1.5
			if isEquipped and equipped ~= lastEquipped then
				HudStyle.pop(slot.scale, 1.12)
			end
		end

		local info = if equipped then InventoryConfig.weapon(equipped) else nil
		local rarity = if info then InventoryConfig.rarity(info.Name) else nil
		held.Text = if info then info.Name else "Unarmed"
		held.TextColor3 = if rarity and rarity ~= InventoryConfig.Rarities[1] then rarity.Color else Color3.new(1, 1, 1)
		local slotIndex = if info then InventoryConfig.weaponSlot(info.Name) else nil
		heldClass.Text = if slotIndex then string.upper(InventoryConfig.WeaponSlots[slotIndex].Id) else ""
		lastEquipped = equipped
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not root.Visible then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index and index <= count then
			useSlot(index)
		end
	end)

	player:GetAttributeChangedSignal("Hotbar"):Connect(update)
	player:GetAttributeChangedSignal("Consumables"):Connect(update)
	player:GetAttributeChangedSignal("Skills"):Connect(update)
	WeaponIcon.Previews.ChildAdded:Connect(function()
		for _, slot in slots do
			slot.shown = nil -- a weapon's look arrived: redraw
		end
		update()
	end)
	-- Equipping moves a tool into the character; watch it come and go.
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				update()
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				update()
			end
		end)
		update()
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	update()
end

return Hotbar
