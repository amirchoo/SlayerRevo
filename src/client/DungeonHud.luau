--!strict
-- What a dungeon run shows (DungeonService, BossService over the DungeonEvent remote):
--   The boss bar: across the top while you're in a run and its boss is awake (BossState
--     Intro or Fight) within BAR_RANGE: name, title, health with a lagging trail, and ticks
--     where its phases change.
--   Banners: room names, "The way is open", phase changes, victory.
--   Telegraphs: red shapes on the floor that fill up until the blow lands (following the boss
--     while it's still aiming), the beam, the slam's dust ring, and being thrown by a hit.
-- Looks only; the server decides every hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local HudStyle = require(script.Parent.HudStyle)
local Push = require(script.Parent.Push)

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DungeonEvent") :: RemoteEvent

local BAR_RANGE = 220 -- studs from the boss
local BAR_WIDTH = 560
local TRAIL_DELAY = 0.4 -- seconds before the trail catches up with the health
local BANNER_TIME = 2.6
local TELEGRAPH_COLOR = Color3.fromRGB(255, 50, 40)
local BEAM_COLOR = Color3.fromRGB(255, 120, 40)
local KNOCKBACK_TIME = 0.3
local KNOCKBACK_LIFT = 22 -- studs/s up, so the throw leaves the ground

local DungeonHud = {}

local effects = Instance.new("Folder")
effects.Name = "BossEffects"

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

local function effectPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = effects
	return part
end

local function fadeOut(part: BasePart, time: number)
	TweenService:Create(part, TweenInfo.new(time), { Transparency = 1 }):Play()
	task.delay(time, part.Destroy, part)
end

-- Boss bar -----------------------------------------------------------------------------------

type Bar = { gui: ScreenGui, name: TextLabel, title: TextLabel, fill: Frame, trail: Frame, ticks: Frame, boss: Model? }

local function makeBar(): Bar
	local gui = Instance.new("ScreenGui")
	gui.Name = "BossBar"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 24)
	holder.Size = UDim2.fromOffset(BAR_WIDTH, 64)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(BAR_WIDTH, 64)
	constraint.Parent = holder
	holder.Size = UDim2.new(0.8, 0, 0, 64)

	local name = HudStyle.caption(holder, "", 26)
	name.Size = UDim2.new(1, 0, 0, 28)
	name.TextXAlignment = Enum.TextXAlignment.Left

	local title = HudStyle.caption(holder, "", 15)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Right
	title.TextColor3 = Color3.fromRGB(230, 200, 170)

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 32)
	back.Size = UDim2.new(1, 0, 0, 22)
	back.BackgroundColor3 = HudStyle.EMPTY
	back.ClipsDescendants = false
	back.Parent = holder
	HudStyle.chunky(back, 8)

	local inner = Instance.new("Frame")
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.ClipsDescendants = true
	inner.Parent = back
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 8)
	innerCorner.Parent = inner

	local trail = Instance.new("Frame")
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = Color3.fromRGB(255, 235, 200)
	trail.BorderSizePixel = 0
	trail.Parent = inner

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(205, 45, 40)
	fill.BorderSizePixel = 0
	fill.Parent = inner
	HudStyle.gloss(fill)

	local ticks = Instance.new("Frame")
	ticks.Size = UDim2.fromScale(1, 1)
	ticks.BackgroundTransparency = 1
	ticks.Parent = back

	return { gui = gui, name = name, title = title, fill = fill, trail = trail, ticks = ticks, boss = nil }
end

local function showBoss(bar: Bar, boss: Model)
	bar.boss = boss
	local id = boss:GetAttribute("BossId")
	local config = if typeof(id) == "string" then BossConfig[id] :: BossConfig.Boss? else nil
	bar.name.Text = if config then config.DisplayName else boss.Name
	bar.title.Text = if config then `{config.Title} · Lv {config.Level}` else ""
	bar.ticks:ClearAllChildren()
	if config then
		for index = 2, #config.Phases do
			local tick = Instance.new("Frame")
			tick.AnchorPoint = Vector2.new(0.5, 0)
			tick.Position = UDim2.fromScale(config.Phases[index].HealthBelow, 0)
			tick.Size = UDim2.new(0, 3, 1, 0)
			tick.BackgroundColor3 = HudStyle.OUTLINE
			tick.BorderSizePixel = 0
			tick.Parent = bar.ticks
		end
	end
end

-- The boss to show: awake, in this run's space and near enough.
local function activeBoss(): Model?
	if typeof(player:GetAttribute("Dungeon")) ~= "string" then
		return nil
	end
	local me = rootOf(player.Character)
	local enemies = workspace:FindFirstChild("Enemies")
	if not me or not enemies then
		return nil
	end
	for _, model in enemies:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Boss") then
			local state = model:GetAttribute("BossState")
			local root = rootOf(model)
			if (state == "Intro" or state == "Fight" or state == "Dead") and root and (root.Position - me.Position).Magnitude <= BAR_RANGE then
				return model
			end
		end
	end
	return nil
end

local function updateBar(bar: Bar)
	local boss = activeBoss()
	if boss ~= bar.boss then
		if boss then
			showBoss(bar, boss)
		end
		bar.boss = boss
	end
	bar.gui.Enabled = boss ~= nil and boss:GetAttribute("BossState") ~= "Dead"
	if not boss then
		return
	end
	local health, maxHealth = boss:GetAttribute("Health"), boss:GetAttribute("MaxHealth")
	if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end
	local fraction = math.clamp(health / maxHealth, 0, 1)
	if math.abs(bar.fill.Size.X.Scale - fraction) > 1e-4 then
		bar.fill.Size = UDim2.fromScale(fraction, 1)
		if fraction > bar.trail.Size.X.Scale then
			bar.trail.Size = UDim2.fromScale(fraction, 1) -- healed: no trail
		else
			local target = fraction
			task.delay(TRAIL_DELAY, function()
				if math.abs(bar.fill.Size.X.Scale - target) < 1e-4 then
					TweenService:Create(bar.trail, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(target, 1) }):Play()
				end
			end)
		end
	end
end

-- Banners ------------------------------------------------------------------------------------

local bannerLabel: TextLabel
local bannerShow = 0

local function makeBanner()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DungeonBanner"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	bannerLabel = HudStyle.caption(gui, "", 40)
	bannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerLabel.Position = UDim2.fromScale(0.5, 0.3)
	bannerLabel.Size = UDim2.fromOffset(700, 60)
	bannerLabel.TextTransparency = 1
	bannerLabel.TextColor3 = Color3.fromRGB(255, 200, 150)
end

local function banner(text: string, small: boolean?)
	bannerShow += 1
	local show = bannerShow
	bannerLabel.Text = text
	bannerLabel.TextSize = if small then 28 else 44
	local stroke = bannerLabel:FindFirstChildOfClass("UIStroke")
	bannerLabel.TextTransparency = 1
	TweenService:Create(bannerLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	if stroke then
		stroke.Transparency = 0
	end
	task.delay(BANNER_TIME, function()
		if show == bannerShow then
			TweenService:Create(bannerLabel, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
	end)
end

-- Telegraphs and blows -----------------------------------------------------------------------

-- Where a shape sits on the floor in front of the boss: its frame (centre, facing the boss's
-- front) and its outline size.
local function shapeFrame(root: BasePart, shape: BossConfig.Shape, floorY: number): (CFrame, Vector3)
	local look = flatLook(root)
	local base = Vector3.new(root.Position.X, floorY + 0.15, root.Position.Z)
	if shape.Kind == "Line" then
		local length = shape.Length or 0
		return CFrame.lookAt(base + look * length / 2, base + look * length), Vector3.new(shape.Width or 0, 0.1, length)
	end
	local radius = shape.Radius or 0
	local center = base + look * (shape.Forward or 0)
	return CFrame.lookAt(center, center + look), Vector3.new(radius * 2, 0.1, radius * 2)
end

local function telegraph(data: { [string]: any })
	local boss = data.boss :: Model?
	local shape = data.shape :: BossConfig.Shape
	local floorY, duration, aim = data.floorY :: number, data.duration :: number, data.aim :: number
	local root = rootOf(boss)
	if not root or shape.Kind == "Cone" then
		return
	end
	local round = shape.Kind == "Circle"
	local function make(size: Vector3, transparency: number): BasePart
		if round then
			return effectPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, size.X, size.Z), Color = TELEGRAPH_COLOR, Transparency = transparency })
		end
		return effectPart({ Size = size, Color = TELEGRAPH_COLOR, Transparency = transparency })
	end
	local frame, size = shapeFrame(root, shape, floorY)
	local outline = make(size, 0.75)
	local fill = make(size * Vector3.new(0, 1, 0) + Vector3.new(0.1, 0.1, 0.1), 0.5)
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function()
		local t = os.clock() - start
		if t < aim and root.Parent then
			frame = shapeFrame(root, shape, floorY)
		end
		local f = math.clamp(t / math.max(duration, 0.05), 0, 1)
		local orient = if round then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity
		outline.CFrame = frame * orient
		if round then
			fill.Size = Vector3.new(0.12, math.max(size.X * f, 0.1), math.max(size.Z * f, 0.1))
			fill.CFrame = frame * orient
		else
			-- A line fills from the boss outward.
			local length = size.Z * f
			fill.Size = Vector3.new(size.X, 0.12, math.max(length, 0.1))
			fill.CFrame = frame * CFrame.new(0, 0, size.Z / 2 - length / 2)
		end
		if t >= duration then
			connection:Disconnect()
			outline.Transparency = 0.2
			fill.Transparency = 0.2
			fadeOut(outline, 0.3)
			fadeOut(fill, 0.3)
		end
	end)
end

local function beam(data: { [string]: any })
	local boss = data.boss :: Model?
	local root = rootOf(boss)
	if not boss or not root then
		return
	end
	local length, width, duration = data.length :: number, data.width :: number, data.duration :: number
	local mouth: Bone? = nil
	for _, name in { "Jaw", "Head" } do
		local found = boss:FindFirstChild(name, true)
		if found and found:IsA("Bone") then
			mouth = found
			break
		end
	end
	local core = effectPart({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 230, 160), Transparency = 0.1 })
	local glow = effectPart({ Shape = Enum.PartType.Cylinder, Color = BEAM_COLOR, Transparency = 0.45 })
	local light = Instance.new("PointLight")
	light.Color = BEAM_COLOR
	light.Range = 40
	light.Brightness = 4
	light.Parent = glow
	Sounds.play("StaffBlast", root, 0.55)
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function()
		local t = os.clock() - start
		if t >= duration or not root.Parent then
			connection:Disconnect()
			fadeOut(core, 0.25)
			fadeOut(glow, 0.25)
			return
		end
		local from = if mouth then mouth.WorldPosition else root.Position + Vector3.new(0, 6, 0)
		local floor = root.Position.Y - (root.Size.Y / 2) - (boss:FindFirstChildOfClass("Humanoid") :: Humanoid).HipHeight
		local to = Vector3.new(root.Position.X, floor + 1.5, root.Position.Z) + flatLook(root) * length
		local span = (to - from).Magnitude
		local frame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.pi / 2, 0)
		local pulse = 1 + math.sin(t * 40) * 0.08
		core.Size = Vector3.new(span, width * 0.35 * pulse, width * 0.35 * pulse)
		glow.Size = Vector3.new(span, width * pulse, width * pulse)
		core.CFrame = frame
		glow.CFrame = frame
	end)
end

local function slam(data: { [string]: any })
	local position, radius = data.position :: Vector3, data.radius :: number
	local ring = effectPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4, 4), CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(150, 130, 110), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(0.3, radius * 2.6, radius * 2.6), Transparency = 1 }):Play()
	task.delay(0.5, ring.Destroy, ring)
	local anchor = effectPart({ Size = Vector3.one, CFrame = CFrame.new(position), Transparency = 1 })
	Sounds.play("GreatswordSlam", anchor, 0.6)
	task.delay(3, anchor.Destroy, anchor)
	-- A jolt for anyone close.
	local me = rootOf(player.Character)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if me and humanoid and (me.Position - position).Magnitude < radius * 3 then
		local random = Random.new()
		local started = os.clock()
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			local left = 1 - (os.clock() - started) / 0.35
			if left <= 0 then
				connection:Disconnect()
				humanoid.CameraOffset = Vector3.zero
				return
			end
			local s = 0.6 * left
			humanoid.CameraOffset = Vector3.new(random:NextNumber(-s, s), random:NextNumber(-s, s), 0)
		end)
	end
end

local function knockback(data: { [string]: any })
	local root = rootOf(player.Character)
	local direction, speed = data.direction, data.speed
	if not root or typeof(direction) ~= "Vector3" or typeof(speed) ~= "number" then
		return
	end
	Push.apply(root, direction, speed, KNOCKBACK_TIME)
	root.AssemblyLinearVelocity += Vector3.new(0, KNOCKBACK_LIFT, 0)
end

function DungeonHud.start()
	effects.Parent = workspace
	local bar = makeBar()
	makeBanner()
	RunService.Heartbeat:Connect(function()
		updateBar(bar)
	end)

	remote.OnClientEvent:Connect(function(kind: string, data: { [string]: any })
		if kind == "Banner" then
			banner(data.text, data.small)
		elseif kind == "Telegraph" then
			telegraph(data)
		elseif kind == "Beam" then
			beam(data)
		elseif kind == "Slam" then
			slam(data)
		elseif kind == "Knockback" then
			knockback(data)
		end
	end)
end

return DungeonHud
