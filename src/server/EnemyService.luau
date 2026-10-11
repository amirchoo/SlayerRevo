--!strict
-- Spawns enemies and runs their simple AI: chase the nearest player, then attack
-- after a short wind-up (so players can dodge). Dead enemies respawn after a delay.
-- Looks: the enemy's Model from ServerStorage.EnemyModels (assets/enemies) if it's there,
-- an R15 character (with a Humanoid and HumanoidRootPart, e.g. made with Avatar Auto Setup);
-- otherwise a plain R15 body in the enemy's color.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BlockService = require(script.Parent.BlockService)
local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)

local LESSER_DEMON = EnemyConfig.LesserDemon
local SPAWN_RAY_HEIGHT = 500
local SPAWN_HEIGHT_ABOVE_GROUND = 4

local IDLE_ANIMATION = EnemyConfig.IdleAnimation
local WALK_ANIMATION = EnemyConfig.WalkAnimation
local DEFAULT_ATTACK_ANIMATION = EnemyConfig.DefaultAttackAnimation
local AI_TICK = EnemyConfig.AiTick

local EnemyService = {}

local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"

local spawnPointOf: { [Model]: Vector2 } = {}

local function groundCFrame(spawnPoint: Vector2): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemiesFolder }

	local origin = Vector3.new(spawnPoint.X, SPAWN_RAY_HEIGHT, spawnPoint.Y)
	local result = workspace:Raycast(origin, Vector3.new(0, -SPAWN_RAY_HEIGHT * 2, 0), params)
	if not result then
		warn(`[EnemyService] No ground under spawn point {spawnPoint}; the enemy may fall`)
	end
	local groundY = if result then result.Position.Y else 0
	return CFrame.new(spawnPoint.X, groundY + SPAWN_HEIGHT_ABOVE_GROUND, spawnPoint.Y)
end

local function loadAnimation(animator: Animator, id: string): AnimationTrack
	local animation = Instance.new("Animation")
	-- A bare number (e.g. pasted straight from the Creator Dashboard) still works.
	animation.AnimationId = if string.match(id, "^%d+$") then `rbxassetid://{id}` else id
	return animator:LoadAnimation(animation)
end

local function findNearestCharacter(position: Vector3, maxDistance: number): (Model?, BasePart?, number)
	local nearest: Model?, nearestRoot: BasePart? = nil, nil
	local nearestDistance = maxDistance
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- The town is a safe zone: players inside it are ignored.
		if
			character
			and root
			and root:IsA("BasePart")
			and not SafeZone.contains(root.Position)
			and HealthService.isAlive(character)
		then
			local distance = (root.Position - position).Magnitude
			if distance < nearestDistance then
				nearest, nearestRoot, nearestDistance = character, root, distance
			end
		end
	end
	return nearest, nearestRoot, nearestDistance
end

local function runAI(enemy: Model, humanoid: Humanoid, root: BasePart, home: Vector3)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	-- Idle always runs underneath, so the enemy never shows its rest pose (a T-pose for
	-- models made with Avatar Auto Setup); walking and attacking play over it.
	local idleTrack = loadAnimation(animator, IDLE_ANIMATION)
	idleTrack.Priority = Enum.AnimationPriority.Idle
	idleTrack.Looped = true
	idleTrack:Play()
	local walkTrack = loadAnimation(animator, WALK_ANIMATION)
	walkTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true
	local attackTrack = loadAnimation(animator, if LESSER_DEMON.AttackAnimation ~= "" then LESSER_DEMON.AttackAnimation else DEFAULT_ATTACK_ANIMATION)
	attackTrack.Priority = Enum.AnimationPriority.Action -- plays over the walk

	humanoid.Running:Connect(function(speed)
		if speed > 0.5 and not walkTrack.IsPlaying then
			walkTrack:Play()
		elseif speed <= 0.5 and walkTrack.IsPlaying then
			walkTrack:Stop()
		end
	end)

	local lastAttack = 0
	while enemy.Parent and HealthService.isAlive(enemy) do
		if EnemyEffects.isStunned(enemy) then
			humanoid:MoveTo(root.Position)
			attackTrack:Stop(0.1)
			task.wait(AI_TICK)
			continue
		end

		local target, targetRoot, distance = findNearestCharacter(root.Position, LESSER_DEMON.AggroRange)

		if target and targetRoot then
			if distance > LESSER_DEMON.AttackRange then
				humanoid:MoveTo(targetRoot.Position)
			else
				humanoid:MoveTo(root.Position)
				local lookAt = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
				root.CFrame = CFrame.lookAt(root.Position, lookAt)

				if os.clock() - lastAttack >= LESSER_DEMON.AttackCooldown then
					lastAttack = os.clock()
					attackTrack:Play(0.1)
					enemy:SetAttribute("Attacking", true) -- no flinching mid-attack (EnemyEffects.flinch)
					task.delay(LESSER_DEMON.AttackWindup, function()
						enemy:SetAttribute("Attacking", false)
						-- Re-check range after the wind-up so players can dodge out of it, and
						-- a stun during the wind-up cancels the attack.
						local stillInRange = (targetRoot.Position - root.Position).Magnitude <= LESSER_DEMON.AttackRange + 1
						if HealthService.isAlive(enemy) and stillInRange and not EnemyEffects.isStunned(enemy) then
							if BlockService.tryParry(target, enemy) then
								attackTrack:Stop(0.05) -- parried: knocked out of the swing
								return
							end
							local dealt = HealthService.damage(target, LESSER_DEMON.AttackDamage, nil, root.Position)
							if dealt > 0 then
								local impact, direction = HitEffects.meleeImpactPoint(target, root.Position)
								HitEffects.broadcast(target, impact, direction, "DemonClaw", dealt)
							end
						end
					end)
				end
			end
		elseif (root.Position - home).Magnitude > 4 then
			humanoid:MoveTo(home) -- no target: walk back to the spawn point
		else
			humanoid:MoveTo(root.Position)
		end

		task.wait(AI_TICK)
	end
end

-- The enemy's own R15 model, ready to spawn, or nil if it hasn't been added (or is unusable).
local function modelFromTemplate(): Model?
	local folder = ServerStorage:FindFirstChild("EnemyModels")
	local template = folder and folder:FindFirstChild(LESSER_DEMON.Model)
	if not template or not template:IsA("Model") then
		return nil
	end
	if not template:FindFirstChildOfClass("Humanoid") or not template:FindFirstChild("HumanoidRootPart") then
		warn(`[EnemyService] EnemyModels.{LESSER_DEMON.Model} needs a Humanoid and a HumanoidRootPart (an R15 rig); using the plain body`)
		return nil
	end
	local enemy = template:Clone()
	for _, descendant in enemy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false -- models are often saved anchored
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy() -- e.g. an "Animate" script; the AI plays its own animations
		end
	end
	local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") :: BasePart
	enemy.PrimaryPart = enemyRoot
	enemyRoot.Transparency = 1
	return enemy
end

-- A plain R15 body in the enemy's color.
local function plainBody(): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = LESSER_DEMON.Color
	description.TorsoColor = LESSER_DEMON.Color
	description.LeftArmColor = LESSER_DEMON.Color
	description.RightArmColor = LESSER_DEMON.Color
	description.LeftLegColor = LESSER_DEMON.Color
	description.RightLegColor = LESSER_DEMON.Color

	local ok, result = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[EnemyService] Failed to build enemy model:", result)
		return nil
	end
	return result :: Model
end

local function spawnEnemy(spawnPoint: Vector2)
	local enemy = modelFromTemplate() or plainBody()
	if not enemy then
		return
	end
	enemy.Name = LESSER_DEMON.DisplayName

	local humanoid = enemy:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = enemy:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayName = LESSER_DEMON.DisplayName
	humanoid.WalkSpeed = LESSER_DEMON.WalkSpeed
	-- The name and health bar are drawn by the client (EnemyHealthBars), not the Humanoid.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Only HealthService changes health; drop any default regen script.
	local regen = enemy:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end

	local spawnCFrame = groundCFrame(spawnPoint)
	enemy:PivotTo(spawnCFrame)
	enemy.Parent = enemiesFolder
	root:SetNetworkOwner(nil) -- server simulates enemy movement
	print(`[EnemyService] Spawned {enemy.Name} at {root.Position}`)

	spawnPointOf[enemy] = spawnPoint
	HealthService.register(enemy, LESSER_DEMON.MaxHealth)
	task.spawn(runAI, enemy, humanoid, root, spawnCFrame.Position)
end

-- Spawns one more enemy at X/Z (dropped onto the ground there); it respawns there too.
-- Yields while the model loads, so call it with task.spawn.
EnemyService.spawnAt = spawnEnemy

function EnemyService.start()
	enemiesFolder.Parent = workspace

	HealthService.Died:Connect(function(model: Model)
		local spawnPoint = spawnPointOf[model]
		if not spawnPoint then
			return
		end
		spawnPointOf[model] = nil

		task.delay(LESSER_DEMON.RespawnDelay, function()
			model:Destroy()
			spawnEnemy(spawnPoint)
		end)
	end)

	for _, spawnPoint in LESSER_DEMON.SpawnPoints do
		task.spawn(spawnEnemy, spawnPoint)
	end
end

return EnemyService
