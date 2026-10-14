--!strict
-- The admin panel (see server AdminService): the ` key toggles it, for players the server marked
-- "Admin" (everyone in Studio). Buttons ask the server to change your level (each level is a
-- skill point), reset your skills, heal, hurt you, or give coins (AdminCommand).
-- Below them, a live readout of every skill-driven stat, to check the skill trees work:
-- for stats the server publishes (max health, stamina, mana, block charges) it shows the
-- real value next to what your skills say it should be, red if they don't match. Then the
-- bonuses from the equipped weapon's tree. Stays open over the skill screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)
local SkillTrees = require(ReplicatedStorage.Shared.Config.SkillTrees)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local HudStyle = require(script.Parent.HudStyle)

local TOGGLE_KEY = Enum.KeyCode.Backquote -- the ` key left of 1 (F-keys need Fn on a Mac)
local WIDTH = 320
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local BUTTON_COLOR = Color3.fromRGB(58, 54, 74)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local GOOD = Color3.fromRGB(120, 220, 140)
local BAD = Color3.fromRGB(255, 110, 100)
local REFRESH = 0.25 -- seconds between readout updates while open

-- Weapon stats that aren't fractions, with their unit ("" for plain counts).
local FLAT_STATS: { [string]: string } = {
	FlurryHits = "",
	BleedDamage = "",
	BurnDamage = "",
	ExtraHands = "",
	BlockAmount = "",
	SpinDuration = " s",
	RushDuration = " s",
	EarthStun = " s",
	ParryWindow = " s",
}

local commandRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AdminCommand") :: RemoteEvent
local player = Players.LocalPlayer

local AdminPanel = {}

local function percent(fraction: number): string
	return string.format("%+d%%", math.round(fraction * 100))
end

local function number(value: number): string
	return if value == math.floor(value) then tostring(value) else string.format("%.2f", value)
end

local function text(parent: Instance, value: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, size + 2)
	label.RichText = true
	label.Text = value
	label.Parent = parent
	return label
end

local function buttonRow(parent: Instance, buttons: { { label: string, action: string, amount: number? } })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	local width = (WIDTH - 24 - 6 * (#buttons - 1)) / #buttons
	for _, info in buttons do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, width, 1, 0)
		button.BackgroundColor3 = BUTTON_COLOR
		button.Font = HudStyle.FONT
		button.TextSize = 15
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = info.label
		button.AutoButtonColor = true
		button.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		button.Activated:Connect(function()
			commandRemote:FireServer(info.action, info.amount)
		end)
	end
end

-- "real (expected)" for a stat the server publishes; red when the skill bonus didn't reach it.
-- `atLeast`: other things may add on top (e.g. a shield's extra block charges).
local function checked(name: string, actual: unknown, base: number, bonus: number, atLeast: boolean?): string
	local expected = base + bonus
	if typeof(actual) ~= "number" then
		return `{name}: <font color="#ff6e64">not set</font> (expected {number(expected)})`
	end
	local ok = if atLeast then actual >= expected - 0.01 else math.abs(actual - expected) < 0.01
	local color = if ok then GOOD else BAD
	return `{name}: <font color="#{color:ToHex()}">{number(actual)}</font> (base {number(base)} + skills {number(bonus)})`
end

local function generalLines(): { string }
	local general = function(stat: string): number
		return SkillMath.general(player, stat)
	end
	local character = player.Character
	local dash = CombatConfig.Dash
	return {
		checked("Max health", character and character:GetAttribute("MaxHealth"), PlayerConfig.MaxHealth, general("MaxHealth")),
		`Health regen: {number(PlayerConfig.RegenPerSecond + general("HealthRegen"))}/s (skills +{number(general("HealthRegen"))})`,
		checked("Max stamina", player:GetAttribute("MaxStamina"), CombatConfig.Stamina.Max, general("MaxStamina")),
		`Stamina regen: {number(CombatConfig.Stamina.RegenPerSecond + general("StaminaRegen"))}/s`,
		checked("Max mana", player:GetAttribute("MaxMana"), CombatConfig.Mana.Max, general("MaxMana")),
		`Mana regen: {number(CombatConfig.Mana.RegenPerSecond + general("ManaRegen"))}/s`,
		`Dash: {dash.MaxCharges + general("DashCharges")} charges, recharge {percent(-general("DashRecharge"))}, i-frames +{number(general("DashIFrames"))} s`,
		checked("Block charges", player:GetAttribute("MaxBlockCharges"), CombatConfig.Blocking.MaxCharges, general("BlockCharges"), true),
		`Block absorb +{number(general("BlockAmount"))}, parry window +{number(general("ParryWindow"))} s`,
		`Damage (every weapon): {percent(general("Damage"))}`,
	}
end

local function weaponLines(): { string }
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return { `<font color="#{SOFT_TEXT:ToHex()}">Equip a weapon to see its tree's bonuses.</font>` }
	end
	local tree = SkillMath.treeOf(tool.Name)
	local nodes = SkillTrees.Weapons[tree]
	if not nodes then
		return { `{tool.Name}: no skill tree` }
	end
	local stats: { string } = {}
	for _, node in nodes do
		for stat in node.Effects do
			if not table.find(stats, stat) then
				table.insert(stats, stat)
			end
		end
	end
	table.sort(stats)
	local lines = { `{tool.Name} ({tree} tree, {SkillMath.spent(SkillMath.allocations(player), tree)} points):` }
	for _, stat in stats do
		local value = SkillMath.weapon(player, tool.Name, stat)
		if value ~= 0 then
			local unit = FLAT_STATS[stat]
			table.insert(lines, `  {stat}: {if unit then "+" .. number(value) .. unit else percent(value)}`)
		end
	end
	if #lines == 1 then
		table.insert(lines, `<font color="#{SOFT_TEXT:ToHex()}">  no bonuses yet</font>`)
	end
	table.insert(lines, `  100 light hit -> {SkillMath.damage(player, tool.Name, 100, "Light")}, 100 heavy -> {SkillMath.damage(player, tool.Name, 100, "Heavy")}`)
	return lines
end

function AdminPanel.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50 -- over the skill screen
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 16, 0.5, 0)
	panel.Size = UDim2.fromOffset(WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.Parent = gui
	HudStyle.chunky(panel, 10, 2)
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 12)
	end
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	text(panel, "ADMIN  <font color=\"#bebacd\">( ` )</font>", 20)
	local status = text(panel, "", 16)
	buttonRow(panel, {
		{ label = "Lv -1", action = "Level", amount = -1 },
		{ label = "Lv +1", action = "Level", amount = 1 },
		{ label = "Lv +10", action = "Level", amount = 10 },
		{ label = "Max lv", action = "MaxLevel" },
	})
	buttonRow(panel, {
		{ label = "Reset skills", action = "ResetSkills" },
		{ label = "+1000 coins", action = "Coins", amount = 1000 },
	})
	buttonRow(panel, {
		{ label = "Full heal", action = "Heal" },
		{ label = "Hurt 50", action = "Damage", amount = 50 },
	})
	text(panel, "SKILL STATS", 15, SOFT_TEXT)
	local generalReadout = text(panel, "", 14)
	text(panel, "WEAPON TREE", 15, SOFT_TEXT)
	local weaponReadout = text(panel, "", 14)

	local function refresh()
		local points = player:GetAttribute("SkillPoints")
		status.Text = `Level {SkillMath.level(player)} · {if typeof(points) == "number" then points else "?"} unspent points`
		generalReadout.Text = table.concat(generalLines(), "\n")
		weaponReadout.Text = table.concat(weaponLines(), "\n")
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= TOGGLE_KEY or player:GetAttribute("Admin") ~= true then
			return
		end
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			if gui.Enabled then
				refresh()
			end
			task.wait(REFRESH)
		end
	end)
end

return AdminPanel
