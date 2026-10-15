--!strict
-- Lock-on: press the lock key (Q), R3, or the touch Lock button to lock onto the enemy nearest
-- the middle of your view (within LockOn.Range and MaxAngle; training dummies count too).
-- While locked:
--   * your character keeps facing the target, so moving circles around it, and swings and
--     guards always point at it
--   * the camera orbits behind you and off to your right, so you're low on the left and the
--     target is clear on the right. Up close it's a wide two-shot (you see the enemy's whole
--     wind-up, to time a parry); with a ranged or magic weapon out it closes in over your
--     shoulder and aims straight at the target. It pulls back for big targets, swings round
--     smoothly as you circle, and doesn't clip through walls
--   * flick the mouse sideways, push the right stick left or right, or swipe across the
--     screen to switch to the next enemy on that side
--   * a gold reticle marks the target; the bow and staff aim straight at it (LockOn.target)
-- Press again to let go. When the target dies the lock moves to the next enemy in range (or
-- lets go); going past BreakRange lets go too. Client-only: it changes your camera and
-- facing; the server still decides every hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local CombatInput = require(script.Parent.CombatInput)
local Gamepad = require(script.Parent.Gamepad)
local HudStyle = require(script.Parent.HudStyle)

local LOCK = CombatConfig.LockOn
local RETICLE_COLOR = Color3.fromRGB(255, 210, 90)
local TARGET_FOLDERS = { "Enemies", "Animals", "TrainingGround", "TrainingCamp" } -- where lockable things live in workspace
local RANGED_CLASSES: { [string]: boolean } = { Ranged = true, Magic = true } -- weapons that get the over-the-shoulder framing
local CHEST_HEIGHT = 1.5 -- studs above your root the camera orbits round

local player = Players.LocalPlayer

local LockOn = {}

local target: Model? = nil

-- The locked target, if any (e.g. for the bow's aim).
function LockOn.target(): Model?
	return target
end

-- Where to look at a model: its root, or its middle.
local function centerOf(model: Model): Vector3?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	if model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true) then
		return model:GetBoundingBox().Position
	end
	return nil
end

local function isAlive(model: Model): boolean
	local health = model:GetAttribute("Health")
	return model.Parent ~= nil and typeof(health) == "number" and health > 0
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The signed angle (radians) from flat direction a round to flat direction b; positive is
-- to the right (clockwise seen from above).
local function signedAngle(a: Vector3, b: Vector3): number
	local right = a:Cross(Vector3.yAxis)
	return math.atan2(b:Dot(right), b:Dot(a))
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Every lockable thing in range of `from` (alive, and in the training camp only your own),
-- with where it is.
local function candidates(from: Vector3): { { model: Model, center: Vector3 } }
	local found = {}
	for _, folderName in TARGET_FOLDERS do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, model in folder:GetDescendants() do
				if model:IsA("Model") and model:GetAttribute("Health") ~= nil and isAlive(model) then
					local owner = model:GetAttribute("SparringOwner") -- the training camp's: only your own
					local center = centerOf(model)
					if (owner == nil or owner == player.UserId) and center and (center - from).Magnitude <= LOCK.Range then
						table.insert(found, { model = model, center = center })
					end
				end
			end
		end
	end
	return found
end

-- The best target to lock onto: in range, near the middle of the view, preferring whatever's
-- most centred and closest. `except` is skipped (e.g. the one that just died).
local function findTarget(except: Model?): Model?
	local root = myRoot()
	if not root then
		return nil
	end
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local best: Model?, bestScore = nil, math.huge
	local minDot = math.cos(math.rad(LOCK.MaxAngle))
	for _, item in candidates(root.Position) do
		if item.model ~= except then
			local dot = look:Dot((item.center - camera.CFrame.Position).Unit)
			if dot >= minDot then
				local score = math.deg(math.acos(math.clamp(dot, -1, 1))) + (item.center - root.Position).Magnitude * 0.6
				if score < bestScore then
					best, bestScore = item.model, score
				end
			end
		end
	end
	return best
end

-- The next target from the current one towards `side` (1 right, -1 left) as the camera sees
-- it: the smallest turn that way, then the closest.
local function findSwitch(current: Model, side: number): Model?
	local root = myRoot()
	local currentCenter = centerOf(current)
	if not root or not currentCenter then
		return nil
	end
	local eye = workspace.CurrentCamera.CFrame.Position
	local toCurrent = flat(currentCenter - eye)
	if toCurrent.Magnitude < 0.1 then
		return nil
	end
	toCurrent = toCurrent.Unit
	local best: Model?, bestScore = nil, math.huge
	for _, item in candidates(root.Position) do
		local toItem = flat(item.center - eye)
		if item.model ~= current and toItem.Magnitude > 0.1 then
			local angle = math.deg(signedAngle(toCurrent, toItem.Unit)) * side
			if angle > 1 then
				local score = angle + (item.center - root.Position).Magnitude * 0.3
				if score < bestScore then
					best, bestScore = item.model, score
				end
			end
		end
	end
	return best
end

-- True while the tool in hand is a ranged or magic weapon.
local function holdingRanged(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	local info = tool and InventoryConfig.weapon(tool.Name)
	return info ~= nil and RANGED_CLASSES[info.Class] == true
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function LockOn.start()
	-- The reticle: a gold ring with a turning diamond, over the target (only you see it).
	local reticle = Instance.new("BillboardGui")
	reticle.Name = "LockOnReticle"
	reticle.Size = UDim2.fromOffset(30, 30) -- small, so it doesn't hide small enemies
	reticle.AlwaysOnTop = true
	reticle.LightInfluence = 0
	reticle.Enabled = false
	reticle.ResetOnSpawn = false -- otherwise respawning deletes it, and later locks show no marker
	reticle.Parent = player:WaitForChild("PlayerGui")
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.8, 0.8)
	ring.BackgroundTransparency = 1
	ring.Parent = reticle
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = RETICLE_COLOR
	ringStroke.Thickness = 2
	ringStroke.Parent = ring
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(0.42, 0.42)
	diamond.BackgroundTransparency = 1
	diamond.Rotation = 45
	diamond.Parent = reticle
	local diamondStroke = Instance.new("UIStroke")
	diamondStroke.Color = RETICLE_COLOR
	diamondStroke.Thickness = 1.5
	diamondStroke.Parent = diamond
	local reticleScale = Instance.new("UIScale")
	reticleScale.Parent = ring

	-- "No target in range", when there's nothing to lock onto.
	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "LockOnHint"
	hintGui.ResetOnSpawn = false
	hintGui.Parent = player:WaitForChild("PlayerGui")
	local hint = HudStyle.caption(HudStyle.holder(hintGui, Vector2.new(0.5, 0.5)), "No target in range", 18)
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.new(0.5, 0, 0.5, 60)
	hint.Size = UDim2.fromOffset(260, 24)
	hint.TextColor3 = Color3.fromRGB(220, 215, 230)
	hint.Visible = false
	local hintToken = 0
	local function showNoTarget()
		hintToken += 1
		local mine = hintToken
		hint.Visible = true
		task.delay(1.2, function()
			if mine == hintToken then
				hint.Visible = false
			end
		end)
	end

	-- The camera's state while locked, eased each frame towards where the framing wants it.
	local yaw = 0 -- the direction from you to the target the camera is set behind (radians)
	local focus: Vector3? = nil -- the point the camera aims at
	local angle, distance, height = 0, 0, 0
	local enterFrom: CFrame? = nil -- where the camera was when the lock started...
	local enteredAt = 0 -- ...and when
	local targetHeight = 0 -- how tall the target is (bigger ones push the camera back)
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Exclude

	local function yawOf(direction: Vector3): number
		return math.atan2(direction.X, direction.Z)
	end

	local function setTarget(model: Model?, switching: boolean?)
		local was = target
		target = model
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if model then
			reticle.Adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			reticle.Enabled = true
			reticleScale.Scale = 1.6
			TweenService:Create(reticleScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			targetHeight = model:GetExtentsSize().Y
			if not was and not switching then
				-- A fresh lock: start the orbit from where the camera already looks, and glide in.
				local camera = workspace.CurrentCamera
				local look = flat(camera.CFrame.LookVector)
				yaw = if look.Magnitude > 0.01 then yawOf(look) else 0
				focus = nil
				angle, distance, height = LOCK.Melee.Angle, LOCK.Melee.Distance, LOCK.Melee.Height
				enterFrom = camera.CFrame
				enteredAt = os.clock()
			end
		else
			reticle.Enabled = false
			reticle.Adornee = nil
			focus = nil
			enterFrom = nil
			if humanoid then
				humanoid.AutoRotate = true
			end
		end
	end

	CombatInput.Lock:Connect(function()
		if target then
			setTarget(nil)
			return
		end
		local found = findTarget(nil)
		setTarget(found)
		if not found then
			showNoTarget()
		end
	end)
	player.CharacterAdded:Connect(function()
		setTarget(nil)
	end)

	-- Switching targets: a sideways mouse flick, the right stick, or a swipe.
	local lastSwitch = 0
	local function switch(side: number)
		local current = target
		local now = os.clock()
		if not current or now - lastSwitch < LOCK.SwitchCooldown then
			return
		end
		lastSwitch = now
		local nextTarget = findSwitch(current, side)
		if nextTarget then
			setTarget(nextTarget, true)
		end
	end
	local flick, flickAt = 0, 0
	local stickArmed = true
	UserInputService.InputChanged:Connect(function(input)
		if not target then
			flick, stickArmed = 0, true
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local now = os.clock()
			flick = flick * math.exp(-(now - flickAt) / LOCK.SwitchFlickTime) + input.Delta.X
			flickAt = now
			if math.abs(flick) >= LOCK.SwitchFlick then
				switch(math.sign(flick))
				flick = 0
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and not Gamepad.inMenu() then
			local x = input.Position.X
			if stickArmed and math.abs(x) >= LOCK.SwitchStick then
				stickArmed = false
				switch(math.sign(x))
			elseif math.abs(x) < 0.35 then
				stickArmed = true
			end
		end
	end)
	local swipes: { [InputObject]: { start: Vector3, at: number } } = {}
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Touches on buttons or the move stick are the game's; the rest of the screen is the camera's.
		if input.UserInputType == Enum.UserInputType.Touch and not gameProcessed and target then
			swipes[input] = { start = input.Position, at = os.clock() }
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local swipe = swipes[input]
		if not swipe then
			return
		end
		swipes[input] = nil
		local moved = input.Position - swipe.start
		if os.clock() - swipe.at < 0.45 and math.abs(moved.X) >= LOCK.SwitchSwipe and math.abs(moved.X) > math.abs(moved.Y) * 1.5 then
			switch(math.sign(moved.X))
		end
	end)

	-- Facing and camera, every frame, after Roblox's camera has updated (so ours wins).
	RunService:BindToRenderStep("LockOn", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local locked = target
		if not locked then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = myRoot()
		local center = centerOf(locked)
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			setTarget(nil)
			return
		end
		-- Dead or gone: move on to the next one in range (or let go). Too far: let go.
		if not center or not isAlive(locked) then
			setTarget(findTarget(locked), true)
			return
		end
		local toTarget = flat(center - root.Position)
		local separation = toTarget.Magnitude
		if (center - root.Position).Magnitude > LOCK.BreakRange then
			setTarget(nil)
			return
		end

		-- Face the target (flat), whatever else would turn the character.
		if separation > 1 then
			humanoid.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, root.Position + toTarget)
		end

		-- The framing for now: melee up close, over the shoulder for a ranged weapon further out.
		local far = math.clamp(separation / LOCK.FarDistance, 0, 1)
		local ranged = if holdingRanged(character) then math.clamp((separation - LOCK.RangedFrom) / 10, 0, 1) else 0
		local M, R = LOCK.Melee, LOCK.Ranged
		local big = math.max(0, targetHeight - LOCK.BigTarget)
		local wantAngle = lerp(lerp(M.Angle, M.FarAngle, far), lerp(R.Angle, R.FarAngle, far), ranged)
		local wantDistance = lerp(lerp(M.Distance, M.FarDistance, far), lerp(R.Distance, R.FarDistance, far), ranged) + big * LOCK.BigBack
		local wantHeight = lerp(M.Height, R.Height, ranged) + big * LOCK.BigUp
		local wantFocus = lerp(lerp(M.Focus, M.FarFocus, far), lerp(R.Focus, R.FarFocus, far), ranged)

		local zoom = 1 - math.exp(-LOCK.ZoomSpeed * dt)
		angle = lerp(angle, wantAngle, zoom)
		distance = lerp(distance, wantDistance, zoom)
		height = lerp(height, wantHeight, zoom)

		-- Swing round behind you (by the shortest way) as the target moves.
		if separation > 1 then
			local turn = (yawOf(toTarget) - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += turn * (1 - math.exp(-LOCK.TurnSpeed * dt))
		end
		local forward = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local right = forward:Cross(Vector3.yAxis)
		local pivot = root.Position + Vector3.new(0, CHEST_HEIGHT, 0)
		local turnRad = math.rad(angle)
		local back = -forward * math.cos(turnRad) + right * math.sin(turnRad)
		local desired = pivot + back * distance + Vector3.new(0, height, 0)

		-- Aim between you and the target (at its middle, or its chest if it's big).
		local aimAt = center + Vector3.new(0, math.min(big * 0.25, 2), 0)
		local wantFocusPoint = pivot:Lerp(aimAt, wantFocus)
		local current = focus or wantFocusPoint
		local focusPoint = current:Lerp(wantFocusPoint, 1 - math.exp(-LOCK.FocusSpeed * dt))
		focus = focusPoint

		-- Don't go through walls between you and the camera (pulled in at once, eased out above).
		wallParams.FilterDescendantsInstances = { character, locked }
		local toCamera = desired - pivot
		local hit = workspace:Spherecast(pivot, 0.5, toCamera, wallParams)
		if hit then
			desired = pivot + toCamera.Unit * math.max(hit.Distance - 0.2, 1)
		end

		local camera = workspace.CurrentCamera
		local frame = CFrame.lookAt(desired, focusPoint)
		-- Glide in from where the camera was when the lock started.
		local from = enterFrom
		if from then
			local t = (os.clock() - enteredAt) / LOCK.EnterTime
			if t >= 1 then
				enterFrom = nil
			else
				frame = from:Lerp(frame, 1 - (1 - t) ^ 3)
			end
		end
		camera.CFrame = frame * CFrame.new(humanoid.CameraOffset) -- hit and block shakes still show

		diamond.Rotation += dt * 90
	end)
end

return LockOn
