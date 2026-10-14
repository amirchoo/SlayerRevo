--!strict
-- Names over heads, in the HUD's style (FredokaOne with a dark outline; see HudStyle), in
-- place of the ones Roblox draws:
--   * townsfolk (workspace.Townsfolk, NpcConfig): their name, and their title under it
--   * other players: their level and display name, and under it a small chunky health bar
--     like your own (green, red when low, with the pale chunk that drains after a hit),
--     shown only while they're hurt
-- Your own character gets none. Display only: reads the Health/MaxHealth attributes the
-- server sets and the player's "Level" attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local HudStyle = require(script.Parent.HudStyle)

local PLAYER_DISTANCE = 70 -- studs a player's nameplate shows from
local NPC_DISTANCE = 40
local ABOVE_HEAD = 2.3 -- studs above the head's middle
local PLATE_WIDTH = 200
local NAME_SIZE = 17
local TITLE_SIZE = 13
local BAR_WIDTH = 96
local BAR_HEIGHT = 10

local NAME_COLOR = Color3.fromRGB(255, 250, 240)
local NPC_NAME_COLOR = Color3.fromRGB(255, 226, 150)
local TITLE_COLOR = Color3.fromRGB(215, 210, 225)
local LEVEL_COLOR = "#FFD25A"
local HIGH_COLOR = Color3.fromRGB(90, 220, 90)
local LOW_COLOR = Color3.fromRGB(235, 65, 60)
local TRAIL_COLOR = Color3.fromRGB(255, 240, 220)
local LOW_THRESHOLD = 0.3
local FILL_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_DELAY = 0.4
local TRAIL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local player = Players.LocalPlayer

local Nameplates = {}

local playerGui: Instance

local function outlined(parent: Instance, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.TextColor3 = color
	label.RichText = true
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

local function plate(adornee: BasePart, name: string, height: number, distance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(PLATE_WIDTH, height)
	gui.StudsOffset = Vector3.new(0, ABOVE_HEAD, 0)
	gui.MaxDistance = distance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = playerGui -- billboards are drawn from here, and these survive respawns
	return gui
end

local function hideDefault(humanoid: Humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
end

-- Townsfolk -----------------------------------------------------------------------------------

local function attachNpc(model: Model)
	local npc: NpcConfig.Npc? = nil
	for _, entry in NpcConfig.List do
		if entry.Name == model.Name then
			npc = entry
		end
	end
	local head = model:WaitForChild("Head", 10)
	if not npc or not head or not head:IsA("BasePart") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hideDefault(humanoid)
	end
	local gui = plate(head, `Npc_{npc.Id}`, NAME_SIZE + TITLE_SIZE + 8, NPC_DISTANCE)
	local name = outlined(gui, NAME_SIZE, NPC_NAME_COLOR)
	name.Size = UDim2.new(1, 0, 0, NAME_SIZE + 2)
	name.Text = npc.Name
	local title = outlined(gui, TITLE_SIZE, TITLE_COLOR)
	title.Position = UDim2.fromOffset(0, NAME_SIZE + 4)
	title.Size = UDim2.new(1, 0, 0, TITLE_SIZE + 2)
	title.Text = npc.Title
	model.Destroying:Connect(function()
		gui:Destroy()
	end)
end

-- Players -----------------------------------------------------------------------------------

local function attachCharacter(other: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not head or not head:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid") or other.Character ~= character then
		return
	end
	hideDefault(humanoid)

	local gui = plate(head, `Player_{other.UserId}`, NAME_SIZE + BAR_HEIGHT + 12, PLAYER_DISTANCE)
	local name = outlined(gui, NAME_SIZE, NAME_COLOR)
	name.Size = UDim2.new(1, 0, 0, NAME_SIZE + 2)
	local function refreshName()
		local level = other:GetAttribute("Level")
		local prefix = if typeof(level) == "number" then `<font color="{LEVEL_COLOR}">Lv {level}</font>  ` else ""
		name.Text = prefix .. other.DisplayName
	end
	refreshName()
	local connections = { other:GetAttributeChangedSignal("Level"):Connect(refreshName) }

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, NAME_SIZE + 6)
	bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	bar.BackgroundColor3 = HudStyle.EMPTY
	bar.Visible = false
	bar.Parent = gui
	HudStyle.chunky(bar, 5, 2)
	local trail = Instance.new("Frame")
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = TRAIL_COLOR
	trail.Parent = bar
	local trailCorner = Instance.new("UICorner")
	trailCorner.CornerRadius = UDim.new(0, 4)
	trailCorner.Parent = trail
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HIGH_COLOR
	fill.ZIndex = 2
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill
	HudStyle.gloss(fill)

	local lastRatio = 1
	local trailToken = 0
	local function update()
		local health = character:GetAttribute("Health")
		local maxHealth = character:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			return
		end
		local ratio = math.clamp(health / maxHealth, 0, 1)
		bar.Visible = ratio < 1
		fill.BackgroundColor3 = if ratio <= LOW_THRESHOLD then LOW_COLOR else HIGH_COLOR
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		if ratio < lastRatio then
			trailToken += 1
			local token = trailToken
			task.delay(TRAIL_DELAY, function()
				if token == trailToken then
					TweenService:Create(trail, TRAIL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
				end
			end)
		else
			trail.Size = UDim2.fromScale(ratio, 1)
		end
		lastRatio = ratio
	end
	table.insert(connections, character:GetAttributeChangedSignal("Health"):Connect(update))
	table.insert(connections, character:GetAttributeChangedSignal("MaxHealth"):Connect(update))
	update()

	local function remove()
		for _, connection in connections do
			connection:Disconnect()
		end
		gui:Destroy()
	end
	character.Destroying:Connect(remove)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			remove()
		end
	end)
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character)
		attachCharacter(other, character)
	end)
	if other.Character then
		task.spawn(attachCharacter, other, other.Character)
	end
end

function Nameplates.start()
	playerGui = player:WaitForChild("PlayerGui")

	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end

	task.spawn(function()
		local townsfolk = workspace:WaitForChild("Townsfolk")
		townsfolk.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.spawn(attachNpc, child)
			end
		end)
		for _, child in townsfolk:GetChildren() do
			if child:IsA("Model") then
				task.spawn(attachNpc, child)
			end
		end
	end)
end

return Nameplates
