--!strict
-- Blocking with a melee weapon (sword, mace, spear, or greatsword). While a player holds block with one out,
-- each hit has up to that weapon's block amount absorbed (the rest still gets through), using one of
-- BLOCK.MaxCharges charges; every used charge comes back BLOCK.RechargeTime seconds later.
-- Hits with no charges left go straight through.
-- The client only says whether it's holding block; the server decides every block, and
-- tells the blocker's client (GuardHit) which way to be knocked back. The client applies
-- the shove itself because it controls its own character's movement.
-- State lives in player attributes (Blocking, BlockCharges, MaxBlockCharges) for the HUD.
-- Parry: an enemy hit landing within the weapon's ParryWindow of raising the guard is
-- negated outright (no charge used) and stuns the attacker. Enemies check this first with
-- tryParry before dealing damage. The guard time is the server's own, so it can't be faked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local EnemyEffects = require(script.Parent.EnemyEffects)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)

local BLOCK = CombatConfig.Blocking -- charges, recharge, and knockback are shared by all blades

-- Weapons that can block, and how much damage each absorbs per block.
local BLOCK_AMOUNTS: { [string]: number } = {
	[CombatConfig.Sword.ToolName] = CombatConfig.Sword.Block.BlockAmount,
	[CombatConfig.Emberfang.ToolName] = CombatConfig.Emberfang.Block.BlockAmount,
	[CombatConfig.Mace.ToolName] = CombatConfig.Mace.Block.BlockAmount,
	[CombatConfig.Spear.ToolName] = CombatConfig.Spear.Block.BlockAmount,
	[CombatConfig.Rapier.ToolName] = CombatConfig.Rapier.Block.BlockAmount,
	[CombatConfig.Axe.ToolName] = CombatConfig.Axe.Block.BlockAmount,
	[CombatConfig.DualBlade.ToolName] = CombatConfig.DualBlade.Block.BlockAmount,
	[CombatConfig.Scythe.ToolName] = CombatConfig.Scythe.Block.BlockAmount,
	[CombatConfig.Hammer.ToolName] = CombatConfig.Hammer.Block.BlockAmount,
	[CombatConfig.Staff.ToolName] = CombatConfig.Staff.BlockAmount,
	[CombatConfig.Grimoire.ToolName] = CombatConfig.Grimoire.BlockAmount,
	[CombatConfig.Greatsword.ToolName] = CombatConfig.Greatsword.BlockAmount,
}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local blockRemote = remotes:WaitForChild("SwordBlock") :: RemoteEvent
local guardHitRemote = remotes:WaitForChild("GuardHit") :: RemoteEvent

local BlockService = {}

-- How much the weapon in hand absorbs per block, or nil if it can't block.
local function blockAmountInHand(character: Model): number?
	local tool = character:FindFirstChildOfClass("Tool")
	return if tool then BLOCK_AMOUNTS[tool.Name] else nil
end

-- Seconds after raising the guard that a hit is parried, per weapon (heavier = shorter).
local PARRY_WINDOWS: { [string]: number } = {
	[CombatConfig.Sword.ToolName] = CombatConfig.Sword.Block.ParryWindow,
	[CombatConfig.Emberfang.ToolName] = CombatConfig.Emberfang.Block.ParryWindow,
	[CombatConfig.Mace.ToolName] = CombatConfig.Mace.Block.ParryWindow,
	[CombatConfig.Spear.ToolName] = CombatConfig.Spear.Block.ParryWindow,
	[CombatConfig.Rapier.ToolName] = CombatConfig.Rapier.Block.ParryWindow,
	[CombatConfig.Axe.ToolName] = CombatConfig.Axe.Block.ParryWindow,
	[CombatConfig.DualBlade.ToolName] = CombatConfig.DualBlade.Block.ParryWindow,
	[CombatConfig.Scythe.ToolName] = CombatConfig.Scythe.Block.ParryWindow,
	[CombatConfig.Hammer.ToolName] = CombatConfig.Hammer.Block.ParryWindow,
	[CombatConfig.Staff.ToolName] = CombatConfig.Staff.ParryWindow,
	[CombatConfig.Grimoire.ToolName] = CombatConfig.Grimoire.ParryWindow,
	[CombatConfig.Greatsword.ToolName] = CombatConfig.Greatsword.ParryWindow,
}

-- When each player's guard went up, if that raise can still parry (see ParryRecovery),
-- and when they last raised it at all.
local parryableSince: { [Player]: number } = {}
local lastGuardRaise: { [Player]: number } = {}

local function onBlockRequest(player: Player, wantsBlock: unknown)
	if typeof(wantsBlock) ~= "boolean" then
		return
	end
	local character = player.Character
	local canBlock = character ~= nil
		and HealthService.isAlive(character)
		and blockAmountInHand(character) ~= nil
		and player:GetAttribute("HeavyAttacking") ~= true -- can't guard mid-spin
	local blocking = wantsBlock and canBlock
	if blocking and player:GetAttribute("Blocking") ~= true then
		-- Guard going up: it opens a parry window, unless it was raised too recently.
		local now = os.clock()
		if now - (lastGuardRaise[player] or 0) >= BLOCK.ParryRecovery then
			parryableSince[player] = now
		else
			parryableSince[player] = nil
		end
		lastGuardRaise[player] = now
	elseif not blocking then
		parryableSince[player] = nil
	end
	player:SetAttribute("Blocking", blocking)
end

-- Block charges, with the player's skill bonus (see SkillTrees).
local function maxChargesOf(player: Player): number
	return BLOCK.MaxCharges + SkillMath.general(player, "BlockCharges")
end

-- Re-applies max block charges after the player's skills change.
function BlockService.refreshCharges(player: Player)
	local max = maxChargesOf(player)
	local old = player:GetAttribute("MaxBlockCharges")
	player:SetAttribute("MaxBlockCharges", max)
	local charges = player:GetAttribute("BlockCharges")
	if typeof(charges) == "number" then
		-- A new charge is ready right away; a removed one is taken away.
		local gained = if typeof(old) == "number" then max - old else 0
		player:SetAttribute("BlockCharges", math.clamp(charges + gained, 0, max))
	end
end

local function rechargeOne(player: Player)
	task.delay(BLOCK.RechargeTime, function()
		local charges = player:GetAttribute("BlockCharges")
		if player.Parent and typeof(charges) == "number" then
			player:SetAttribute("BlockCharges", math.min(charges + 1, maxChargesOf(player)))
		end
	end)
end

local function knockbackDirection(target: Model, origin: Vector3?): Vector3
	local root = target:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Vector3.zero
	end
	-- Away from the attacker, flat; without a known attacker, straight backwards.
	local away = if origin then root.Position - origin else -root.CFrame.LookVector
	local flat = Vector3.new(away.X, 0, away.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else -root.CFrame.LookVector
end

-- Damage filter: on a block, returns the damage left after absorbing the weapon's block amount
-- (0 if it was fully absorbed); otherwise the damage unchanged.
local function tryBlock(target: Model, amount: number, _source: Player?, origin: Vector3?): number
	local player = Players:GetPlayerFromCharacter(target)
	if not player or player:GetAttribute("Blocking") ~= true then
		return amount
	end
	-- Re-check the weapon: they may have switched without the client saying so.
	local blockAmount = blockAmountInHand(target)
	if not blockAmount then
		player:SetAttribute("Blocking", false)
		return amount
	end
	local charges = player:GetAttribute("BlockCharges")
	if typeof(charges) ~= "number" or charges <= 0 then
		return amount
	end

	player:SetAttribute("BlockCharges", charges - 1)
	rechargeOne(player)
	guardHitRemote:FireClient(player, knockbackDirection(target, origin))
	local tool = target:FindFirstChildOfClass("Tool")
	local bonus = SkillMath.general(player, "BlockAmount") + (if tool then SkillMath.weapon(player, tool.Name, "BlockAmount") else 0)
	return math.max(amount - (blockAmount + bonus), 0)
end

-- Called by an enemy as its hit lands on `target`: true if the player parried it (the hit
-- should then deal no damage). Stuns `attacker` and shows the parry.
function BlockService.tryParry(target: Model, attacker: Model): boolean
	local player = Players:GetPlayerFromCharacter(target)
	local raisedAt = player and parryableSince[player]
	if not player or not raisedAt or player:GetAttribute("Blocking") ~= true then
		return false
	end
	local tool = target:FindFirstChildOfClass("Tool")
	local window = tool and PARRY_WINDOWS[tool.Name]
	if tool and window then
		window += SkillMath.general(player, "ParryWindow") + SkillMath.weapon(player, tool.Name, "ParryWindow")
	end
	if not window or os.clock() - raisedAt > window then
		return false
	end

	parryableSince[player] = nil -- one parry per raise
	EnemyEffects.stun(attacker, BLOCK.ParryStun)
	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	local origin = if attackerRoot and attackerRoot:IsA("BasePart") then attackerRoot.Position else nil
	guardHitRemote:FireClient(player, knockbackDirection(target, origin), true)
	-- Everyone sees the clash: sparks between the two, and the attacker reeling.
	if origin then
		local impact, direction = HitEffects.meleeImpactPoint(target, origin)
		HitEffects.broadcast(attacker, impact, direction, "Parry", BLOCK.ParryStun * 50)
	end
	return true
end

function BlockService.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("MaxBlockCharges", maxChargesOf(player))
		player:SetAttribute("BlockCharges", maxChargesOf(player))
		player:SetAttribute("Blocking", false)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Blocking", false)
			player:SetAttribute("MaxBlockCharges", maxChargesOf(player))
			player:SetAttribute("BlockCharges", maxChargesOf(player))
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		parryableSince[player] = nil
		lastGuardRaise[player] = nil
	end)
	RemoteGuard.connect(blockRemote, onBlockRequest)
	HealthService.addDamageFilter(tryBlock)
end

return BlockService
