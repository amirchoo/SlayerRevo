--!strict
-- Bow input and draw visuals. While equipped the idle animation loops. Hold right-click to
-- draw (the charge animation plays, the string pulls back with an arrow nocked, a power
-- meter fills, the camera zooms in, the player slows and faces the aim), release to fire
-- (the shoot animation plays, the camera zooms back out). The server times the draw itself and owns
-- ammo, the arrow's flight, and damage. The animations replicate to other players; the
-- string, nocked arrow, and meter are local only.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HandGrip = require(ReplicatedStorage.Shared.HandGrip)

local BOW = CombatConfig.Bow
local AIM_DISTANCE = 1000
local METER_COLOR = Color3.fromRGB(240, 240, 240)
local METER_FULL_COLOR = Color3.fromRGB(255, 200, 70)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local drawRemote = remotes:WaitForChild("BowDraw") :: RemoteEvent
local shootRemote = remotes:WaitForChild("BowShoot") :: RemoteEvent

local BowClient = {}

local hookedTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastShot = 0

local function makeAnimation(id: string): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	return animation
end

local IDLE_ANIMATION = makeAnimation(BOW.IdleAnimation)
local DRAW_ANIMATION = makeAnimation(BOW.ChargeAnimation)
local RELEASE_ANIMATION = makeAnimation(BOW.ShootAnimation)
local HOLD_MARGIN = 0.05 -- pause the draw this close to its end so it holds the full-draw pose

type BowTracks = { idle: AnimationTrack, draw: AnimationTrack, release: AnimationTrack }
local tracksByHumanoid: { [Humanoid]: BowTracks } = setmetatable({}, { __mode = "k" }) :: any

local function getTracks(humanoid: Humanoid): BowTracks?
	local cached = tracksByHumanoid[humanoid]
	if cached then
		return cached
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local tracks = {
		idle = animator:LoadAnimation(IDLE_ANIMATION),
		draw = animator:LoadAnimation(DRAW_ANIMATION),
		release = animator:LoadAnimation(RELEASE_ANIMATION),
	}
	-- Set here so it doesn't matter how each animation was published:
	-- the idle sits above the default walk/idle, and drawing/shooting play over the idle.
	tracks.idle.Priority = Enum.AnimationPriority.Idle
	tracks.idle.Looped = true
	tracks.draw.Priority = Enum.AnimationPriority.Action
	tracks.draw.Looped = false
	tracks.release.Priority = Enum.AnimationPriority.Action
	tracks.release.Looped = false
	tracksByHumanoid[humanoid] = tracks
	return tracks
end

-- The camera's field of view before the bow zoomed it; kept until the zoom-out finishes, so
-- drawing again mid zoom-out still returns to the real original.
local normalFov: number? = nil
local zoomOutTween: Tween? = nil

-- Set while the player is holding a draw; `fired` is false when the draw is cancelled.
local stopDraw: ((fired: boolean) -> ())? = nil

-- The world point under the cursor (or the screen center when the mouse is locked),
-- ignoring our own character and arrows in flight.
local function getAimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local screenPoint = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)

	local exclude: { Instance } = { camera }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local arrows = workspace:FindFirstChild("Arrows")
	if arrows then
		table.insert(exclude, arrows)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
	return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
end

local function createMeter(): (Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BowPowerMeter"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.fromScale(0.5, 0.6)
	background.Size = UDim2.fromOffset(160, 8)
	background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	background.BackgroundTransparency = 0.3
	background.BorderSizePixel = 0
	background.Visible = false
	background.Parent = gui
	Instance.new("UICorner").Parent = background

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = METER_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = background
	Instance.new("UICorner").Parent = fill

	return background, fill
end

local meter, meterFill = createMeter()

local function localPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace.CurrentCamera -- parts under the camera exist only for this player
	return part
end

local function startDraw(tool: Tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local handle = tool:FindFirstChild(HandGrip.GRIP_NAME)
	local upperTip = handle and handle:FindFirstChild("UpperTip")
	local lowerTip = handle and handle:FindFirstChild("LowerTip")
	local bowString = tool:FindFirstChild("String")
	if
		not humanoid
		or not root
		or not root:IsA("BasePart")
		or not handle
		or not handle:IsA("BasePart")
		or not upperTip
		or not upperTip:IsA("Attachment")
		or not lowerTip
		or not lowerTip:IsA("Attachment")
	then
		return
	end
	-- Pin the checked types for use inside the per-frame callback below.
	local hum, rootPart, grip = humanoid :: Humanoid, root :: BasePart, handle :: BasePart
	local upper, lower = upperTip :: Attachment, lowerTip :: Attachment

	drawRemote:FireServer()
	local startTime = os.clock()

	-- Slow down and face the aim while drawing.
	local walkSpeed, autoRotate = hum.WalkSpeed, hum.AutoRotate
	hum.WalkSpeed = BOW.DrawWalkSpeed
	hum.AutoRotate = false

	-- Swap the straight string for two local segments meeting at a pulled-back nock point.
	if bowString and bowString:IsA("BasePart") then
		bowString.LocalTransparencyModifier = 1
	end
	local stringColor = Color3.fromRGB(235, 230, 215)
	local upperSegment = localPart("DrawnString", Vector3.new(0.05, 0.05, 1), stringColor, Enum.Material.SmoothPlastic)
	local lowerSegment = localPart("DrawnString", Vector3.new(0.05, 0.05, 1), stringColor, Enum.Material.SmoothPlastic)
	local nockedArrow = localPart("NockedArrow", Vector3.new(0.15, 0.15, 3), Color3.fromRGB(200, 170, 120), Enum.Material.Wood)

	meter.Visible = true

	local camera = workspace.CurrentCamera
	if zoomOutTween then
		zoomOutTween:Cancel()
		zoomOutTween = nil
	end
	normalFov = normalFov or camera.FieldOfView
	local baseFov = normalFov :: number
	local startFov = camera.FieldOfView -- may be mid zoom-out; continue from here without a jump

	-- Play the draw so it reaches full draw exactly when power hits 1.
	local tracks = getTracks(hum)
	if tracks then
		local length = tracks.draw.Length
		tracks.release:Stop(0)
		tracks.draw:Play(0.1, 1, if length > 0 then length / BOW.MaxDrawTime else 1)
	end

	local function segment(part: Part, from: Vector3, to: Vector3)
		part.Size = Vector3.new(0.05, 0.05, (to - from).Magnitude)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
	end

	local connection = RunService.RenderStepped:Connect(function()
		local power = math.clamp((os.clock() - startTime) / BOW.MaxDrawTime, 0, 1)

		-- The string pulls straight back from the grip; "forward" is grip-from-string.
		local top, bottom = upper.WorldPosition, lower.WorldPosition
		local restNock = (top + bottom) / 2
		local forward = (grip.Position - restNock).Unit
		local nock = restNock - forward * BOW.DrawPull * power
		segment(upperSegment, top, nock)
		segment(lowerSegment, bottom, nock)
		nockedArrow.CFrame = CFrame.lookAt(nock + forward * 1.5, nock + forward * 3)

		-- Turn to face the aim (horizontally).
		local aim = getAimPoint()
		local flat = Vector3.new(aim.X - rootPart.Position.X, 0, aim.Z - rootPart.Position.Z)
		if flat.Magnitude > 0.1 then
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flat)
		end

		-- Freeze on the last frame instead of letting the non-looping track end.
		if tracks then
			local draw = tracks.draw
			if draw.IsPlaying and draw.Speed > 0 and draw.Length > 0 and draw.TimePosition >= draw.Length - HOLD_MARGIN then
				draw:AdjustSpeed(0)
			end
		end
		-- Zoom in with the draw, fast at first then settling (ease-out).
		local eased = 1 - (1 - power) ^ 2
		local zoomedFov = math.min(startFov, BOW.DrawZoomFov + (baseFov - BOW.DrawZoomFov) * (1 - eased))
		camera.FieldOfView = zoomedFov
		meterFill.Size = UDim2.fromScale(power, 1)
		meterFill.BackgroundColor3 = if power >= 1 then METER_FULL_COLOR else METER_COLOR
	end)

	stopDraw = function(fired: boolean)
		stopDraw = nil
		connection:Disconnect()

		local tween = TweenService:Create(camera, TweenInfo.new(BOW.ZoomOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		})
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and zoomOutTween == tween then
				zoomOutTween = nil
				normalFov = nil
			end
		end)
		zoomOutTween = tween
		tween:Play()
		if tracks then
			if fired then
				tracks.draw:Stop(0.05)
				tracks.release:Play(0.05)
			else
				tracks.draw:Stop(0.2)
			end
		end
		upperSegment:Destroy()
		lowerSegment:Destroy()
		nockedArrow:Destroy()
		if bowString and bowString:IsA("BasePart") then
			bowString.LocalTransparencyModifier = 0
		end
		hum.WalkSpeed = walkSpeed
		hum.AutoRotate = autoRotate
		meter.Visible = false
		meterFill.Size = UDim2.fromScale(0, 1)
	end
end

local function equippedBow(): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if tool and tool.Name == BOW.ToolName then tool else nil
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton2 or stopDraw then
		return
	end
	local tool = equippedBow()
	local arrows = player:GetAttribute("Arrows")
	-- Local checks only avoid pointless requests; the server enforces the real ones.
	if not tool or typeof(arrows) ~= "number" or arrows <= 0 or os.clock() - lastShot < BOW.Cooldown then
		return
	end
	startDraw(tool)
end

local function onInputEnded(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 or not stopDraw then
		return
	end
	local aimPoint = getAimPoint()
	stopDraw(true)
	lastShot = os.clock()
	shootRemote:FireServer(aimPoint)
end

local function hookTool(child: Instance)
	if not child:IsA("Tool") or child.Name ~= BOW.ToolName then
		return
	end
	-- Equipping moves the tool into the character: weld it into its hand locally right
	-- away; the server adds the replicated weld (see HandGrip).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and child.Parent == character then
		HandGrip.attachLocal(child, character, BOW.Hand :: HandGrip.Hand, "BowGrip")
		local tracks = humanoid and getTracks(humanoid)
		if tracks then
			tracks.idle:Play(0.2)
		end
	end

	if not hookedTools[child] then
		hookedTools[child] = true
		child.Unequipped:Connect(function()
			HandGrip.detach(child, "LocalBowGrip")
			local currentHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local tracks = currentHumanoid and tracksByHumanoid[currentHumanoid]
			if tracks then
				tracks.idle:Stop(0.2)
			end
			-- Putting the bow away mid-draw cancels the shot.
			if stopDraw then
				stopDraw(false)
			end
		end)
	end
end

function BowClient.start()
	-- Load the animations up front so the first draw doesn't stall or have Length 0.
	task.spawn(function()
		ContentProvider:PreloadAsync({ IDLE_ANIMATION, DRAW_ANIMATION, RELEASE_ANIMATION })
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	local function onCharacterAdded(character: Model)
		-- A respawn mid-draw cancels it.
		if stopDraw then
			stopDraw(false)
		end
		-- Tools move into the character when equipped.
		character.ChildAdded:Connect(hookTool)
		for _, child in character:GetChildren() do
			hookTool(child)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return BowClient
