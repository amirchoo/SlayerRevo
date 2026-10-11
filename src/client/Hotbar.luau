--!strict
-- Our hotbar, replacing Roblox's: a row of chunky slots (HudStyle) under the health bar, one
-- per hotbar slot, each showing its weapon's model (WeaponIcon), number key, and name.
-- Number keys 1..N or clicking a slot equip that weapon; doing it again puts it away. The
-- equipped slot is outlined in gold, and a star in the corner counts the skill points spent in
-- that weapon's tree (SkillMath). Names above Common are tinted their rarity's color, and so
-- is the outline of an unequipped slot. The weapons and their order come from the server's
-- "Hotbar" player attribute (see InventoryService); the tools themselves are in the Backpack.
-- The backpack hides it while it's open (Hotbar.setHidden).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local HudStyle = require(script.Parent.HudStyle)
local WeaponIcon = require(script.Parent.WeaponIcon)

local SLOT = 64
local GAP = 8
local BOTTOM = -14 -- the row's bottom edge, from the bottom of the screen
local SLOT_COLOR = Color3.fromRGB(58, 54, 74)
local EMPTY_COLOR = Color3.fromRGB(42, 40, 54)
local EQUIPPED_BORDER = Color3.fromRGB(255, 205, 70)
local SKILL_STAR_COLOR = Color3.fromRGB(255, 215, 90)
local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local player = Players.LocalPlayer

local Hotbar = {}

local row: Frame? = nil

-- Hides the hotbar (e.g. while the backpack is open) or shows it again.
function Hotbar.setHidden(hidden: boolean)
	if row then
		row.Visible = not hidden
	end
end

local function hotbarList(): { string }
	local value = player:GetAttribute("Hotbar")
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
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

-- Equips the weapon in slot `index`, or puts it away if it's already in hand.
local function useSlot(index: number)
	local name = hotbarList()[index]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not name or not humanoid or humanoid.Health <= 0 then
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

	local count = InventoryConfig.HotbarSlots
	local width = count * SLOT + (count - 1) * GAP
	local bar = Instance.new("Frame")
	bar.Name = "Slots"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, BOTTOM)
	bar.Size = UDim2.fromOffset(width, SLOT)
	bar.BackgroundTransparency = 1
	bar.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))
	row = bar

	type Slot = { frame: Frame, stroke: UIStroke, viewport: ViewportFrame, name: TextLabel, skill: TextLabel, shown: string? }
	local slots: { Slot } = {}
	for index = 1, count do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset((index - 1) * (SLOT + GAP), 0)
		frame.Size = UDim2.fromOffset(SLOT, SLOT)
		frame.BackgroundColor3 = SLOT_COLOR
		frame.BackgroundTransparency = 0.1
		frame.Parent = bar
		HudStyle.chunky(frame, 12, 3)
		Instance.new("UIScale").Parent = frame
		local viewport = WeaponIcon.viewport(frame)
		local key = HudStyle.caption(frame, tostring(index), 15)
		key.Position = UDim2.fromOffset(6, 2)
		key.Size = UDim2.fromOffset(14, 16)
		key.ZIndex = 2
		local name = HudStyle.caption(frame, "", 11)
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -2)
		name.Size = UDim2.new(1, -4, 0, 13)
		name.ZIndex = 2
		local skill = HudStyle.caption(frame, "", 12)
		skill.AnchorPoint = Vector2.new(1, 0)
		skill.Position = UDim2.new(1, -4, 0, 2)
		skill.Size = UDim2.fromOffset(30, 14)
		skill.TextXAlignment = Enum.TextXAlignment.Right
		skill.TextColor3 = SKILL_STAR_COLOR
		skill.ZIndex = 2
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 3
		button.Parent = frame
		button.Activated:Connect(function()
			useSlot(index)
		end)
		slots[index] = { frame = frame, stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke, viewport = viewport, name = name, skill = skill, shown = nil }
	end

	local lastEquipped: string? = nil
	local function update()
		local list = hotbarList()
		local equipped = equippedName()
		local alloc = SkillMath.allocations(player)
		for index, slot in slots do
			local weapon = list[index]
			if slot.shown ~= weapon then
				slot.shown = if WeaponIcon.show(slot.viewport, weapon) then weapon else nil
			end
			slot.name.Text = weapon or ""
			local spent = if weapon then SkillMath.spent(alloc, SkillMath.treeOf(weapon)) else 0
			slot.skill.Text = if spent > 0 then `★{spent}` else ""
			slot.frame.BackgroundColor3 = if weapon then SLOT_COLOR else EMPTY_COLOR
			local isEquipped = weapon ~= nil and weapon == equipped
			local rarity = if weapon then InventoryConfig.rarity(weapon) else nil
			local special = rarity ~= nil and rarity ~= InventoryConfig.Rarities[1]
			slot.name.TextColor3 = if rarity and special then rarity.Color else Color3.new(1, 1, 1)
			slot.stroke.Color = if isEquipped then EQUIPPED_BORDER elseif rarity and special then rarity.Color else HudStyle.OUTLINE
			slot.stroke.Thickness = if isEquipped then 4 else 3
			if isEquipped and equipped ~= lastEquipped then
				HudStyle.pop(slot.frame, 1.15)
			end
		end
		lastEquipped = equipped
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not bar.Visible then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index and index <= count then
			useSlot(index)
		end
	end)

	player:GetAttributeChangedSignal("Hotbar"):Connect(update)
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
