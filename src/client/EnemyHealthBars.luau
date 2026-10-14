--!strict
-- A small health bar over enemies (workspace.Enemies) and wild animals (workspace.Animals);
-- nothing inside the town (the safe zone) gets one. So a pack doesn't turn into a stack of
-- bars, only a few show at once: the one you're locked on to (with its name, level and health
-- numbers), plus up to MAX_OTHERS more, bar only, picked from the nearest that are hurt or (for
-- enemies, not animals) close to you.
-- Display only: reads the Health/MaxHealth attributes the server sets. The bar keeps a constant size on screen;
-- when the enemy takes damage the lost chunk shows pale for a moment, then drains away, so
-- each hit's size is easy to read. Hidden beyond MAX_DISTANCE; fades out on death. The name
-- starts with the enemy's level ("Level" attribute), colored by how it compares to yours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local LockOn = require(script.Parent.LockOn)

local BAR_WIDTH = 110
local BAR_HEIGHT = 8
local NAME_HEIGHT = 16
local MAX_DISTANCE = 80 -- studs
local ABOVE_HEAD = 1.2 -- studs above the top of the model
local MAX_OTHERS = 3 -- bars shown besides the locked target's
local NEAR = 30 -- studs: an unhurt enemy this close to you shows its bar
local PICK_INTERVAL = 0.2 -- seconds between choosing which bars show

local FILL_TOP = Color3.fromRGB(235, 70, 60)
local FILL_BOTTOM = Color3.fromRGB(160, 30, 30)
local TRAIL_COLOR = Color3.fromRGB(255, 225, 190)
local BACKGROUND = Color3.fromRGB(25, 20, 22)

local FILL_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_DELAY = 0.35 -- seconds the lost chunk stays before draining
local TRAIL_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_TWEEN = TweenInfo.new(0.6)

local LEVEL_HARDER = "#FF6450" -- 3+ levels above you
local LEVEL_EVEN = "#FFD25A" -- within 2 levels
local LEVEL_EASIER = "#B4B4BE" -- 3+ levels below

local player = Players.LocalPlayer

local EnemyHealthBars = {}

type Bar = { enemy: Model, root: BasePart, gui: BillboardGui, name: TextLabel, amount: TextLabel, animal: boolean, hurt: boolean, dyingSince: number? }
local bars: { [Model]: Bar } = {}

-- "Lv 8  Lesser Demon", the level colored by how it compares to the player's.
local function nameText(enemy: Model, displayName: string): string
	local level = enemy:GetAttribute("Level")
	if typeof(level) ~= "number" then
		return displayName
	end
	local mine = player:GetAttribute("Level")
	local gap = level - (if typeof(mine) == "number" then mine else 1)
	local color = if gap >= 3 then LEVEL_HARDER elseif gap <= -3 then LEVEL_EASIER else LEVEL_EVEN
	return `<font color="{color}">Lv {level}</font>  {displayName}`
end

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

local function attach(enemy: Model)
	local root = enemy:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or not enemy.Parent then
		return
	end
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")

	-- Above the top of the model, whatever its size.
	local boxCFrame, boxSize = enemy:GetBoundingBox()
	local top = boxCFrame.Position.Y + boxSize.Y / 2 - root.Position.Y

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(BAR_WIDTH + 8, NAME_HEIGHT + BAR_HEIGHT + 8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, top + ABOVE_HEAD, 0)
	gui.MaxDistance = MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Parent = root

	local group = Instance.new("CanvasGroup") -- fades everything together on death
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 13
	name.TextColor3 = Color3.fromRGB(255, 240, 225)
	name.TextStrokeTransparency = 0.35
	name.RichText = true
	local displayName = if humanoid and humanoid.DisplayName ~= "" then humanoid.DisplayName else enemy.Name
	local function refreshName()
		name.Text = nameText(enemy, displayName)
	end
	refreshName()
	enemy:GetAttributeChangedSignal("Level"):Connect(refreshName)
	local levelChanged = player:GetAttributeChangedSignal("Level"):Connect(refreshName)
	enemy.Destroying:Connect(function()
		levelChanged:Disconnect()
	end)
	name.Parent = group

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, NAME_HEIGHT + 1)
	bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	bar.BackgroundColor3 = BACKGROUND
	bar.BackgroundTransparency = 0.15
	bar.ClipsDescendants = true
	bar.Parent = group
	corner(bar, 3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.Parent = bar

	local trail = Instance.new("Frame")
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = TRAIL_COLOR
	trail.BorderSizePixel = 0
	trail.Parent = bar
	corner(trail, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = bar
	corner(fill, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(FILL_TOP, FILL_BOTTOM)
	gradient.Parent = fill

	local amount = Instance.new("TextLabel")
	amount.Size = UDim2.fromScale(1, 1)
	amount.BackgroundTransparency = 1
	amount.Font = Enum.Font.GothamBold
	amount.TextSize = 11
	amount.TextColor3 = Color3.new(1, 1, 1)
	amount.TextStrokeTransparency = 0.4
	amount.ZIndex = 3
	-- The numbers sit just under the bar (it's too thin to hold them).
	amount.AnchorPoint = Vector2.new(0.5, 0)
	amount.Position = UDim2.new(0.5, 0, 0, NAME_HEIGHT + BAR_HEIGHT + 2)
	amount.Size = UDim2.fromOffset(BAR_WIDTH, 12)
	amount.Parent = group
	gui.Size = UDim2.fromOffset(BAR_WIDTH + 8, NAME_HEIGHT + BAR_HEIGHT + 16)
	gui.Enabled = false -- the picker below decides

	local record: Bar = { enemy = enemy, root = root, gui = gui, name = name, amount = amount, animal = enemy:GetAttribute("Animal") ~= nil, hurt = false, dyingSince = nil }
	bars[enemy] = record
	enemy.Destroying:Connect(function()
		bars[enemy] = nil
	end)
	enemy.AncestryChanged:Connect(function()
		if not enemy:IsDescendantOf(workspace) then
			bars[enemy] = nil
		end
	end)

	local lastRatio = 1
	local trailToken = 0
	local function update()
		local health = enemy:GetAttribute("Health")
		local maxHealth = enemy:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			return
		end
		local ratio = math.clamp(health / maxHealth, 0, 1)
		record.hurt = ratio < 1
		amount.Text = `{math.ceil(math.max(health, 0))} / {math.ceil(maxHealth)}`
		TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
		if ratio < lastRatio then
			-- Took damage: the pale chunk lingers, then drains down to the new health.
			trailToken += 1
			local token = trailToken
			task.delay(TRAIL_DELAY, function()
				if token == trailToken then
					TweenService:Create(trail, TRAIL_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
				end
			end)
		else
			trail.Size = UDim2.fromScale(ratio, 1) -- healed or respawned: no trail
		end
		lastRatio = ratio
		if health <= 0 then
			record.dyingSince = record.dyingSince or os.clock()
			TweenService:Create(group, FADE_TWEEN, { GroupTransparency = 1 }):Play()
		end
	end

	enemy:GetAttributeChangedSignal("Health"):Connect(update)
	enemy:GetAttributeChangedSignal("MaxHealth"):Connect(update)
	update()
end

local function watch(folderName: string)
	local folder = workspace:WaitForChild(folderName)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(attach, child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(attach, child)
		end
	end
end

-- Chooses which bars show: the locked target's in full, then the nearest few others that are
-- hurt or close, bar only. None in town, and none past MAX_DISTANCE.
local function pick()
	local character = player.Character
	local me = character and character:FindFirstChild("HumanoidRootPart")
	local here = if me and me:IsA("BasePart") then me.Position else nil
	local locked = LockOn.target()
	local candidates: { { bar: Bar, distance: number } } = {}
	for enemy, bar in bars do
		local distance = if here then (bar.root.Position - here).Magnitude else math.huge
		local dying = bar.dyingSince ~= nil and os.clock() - bar.dyingSince < FADE_TWEEN.Time
		local alive = bar.dyingSince == nil
		local hasHealth = enemy:GetAttribute("MaxHealth") ~= nil -- tame town animals have none
		local allowed = hasHealth and distance <= MAX_DISTANCE and not SafeZone.contains(bar.root.Position)
		local full = allowed and enemy == locked and (alive or dying)
		bar.name.Visible = full
		bar.amount.Visible = full
		bar.gui.Enabled = full or (dying and bar.gui.Enabled)
		if allowed and alive and not full and (bar.hurt or (distance <= NEAR and not bar.animal)) then
			table.insert(candidates, { bar = bar, distance = distance })
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(MAX_OTHERS, #candidates) do
		candidates[index].bar.gui.Enabled = true
	end
end

function EnemyHealthBars.start()
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= PICK_INTERVAL then
			since = 0
			pick()
		end
	end)
	task.spawn(watch, "Animals")
	watch("Enemies")
end

return EnemyHealthBars
