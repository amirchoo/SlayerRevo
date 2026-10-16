--!strict
-- A warm glow carried by every player on this screen (LightingConfig.PlayerLight), so the
-- caves and the wilds at night aren't pitch black. Looks only: each screen lights everyone's
-- character itself. Full in a dungeon run (the player's "Dungeon" attribute), and at night
-- (DayCycle) out of the safe zone; dimmer in town at night; off by day. Only the MaxLit
-- characters nearest the camera are lit (fewer at lower Quality); the light fades in and out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local LightingConfig = require(ReplicatedStorage.Shared.Config.LightingConfig)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local Quality = require(script.Parent.Quality)

local CONFIG = LightingConfig.PlayerLight
local CHECK_INTERVAL = 0.25 -- seconds between choosing who's lit and how much

local PlayerLight = {}

type Glow = { light: PointLight, attachment: Attachment, target: number, current: number }
local glows: { [Player]: Glow } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The glow on `player`'s current character, made if it's missing (a new character drops it).
local function glowOf(player: Player, root: BasePart): Glow
	local glow = glows[player]
	if glow and glow.attachment.Parent == root then
		return glow
	end
	if glow then
		glow.attachment:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PlayerGlow"
	attachment.Position = CONFIG.Offset
	local light = Instance.new("PointLight")
	light.Color = CONFIG.Color
	light.Range = CONFIG.Range
	light.Brightness = 0
	light.Shadows = false
	light.Enabled = false
	light.Parent = attachment
	attachment.Parent = root
	glow = { light = light, attachment = attachment, target = 0, current = 0 }
	glows[player] = glow
	return glow
end

-- How bright `player`'s glow should be (0..1).
local function strength(player: Player, root: BasePart, night: number): number
	if typeof(player:GetAttribute("Dungeon")) == "string" then
		return 1
	end
	if SafeZone.contains(root.Position) then
		return night * CONFIG.TownNight
	end
	return night
end

local function choose()
	local camera = workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else Vector3.zero
	local night = DayCycle.night(DayCycle.clock())
	local nearest: { { player: Player, root: BasePart, distance: number } } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			table.insert(nearest, { player = player, root = root, distance = (root.Position - from).Magnitude })
		end
	end
	table.sort(nearest, function(a, b)
		return a.distance < b.distance
	end)
	local maxLit = math.min(CONFIG.MaxLit, Quality.settings().PlayerLights)
	local seen: { [Player]: boolean } = {}
	for index, entry in nearest do
		local glow = glowOf(entry.player, entry.root)
		glow.target = if index <= maxLit then strength(entry.player, entry.root, night) else 0
		seen[entry.player] = true
	end
	for player, glow in glows do
		if not seen[player] then
			glow.target = 0
		end
	end
end

function PlayerLight.start()
	Players.PlayerRemoving:Connect(function(player)
		local glow = glows[player]
		if glow then
			glow.attachment:Destroy()
			glows[player] = nil
		end
	end)
	local since = math.huge
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= CHECK_INTERVAL then
			since = 0
			choose()
		end
		local step = CONFIG.FadeSpeed * dt
		for _, glow in glows do
			if glow.current ~= glow.target then
				glow.current = if glow.current < glow.target then math.min(glow.current + step, glow.target) else math.max(glow.current - step, glow.target)
				glow.light.Brightness = CONFIG.Brightness * glow.current
				glow.light.Enabled = glow.current > 0.01
			end
		end
	end)
end

return PlayerLight
