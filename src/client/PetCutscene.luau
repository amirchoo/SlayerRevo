--!strict
-- The short cutscene when you pet a pet (PetCutscene remote from PetService: the pet's
-- model, and the id of the buff it gave you, if any). The HUD, nameplates and prompts hide,
-- your character stops (and is hidden on your screen while the camera is on the pet, since
-- you stand about where the shot is), letterbox bars slide in and the camera flies in to a
-- close shot in front of the pet (which has turned to you and is playing), pushing in slowly while the
-- buff's name and what it does show (BuffConfig). Then the camera flies back behind you and
-- everything comes back. Shot and timing: NpcConfig.PetCutscene.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BuffConfig = require(ReplicatedStorage.Shared.Config.BuffConfig)
local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local HudStyle = require(script.Parent.HudStyle)

local SHOT = NpcConfig.PetCutscene
local BAR_HEIGHT = 0.11 -- of the screen, each letterbox bar
local BAR_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TEXT_FADE = TweenInfo.new(0.4)
local RENDER_NAME = "PetCutscene"

local cutsceneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PetCutscene") :: RemoteEvent
local player = Players.LocalPlayer

local PetCutscene = {}

local playing = false

local function configOf(id: unknown): NpcConfig.Pet?
	for _, pet in NpcConfig.Pets do
		if pet.Id == id then
			return pet
		end
	end
	return nil
end

-- Loads the player's movement controls (PlayerModule), to switch them off and on.
local function getControls(): any
	local module = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require :: any)(module):GetControls()
	end)
	return if ok then result else nil
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function formatDuration(seconds: number): string
	return if seconds >= 60 and seconds % 60 == 0 then `{seconds // 60} min` else `{seconds} s`
end

-- The bars, title and description, all hidden to start.
local function makeOverlay(): (ScreenGui, Frame, Frame, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PetCutscene"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local function bar(y: number): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0, y)
		frame.Position = UDim2.fromScale(0, y)
		frame.Size = UDim2.fromScale(1, 0)
		frame.Parent = gui
		return frame
	end
	local top, bottom = bar(0), bar(1)
	local holder = HudStyle.holder(gui, Vector2.new(0.5, 1))
	local title = HudStyle.caption(holder, "", 40)
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 1, -150)
	title.Size = UDim2.fromOffset(600, 46)
	local description = HudStyle.caption(holder, "", 20)
	description.AnchorPoint = Vector2.new(0.5, 1)
	description.Position = UDim2.new(0.5, 0, 1, -120)
	description.Size = UDim2.fromOffset(600, 26)
	description.TextColor3 = Color3.fromRGB(235, 230, 245)
	for _, label in { title, description } do
		label.TextTransparency = 1
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
	return gui, top, bottom, title, description
end

local function fadeText(label: TextLabel, shown: boolean)
	local to = if shown then 0 else 1
	TweenService:Create(label, TEXT_FADE, { TextTransparency = to }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TEXT_FADE, { Transparency = to }):Play()
	end
end

-- Hides the HUD and every nameplate, stops prompts and the character; returns how to undo it.
local function takeOver(overlay: ScreenGui): () -> ()
	local hidden: { LayerCollector } = {}
	for _, child in player:WaitForChild("PlayerGui"):GetChildren() do
		if child:IsA("LayerCollector") and child ~= overlay and child.Enabled then
			child.Enabled = false
			table.insert(hidden, child)
		end
	end
	ProximityPromptService.Enabled = false
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	return function()
		for _, gui in hidden do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		ProximityPromptService.Enabled = true
		if controls then
			controls:Enable()
		end
	end
end

-- Hides (or shows) your own character on your screen. Set every frame while hidden: the
-- camera scripts reset it otherwise.
local function hideOwnCharacter(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function play(model: Model, buffId: string?)
	local config = configOf(model:GetAttribute("PetId"))
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if playing or not config or not root or not root:IsA("BasePart") or not humanoid then
		return
	end
	playing = true
	local petRoot: BasePart = root
	local height = config.Height
	local hover = humanoid.HipHeight + petRoot.Size.Y / 2

	-- The close shot `distance` (per stud of Height) in front of the pet, from where it is now.
	local function shot(distance: number): CFrame
		local frame = petRoot.CFrame
		local ground = frame.Position - Vector3.new(0, hover, 0)
		local front = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z).Unit
		local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit
		local position = ground + (front * distance + right * SHOT.Side + Vector3.new(0, SHOT.Up, 0)) * height
		return CFrame.lookAt(position, ground + Vector3.new(0, SHOT.LookUp * height, 0))
	end
	-- Where the camera hands back: behind your character, looking at it.
	local function behind(): CFrame?
		local character = player.Character
		local own = character and character:FindFirstChild("HumanoidRootPart")
		if not own or not own:IsA("BasePart") then
			return nil
		end
		local back = own.CFrame * CFrame.new(0, 4, 12)
		return CFrame.lookAt(back.Position, own.Position + Vector3.new(0, 2, 0))
	end

	local overlay, top, bottom, title, description = makeOverlay()
	local restore = takeOver(overlay)
	TweenService:Create(top, BAR_TWEEN, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	TweenService:Create(bottom, BAR_TWEEN, { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
	local buff = if buffId then BuffConfig.Buffs[buffId] else nil
	if buff then
		title.Text = buff.Name
		title.TextColor3 = buff.Color
		description.Text = `{buff.Description} for {formatDuration(buff.Duration)}`
	else
		title.Text = config.Name
	end

	local camera = workspace.CurrentCamera
	local fieldOfView = camera.FieldOfView
	local from = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local started = os.clock()
	local inEnd = SHOT.ZoomTime
	local holdEnd = inEnd + SHOT.HoldTime
	local outEnd = holdEnd + SHOT.BackTime
	local textShown, textHidden = false, false
	local finished = Instance.new("BindableEvent")
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		if not petRoot:IsDescendantOf(workspace) then
			finished:Fire()
			return
		end
		hideOwnCharacter(t < holdEnd)
		if t < inEnd then
			local a = smooth(t / SHOT.ZoomTime)
			camera.CFrame = from:Lerp(shot(SHOT.Distance), a)
			camera.FieldOfView = fieldOfView + (SHOT.FieldOfView - fieldOfView) * a
		elseif t < holdEnd then
			if not textShown then
				textShown = true
				fadeText(title, true)
				fadeText(description, true)
			end
			local k = smooth((t - inEnd) / SHOT.HoldTime)
			camera.CFrame = shot(SHOT.Distance + (SHOT.EndDistance - SHOT.Distance) * k)
			camera.FieldOfView = SHOT.FieldOfView
		elseif t < outEnd then
			if not textHidden then
				textHidden = true
				fadeText(title, false)
				fadeText(description, false)
				TweenService:Create(top, BAR_TWEEN, { Size = UDim2.fromScale(1, 0) }):Play()
				TweenService:Create(bottom, BAR_TWEEN, { Size = UDim2.fromScale(1, 0) }):Play()
			end
			local a = smooth((t - holdEnd) / SHOT.BackTime)
			local start = shot(SHOT.EndDistance)
			camera.CFrame = start:Lerp(behind() or start, a)
			camera.FieldOfView = SHOT.FieldOfView + (fieldOfView - SHOT.FieldOfView) * a
		else
			finished:Fire()
		end
	end)
	finished.Event:Wait()
	RunService:UnbindFromRenderStep(RENDER_NAME)
	hideOwnCharacter(false)
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = fieldOfView
	local character = player.Character
	local ownHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if ownHumanoid then
		camera.CameraSubject = ownHumanoid
	end
	restore()
	overlay:Destroy()
	finished:Destroy()
	playing = false
end

function PetCutscene.isPlaying(): boolean
	return playing
end

function PetCutscene.start()
	cutsceneRemote.OnClientEvent:Connect(function(model: unknown, buffId: unknown)
		if typeof(model) == "Instance" and model:IsA("Model") then
			task.spawn(play, model, if typeof(buffId) == "string" then buffId else nil)
		end
	end)
end

return PetCutscene
