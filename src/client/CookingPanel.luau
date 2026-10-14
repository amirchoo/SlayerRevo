--!strict
-- The cooking panel (CookingConfig), in the backpack's style. Press the campfire's Cook prompt
-- and the server opens a session (Cooking remote: "open"): your character crouches by the
-- fire facing the pot (CookingPose), you can't walk off, the camera flies in beside you, and
-- this panel opens on the right:
--   * a row per recipe (raw meat → food), with what it heals and how much raw meat you have;
--   * how many to cook (-, +, MAX);
--   * COOK, which turns into a progress bar while the pieces cook ("started"/"finished" from
--     the server); each finished piece flies out of the fire into you (LootClient).
-- BACK (or the server, if you're knocked away) closes it and hands the camera back.
-- Display and requests only: the server checks you're at the fire and swaps the meat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CookingConfig = require(ReplicatedStorage.Shared.Config.CookingConfig)
local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local HudStyle = require(script.Parent.HudStyle)
local Panels = require(script.Parent.Panels)
local WeaponIcon = require(script.Parent.WeaponIcon)

local PANEL_SIZE = Vector2.new(470, 600)
local PANEL_COLOR = Color3.fromRGB(30, 28, 42)
local TILE_COLOR = Color3.fromRGB(58, 54, 74)
local ROW_COLOR = Color3.fromRGB(42, 40, 54)
local ROW_SELECTED = Color3.fromRGB(64, 52, 46)
local SELECTED_BORDER = Color3.fromRGB(255, 170, 70)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local HEAL_TEXT = Color3.fromRGB(120, 235, 145)
local COOK_COLOR = Color3.fromRGB(230, 120, 40)
local COOK_DISABLED = Color3.fromRGB(80, 74, 90)
local FILL_COLOR = Color3.fromRGB(255, 200, 90)
local ROW_HEIGHT = 96
local ROW_GAP = 10
local LIST_TOP = 128
local PANEL_MARGIN = 30 -- pixels from the right edge of the screen

local cookingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cooking") :: RemoteEvent
local player = Players.LocalPlayer

local CookingPanel = {}

local function text(parent: Instance, value: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = HudStyle.FONT
	label.TextSize = size
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = value
	label.Parent = parent
	return label
end

-- How many of material `itemId` the player has (the "Materials" attribute: "Id=3,Other=1").
local function rawCount(itemId: string): number
	local value = player:GetAttribute("Materials")
	if typeof(value) ~= "string" then
		return 0
	end
	return tonumber(string.match(value, "%f[%w]" .. itemId .. "=(%d+)")) or 0
end

local function button(parent: Instance, label: string, size: Vector2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.BackgroundColor3 = color
	b.Font = HudStyle.FONT
	b.TextSize = 22
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.AutoButtonColor = true
	b.Parent = parent
	HudStyle.chunky(b, 12, 2.5)
	HudStyle.gloss(b)
	Instance.new("UIScale").Parent = b
	return b
end

-- Loads the player's movement controls (PlayerModule), to switch them off and on.
local function getControls(): any
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require :: any)(module):GetControls()
	end)
	return if ok then result else nil
end

local function groundAt(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain, workspace:FindFirstChild("Town") or workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position.Y else 0
end

type Row = { recipe: CookingConfig.Recipe, frame: TextButton, stroke: UIStroke, have: TextLabel }

function CookingPanel.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cooking"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The panel sits on the right, in a holder that scales it down on small screens.
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -PANEL_MARGIN, 0.5, 0)
	holder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local function refit()
		local screen = workspace.CurrentCamera.ViewportSize
		fit.Scale = math.min(1, (screen.Y - 40) / PANEL_SIZE.Y, (screen.X * 0.5) / PANEL_SIZE.X)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.Parent = holder
	HudStyle.chunky(panel, 26, 4)
	local rim = panel:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(200, 200, 215)
	end
	Instance.new("UIScale").Parent = panel -- for the open pop
	local modal = Instance.new("TextButton") -- frees the mouse while it's open (even in shift lock)
	modal.Modal = true
	modal.Size = UDim2.fromScale(0, 0)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Parent = panel

	-- Header.
	local title = text(panel, "// CAMPFIRE", 34)
	title.Position = UDim2.fromOffset(30, 24)
	title.Size = UDim2.fromOffset(280, 40)
	local back = Instance.new("TextButton")
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, -28, 0, 28)
	back.Size = UDim2.fromOffset(110, 34)
	back.BackgroundTransparency = 1
	back.Font = HudStyle.FONT
	back.TextSize = 22
	back.TextColor3 = Color3.new(1, 1, 1)
	back.TextXAlignment = Enum.TextXAlignment.Right
	back.Text = "BACK  →"
	back.Parent = panel
	local subtitle = text(panel, "Pick a meat and how many to cook.", 16, SOFT_TEXT)
	subtitle.Position = UDim2.fromOffset(30, 72)
	subtitle.Size = UDim2.fromOffset(400, 22)
	local listCaption = text(panel, "RECIPES", 15, SOFT_TEXT)
	listCaption.Position = UDim2.fromOffset(30, 100)
	listCaption.Size = UDim2.fromOffset(200, 20)

	-- Recipe rows.
	local rows: { Row } = {}
	local selected = 1
	for index, recipe in CookingConfig.Recipes do
		local raw = MaterialConfig.item(recipe.From)
		local food = ShopConfig.item(recipe.To)
		local row = Instance.new("TextButton")
		row.Text = ""
		row.AutoButtonColor = false
		row.Position = UDim2.fromOffset(30, LIST_TOP + (index - 1) * (ROW_HEIGHT + ROW_GAP))
		row.Size = UDim2.fromOffset(PANEL_SIZE.X - 60, ROW_HEIGHT)
		row.BackgroundColor3 = ROW_COLOR
		row.Parent = panel
		HudStyle.chunky(row, 16, 2.5)
		local stroke = row:FindFirstChildOfClass("UIStroke") :: UIStroke
		Instance.new("UIScale").Parent = row

		local function tile(x: number, modelName: string?): Frame
			local frame = Instance.new("Frame")
			frame.Position = UDim2.fromOffset(x, 12)
			frame.Size = UDim2.fromOffset(72, 72)
			frame.BackgroundColor3 = TILE_COLOR
			frame.Parent = row
			HudStyle.chunky(frame, 12, 2)
			WeaponIcon.showItem(WeaponIcon.viewport(frame), modelName)
			return frame
		end
		tile(12, raw and raw.Model)
		local arrow = text(row, "→", 26, SOFT_TEXT)
		arrow.Position = UDim2.fromOffset(88, 32)
		arrow.Size = UDim2.fromOffset(26, 30)
		arrow.TextXAlignment = Enum.TextXAlignment.Center
		tile(116, food and food.Model)

		local name = text(row, if food then food.Name else recipe.To, 21)
		name.Position = UDim2.fromOffset(204, 12)
		name.Size = UDim2.fromOffset(200, 26)
		local heals = text(row, if food and food.Heal then `Heals {food.Heal} HP over {food.EatTime or 0}s` else "", 14, HEAL_TEXT)
		heals.Position = UDim2.fromOffset(204, 40)
		heals.Size = UDim2.fromOffset(200, 18)
		local have = text(row, "", 15, SOFT_TEXT)
		have.Position = UDim2.fromOffset(204, 62)
		have.Size = UDim2.fromOffset(200, 20)

		table.insert(rows, { recipe = recipe, frame = row, stroke = stroke, have = have })
		row.Activated:Connect(function()
			if selected ~= index then
				selected = index
				HudStyle.pop(row, 0.94)
			end
		end)
	end

	-- Amount.
	local amountTop = LIST_TOP + #CookingConfig.Recipes * (ROW_HEIGHT + ROW_GAP) + 14
	local amountCaption = text(panel, "AMOUNT", 15, SOFT_TEXT)
	amountCaption.Position = UDim2.fromOffset(30, amountTop)
	amountCaption.Size = UDim2.fromOffset(200, 20)
	local minus = button(panel, "−", Vector2.new(56, 48), TILE_COLOR)
	minus.Position = UDim2.fromOffset(30, amountTop + 26)
	local amountBox = Instance.new("Frame")
	amountBox.Position = UDim2.fromOffset(96, amountTop + 26)
	amountBox.Size = UDim2.fromOffset(120, 48)
	amountBox.BackgroundColor3 = ROW_COLOR
	amountBox.Parent = panel
	HudStyle.chunky(amountBox, 12, 2.5)
	local amountLabel = text(amountBox, "1", 26)
	amountLabel.Size = UDim2.fromScale(1, 1)
	amountLabel.TextXAlignment = Enum.TextXAlignment.Center
	local plus = button(panel, "+", Vector2.new(56, 48), TILE_COLOR)
	plus.Position = UDim2.fromOffset(226, amountTop + 26)
	local maxButton = button(panel, "MAX", Vector2.new(96, 48), TILE_COLOR)
	maxButton.Position = UDim2.fromOffset(PANEL_SIZE.X - 30 - 96, amountTop + 26)

	-- Cook button, with the progress bar inside it.
	local cookButton = button(panel, "COOK", Vector2.new(PANEL_SIZE.X - 60, 62), COOK_COLOR)
	cookButton.Position = UDim2.fromOffset(30, amountTop + 94)
	cookButton.Text = ""
	cookButton.ClipsDescendants = true
	local fill = Instance.new("Frame") -- the progress bar, under the label
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = FILL_COLOR
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.Visible = false
	fill.Parent = cookButton
	Instance.new("UICorner").Parent = fill
	local cookLabel = text(cookButton, "COOK", 28)
	cookLabel.Size = UDim2.fromScale(1, 1)
	cookLabel.TextXAlignment = Enum.TextXAlignment.Center
	cookLabel.ZIndex = 2

	local hint = text(panel, "Food goes in your backpack. Put it in a potion slot to eat it.", 14, SOFT_TEXT)
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 30, 1, -22)
	hint.Size = UDim2.fromOffset(PANEL_SIZE.X - 60, 36)
	hint.TextWrapped = true

	-- State ------------------------------------------------------------------------------
	local isOpen = false
	local amount = 1
	local busy: { food: string, count: number, cookTime: number, started: number }? = nil
	local controls: any = nil
	local savedFieldOfView = 70

	local function available(): number
		local row = rows[selected]
		return if row then math.min(rawCount(row.recipe.From), CookingConfig.MaxBatch) else 0
	end

	local function refresh()
		for index, row in rows do
			local count = rawCount(row.recipe.From)
			local raw = MaterialConfig.item(row.recipe.From)
			row.have.Text = `{if raw then raw.Name else row.recipe.From}: x{count}`
			row.have.TextColor3 = if count > 0 then SOFT_TEXT else Color3.fromRGB(150, 110, 110)
			local isSelected = index == selected
			row.frame.BackgroundColor3 = if isSelected then ROW_SELECTED else ROW_COLOR
			row.stroke.Color = if isSelected then SELECTED_BORDER else HudStyle.OUTLINE
			row.stroke.Thickness = if isSelected then 3 else 2.5
		end
		local most = available()
		amount = math.clamp(amount, if most > 0 then 1 else 0, most)
		amountLabel.Text = tostring(amount)
		if busy then
			cookButton.BackgroundColor3 = COOK_DISABLED
		elseif amount > 0 then
			cookButton.BackgroundColor3 = COOK_COLOR
			cookLabel.Text = `COOK {amount}`
		else
			cookButton.BackgroundColor3 = COOK_DISABLED
			cookLabel.Text = "NO RAW MEAT"
		end
	end

	-- Camera and character --------------------------------------------------------------
	local function seatCFrame(): CFrame
		local seat = CookingConfig.Station.Seat
		local fire = CookingConfig.Station.Position
		local ground = Vector3.new(seat.X, groundAt(seat.X, seat.Y), seat.Y)
		return CFrame.lookAt(ground, Vector3.new(fire.X, ground.Y, fire.Y))
	end

	local function cameraCFrame(): CFrame
		local look = CookingConfig.Camera
		local seat = seatCFrame()
		local fire = CookingConfig.Station.Position
		local focus = seat.Position:Lerp(Vector3.new(fire.X, seat.Position.Y, fire.Y), 0.5) + Vector3.new(0, 1.5, 0)
		local position = seat.Position + seat.RightVector * look.Side + seat.LookVector * look.Front + Vector3.new(0, look.Up, 0)
		return CFrame.lookAt(position, focus) * CFrame.Angles(0, -math.rad(look.Turn), 0)
	end

	local function open()
		if isOpen then
			return
		end
		isOpen = true
		Panels.opened("Cooking")
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		controls = getControls()
		if controls then
			controls:Disable()
		end
		if character and humanoid and root and root:IsA("BasePart") then
			humanoid:Move(Vector3.zero)
			character:PivotTo(seatCFrame() * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
		end
		local camera = workspace.CurrentCamera
		savedFieldOfView = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		local zoom = TweenInfo.new(CookingConfig.Camera.ZoomTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(camera, zoom, { CFrame = cameraCFrame(), FieldOfView = CookingConfig.Camera.FieldOfView }):Play()
		amount = 1
		refresh()
		gui.Enabled = true
		HudStyle.pop(panel, 0.9)
	end

	local function close(tellServer: boolean)
		if not isOpen then
			return
		end
		isOpen = false
		gui.Enabled = false
		if tellServer then
			cookingRemote:FireServer("close")
		end
		Panels.closed("Cooking")
		if controls then
			controls:Enable()
		end
		-- Fly back out to behind the player, then hand the camera back.
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			local behind = root.CFrame * CFrame.new(0, 4, 12)
			local back = TweenInfo.new(CookingConfig.Camera.ZoomTime * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			local tween = TweenService:Create(camera, back, { CFrame = CFrame.lookAt(behind.Position, root.Position + Vector3.new(0, 2, 0)), FieldOfView = savedFieldOfView })
			tween:Play()
			tween.Completed:Wait()
		end
		if not isOpen then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = savedFieldOfView
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	Panels.register("Cooking", function()
		task.spawn(close, true)
	end)

	-- Input --------------------------------------------------------------------------------
	back.Activated:Connect(function()
		task.spawn(close, true)
	end)
	minus.Activated:Connect(function()
		amount = math.max(1, amount - 1)
		HudStyle.pop(minus, 0.9)
		refresh()
	end)
	plus.Activated:Connect(function()
		amount += 1
		HudStyle.pop(plus, 0.9)
		refresh()
	end)
	maxButton.Activated:Connect(function()
		amount = available()
		HudStyle.pop(maxButton, 0.9)
		refresh()
	end)
	for _, row in rows do
		row.frame.Activated:Connect(function()
			amount = math.max(amount, 1)
			refresh()
		end)
	end
	cookButton.Activated:Connect(function()
		if busy or amount <= 0 then
			return
		end
		HudStyle.pop(cookButton, 0.92)
		cookingRemote:FireServer("cook", rows[selected].recipe.To, amount)
	end)
	player:GetAttributeChangedSignal("Materials"):Connect(function()
		if isOpen then
			refresh()
		end
	end)

	cookingRemote.OnClientEvent:Connect(function(action: string, food: string?, count: number?, cookTime: number?)
		if action == "open" then
			open()
		elseif action == "close" then
			busy = nil
			task.spawn(close, false)
		elseif action == "started" and food and count and cookTime then
			busy = { food = food, count = count, cookTime = cookTime, started = os.clock() }
			fill.Visible = true
			refresh()
		elseif action == "finished" then
			busy = nil
			fill.Visible = false
			refresh()
		end
	end)

	-- The progress bar fills once per piece.
	RunService.RenderStepped:Connect(function()
		local job = busy
		if not job or not isOpen then
			return
		end
		local elapsed = os.clock() - job.started
		local piece = math.min(math.floor(elapsed / job.cookTime) + 1, job.count)
		fill.Size = UDim2.fromScale(math.clamp((elapsed % job.cookTime) / job.cookTime, 0, 1), 1)
		local food = ShopConfig.item(job.food)
		cookLabel.Text = `COOKING {if food then food.Name else ""}  {piece}/{job.count}`
	end)

	player.CharacterAdded:Connect(function()
		busy = nil
		fill.Visible = false
		task.spawn(close, false)
	end)
end

return CookingPanel
