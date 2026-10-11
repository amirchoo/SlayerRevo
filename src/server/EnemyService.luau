--!strict
-- Spawns enemies and runs their simple AI: chase the nearest player, then attack
-- after a short wind-up (so players can dodge). Dead enemies respawn after a delay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyEffects = require(script.Parent.EnemyEffects)
local HealthService = require(script.Parent.HealthService)
local SafeZone = require(ReplicatedStorage.Shared.SafeZone)

local LESSER_DEMON = {
	DisplayName = "Lesser Demon",
	MaxHealth = 200,
	WalkSpeed = 10,
	Color = Color3.fromRGB(120, 25, 30),
	AggroRange = 60, -- studs
	AttackRange = 5,
	AttackDamage = 30,
	AttackWindup = 0.4, -- seconds between starting the attack and the hit landing
	AttackCooldown = 1.5,
	RespawnDelay = 8,
}

-- Only X/Z matter: enemies are dropped onto whatever ground (terrain or parts) is below.
-- These are in the hunting grounds just north of the hub's edge.
local HUNTING_GROUNDS_Z = -SafeZone.HALF_SIZE - 55
local SPAWN_POINTS = {
	Vector2.new(0, HUNTING_GROUNDS_Z),
	Vector2.new(22, HUNTING_GROUNDS_Z - 20),
	Vector2.new(-22, HUNTING_GROUNDS_Z - 15),
}
local SPAWN_RAY_HEIGHT = 500
local SPAWN_HEIGHT_ABOVE_GROUND = 4

-- Default Roblox R15 animations.
local WALK_ANIMATION = "rbxassetid://507777826"
local ATTACK_ANIMATION = "rbxassetid://522635514"

local AI_TICK = 0.2

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
	animation.AnimationId = id
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
	local walkTrack = loadAnimation(animator, WALK_ANIMATION)
	local attackTrack = loadAnimation(animator, ATTACK_ANIMATION)

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
					attackTrack:Play()
					task.delay(LESSER_DEMON.AttackWindup, function()
						-- Re-check range after the wind-up so players can dodge out of it, and
						-- a stun during the wind-up cancels the attack.
						local stillInRange = (targetRoot.Position - root.Position).Magnitude <= LESSER_DEMON.AttackRange + 1
						if HealthService.isAlive(enemy) and stillInRange and not EnemyEffects.isStunned(enemy) then
							HealthService.damage(target, LESSER_DEMON.AttackDamage, nil, root.Position)
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

local function spawnEnemy(spawnPoint: Vector2)
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
		return
	end
	local enemy = result :: Model
	enemy.Name = LESSER_DEMON.DisplayName

	local humanoid = enemy:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = enemy:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayName = LESSER_DEMON.DisplayName
	humanoid.WalkSpeed = LESSER_DEMON.WalkSpeed
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn

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

	for _, spawnPoint in SPAWN_POINTS do
		task.spawn(spawnEnemy, spawnPoint)
	end
end

return EnemyService
