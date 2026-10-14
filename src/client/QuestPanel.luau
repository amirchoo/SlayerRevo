--!strict
-- Quest UI: a left-side badge shows the active quest, and the town Quest Board opens this panel
-- to accept available quests. The server owns progress and rewards; this only displays attrs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local CurrencyConfig = require(ReplicatedStorage.Shared.Config.CurrencyConfig)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)

local PANEL_SIZE = Vector2.new(560, 380)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local CARD_COLOR = Color3.fromRGB(46, 43, 60)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local ACCEPT_COLOR = Color3.fromRGB(80, 190, 110)
local LOCKED_COLOR = Color3.fromRGB(70, 68, 85)
local ICON_SIZE = 60
local OPEN_KEY = Enum.KeyCode.T

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boardRemote = remotes:WaitForChild("QuestBoardOpen") :: RemoteEvent
local startRemote = remotes:WaitForChild("QuestStart") :: RemoteEvent
local cancelRemote = remotes:WaitForChild("QuestCancel") :: RemoteEvent
local trackRemote = remotes:WaitForChild("QuestTrack") :: RemoteEvent
local player = Players.LocalPlayer

local QuestPanel = {}

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = HudStyle.FONT
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function activeQuest(): QuestConfig.Quest?
	local active = player:GetAttribute("QuestActive")
	return if typeof(active) == "string" then QuestConfig.quest(active) else nil
end

local function activeIds(): { string }
	local value = player:GetAttribute("QuestActiveList")
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
end

local function isActiveQuest(questId: string): boolean
	return table.find(activeIds(), questId) ~= nil
end

local function progressText(quest: QuestConfig.Quest?): string
	if not quest then
		return "No active quest"
	end
	local progress = player:GetAttribute("QuestProgress")
	local value = if typeof(progress) == "number" then progress else 0
	return `{quest.Title}: {value}/{QuestConfig.totalTarget(quest)}`
end

local function progressFor(quest: QuestConfig.Quest, target: QuestConfig.Target): number
	local allProgress = player:GetAttribute("QuestActiveProgress")
	if typeof(allProgress) ~= "string" or allProgress == "" then
		return 0
	end
	local key = QuestConfig.targetKey(target)
	for _, entry in string.split(allProgress, "|") do
		local questSplit = string.split(entry, ";")
		if questSplit[1] == quest.Id and questSplit[2] then
			for _, part in string.split(questSplit[2], ",") do
				local split = string.split(part, "=")
				if split[1] == key then
					local value = tonumber(split[2])
					return if value then value else 0
				end
			end
		end
	end
	return 0
end

local function objectiveText(quest: QuestConfig.Quest, isActive: boolean): string
	local parts: { string } = {}
	for _, target in quest.Targets do
		local progress = if isActive then progressFor(quest, target) else 0
		table.insert(parts, `{target.Label}: {progress}/{target.Count}`)
	end
	return `Progress: {table.concat(parts, "  |  ")}`
end

function QuestPanel.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local badge = HudStyle.badge(HudStyle.holder(gui, Vector2.new(0, 0.5)), ICON_SIZE, Color3.fromRGB(70, 130, 90), "!")
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 20, 0.5, 152)
	local keyHint = HudStyle.caption(badge, OPEN_KEY.Name, 16)
	keyHint.AnchorPoint = Vector2.new(0.5, 0.5)
	keyHint.Position = UDim2.new(0.5, 0, 1, 0)
	keyHint.Size = UDim2.fromOffset(20, 16)
	local progressDot = HudStyle.caption(badge, "", 13)
	progressDot.AnchorPoint = Vector2.new(0.5, 0.5)
	progressDot.Position = UDim2.new(1, -2, 0, 4)
	progressDot.Size = UDim2.fromOffset(34, 20)
	progressDot.BackgroundColor3 = Color3.fromRGB(210, 150, 55)
	progressDot.BackgroundTransparency = 0
	progressDot.ZIndex = 3
	HudStyle.chunky(progressDot, 10, 2)

	local badgeButton = Instance.new("TextButton")
	badgeButton.Size = UDim2.fromScale(1, 1)
	badgeButton.BackgroundTransparency = 1
	badgeButton.Text = ""
	badgeButton.ZIndex = 4
	badgeButton.Parent = badge

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local function refit()
		local screen = workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(1, (screen.X - 40) / PANEL_SIZE.X, (screen.Y - 40) / PANEL_SIZE.Y)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = holder
	HudStyle.chunky(panel, 26, 4)
	Instance.new("UIScale").Parent = panel
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	local title = label(panel, "Quests", 30)
	title.Position = UDim2.fromOffset(86, 24)
	title.Size = UDim2.new(1, -172, 0, 36)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local subtitle = label(panel, "", 15, SOFT_TEXT)
	subtitle.Position = UDim2.fromOffset(72, 62)
	subtitle.Size = UDim2.new(1, -144, 0, 22)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -20, 0, 20)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
	close.Font = HudStyle.FONT
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = panel
	HudStyle.chunky(close, 12, 3)

	local content = Instance.new("ScrollingFrame")
	content.Position = UDim2.fromOffset(32, 104)
	content.Size = UDim2.new(1, -64, 1, -132)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.Parent = panel
	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 4)
	contentPadding.PaddingBottom = UDim.new(0, 14)
	contentPadding.PaddingLeft = UDim.new(0, 4)
	contentPadding.PaddingRight = UDim.new(0, 14)
	contentPadding.Parent = content

	local mode = "active"
	local setOpen: (boolean) -> ()
	local refresh: () -> ()

	local function clearContent()
		for _, child in content:GetChildren() do
			if not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function questCard(quest: QuestConfig.Quest, order: number, boardMode: boolean)
		local tracked = activeQuest()
		local isActive = isActiveQuest(quest.Id)
		local isTracked = tracked ~= nil and tracked.Id == quest.Id
		local canAccept = boardMode and not isActive

		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, -6, 0, if boardMode then 132 else 150)
		card.BackgroundColor3 = CARD_COLOR
		card.Parent = content
		HudStyle.chunky(card, 16, 3)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke and isTracked then
			stroke.Color = Color3.fromRGB(255, 210, 90)
		end

		local name = label(card, quest.Title, 22)
		name.Position = UDim2.fromOffset(18, 12)
		name.Size = UDim2.new(1, -150, 0, 28)
		local description = label(card, quest.Description, 15, SOFT_TEXT)
		description.Position = UDim2.fromOffset(18, 42)
		description.Size = UDim2.new(1, -150, 0, 24)
		local rewardText = `Reward: {quest.RewardXP} XP and {CurrencyConfig.format(quest.RewardCoins)} coins`
		local rewards = label(card, rewardText, 14, Color3.fromRGB(255, 220, 120))
		rewards.Position = UDim2.fromOffset(18, 72)
		rewards.Size = UDim2.new(1, -150, 0, 20)
		local progress = label(card, objectiveText(quest, isActive), 14, SOFT_TEXT)
		progress.Position = UDim2.fromOffset(18, 96)
		progress.Size = UDim2.new(1, -150, 0, 42)
		progress.TextWrapped = true

		local function actionButton(textValue: string, y: number, color: Color3, enabled: boolean, action: () -> ())
			local button = Instance.new("TextButton")
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -16, 0, y)
			button.Size = UDim2.fromOffset(118, 38)
			button.BackgroundColor3 = if enabled then color else LOCKED_COLOR
			button.AutoButtonColor = enabled
			button.Font = HudStyle.FONT
			button.TextSize = 16
			button.TextColor3 = if enabled then Color3.new(1, 1, 1) else SOFT_TEXT
			button.Text = textValue
			button.Parent = card
			HudStyle.chunky(button, 10, 3)
			if enabled then
				button.Activated:Connect(function()
					HudStyle.pop(button, 0.88)
					action()
				end)
			end
		end

		if boardMode then
			actionButton(if isActive then "Active" else "Accept", 66, ACCEPT_COLOR, canAccept, function()
				startRemote:FireServer(quest.Id)
			end)
		else
			actionButton(if isTracked then "Tracking" else "Track", 52, Color3.fromRGB(205, 150, 60), not isTracked, function()
				trackRemote:FireServer(quest.Id)
			end)
			actionButton("Cancel", 102, Color3.fromRGB(190, 80, 70), true, function()
				cancelRemote:FireServer(quest.Id)
			end)
		end
	end

	refresh = function()
		clearContent()
		local active = activeQuest()
		progressDot.Visible = active ~= nil
		if active then
			local progress = player:GetAttribute("QuestProgress")
			progressDot.Text = `{if typeof(progress) == "number" then progress else 0}/{QuestConfig.totalTarget(active)}`
		else
			progressDot.Text = ""
		end

		if mode == "board" then
			title.Text = "Quest Board"
			subtitle.Text = "Choose any quest that is not already active."
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 12)
			layout.Parent = content
			for order, quest in QuestConfig.Quests do
				questCard(quest, order, true)
			end
		elseif #activeIds() > 0 then
			title.Text = "Active Quests"
			subtitle.Text = if active then `Tracking: {progressText(active)}` else "Choose a quest to track."
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 12)
			layout.Parent = content
			local order = 0
			for _, quest in QuestConfig.Quests do
				if isActiveQuest(quest.Id) then
					order += 1
					questCard(quest, order, false)
				end
			end
		else
			title.Text = "Active Quests"
			subtitle.Text = "No active quest. Visit the Quest Board in town."
			local empty = label(content, "No active quest.\nInteract with the Quest Board at the edge of the central square to pick one up.", 20, SOFT_TEXT)
			empty.Size = UDim2.fromScale(1, 1)
			empty.TextWrapped = true
			empty.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	setOpen = function(open: boolean)
		if panel.Visible == open then
			return
		end
		panel.Visible = open
		if open then
			Panels.opened("QuestPanel")
			refresh()
			HudStyle.pop(panel, 0.92)
		else
			Panels.closed("QuestPanel")
		end
	end

	local function toggleActive()
		mode = "active"
		setOpen(not panel.Visible)
	end

	badgeButton.Activated:Connect(function()
		toggleActive()
	end)
	boardRemote.OnClientEvent:Connect(function()
		mode = "board"
		setOpen(true)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == OPEN_KEY then
			toggleActive()
		elseif panel.Visible and input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "QuestActive" or attribute == "QuestActiveList" or attribute == "QuestActiveProgress" or attribute == "QuestProgress" or attribute == "QuestTarget" or attribute == "QuestTitle" or attribute == "QuestCompleted" or attribute == "QuestProgressDetail" then
			refresh()
		end
	end)
	Panels.register("QuestPanel", function()
		setOpen(false)
	end)
	RunService.Heartbeat:Connect(function()
		if panel.Visible then
			return
		end
		local active = activeQuest()
		progressDot.Visible = active ~= nil
		if active then
			local progress = player:GetAttribute("QuestProgress")
			progressDot.Text = `{if typeof(progress) == "number" then progress else 0}/{QuestConfig.totalTarget(active)}`
		end
	end)
	refresh()
end

return QuestPanel
