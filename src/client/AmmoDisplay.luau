--!strict
-- Arrow counter in the bottom-right corner. Display only: reads the Arrows/MaxArrows
-- attributes the server keeps on the player.

local Players = game:GetService("Players")

local NORMAL_COLOR = Color3.new(1, 1, 1)
local LOW_COLOR = Color3.fromRGB(255, 200, 90)
local EMPTY_COLOR = Color3.fromRGB(235, 90, 80)
local LOW_THRESHOLD = 0.25

local player = Players.LocalPlayer

local AmmoDisplay = {}

local function createGui(): (TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "AmmoDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -24, 1, -24)
	panel.Size = UDim2.fromOffset(190, 64)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextColor3 = Color3.fromRGB(190, 190, 190)
	title.TextXAlignment = Enum.TextXAlignment.Right
	title.Text = "ARROWS"
	title.Parent = panel

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.fromOffset(12, 22)
	count.Size = UDim2.new(1, -24, 0, 36)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextSize = 30
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = panel

	return title, count
end

function AmmoDisplay.start()
	local title, count = createGui()

	local function update()
		local arrows = player:GetAttribute("Arrows")
		local maxArrows = player:GetAttribute("MaxArrows")
		if typeof(arrows) ~= "number" or typeof(maxArrows) ~= "number" or maxArrows <= 0 then
			count.Text = "-- / --"
			return
		end

		count.Text = `{arrows} / {maxArrows}`
		if arrows <= 0 then
			count.TextColor3 = EMPTY_COLOR
			title.Text = "EMPTY · REFILL IN HUB"
		else
			count.TextColor3 = if arrows / maxArrows <= LOW_THRESHOLD then LOW_COLOR else NORMAL_COLOR
			title.Text = "ARROWS"
		end
	end

	player:GetAttributeChangedSignal("Arrows"):Connect(update)
	player:GetAttributeChangedSignal("MaxArrows"):Connect(update)
	update()
end

return AmmoDisplay
