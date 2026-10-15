--!strict
-- Plays the parry clang the instant a parried claw lands on this screen, instead of a
-- network trip later when the server's verdict arrives. The server still decides every parry
-- (BlockService); this only predicts it, with the same rules: the guard went up within the
-- weapon's parry window (ParryWindow) before the enemy's attack reaches its hit frame, the
-- raise wasn't a mash (Blocking.ParryRecovery), and the enemy is close enough to hit us. When
-- the server's parry effect for that enemy arrives, HitEffectsClient skips its own clang
-- (`consume`). The weapon controllers report the guard (`guardUp` / `guardDown`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local ParryWindow = require(ReplicatedStorage.Shared.ParryWindow)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local BLOCK = CombatConfig.Blocking
local REACH_SLACK = 1.5 -- studs past an enemy's AttackRange still counted (the server allows +1)
local MATCH_TIME = 1 -- seconds a prediction waits for the server's parry of the same enemy

local player = Players.LocalPlayer

local ParryPredict = {}

local raisedAt: number? = nil -- when the guard went up, while that raise can still parry
local lastRaise = 0
local predicted: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Each enemy attack animation (by asset number): when in the clip its hit lands, and its reach.
type Attack = { hit: number, reach: number }
local attacks: { [string]: Attack } = {}
for _, kind in EnemyConfig :: { [string]: any } do
	if typeof(kind) == "table" and typeof(kind.AttackAnimation) == "string" and typeof(kind.AttackWindup) == "number" then
		local number = string.match(kind.AttackAnimation, "%d+")
		if number then
			attacks[number] = { hit = kind.AttackWindup, reach = kind.AttackRange }
		end
	end
end

function ParryPredict.guardUp()
	local now = os.clock()
	raisedAt = if now - lastRaise >= BLOCK.ParryRecovery then now else nil
	lastRaise = now
end

function ParryPredict.guardDown()
	raisedAt = nil
end

-- True (once) if we already played the clang for a parry of `enemy` just now.
function ParryPredict.consume(enemy: Model?): boolean
	local at = enemy and predicted[enemy]
	if enemy and at then
		predicted[enemy] = nil
		return os.clock() - at < MATCH_TIME
	end
	return false
end

-- The enemy's claw reached its hit frame on this screen: is it a parry?
local function onHitFrame(enemy: Model, attack: Attack)
	local guardTime = raisedAt
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not guardTime or not root or not root:IsA("BasePart") or not enemyRoot or not enemyRoot:IsA("BasePart") or not tool then
		return
	end
	local window = ParryWindow.of(player, tool.Name)
	if not window or os.clock() - guardTime > window then
		return
	end
	if (root.Position - enemyRoot.Position).Magnitude > attack.reach + REACH_SLACK then
		return
	end
	raisedAt = nil -- one parry per raise, like the server
	predicted[enemy] = os.clock()
	local clash = Instance.new("Attachment")
	clash.WorldPosition = (root.Position + enemyRoot.Position) / 2
	clash.Parent = workspace.Terrain
	Sounds.play("ParryHit", clash)
	task.delay(3, function()
		clash:Destroy()
	end)
end

local function watchTrack(enemy: Model, track: AnimationTrack)
	local number = string.match(track.Animation and track.Animation.AnimationId or "", "%d+")
	local attack = number and attacks[number]
	if not attack then
		return
	end
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not track.IsPlaying or not enemy.Parent then
			connection:Disconnect()
		elseif track.TimePosition >= attack.hit then
			connection:Disconnect()
			onHitFrame(enemy, attack)
		end
	end)
end

local function watchEnemy(enemy: Instance)
	if not enemy:IsA("Model") then
		return
	end
	task.spawn(function()
		local humanoid = enemy:WaitForChild("Humanoid", 10)
		local animator = humanoid and humanoid:WaitForChild("Animator", 10)
		if animator and animator:IsA("Animator") then
			animator.AnimationPlayed:Connect(function(track)
				watchTrack(enemy, track)
			end)
		end
	end)
end

function ParryPredict.start()
	task.spawn(function()
		local enemies = workspace:WaitForChild("Enemies")
		enemies.ChildAdded:Connect(watchEnemy)
		for _, enemy in enemies:GetChildren() do
			watchEnemy(enemy)
		end
	end)
	player.CharacterAdded:Connect(function()
		raisedAt = nil
	end)
end

return ParryPredict
