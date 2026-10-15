--!strict
-- The training camp, client side (server TutorialService runs it; TutorialConfig has the text).
--   * Its opening cutscene (first time only, once the new-player intro is over): letterboxed,
--     the camera sweeping over the yard, then on Drill Master Hode, then on you, with his lines.
--   * A card at the top of the screen while training: Hode's line for the step, what to do
--     (naming the right control for keyboard, controller or touch), and how many are done.
--     It moves to the bottom during the skill tree steps, so the open tree stays clear.
--   * A pop-up for each drill result (Parried!, Too early, ...), and a banner when it's done.
--   * The steps only the client can see: it tells the server when the cutscene ends, when you
--     lock on to the sparring partner, and when the skill tree opens (TutorialAction).
--   * A "Leave training" button while replaying the drills.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local Gamepad = require(script.Parent.Gamepad)
local HudStyle = require(script.Parent.HudStyle)
local Intro = require(script.Parent.Intro)
local LockOn = require(script.Parent.LockOn)
local Panels = require(script.Parent.Panels)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("TutorialAction") :: RemoteEvent
local eventRemote = remotes:WaitForChild("TutorialEvent") :: RemoteEvent

local player = Players.LocalPlayer

local CARD_WIDTH = 540
local CARD_COLOR = Color3.fromRGB(30, 28, 42)
local ACCENT = Color3.fromRGB(250, 210, 120)
local TEXT = Color3.fromRGB(240, 235, 225)
local SOFT_TEXT = Color3.fromRGB(190, 185, 205)
local DONE = Color3.fromRGB(110, 220, 120)
local GOOD = Color3.fromRGB(255, 220, 110)
local BAD = Color3.fromRGB(255, 110, 90)
local WARN = Color3.fromRGB(255, 175, 80)
local PIP_EMPTY = Color3.fromRGB(70, 66, 90)
local SPEAKER = "Drill Master Hode"
local TYPE_SPEED = 55 -- characters per second
local STORY_FONT = Enum.Font.Fondamento
local LETTERBOX = 0.11
local POPUP_TIME = 1.4
local BANNER_TIME = 6
local SKILL_STEPS = { SkillsOpen = true, SkillsSpend = true }
local GOOD_RESULTS = { Dodge = true, Block = true, Parry = true }
local BAD_RESULTS = { Hit = true }

local TutorialClient = {}

local function label(parent: Instance, font: Enum.Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextWrapped = true
	text.Text = ""
	text.Parent = parent
	return text
end

local function outline(text: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudStyle.OUTLINE
	stroke.Thickness = thickness
	stroke.Parent = text
end

local function stepAttribute(): string
	local value = player:GetAttribute("TutorialStep")
	return if typeof(value) == "string" then value else ""
end

local function weaponAttribute(): string
	local value = player:GetAttribute("TutorialWeapon")
	return if typeof(value) == "string" then value else ""
end

local function inputKind(): string
	if Gamepad.active() then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

-- "DualBlade" -> "Dual Blade".
local function weaponName(weapon: string): string
	return (string.gsub(weapon, "(%l)(%u)", "%1 %2"))
end

-- Fills in {Weapon}, {ParryTip} and the controls ({Attack}, ...) for this player's input.
local function fill(text: string, weapon: string): string
	text = string.gsub(text, "{ParryTip}", TutorialConfig.parryTip(weapon))
	local keys = (TutorialConfig.Keys :: any)[inputKind()]
	return (string.gsub(text, "{(%w+)}", function(name: string): string?
		if name == "Weapon" then
			return weaponName(weapon)
		end
		return keys[name]
	end))
end

-- Loads the player's movement controls (PlayerModule), to switch them off and on.
local function getControls(): any
	local scripts = player:WaitForChild("PlayerScripts")
	local module = scripts:WaitForChild("PlayerModule", 10)
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require :: any)(module):GetControls()
	end)
	return if ok then result else nil
end

local function ease(alpha: number): number
	return (1 - math.cos(math.pi * math.clamp(alpha, 0, 1))) / 2
end

function TutorialClient.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 7 -- over the panels (the skill tree steps happen with it open)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The card ---------------------------------------------------------------------------
	local top = HudStyle.holder(gui, Vector2.new(0.5, 0))
	local bottom = HudStyle.holder(gui, Vector2.new(0.5, 1))
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 64)
	card.Size = UDim2.fromOffset(CARD_WIDTH, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = CARD_COLOR
	card.BackgroundTransparency = 0.08
	card.Visible = false
	card.Parent = top
	HudStyle.chunky(card, 14)
	Instance.new("UIScale").Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = card

	local header = Instance.new("Frame")
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.Parent = card
	local speaker = label(header, HudStyle.FONT, 18, ACCENT)
	speaker.Size = UDim2.fromScale(0.7, 1)
	speaker.TextXAlignment = Enum.TextXAlignment.Left
	speaker.Text = SPEAKER
	local stepCounter = label(header, HudStyle.FONT, 15, SOFT_TEXT)
	stepCounter.AnchorPoint = Vector2.new(1, 0)
	stepCounter.Position = UDim2.fromScale(1, 0)
	stepCounter.Size = UDim2.fromScale(0.3, 1)
	stepCounter.TextXAlignment = Enum.TextXAlignment.Right

	local line = label(card, STORY_FONT, 19, TEXT)
	line.LayoutOrder = 2
	line.Size = UDim2.new(1, 0, 0, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top

	local divider = Instance.new("Frame")
	divider.LayoutOrder = 3
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.BackgroundColor3 = PIP_EMPTY
	divider.BorderSizePixel = 0
	divider.Parent = card

	local objectiveRow = Instance.new("Frame")
	objectiveRow.LayoutOrder = 4
	objectiveRow.Size = UDim2.new(1, 0, 0, 26)
	objectiveRow.BackgroundTransparency = 1
	objectiveRow.Parent = card
	local objective = label(objectiveRow, HudStyle.FONT, 18, Color3.new(1, 1, 1))
	objective.Size = UDim2.new(1, -90, 1, 0)
	objective.TextXAlignment = Enum.TextXAlignment.Left
	objective.TextScaled = true
	local objectiveSize = Instance.new("UITextSizeConstraint")
	objectiveSize.MaxTextSize = 18
	objectiveSize.Parent = objective
	local countLabel = label(objectiveRow, HudStyle.FONT, 20, ACCENT)
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.fromScale(1, 0)
	countLabel.Size = UDim2.new(0, 86, 1, 0)
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	outline(countLabel, 1.5)

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.LayoutOrder = 5
	leave.Size = UDim2.fromOffset(150, 30)
	leave.BackgroundColor3 = Color3.fromRGB(60, 50, 70)
	leave.Font = HudStyle.FONT
	leave.TextSize = 16
	leave.TextColor3 = TEXT
	leave.Text = "Leave training"
	leave.Visible = false
	leave.Parent = card
	HudStyle.chunky(leave, 10, 2)
	Instance.new("UIScale").Parent = leave

	-- Pop-ups and banner -----------------------------------------------------------------
	local middle = HudStyle.holder(gui, Vector2.new(0.5, 0.5))
	local popup = label(middle, HudStyle.FONT, 38, GOOD)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.36)
	popup.Size = UDim2.fromOffset(700, 50)
	popup.TextTransparency = 1
	outline(popup, 3)
	local popupStroke = popup:FindFirstChildOfClass("UIStroke") :: UIStroke
	popupStroke.Transparency = 1
	Instance.new("UIScale").Parent = popup

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.Size = UDim2.fromOffset(760, 130)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.Parent = middle
	local bannerTitle = label(banner, STORY_FONT, 64, Color3.new(1, 1, 1))
	bannerTitle.Size = UDim2.new(1, 0, 0, 70)
	bannerTitle.Text = TutorialConfig.Complete.Banner
	local bannerGradient = Instance.new("UIGradient")
	bannerGradient.Rotation = 90
	bannerGradient.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214), ACCENT)
	bannerGradient.Parent = bannerTitle
	outline(bannerTitle, 2.5)
	local bannerLine = label(banner, STORY_FONT, 22, TEXT)
	bannerLine.Position = UDim2.fromOffset(0, 76)
	bannerLine.Size = UDim2.new(1, 0, 0, 54)
	outline(bannerLine, 1.5)

	-- Cutscene layer ---------------------------------------------------------------------
	local cutscene = Instance.new("Frame")
	cutscene.Size = UDim2.fromScale(1, 1)
	cutscene.BackgroundTransparency = 1
	cutscene.Visible = false
	cutscene.Parent = gui
	local bars: { Frame } = {}
	for index, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, 0)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Parent = cutscene
		bars[index] = bar
	end
	local captionName = label(cutscene, HudStyle.FONT, 20, ACCENT)
	captionName.AnchorPoint = Vector2.new(0.5, 1)
	captionName.Position = UDim2.new(0.5, 0, 1, -86)
	captionName.Size = UDim2.new(0.8, 0, 0, 24)
	captionName.Text = SPEAKER
	captionName.ZIndex = 2
	outline(captionName, 1.5)
	local caption = label(cutscene, STORY_FONT, 26, TEXT)
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -18)
	caption.Size = UDim2.new(0.8, 0, 0, 66)
	caption.TextYAlignment = Enum.TextYAlignment.Top
	caption.ZIndex = 2
	caption.TextScaled = true
	local captionSize = Instance.new("UITextSizeConstraint")
	captionSize.MaxTextSize = 26
	captionSize.MinTextSize = 14
	captionSize.Parent = caption
	outline(caption, 2)

	-- Typing --------------------------------------------------------------------------------
	local typeToken = 0
	local function typeOut(target: TextLabel, text: string)
		typeToken += 1
		local token = typeToken
		target.Text = text
		target.MaxVisibleGraphemes = 0
		task.spawn(function()
			local total = utf8.len(text) or #text
			local shown = 0
			while shown < total and token == typeToken do
				shown = math.min(total, shown + math.max(1, math.floor(TYPE_SPEED * RunService.Heartbeat:Wait())))
				target.MaxVisibleGraphemes = shown
			end
			if token == typeToken then
				target.MaxVisibleGraphemes = -1
			end
		end)
	end

	-- The card's contents ----------------------------------------------------------------
	local shownStep = ""
	local function updateCount()
		local count = player:GetAttribute("TutorialCount")
		local goal = player:GetAttribute("TutorialGoal")
		local n = if typeof(count) == "number" then count else 0
		local g = if typeof(goal) == "number" then goal else 1
		if n >= g then
			countLabel.Text = "✓"
			countLabel.TextColor3 = DONE
			objective.TextColor3 = DONE
		else
			countLabel.Text = if g > 1 then `{n} / {g}` else ""
			countLabel.TextColor3 = ACCENT
			objective.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	local function placeCard(id: string)
		if SKILL_STEPS[id] then
			card.Parent = bottom
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Position = UDim2.new(0.5, 0, 1, -24)
		else
			card.Parent = top
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.new(0.5, 0, 0, 64)
		end
	end

	local function showStep(id: string, retype: boolean)
		local weapon = weaponAttribute()
		local step = TutorialConfig.step(id, weapon)
		local order = TutorialConfig.order(weapon)
		local position = table.find(order, id) or 1
		local total = #order
		if player:GetAttribute("TutorialReplay") == true and table.find(order, "Intro") then
			position -= 1 -- replays skip the cutscene
			total -= 1
		end
		stepCounter.Text = `Training {position} / {total}`
		local stepWeapon = TutorialConfig.stepWeapon(id, weapon) -- a caster's sidearm for the guard drills
		objective.Text = fill(step.Objective, stepWeapon)
		if retype then
			typeOut(line, fill(step.Line, stepWeapon))
			HudStyle.pop(card, 0.94)
		else
			line.Text = fill(step.Line, stepWeapon)
		end
		placeCard(id)
		updateCount()
	end

	-- Cutscene -----------------------------------------------------------------------------
	local cutscenePlaying = false
	local function setBars(open: boolean, time: number)
		for _, bar in bars do
			TweenService:Create(bar, TweenInfo.new(time, Enum.EasingStyle.Sine), { Size = UDim2.fromScale(1, if open then LETTERBOX else 0) }):Play()
		end
	end

	-- Hides the HUD and stops the character; returns how to put it all back.
	local function takeOver(): () -> ()
		local hidden: { ScreenGui } = {}
		for _, child in player:WaitForChild("PlayerGui"):GetChildren() do
			if child:IsA("ScreenGui") and child ~= gui and child.Enabled then
				child.Enabled = false
				table.insert(hidden, child)
			end
		end
		Panels.opened("TutorialCutscene")
		local listShown = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		local controls = getControls()
		if controls then
			controls:Disable()
		end
		return function()
			for _, screen in hidden do
				screen.Enabled = true
			end
			Panels.opened("TutorialCutscene") -- closes any panel a key opened meanwhile
			Panels.closed("TutorialCutscene")
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, listShown)
			if controls then
				controls:Enable()
			end
		end
	end

	-- The three shots: over the yard, on Hode, then on the player (ending near the usual camera).
	local function shots(root: BasePart): { { From: CFrame, To: CFrame } }
		local middle = Vector3.zero
		for _, station in TutorialConfig.Stations do
			middle += Vector3.new(station.Stand.X, 0, station.Stand.Y)
		end
		middle = middle / math.max(#TutorialConfig.Stations, 1) + Vector3.new(0, root.Position.Y - 2, 0)
		local list = {
			{
				From = CFrame.lookAt(middle + Vector3.new(34, 26, 30), middle),
				To = CFrame.lookAt(middle + Vector3.new(12, 18, 34), middle),
			},
		}
		local hode = NpcConfig.get("DrillMaster")
		local folder = workspace:FindFirstChild("Townsfolk")
		local model = hode and folder and folder:FindFirstChild(hode.Name)
		local head = model and model:FindFirstChild("Head")
		if hode and head and head:IsA("BasePart") then
			local facing = Vector3.new(hode.Facing.X, 0, hode.Facing.Y).Unit
			local right = facing:Cross(Vector3.yAxis)
			local face = head.Position
			table.insert(list, {
				From = CFrame.lookAt(face + facing * 10 + right * 3 + Vector3.new(0, 1.5, 0), face),
				To = CFrame.lookAt(face + facing * 6 + right * 1.5 + Vector3.new(0, 0.5, 0), face),
			})
		end
		local look = root.CFrame.LookVector
		local ahead = root.Position + look * 10 + Vector3.new(0, 1, 0)
		table.insert(list, {
			From = CFrame.lookAt((root.CFrame * CFrame.new(6, 3, -6)).Position, root.Position + Vector3.new(0, 1, 0)),
			To = CFrame.lookAt((root.CFrame * CFrame.new(2, 4, 11)).Position, ahead),
		})
		return list
	end

	local function playCutscene()
		if cutscenePlaying then
			return
		end
		cutscenePlaying = true
		while Intro.isPlaying() do
			task.wait(0.2)
		end
		local character = player.Character or player.CharacterAdded:Wait()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or not root:IsA("BasePart") or stepAttribute() ~= "Intro" then
			cutscenePlaying = false
			return
		end
		task.wait(0.6) -- let the server's move into the yard land
		local restore = takeOver()
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		cutscene.Visible = true
		card.Visible = false
		setBars(true, 0.6)
		local list = shots(root)
		local lines = TutorialConfig.Cutscene.Lines
		local shotTime = TutorialConfig.Cutscene.ShotTime
		local shot = list[1]
		local started = os.clock()
		RunService:BindToRenderStep("TutorialCutscene", Enum.RenderPriority.Camera.Value + 1, function()
			camera.CFrame = shot.From:Lerp(shot.To, ease((os.clock() - started) / shotTime))
		end)
		for index, nextShot in list do
			shot = nextShot
			started = os.clock()
			typeOut(caption, fill(lines[math.min(index, #lines)], weaponAttribute()))
			task.wait(shotTime)
		end
		RunService:UnbindFromRenderStep("TutorialCutscene")
		setBars(false, 0.5)
		task.wait(0.5)
		cutscene.Visible = false
		caption.Text = ""
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
		restore()
		cutscenePlaying = false
		actionRemote:FireServer("Intro")
	end

	-- Reacting to the server -----------------------------------------------------------------
	local lockReported = false
	local function refresh()
		local id = stepAttribute()
		if id ~= shownStep then
			lockReported = false
		end
		leave.Visible = id ~= "" and player:GetAttribute("TutorialReplay") == true
		if id == "" then
			card.Visible = false
			shownStep = ""
			return
		end
		if id == "Intro" then
			card.Visible = false
			shownStep = id
			task.spawn(playCutscene)
			return
		end
		card.Visible = not cutscenePlaying
		banner.Visible = false
		showStep(id, id ~= shownStep)
		shownStep = id
	end
	for _, name in { "TutorialStep", "TutorialWeapon", "TutorialReplay" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	player:GetAttributeChangedSignal("TutorialCount"):Connect(updateCount)
	player:GetAttributeChangedSignal("TutorialGoal"):Connect(updateCount)
	Gamepad.Changed:Connect(function()
		if shownStep ~= "" and shownStep ~= "Intro" then
			showStep(shownStep, false)
		end
	end)

	local popupToken = 0
	local function showPopup(text: string, color: Color3)
		popupToken += 1
		local token = popupToken
		popup.Text = text
		popup.TextColor3 = color
		popup.TextTransparency = 0
		popupStroke.Transparency = 0
		HudStyle.pop(popup, 1.35)
		task.delay(POPUP_TIME, function()
			if token == popupToken then
				local info = TweenInfo.new(0.4)
				TweenService:Create(popup, info, { TextTransparency = 1 }):Play()
				TweenService:Create(popupStroke, info, { Transparency = 1 }):Play()
			end
		end)
	end

	eventRemote.OnClientEvent:Connect(function(kind: string, detail: string?)
		if kind == "Result" and detail then
			local text = (TutorialConfig.Results :: any)[detail]
			if typeof(text) == "string" then
				showPopup(text, if GOOD_RESULTS[detail] then GOOD elseif BAD_RESULTS[detail] then BAD else WARN)
			end
		elseif kind == "StepDone" and shownStep ~= "Intro" then
			showPopup("Well done!", DONE)
		elseif kind == "Complete" then
			card.Visible = false
			bannerLine.Text = TutorialConfig.Complete.Line
			banner.Visible = true
			bannerTitle.TextTransparency, bannerLine.TextTransparency = 0, 0
			task.delay(BANNER_TIME, function()
				local info = TweenInfo.new(0.8)
				TweenService:Create(bannerTitle, info, { TextTransparency = 1 }):Play()
				TweenService:Create(bannerLine, info, { TextTransparency = 1 }):Play()
				task.wait(0.8)
				banner.Visible = false
			end)
		end
	end)

	leave.Activated:Connect(function()
		HudStyle.pop(leave, 0.9)
		actionRemote:FireServer("Quit")
	end)

	-- Steps only this client can see.
	Panels.Opened:Connect(function(name: string)
		if name == "SkillTree" and stepAttribute() == "SkillsOpen" then
			actionRemote:FireServer("SkillsOpen")
		end
	end)
	RunService.Heartbeat:Connect(function()
		if lockReported or shownStep ~= "LockOn" then
			return
		end
		local target = LockOn.target()
		if target and target:GetAttribute("SparringOwner") == player.UserId then
			lockReported = true
			actionRemote:FireServer("LockOn")
		end
	end)

	refresh()
end

return TutorialClient
