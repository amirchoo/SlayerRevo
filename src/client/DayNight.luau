--!strict
-- Day and night on this screen (LightingConfig.DayCycle; the time comes from shared DayCycle,
-- so everyone sees the same sky). Turns the clock, shifts the light toward a moonlit blue at
-- night (with a cooler, punchier grade, a blue fog, crisper shadows and shinier surfaces), and lights the
-- town after dark: lamp and lantern lights in workspace.Town switch on (the nearest few, by
-- LightBudget; lights by a fire, like the campfire, stay on), and windows glow. Looks only.
-- The intro holds the clock at its own time while it plays (DayNight.hold). In a dungeon run
-- (the "Dungeon" attribute) the light and effects switch to LightingConfig.Dungeon instead.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local LightingConfig = require(ReplicatedStorage.Shared.Config.LightingConfig)
local LightBudget = require(script.Parent.LightBudget)

local CYCLE = LightingConfig.DayCycle
local DAY = LightingConfig.Lighting
local NIGHT = CYCLE.Night
local UPDATE_INTERVAL = 0.1 -- seconds between lighting updates
local WINDOW_NAMES = { Windows = true, Window = true } -- House_1/Blacksmith models; part-built houses

local DUNGEON = LightingConfig.Dungeon
-- The effects in Lighting (LightingSetup makes one of each), by class and their LightingConfig key
-- (also their name: there are other ColorCorrectionEffects, like LowHealthGrade).
local EFFECTS = { Atmosphere = "Atmosphere", BloomEffect = "Bloom", ColorCorrectionEffect = "ColorCorrection", SunRaysEffect = "SunRays" }

local player = Players.LocalPlayer

local DayNight = {}

local inDungeon = false

local function set(instance: Instance, properties: { [string]: any })
	for key, value in properties do
		(instance :: any)[key] = value
	end
end

-- Puts the effects (and the environment light) to the dungeon's look, or back to the world's.
local function setDungeonLook(on: boolean)
	inDungeon = on
	for className, key in EFFECTS do
		local named = Lighting:FindFirstChild(key)
		local effect = if named and named:IsA(className) then named else nil
		local look = if on then (DUNGEON :: any)[key] else (LightingConfig :: any)[key]
		if effect and look then
			set(effect, look)
		end
	end
	local world = LightingConfig.Lighting
	Lighting.EnvironmentDiffuseScale = if on then DUNGEON.Lighting.EnvironmentDiffuseScale else world.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = if on then DUNGEON.Lighting.EnvironmentSpecularScale else world.EnvironmentSpecularScale
end

local heldClock: number? = nil
local nightLights: { [Light]: boolean } = {} -- under LightBudget, wanted while lit
type Window = { part: BasePart, color: Color3, material: Enum.Material }
local windows: { [BasePart]: Window } = {}
local lit = false

-- Whether a light is a lamp (on only at night), not a fire's glow (always on).
local function isLamp(light: Light): boolean
	local parent = light.Parent
	return parent ~= nil and parent:FindFirstChildOfClass("Fire") == nil and parent.Name ~= "Coals"
end

local function setWindow(window: Window, on: boolean)
	window.part.Material = if on then Enum.Material.Neon else window.material
	window.part.Color = if on then CYCLE.WindowGlow else window.color
end

local function watch(descendant: Instance)
	if descendant:IsA("Light") and isLamp(descendant) then
		nightLights[descendant] = true
		LightBudget.add(descendant, lit)
	elseif descendant:IsA("BasePart") and WINDOW_NAMES[descendant.Name] and not windows[descendant] then
		local window = { part = descendant, color = descendant.Color, material = descendant.Material }
		windows[descendant] = window
		if lit then
			setWindow(window, true)
		end
	end
end

local function unwatch(descendant: Instance)
	if descendant:IsA("Light") then
		if nightLights[descendant] then
			LightBudget.remove(descendant)
		end
		nightLights[descendant] = nil
	elseif descendant:IsA("BasePart") then
		windows[descendant] = nil
	end
end

local function setLit(on: boolean)
	lit = on
	for light in nightLights do
		LightBudget.setWanted(light, on)
	end
	for _, window in windows do
		setWindow(window, on)
	end
end

local function update()
	local clock = heldClock or DayCycle.clock()
	local night = DayCycle.night(clock)
	Lighting.ClockTime = clock
	local dungeon = typeof(player:GetAttribute("Dungeon")) == "string"
	if dungeon ~= inDungeon then
		setDungeonLook(dungeon)
	end
	if dungeon then
		local look = DUNGEON.Lighting
		Lighting.Brightness = look.Brightness
		Lighting.Ambient = look.Ambient
		Lighting.OutdoorAmbient = look.OutdoorAmbient
		Lighting.ColorShift_Top = look.ColorShift_Top
		Lighting.ExposureCompensation = look.ExposureCompensation
		return
	end
	Lighting.Brightness = DAY.Brightness + (NIGHT.Brightness - DAY.Brightness) * night
	Lighting.Ambient = DAY.Ambient:Lerp(NIGHT.Ambient, night)
	Lighting.OutdoorAmbient = DAY.OutdoorAmbient:Lerp(NIGHT.OutdoorAmbient, night)
	Lighting.ColorShift_Top = DAY.ColorShift_Top:Lerp(NIGHT.ColorShift_Top, night)
	Lighting.ExposureCompensation = DAY.ExposureCompensation + (NIGHT.ExposureCompensation - DAY.ExposureCompensation) * night
	Lighting.ShadowSoftness = DAY.ShadowSoftness + (NIGHT.ShadowSoftness - DAY.ShadowSoftness) * night
	Lighting.EnvironmentSpecularScale = DAY.EnvironmentSpecularScale + (NIGHT.EnvironmentSpecularScale - DAY.EnvironmentSpecularScale) * night
	local grade = Lighting:FindFirstChild("ColorCorrection")
	if grade and grade:IsA("ColorCorrectionEffect") then
		local dayGrade, nightGrade = LightingConfig.ColorCorrection, NIGHT.ColorCorrection
		grade.Saturation = dayGrade.Saturation + (nightGrade.Saturation - dayGrade.Saturation) * night
		grade.Contrast = dayGrade.Contrast + (nightGrade.Contrast - dayGrade.Contrast) * night
		grade.Brightness = dayGrade.Brightness + (nightGrade.Brightness - dayGrade.Brightness) * night
		grade.TintColor = dayGrade.TintColor:Lerp(nightGrade.TintColor, night)
	end
	local fog = Lighting:FindFirstChild("Atmosphere")
	if fog and fog:IsA("Atmosphere") then
		local dayFog, nightFog = LightingConfig.Atmosphere, NIGHT.Atmosphere
		fog.Density = dayFog.Density + (nightFog.Density - dayFog.Density) * night
		fog.Offset = dayFog.Offset + (nightFog.Offset - dayFog.Offset) * night
		fog.Haze = dayFog.Haze + (nightFog.Haze - dayFog.Haze) * night
		fog.Glare = dayFog.Glare + (nightFog.Glare - dayFog.Glare) * night
		fog.Color = dayFog.Color:Lerp(nightFog.Color, night)
		fog.Decay = dayFog.Decay:Lerp(nightFog.Decay, night)
	end
	local shouldLight = night >= CYCLE.LightsOn
	if shouldLight ~= lit then
		setLit(shouldLight)
	end
end

-- Holds the clock at `clock` (hours) until called again with nil.
function DayNight.hold(clock: number?)
	heldClock = clock
	update()
end

function DayNight.start()
	task.spawn(function()
		local town = workspace:WaitForChild("Town")
		town.DescendantAdded:Connect(watch) -- parts stream in and out
		town.DescendantRemoving:Connect(unwatch)
		for _, descendant in town:GetDescendants() do
			watch(descendant)
		end
		update()
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= UPDATE_INTERVAL then
			since = 0
			update()
		end
	end)
	update()
end

return DayNight
