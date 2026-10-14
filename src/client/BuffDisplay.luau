--!strict
-- Your active buffs (BuffConfig), just right of the health bar: each one's icon, name and
-- time left, popping in when you get it. Display only: reads the "Buff<Id>" player
-- attributes the server sets (BuffService), which hold when each one ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffConfig = require(ReplicatedStorage.Shared.Config.BuffConfig)
local Icons = require(ReplicatedStorage.Shared.Icons)
local HudStyle = require(script.Parent.HudStyle)

local TEXT_SIZE = 16
local REFRESH = 0.25 -- seconds between countdown updates

local player = Players.LocalPlayer

local BuffDisplay = {}

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

function BuffDisplay.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuffDisplay"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Just right of the health bar (420 wide, centered, bottom at -124), mirroring the
	-- armor readout on its left.
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0.5, 222, 1, -124)
	row.Size = UDim2.fromOffset(400, 28)
	row.Parent = HudStyle.holder(gui, Vector2.new(0.5, 1))
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local ids: { string } = {}
	for id in BuffConfig.Buffs do
		table.insert(ids, id)
	end
	table.sort(ids)
	local chips: { [string]: TextLabel } = {}
	for index, id in ids do
		local buff = BuffConfig.Buffs[id]
		local label = HudStyle.caption(row, "", TEXT_SIZE)
		label.LayoutOrder = index
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 28)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = buff.Color
		label.Visible = false
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 26) -- room for the icon
		padding.Parent = label
		local icon = Icons.image(label, buff.Icon)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, -26, 0.5, 0) -- in the padding
		icon.Size = UDim2.fromOffset(22, 22)
		Instance.new("UIScale").Parent = label
		chips[id] = label
	end

	local function refresh()
		local now = workspace:GetServerTimeNow()
		for id, label in chips do
			local ends = player:GetAttribute(BuffConfig.attribute(id))
			local left = if typeof(ends) == "number" then ends - now else 0
			label.Visible = left > 0
			if left > 0 then
				label.Text = `{BuffConfig.Buffs[id].Name}  {clock(left)}`
			end
		end
	end
	for id, label in chips do
		player:GetAttributeChangedSignal(BuffConfig.attribute(id)):Connect(function()
			local had = label.Visible
			refresh()
			if label.Visible and not had then
				HudStyle.pop(label, 1.3)
			end
		end)
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return BuffDisplay
