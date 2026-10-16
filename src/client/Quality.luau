--!strict
-- Effects quality on this screen (Config/QualityConfig): Low, Medium or High. Looks only.
-- Starts from the device, by the player's Roblox graphics level: phones and tablets (touch, no
-- keyboard) at Low or Medium (High only at graphics 8+), computers up to High. Then it watches the frame rate: a few
-- seconds under QualityConfig.Fps.DropBelow drops a tier; a long steady stretch climbs back
-- (never above the device's tier). Changing the graphics level starts over from the device.
-- An admin can pin a tier (AdminPanel); Quality.force(nil) goes back to automatic.
-- Effects read Quality.settings() when they draw, or Quality.onChange to adjust live. This
-- module itself scales the world's particle emitters (town smoke, dungeon torches) and turns
-- Bloom and SunRays on or off.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local QualityConfig = require(ReplicatedStorage.Shared.Config.QualityConfig)

type Tier = QualityConfig.Tier
type Settings = QualityConfig.Settings

local FPS = QualityConfig.Fps
local DEVICE = QualityConfig.Device
local EMITTER_ROOTS = { "Town", "Dungeons" } -- workspace folders whose emitters follow Particles

local Quality = {}

local tier: Tier = "High"
local ceiling: Tier = "High" -- the device's tier: automatic climbs stop here
local forced: Tier? = nil
local reason = "start"
local raises = 0
local listeners: { (Settings, Tier) -> () } = {}
local baseRates: { [ParticleEmitter]: number } = setmetatable({}, { __mode = "k" }) :: any

local function indexOf(t: Tier): number
	return table.find(QualityConfig.Order, t) or #QualityConfig.Order
end

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The player's Roblox graphics level, 1-10, or 0 for Automatic.
local function graphicsLevel(): number
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and typeof(level) == "number" then level else 0
end

local function deviceTier(): Tier
	local level = graphicsLevel()
	if isTouchDevice() then
		if level == 0 then
			return DEVICE.TouchAutomatic
		end
		if level >= DEVICE.TouchHighFrom then
			return "High"
		end
		return if level >= DEVICE.TouchMediumFrom then "Medium" else "Low"
	end
	if level == 0 then
		return DEVICE.PcAutomatic
	elseif level >= DEVICE.PcHighFrom then
		return "High"
	end
	return if level >= DEVICE.PcMediumFrom then "Medium" else "Low"
end

local function scaleEmitter(emitter: ParticleEmitter, settings: Settings)
	local base = baseRates[emitter]
	if base == nil then
		base = emitter.Rate
		baseRates[emitter] = base
	end
	emitter.Rate = base * settings.Particles
end

local function applyWorld(settings: Settings)
	for emitter in baseRates do
		if emitter.Parent then
			scaleEmitter(emitter, settings)
		end
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Enabled = settings.Bloom
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Enabled = settings.SunRays
	end
end

local function setTier(new: Tier, why: string)
	if new == tier and why ~= "start" then
		return
	end
	tier = new
	reason = why
	print(`[Quality] {tier} ({why})`)
	local settings = QualityConfig.Tiers[tier]
	applyWorld(settings)
	for _, listener in listeners do
		task.spawn(listener, settings, tier)
	end
end

-- The current tier's settings.
function Quality.settings(): Settings
	return QualityConfig.Tiers[tier]
end

function Quality.tier(): Tier
	return tier
end

-- A line for the admin panel: the tier, why, and whether it's pinned.
function Quality.describe(): string
	return `{tier} ({if forced then "pinned" else "auto: " .. reason}; device {ceiling})`
end

-- Calls `listener(settings, tier)` now and whenever the tier changes.
function Quality.onChange(listener: (Settings, Tier) -> ())
	table.insert(listeners, listener)
	task.spawn(listener, Quality.settings(), tier)
end

-- Pins a tier (testing), or with nil goes back to automatic from the device's tier.
function Quality.force(t: Tier?)
	forced = t
	raises = 0
	setTier(t or ceiling, if t then "pinned" else "auto")
end

local function watchEmitters(rootName: string)
	local root = workspace:WaitForChild(rootName)
	local function add(descendant: Instance)
		if descendant:IsA("ParticleEmitter") then
			scaleEmitter(descendant, Quality.settings())
		end
	end
	root.DescendantAdded:Connect(add) -- parts stream in, dungeon runs are copied in
	for _, descendant in root:GetDescendants() do
		add(descendant)
	end
end

local function watchFps()
	local started = os.clock()
	local frames, elapsed = 0, 0
	local lowFor, highFor = 0, 0
	local focused = true
	UserInputService.WindowFocusReleased:Connect(function()
		focused = false
	end)
	UserInputService.WindowFocused:Connect(function()
		focused = true
	end)
	RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed < 1 then
			return
		end
		local fps = frames / elapsed
		frames, elapsed = 0, 0
		-- Not while loading, pinned, or in the background (the frame rate is throttled there).
		if forced or not focused or os.clock() - started < FPS.Grace then
			lowFor, highFor = 0, 0
			return
		end
		lowFor = if fps < FPS.DropBelow then lowFor + 1 else 0
		highFor = if fps >= FPS.RaiseAbove then highFor + 1 else 0
		local index = indexOf(tier)
		if lowFor >= FPS.DropAfter and index > 1 then
			lowFor, highFor = 0, 0
			setTier(QualityConfig.Order[index - 1], `low FPS {math.floor(fps)}`)
		elseif highFor >= FPS.RaiseAfter and index < indexOf(ceiling) and raises < FPS.MaxRaises then
			lowFor, highFor = 0, 0
			raises += 1
			setTier(QualityConfig.Order[index + 1], "steady FPS")
		end
	end)
end

function Quality.start()
	ceiling = deviceTier()
	tier = ceiling
	setTier(ceiling, "start")
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
			ceiling = deviceTier()
			raises = 0
			if not forced then
				setTier(ceiling, "graphics level changed")
			end
		end)
	end)
	-- Post effects are made by the server; set them once they've replicated too.
	Lighting.ChildAdded:Connect(function(child)
		if child:IsA("PostEffect") then
			applyWorld(Quality.settings())
		end
	end)
	for _, name in EMITTER_ROOTS do
		task.spawn(watchEmitters, name)
	end
	watchFps()
end

return Quality
