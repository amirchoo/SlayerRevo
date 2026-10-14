--!strict
-- Controller support shared by the HUD and menus:
--   * whether a controller is what the player is using right now (Gamepad.active, and
--     Gamepad.Changed when they switch between it and mouse/keyboard/touch);
--   * menus: Gamepad.focus(panel, onBack) makes the panel a selection group and selects its
--     top-left button, so the D-pad / left stick moves between its buttons (Roblox's own GUI
--     navigation) and Cross / A presses the selected one; Circle / B calls onBack (close it).
--     Gamepad.unfocus(panel) lets go. If the selection is lost (say a tab hid that button),
--     the top-left button is picked again. Selected buttons get a gold outline. Roblox's own
--     "View button toggles menu navigation" is off, so the View button is free for the backpack;
--   * button hints: Gamepad.hint(label, keyboardText, keyCode) shows `keyboardText` on mouse
--     and keyboard and the controller button's own picture (PlayStation or Xbox) otherwise.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SELECTION_COLOR = Color3.fromRGB(255, 205, 90)

local player = Players.LocalPlayer

local Gamepad = {}

local changed = Instance.new("BindableEvent")
Gamepad.Changed = changed.Event -- (active: boolean)

local GAMEPAD_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

local active = GAMEPAD_TYPES[UserInputService:GetLastInputType()] == true

-- Whether the player is playing with a controller right now.
function Gamepad.active(): boolean
	return active
end

local function setActive(value: boolean)
	if value ~= active then
		active = value
		changed:Fire(value)
	end
end

-- Menus -------------------------------------------------------------------------------------

type Menu = { panel: GuiObject, onBack: (() -> ())? }
local focused: { Menu } = {} -- open menus, newest last

local function shown(object: GuiObject): boolean
	local current: Instance? = object
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	local layer = object:FindFirstAncestorWhichIsA("LayerCollector")
	return layer == nil or not layer:IsA("ScreenGui") or layer.Enabled
end

-- The visible button nearest the panel's top-left corner.
local function firstButton(panel: GuiObject): GuiObject?
	local best: GuiObject?, bestScore = nil, math.huge
	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Selectable and shown(descendant) and descendant.AbsoluteSize.X > 4 then
			local at = descendant.AbsolutePosition
			local score = at.Y * 4 + at.X
			if score < bestScore then
				best, bestScore = descendant, score
			end
		end
	end
	return best
end

local function topMenu(): Menu?
	local menu = focused[#focused]
	return if menu and shown(menu.panel) then menu else nil
end

local function indexOf(panel: GuiObject): number?
	for index, menu in focused do
		if menu.panel == panel then
			return index
		end
	end
	return nil
end

-- Lets the controller move around `panel`'s buttons (and not leave it), starting at `first`
-- (default: its top-left button); Circle / B calls `onBack`.
function Gamepad.focus(panel: GuiObject, onBack: (() -> ())?, first: GuiObject?)
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local index = indexOf(panel)
	if index then
		table.remove(focused, index)
	end
	table.insert(focused, { panel = panel, onBack = onBack })
	if active then
		task.defer(function() -- once its contents have been laid out
			if topMenu() and topMenu().panel == panel then
				GuiService.SelectedObject = if first and shown(first) then first else firstButton(panel)
			end
		end)
	end
end

-- Stops navigating `panel` (when it closes); goes back to the menu under it, if any.
function Gamepad.unfocus(panel: GuiObject)
	local index = indexOf(panel)
	if index then
		table.remove(focused, index)
	end
	local selected = GuiService.SelectedObject
	if selected and (selected == panel or selected:IsDescendantOf(panel)) then
		GuiService.SelectedObject = nil
	end
end

-- Whether a menu has the controller (so the D-pad navigates it rather than doing hotkeys).
function Gamepad.inMenu(): boolean
	return GuiService.SelectedObject ~= nil
end

-- Hints ---------------------------------------------------------------------------------------

type Hint = { label: TextLabel, text: string, keyCode: Enum.KeyCode, image: ImageLabel }
local hints: { Hint } = {}

local function showHint(hint: Hint)
	local picture = if active then UserInputService:GetImageForKeyCode(hint.keyCode) else ""
	hint.image.Image = picture
	hint.image.Visible = picture ~= ""
	hint.label.TextTransparency = if picture ~= "" then 1 else 0
	local stroke = hint.label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = picture == ""
	end
	hint.label.Text = hint.text
end

-- Shows `keyboardText` in `label` on mouse and keyboard, and `keyCode`'s button picture in
-- its place while a controller is in use.
function Gamepad.hint(label: TextLabel, keyboardText: string, keyCode: Enum.KeyCode)
	local image = Instance.new("ImageLabel")
	image.Name = "ButtonHint"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.new(1, 6, 1, 6)
	image.SizeConstraint = Enum.SizeConstraint.RelativeYY
	image.ZIndex = label.ZIndex + 1
	image.Parent = label
	local hint = { label = label, text = keyboardText, keyCode = keyCode, image = image }
	table.insert(hints, hint)
	showHint(hint)
end

function Gamepad.start()
	-- The View button opens the backpack instead of toggling Roblox's menu navigation.
	GuiService.AutoSelectGuiEnabled = false

	-- A gold outline round whatever the controller has selected.
	local selection = Instance.new("Frame")
	selection.Name = "GamepadSelection"
	selection.BackgroundTransparency = 1
	selection.Size = UDim2.new(1, 8, 1, 8)
	selection.Position = UDim2.fromOffset(-4, -4)
	local stroke = Instance.new("UIStroke")
	stroke.Color = SELECTION_COLOR
	stroke.Thickness = 4
	stroke.Parent = selection
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = selection
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.SelectionImageObject = selection

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if GAMEPAD_TYPES[inputType] then
			setActive(true)
		elseif inputType == Enum.UserInputType.Keyboard or inputType == Enum.UserInputType.Touch
			or inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseMovement then
			setActive(false)
		end
	end)
	Gamepad.Changed:Connect(function(isActive)
		for _, hint in hints do
			showHint(hint)
		end
		if not isActive then
			GuiService.SelectedObject = nil
		end
	end)
	-- Circle / B backs out of the open menu (Roblox marks it as handled while a menu has the
	-- selection, so it's watched here whether or not it was).
	UserInputService.InputBegan:Connect(function(input)
		local menu = topMenu()
		if input.KeyCode == Enum.KeyCode.ButtonB and menu and menu.onBack then
			menu.onBack()
		end
	end)
	-- With a menu open, keep something in it selected (picking up the controller, or after the
	-- selected button was hidden).
	RunService.Heartbeat:Connect(function()
		local menu = topMenu()
		if not active or not menu then
			return
		end
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(menu.panel) or not shown(selected) then
			GuiService.SelectedObject = firstButton(menu.panel)
		end
	end)
end

return Gamepad
