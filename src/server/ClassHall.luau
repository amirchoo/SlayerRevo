--!strict
-- The Hall of Oaths, where new players pick their starter class (client Intro): a round
-- stone temple floating high above the southern forest (IntroConfig.Hall), with a statue per
-- starter choice in a ring, facing in. Each statue is a Training Grounds stand mannequin
-- (wearing the set, holding the weapon, in the weapon's idle) on a pedestal, between two pillars, under a
-- lintel, before a banner in its armor's colors. Look only: nothing here can be used.
-- Each alcove is its own Model streamed atomically, so a statue never arrives half-built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorConfig = require(ReplicatedStorage.Shared.Config.ArmorConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local IntroConfig = require(ReplicatedStorage.Shared.Config.IntroConfig)
local Starter = require(ReplicatedStorage.Shared.Starter)
local TrainingStands = require(script.Parent.TrainingStands)

local STONE = Color3.fromRGB(214, 196, 160)
local STONE_DARK = Color3.fromRGB(150, 132, 104)
local GOLD = Color3.fromRGB(200, 160, 85)
local FLOOR_MARGIN = 14 -- floor beyond the statues' ring
local PILLAR_HEIGHT = 17
local PILLAR_GAP = 5 -- each pillar this far to a statue's side
local LIGHT_COLOR = Color3.fromRGB(255, 205, 150)

local ClassHall = {}

-- Weapon `name`'s idle animation (CombatConfig), if it has one.
local function idleOf(name: string): string?
	local function search(list: any): string?
		for _, entry in list do
			if typeof(entry) == "table" and entry.ToolName == name and typeof(entry.IdleAnimation) == "string" and entry.IdleAnimation ~= "" then
				return entry.IdleAnimation
			end
		end
		return nil
	end
	return search(CombatConfig) or search(CombatConfig.Casters)
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A flat disc (a cylinder standing upright) `height` tall, its top at `top`.
local function disc(parent: Instance, name: string, diameter: number, height: number, top: Vector3, color: Color3, material: Enum.Material): Part
	local cframe = CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return part(parent, name, Vector3.new(height, diameter, diameter), cframe, color, material, Enum.PartType.Cylinder)
end

local function buildFloor(hall: Model)
	local center = IntroConfig.Hall.Center
	local diameter = (IntroConfig.Hall.Radius + FLOOR_MARGIN) * 2
	disc(hall, "Floor", diameter, 4, center, STONE, Enum.Material.Marble)
	disc(hall, "Step", diameter + 10, 3, center - Vector3.new(0, 1.6, 0), STONE_DARK, Enum.Material.Slate)
	disc(hall, "Underside", diameter - 12, 10, center - Vector3.new(0, 4, 0), STONE_DARK, Enum.Material.Rock)
	-- A gold-ringed inlay in the middle, where the camera stands.
	disc(hall, "InlayRing", 26, 0.2, center + Vector3.new(0, 0.1, 0), GOLD, Enum.Material.Metal)
	disc(hall, "Inlay", 24, 0.24, center + Vector3.new(0, 0.12, 0), STONE_DARK, Enum.Material.Slate)
	disc(hall, "InlayHeart", 6, 0.28, center + Vector3.new(0, 0.14, 0), GOLD, Enum.Material.Metal)
end

local function buildAlcove(hall: Model, index: number, count: number, choice: Starter.Choice)
	local set = ArmorConfig.Sets[choice.ArmorSet]
	local feet = Starter.statueFeet(index, count)
	local alcove = Instance.new("Model")
	alcove.Name = choice.Weapon
	alcove.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Feet face the middle; "behind" the statue is +Z in its own space.
	local ground = feet * CFrame.new(0, -IntroConfig.Hall.PedestalHeight, 0)
	disc(alcove, "Pedestal", 7, IntroConfig.Hall.PedestalHeight, feet.Position, STONE_DARK, Enum.Material.Slate)
	disc(alcove, "PedestalTrim", 7.6, 0.3, ground.Position + Vector3.new(0, 0.3, 0), GOLD, Enum.Material.Metal)

	for _, side in { -1, 1 } do
		local base = ground * CFrame.new(side * PILLAR_GAP, 0, 2.5)
		part(alcove, "PillarBase", Vector3.new(3.4, 1, 3.4), base * CFrame.new(0, 0.5, 0), STONE_DARK, Enum.Material.Slate)
		part(alcove, "Pillar", Vector3.new(PILLAR_HEIGHT, 2.4, 2.4), base * CFrame.new(0, 1 + PILLAR_HEIGHT / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Marble, Enum.PartType.Cylinder)
		part(alcove, "Capital", Vector3.new(3.4, 1, 3.4), base * CFrame.new(0, 1.5 + PILLAR_HEIGHT, 0), STONE_DARK, Enum.Material.Slate)
	end
	local lintel = part(alcove, "Lintel", Vector3.new(PILLAR_GAP * 2 + 4, 1.6, 3.6), ground * CFrame.new(0, 2.8 + PILLAR_HEIGHT, 2.5), STONE, Enum.Material.Marble)
	part(alcove, "LintelTrim", Vector3.new(PILLAR_GAP * 2 + 4.2, 0.3, 3.8), lintel.CFrame * CFrame.new(0, -0.9, 0), GOLD, Enum.Material.Metal)

	-- A banner in the armor's colors behind the statue, with a trim stripe down the middle.
	local banner = part(alcove, "Banner", Vector3.new(5, 12, 0.2), ground * CFrame.new(0, 12, 3.6), set.Color, Enum.Material.Fabric)
	banner.CanCollide = false
	local stripe = part(alcove, "BannerStripe", Vector3.new(1, 12, 0.22), banner.CFrame, set.TrimColor, Enum.Material.Fabric)
	stripe.CanCollide = false

	-- Warm light from above the statue, and a soft glow on its face from the front.
	local top = Instance.new("SpotLight")
	top.Face = Enum.NormalId.Bottom
	top.Angle = 70
	top.Range = 22
	top.Brightness = 3
	top.Color = LIGHT_COLOR
	top.Parent = lintel
	local glow = Instance.new("Attachment")
	glow.CFrame = lintel.CFrame:ToObjectSpace(feet * CFrame.new(0, 5, -4))
	glow.Parent = lintel
	local fill = Instance.new("PointLight")
	fill.Range = 10
	fill.Brightness = 0.8
	fill.Color = LIGHT_COLOR
	fill.Parent = glow

	alcove.Parent = hall
	local statue = TrainingStands.mannequin(feet, choice.ArmorSet)
	if statue then
		statue.Name = "Statue"
		-- Stood at ease in the weapon's idle (looping) rather than the stand's guard or
		-- wind-up, where bulky armor pieces collide as the arms cross.
		local idle = idleOf(choice.Weapon)
		if idle then
			statue:SetAttribute("PoseAnimation", idle)
			statue:SetAttribute("PoseLoop", true)
		end
		statue.Parent = alcove
	else
		warn(`ClassHall: no stand shows the {choice.ArmorSet} set, so its statue is missing`)
	end
end

-- Builds the hall (making the statues yields, so call it with task.spawn).
function ClassHall.build()
	local hall = Instance.new("Model")
	hall.Name = "HallOfOaths"
	buildFloor(hall)
	hall.Parent = workspace
	local choices = Starter.choices()
	for index, choice in choices do
		task.spawn(buildAlcove, hall, index, #choices, choice)
	end
end

return ClassHall
