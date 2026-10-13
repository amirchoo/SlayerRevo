--!strict
-- Talking to townsfolk: using an NPC's "Talk" prompt (NpcService) opens a dialogue box at the
-- bottom of the screen with their name, title, and lines (NpcConfig), typed out one at a time;
-- click to continue. The guide (Action "StarterPick") ends by offering a player who hasn't
-- picked yet the starter choice: a card per weapon (with its starter armor set), then a
-- confirm step, then the StarterChoose remote. The server checks and grants the pick.
-- Shop NPCs (Action "Shop") open the shop panel after their lines.
-- Closes with its X, when the lines run out, or when you walk away.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local Starter = require(ReplicatedStorage.Shared.Starter)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local ShopPanel = require(script.Parent.ShopPanel)
local WeaponIcon = require(script.Parent.WeaponIcon)

local BOX_SIZE = Vector2.new(720, 200)
local BOX_COLOR = Color3.fromRGB(30, 28, 42)
local ACCENT = Color3.fromRGB(250, 210, 120)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local CARD_COLOR = Color3.fromRGB(52, 48, 68)
local CONFIRM_COLOR = Color3.fromRGB(80, 190, 110)
local BACK_COLOR = Color3.fromRGB(80, 78, 96)
local CARD_SIZE = Vector2.new(150, 168) -- at most; cards narrow to fit CARDS_WIDTH
local CARD_GAP = 14
local CARDS_WIDTH = 940 -- the row of starter cards never gets wider than this

local chooseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StarterChoose") :: RemoteEvent

local player = Players.LocalPlayer

local Dialogue = {}

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

local function button(parent: Instance, text: string, color: Color3, size: Vector2): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.BackgroundColor3 = color
	b.Font = HudStyle.FONT
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	HudStyle.chunky(b, 10, 3)
	Instance.new("UIScale").Parent = b
	return b
end

local function hasPicked(): boolean
	local value = player:GetAttribute("Starter")
	return typeof(value) == "string" and value ~= ""
end

function Dialogue.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Dialogue"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = HudStyle.holder(gui, Vector2.new(0.5, 1))

	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -40)
	box.Size = UDim2.fromOffset(BOX_SIZE.X, BOX_SIZE.Y)
	box.BackgroundColor3 = BOX_COLOR
	box.BackgroundTransparency = 0.05
	box.Visible = false
	box.Parent = holder
	HudStyle.chunky(box, 20, 4)
	local rim = box:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = ACCENT
	end
	Instance.new("UIScale").Parent = box

	local nameLabel = label(box, "", 24, ACCENT)
	nameLabel.Position = UDim2.fromOffset(24, 14)
	nameLabel.Size = UDim2.fromOffset(400, 28)
	local titleLabel = label(box, "", 14, SOFT_TEXT)
	titleLabel.Position = UDim2.fromOffset(24, 40)
	titleLabel.Size = UDim2.fromOffset(400, 18)

	local textLabel = label(box, "", 19)
	textLabel.Position = UDim2.fromOffset(24, 66)
	textLabel.Size = UDim2.new(1, -48, 0, 90)
	textLabel.TextWrapped = true
	textLabel.TextYAlignment = Enum.TextYAlignment.Top

	local hint = label(box, "click to continue", 13, SOFT_TEXT)
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -20, 1, -12)
	hint.Size = UDim2.fromOffset(200, 16)
	hint.TextXAlignment = Enum.TextXAlignment.Right

	local advance = Instance.new("TextButton") -- the whole box continues the dialogue
	advance.Size = UDim2.fromScale(1, 1)
	advance.BackgroundTransparency = 1
	advance.Text = ""
	advance.ZIndex = 2
	advance.Parent = box

	local close = button(box, "X", Color3.fromRGB(200, 70, 70), Vector2.new(34, 34))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.ZIndex = 4

	-- The starter choice: a row of cards above the box, then a confirm row inside it.
	local cards = Instance.new("Frame")
	cards.AnchorPoint = Vector2.new(0.5, 1)
	cards.Position = UDim2.new(0.5, 0, 0, -16)
	cards.Size = UDim2.fromOffset(CARDS_WIDTH, CARD_SIZE.Y)
	cards.BackgroundTransparency = 1
	cards.Visible = false
	cards.Parent = box
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Horizontal
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Padding = UDim.new(0, CARD_GAP)
	cardLayout.Parent = cards

	local confirmRow = Instance.new("Frame")
	confirmRow.AnchorPoint = Vector2.new(1, 1)
	confirmRow.Position = UDim2.new(1, -20, 1, -16)
	confirmRow.Size = UDim2.fromOffset(300, 44)
	confirmRow.BackgroundTransparency = 1
	confirmRow.Visible = false
	confirmRow.ZIndex = 3
	confirmRow.Parent = box
	local confirmLayout = Instance.new("UIListLayout")
	confirmLayout.FillDirection = Enum.FillDirection.Horizontal
	confirmLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	confirmLayout.Padding = UDim.new(0, 10)
	confirmLayout.Parent = confirmRow
	local backButton = button(confirmRow, "Back", BACK_COLOR, Vector2.new(110, 44))
	backButton.LayoutOrder = 1
	local confirmButton = button(confirmRow, "Confirm", CONFIRM_COLOR, Vector2.new(150, 44))
	confirmButton.LayoutOrder = 2
	-- Above the box-wide "continue" button, so they get the click.
	backButton.ZIndex = 4
	confirmButton.ZIndex = 4

	-- State --------------------------------------------------------------------------------
	local current: NpcConfig.Npc? = nil
	local npcPosition: Vector3? = nil
	local lines: { string } = {}
	local lineIndex = 0
	local typing: thread? = nil
	local mode: "lines" | "choose" | "confirm" = "lines"
	local pending: Starter.Choice? = nil
	local distanceWatch: RBXScriptConnection? = nil

	local function stopTyping()
		if typing then
			task.cancel(typing)
			typing = nil
		end
		textLabel.MaxVisibleGraphemes = -1
	end

	local function say(text: string)
		stopTyping()
		textLabel.Text = text
		textLabel.MaxVisibleGraphemes = 0
		typing = task.spawn(function()
			local length = utf8.len(text) or #text
			local shown = 0
			while shown < length do
				shown = math.min(length, shown + math.max(1, math.floor(NpcConfig.TypeSpeed * task.wait())))
				textLabel.MaxVisibleGraphemes = shown
			end
			typing = nil
			textLabel.MaxVisibleGraphemes = -1
		end)
	end

	local function setOpen(open: boolean)
		if open == box.Visible then
			return
		end
		box.Visible = open
		if open then
			Panels.opened("Dialogue")
			HudStyle.pop(box, 0.9)
			distanceWatch = RunService.Heartbeat:Connect(function()
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if npcPosition and root and root:IsA("BasePart") and (root.Position - npcPosition).Magnitude > NpcConfig.CloseDistance then
					setOpen(false)
				end
			end)
		else
			stopTyping()
			cards.Visible = false
			confirmRow.Visible = false
			current = nil
			Panels.closed("Dialogue")
			if distanceWatch then
				distanceWatch:Disconnect()
				distanceWatch = nil
			end
		end
	end

	local function showChoices()
		mode = "choose"
		stopTyping()
		textLabel.Text = "Pick your starter weapon. It comes with its own armor set, and you can only choose once."
		hint.Visible = false
		confirmRow.Visible = false
		cards.Visible = true
		for _, child in cards:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local choices = Starter.choices()
		local cardWidth = math.min(CARD_SIZE.X, math.floor((CARDS_WIDTH - (#choices - 1) * CARD_GAP) / math.max(#choices, 1)))
		for order, choice in choices do
			local set = ArmorConfig.Sets[choice.ArmorSet]
			local card = Instance.new("TextButton")
			card.LayoutOrder = order
			card.Size = UDim2.fromOffset(cardWidth, CARD_SIZE.Y)
			card.BackgroundColor3 = CARD_COLOR
			card.Text = ""
			card.AutoButtonColor = true
			card.Parent = cards
			HudStyle.chunky(card, 16, 4)
			Instance.new("UIScale").Parent = card
			local iconFrame = Instance.new("Frame")
			iconFrame.Position = UDim2.fromOffset(15, 12)
			iconFrame.Size = UDim2.fromOffset(cardWidth - 30, 84)
			iconFrame.BackgroundTransparency = 1
			iconFrame.Parent = card
			WeaponIcon.show(WeaponIcon.viewport(iconFrame), choice.Weapon)
			local weaponName = label(card, choice.Weapon, 20)
			weaponName.Position = UDim2.fromOffset(0, 100)
			weaponName.Size = UDim2.new(1, 0, 0, 24)
			weaponName.TextXAlignment = Enum.TextXAlignment.Center
			local rarity = InventoryConfig.rarityById(set.Rarity)
			local armorName = label(card, `+ {set.Name} Armor`, 14, rarity.Color)
			armorName.Position = UDim2.fromOffset(0, 126)
			armorName.Size = UDim2.new(1, 0, 0, 18)
			armorName.TextXAlignment = Enum.TextXAlignment.Center
			card.Activated:Connect(function()
				HudStyle.pop(card, 0.9)
				pending = choice
				mode = "confirm"
				cards.Visible = false
				confirmRow.Visible = true
				local info = InventoryConfig.weapon(choice.Weapon)
				textLabel.Text = `Take the {choice.Weapon} and {set.Name} Armor? {if info then info.Description else ""} This choice is permanent.`
			end)
		end
	end

	-- Moves to the next line, or past the last one (the starter choice, or closing).
	local function nextLine()
		if mode ~= "lines" or not current then
			return
		end
		if typing then
			stopTyping() -- first click finishes the line
			return
		end
		lineIndex += 1
		if lineIndex <= #lines then
			say(lines[lineIndex])
			hint.Text = if lineIndex == #lines then "click to finish" else "click to continue"
		elseif current.Action == "StarterPick" and not hasPicked() then
			showChoices()
		elseif current.Action == "Shop" and npcPosition then
			local position = npcPosition
			local sellerId = current.Id
			setOpen(false)
			ShopPanel.open(position, sellerId)
		else
			setOpen(false)
		end
	end

	local function open(npc: NpcConfig.Npc, position: Vector3)
		current = npc
		npcPosition = position
		mode = "lines"
		pending = nil
		lines = if npc.ChosenLines and npc.Action == "StarterPick" and hasPicked() then npc.ChosenLines else npc.Lines
		lineIndex = 0
		nameLabel.Text = npc.Name
		titleLabel.Text = npc.Title
		hint.Visible = true
		cards.Visible = false
		confirmRow.Visible = false
		setOpen(true)
		nextLine()
	end

	advance.Activated:Connect(nextLine)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	backButton.Activated:Connect(function()
		showChoices()
	end)
	confirmButton.Activated:Connect(function()
		if mode ~= "confirm" or not pending then
			return
		end
		HudStyle.pop(confirmButton, 0.88)
		chooseRemote:FireServer(pending.Weapon)
		confirmRow.Visible = false
		mode = "lines"
		textLabel.Text = "..."
	end)
	-- Once the server confirms the pick, the guide says goodbye.
	player:GetAttributeChangedSignal("Starter"):Connect(function()
		if box.Visible and current and current.Action == "StarterPick" and hasPicked() then
			lines = current.ChosenLines or {}
			lineIndex = 0
			hint.Visible = true
			nextLine()
		end
	end)

	-- A "!" over the guide until you've picked your starter, so new players know where to go.
	task.spawn(function()
		local guide = NpcConfig.List[1]
		for _, npc in NpcConfig.List do
			if npc.Action == "StarterPick" then
				guide = npc
			end
		end
		local folder = workspace:WaitForChild("Townsfolk", 60)
		local model = folder and folder:WaitForChild(guide.Name, 60)
		local head = model and model:WaitForChild("Head", 10)
		if not (head and head:IsA("BasePart")) then
			return
		end
		local marker = Instance.new("BillboardGui")
		marker.Name = "StarterMarker"
		marker.Size = UDim2.fromOffset(46, 64)
		marker.StudsOffset = Vector3.new(0, 4, 0)
		marker.MaxDistance = 150
		marker.Adornee = head
		marker.ResetOnSpawn = false
		marker.Parent = gui.Parent -- straight into PlayerGui: a billboard inside a ScreenGui isn't drawn
		local mark = label(marker, "!", 44, ACCENT)
		mark.Size = UDim2.fromScale(1, 1)
		mark.TextScaled = true
		mark.TextXAlignment = Enum.TextXAlignment.Center
		local stroke = Instance.new("UIStroke")
		stroke.Color = HudStyle.OUTLINE
		stroke.Thickness = 3
		stroke.Parent = mark
		local function update()
			marker.Enabled = not hasPicked()
		end
		player:GetAttributeChangedSignal("Starter"):Connect(update)
		update()
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			if marker.Enabled then
				t += dt
				marker.StudsOffset = Vector3.new(0, 4 + math.sin(t * 3) * 0.3, 0)
			end
		end)
	end)

	Panels.register("Dialogue", function()
		setOpen(false)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local id = prompt:GetAttribute("NpcId")
		local npc = if typeof(id) == "string" then NpcConfig.get(id) else nil
		local root = prompt.Parent
		if npc and root and root:IsA("BasePart") then
			open(npc, root.Position)
		end
	end)
end

return Dialogue
