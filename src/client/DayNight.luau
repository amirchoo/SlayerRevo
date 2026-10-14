--!strict
-- Day and night on this screen (LightingConfig.DayCycle; the time comes from shared DayCycle,
-- so everyone sees the same sky). Turns the clock, shifts the light toward a moonlit blue at
-- night, and lights the town after dark: lamp and lantern lights in workspace.Town switch on
-- (lights by a fire, like the campfire, stay on), and windows glow. Looks only.
-- The intro holds the clock at its own time while it plays (DayNight.hold).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local LightingConfig = require(ReplicatedStorage.Shared.Config.LightingConfig)

local CYCLE = LightingConfig.DayCycle
local DAY = LightingConfig.Lighting
local NIGHT = CYCLE.Night
local UPDATE_INTERVAL = 0.1 -- seconds between lighting updates
local WINDOW_NAMES = { Windows = true, Window = true } -- House_1/Blacksmith models; part-built houses

local DayNight = {}

local heldClock: number? = nil
local nightLights: { [Light]: boolean } = {}
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
		descendant.Enabled = lit
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
		nightLights[descendant] = nil
	elseif descendant:IsA("BasePart") then
		windows[descendant] = nil
	end
end

local function setLit(on: boolean)
	lit = on
	for light in nightLights do
		light.Enabled = on
	end
	for _, window in windows do
		setWindow(window, on)
	end
end

local function update()
	local clock = heldClock or DayCycle.clock()
	local night = DayCycle.night(clock)
	Lighting.ClockTime = clock
	Lighting.Brightness = DAY.Brightness + (NIGHT.Brightness - DAY.Brightness) * night
	Lighting.Ambient = DAY.Ambient:Lerp(NIGHT.Ambient, night)
	Lighting.OutdoorAmbient = DAY.OutdoorAmbient:Lerp(NIGHT.OutdoorAmbient, night)
	Lighting.ColorShift_Top = DAY.ColorShift_Top:Lerp(NIGHT.ColorShift_Top, night)
	Lighting.ExposureCompensation = DAY.ExposureCompensation + (NIGHT.ExposureCompensation - DAY.ExposureCompensation) * night
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
