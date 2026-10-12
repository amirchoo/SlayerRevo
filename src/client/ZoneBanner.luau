--!strict
-- Shows a banner when the player moves between zones (hub, training grounds, hunting grounds).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local TrainingArea = require(ReplicatedStorage.Shared.TrainingArea)

local CHECK_INTERVAL = 0.5
local SHOW_TIME = 2.5
local FADE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Zone = { text: string, color: Color3 }

local HUB: Zone = { text = "Beginning Town — Safe Zone", color = Color3.fromRGB(150, 220, 150) }
local TRAINING: Zone = { text = "Training Grounds", color = Color3.fromRGB(240, 200, 90) }
local HUNTING: Zone = { text = "Hunting Grounds", color = Color3.fromRGB(235, 110, 90) }

local player = Players.LocalPlayer

local ZoneBanner = {}

local function zoneAt(position: Vector3): Zone
	if SafeZone.contains(position) then
		return HUB
	elseif TrainingArea.contains(position) then
		return TRAINING
	end
	return HUNTING
end

local function createLabel(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "ZoneBanner"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 80)
	label.Size = UDim2.fromOffset(500, 50)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 34
	label.TextStrokeTransparency = 0.4
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
	return label
end

function ZoneBanner.start()
	local label = createLabel()
	local showId = 0

	local function show(zone: Zone)
		label.Text = zone.text
		label.TextColor3 = zone.color
		TweenService:Create(label, FADE_INFO, { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()

		showId += 1
		local thisShow = showId
		task.delay(SHOW_TIME, function()
			if thisShow == showId then
				TweenService:Create(label, FADE_INFO, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	task.spawn(function()
		local lastZone: Zone? = nil
		while true do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local zone = zoneAt(root.Position)
				-- No banner on the first check after joining, only when changing zones.
				if lastZone ~= nil and zone ~= lastZone then
					show(zone)
				end
				lastZone = zone
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return ZoneBanner
