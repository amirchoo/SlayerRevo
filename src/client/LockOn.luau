--!strict
-- Lock-on: press the lock key (Q) or the touch Lock button to lock onto the enemy nearest the
-- middle of your view (within LockOn.Range and MaxAngle; training dummies count too).
-- While locked:
--   * your character keeps facing the target, so moving circles around it, and swings and
--     guards always point at it
--   * the camera follows from over your right shoulder, so you sit to the left of the view
--     and the target stays clear near the middle (and it doesn't clip through walls)
--   * a gold reticle marks the target; the bow aims straight at it (LockOn.target)
-- Press again to let go. When the target dies the lock moves to the next enemy in range (or
-- lets go); going past BreakRange lets go too. Client-only: it changes your camera and
-- facing; the server still decides every hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local CombatInput = require(script.Parent.CombatInput)
local HudStyle = require(script.Parent.HudStyle)

local LOCK = CombatConfig.LockOn
local RETICLE_COLOR = Color3.fromRGB(255, 210, 90)
local TARGET_FOLDERS = { "Enemies", "Animals", "TrainingGround", "TrainingCamp" } -- where lockable things live in workspace

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

-- The best target to lock onto: alive, in range, near the middle of the view, preferring
-- whatever's most centred and closest. `except` is skipped (e.g. the one that just died).
local function findTarget(except: Model?): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local best: Model?, bestScore = nil, math.huge
	local minDot = math.cos(math.rad(LOCK.MaxAngle))
	for _, folderName in TARGET_FOLDERS do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, model in folder:GetDescendants() do
				local owner = model:GetAttribute("SparringOwner") -- the training camp's: only your own
				if model:IsA("Model") and model ~= except and model:GetAttribute("Health") ~= nil and isAlive(model) and (owner == nil or owner == player.UserId) then
					local center = centerOf(model)
					if center then
						local offset = center - root.Position
						local distance = offset.Magnitude
						local direction = (center - camera.CFrame.Position).Unit
						local dot = look:Dot(direction)
						if distance <= LOCK.Range and dot >= minDot then
							local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
							local score = angle + distance * 0.6
							if score < bestScore then
								best, bestScore = model, score
							end
						end
					end
				end
			end
		end
	end
	return best
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

	local cameraPosition: Vector3? = nil
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Exclude

	local function setTarget(model: Model?)
		target = model
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if model then
			reticle.Adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			reticle.Enabled = true
			reticleScale.Scale = 1.6
			TweenService:Create(reticleScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			cameraPosition = workspace.CurrentCamera.CFrame.Position
		else
			reticle.Enabled = false
			reticle.Adornee = nil
			cameraPosition = nil
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

	-- Facing and camera, every frame, after Roblox's camera has updated (so ours wins).
	RunService:BindToRenderStep("LockOn", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local locked = target
		if not locked then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local center = centerOf(locked)
		if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			setTarget(nil)
			return
		end
		-- Dead or gone: move on to the next one in range (or let go). Too far: let go.
		if not center or not isAlive(locked) then
			setTarget(findTarget(locked))
			return
		end
		if (center - root.Position).Magnitude > LOCK.BreakRange then
			setTarget(nil)
			return
		end

		-- Face the target (flat), whatever else would turn the character.
		local flat = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
		if flat.Magnitude > 0.5 then
			humanoid.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end

		-- Camera: behind your shoulder, looking past you at the target, eased into place.
		local camera = workspace.CurrentCamera
		local origin = root.Position + Vector3.new(0, LOCK.CameraHeight * 0.5, 0)
		local direction = if flat.Magnitude > 0.5 then flat.Unit else root.CFrame.LookVector
		local right = direction:Cross(Vector3.yAxis) -- your right, as you face the target
		local desired = origin - direction * LOCK.CameraDistance + Vector3.new(0, LOCK.CameraHeight * 0.5, 0) + right * LOCK.CameraShoulder
		-- Don't go through walls between you and the camera.
		wallParams.FilterDescendantsInstances = { character, locked }
		local toCamera = desired - origin
		local hit = workspace:Raycast(origin, toCamera, wallParams)
		if hit then
			desired = hit.Position - toCamera.Unit * 0.6
		end
		local current = cameraPosition or camera.CFrame.Position
		local blend = 1 - math.exp(-LOCK.CameraSmoothing * dt)
		local position = current:Lerp(desired, blend)
		cameraPosition = position
		-- Look past your shoulder at the target, along the same line you're facing (offset to
		-- the right like the camera), so you stay on the left and the target near the middle.
		local focus = center + Vector3.new(0, LOCK.CameraFocusHeight, 0) + right * LOCK.CameraShoulder * LOCK.CameraFocusShift
		camera.CFrame = CFrame.lookAt(position, focus)

		diamond.Rotation += dt * 90
	end)
end

return LockOn
