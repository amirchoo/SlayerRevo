--!strict
-- Blocking with a weapon that can (see BLOCK_AMOUNTS). While a player holds block with one out,
-- each hit has up to that weapon's block amount absorbed (the rest still gets through), using one of
-- BLOCK.MaxCharges charges; every used charge comes back BLOCK.RechargeTime seconds later.
-- Hits with no charges left go straight through.
-- A shield (see ShieldConfig) held with a one-handed weapon absorbs its BlockBonus on top, and
-- adds its ExtraCharges. Charges are counted as used ones (each waiting to come back), so
-- the shield's charge comes and goes with the weapon in hand without swapping refilling any.
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
local ShieldConfig = require(ReplicatedStorage.Shared.Config.ShieldConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local ParryWindow = require(ReplicatedStorage.Shared.ParryWindow)
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

-- When each player's guard went up, if that raise can still parry (see ParryRecovery),
-- and when they last raised it at all.
local parryableSince: { [Player]: number } = {}
local lastGuardRaise: { [Player]: number } = {}
-- Charges spent and not back yet, and a count bumped on respawn (when they all come back at
-- once) so recharges still pending from before don't count twice.
local usedCharges: { [Player]: number } = {}
local chargeRound: { [Player]: number } = {}

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

-- Block charges, with the player's skill bonus (see SkillTrees) and a raised shield's.
local function maxChargesOf(player: Player): number
	local shield = ShieldConfig.active(player)
	return BLOCK.MaxCharges + SkillMath.general(player, "BlockCharges") + (if shield then shield.ExtraCharges else 0)
end

local function chargesLeft(player: Player): number
	return math.max(maxChargesOf(player) - (usedCharges[player] or 0), 0)
end

-- Re-publishes block charges for the HUD after anything that changes them (skills, the
-- shield, the weapon in hand). A new charge is ready right away; a removed one is taken away.
function BlockService.refreshCharges(player: Player)
	player:SetAttribute("MaxBlockCharges", maxChargesOf(player))
	player:SetAttribute("BlockCharges", chargesLeft(player))
end

local function rechargeOne(player: Player)
	local round = chargeRound[player]
	task.delay(BLOCK.RechargeTime, function()
		if player.Parent and chargeRound[player] == round then
			usedCharges[player] = math.max((usedCharges[player] or 0) - 1, 0)
			BlockService.refreshCharges(player)
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
	if chargesLeft(player) <= 0 then
		return amount
	end

	usedCharges[player] = (usedCharges[player] or 0) + 1
	BlockService.refreshCharges(player)
	rechargeOne(player)
	guardHitRemote:FireClient(player, knockbackDirection(target, origin))
	local tool = target:FindFirstChildOfClass("Tool")
	local shield = ShieldConfig.active(player)
	local bonus = SkillMath.general(player, "BlockAmount")
		+ (if tool then SkillMath.weapon(player, tool.Name, "BlockAmount") else 0)
		+ (if shield then shield.BlockBonus else 0)
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
	local window = tool and ParryWindow.of(player, tool.Name)
	if not window or os.clock() - raisedAt > window then
		return false
	end

	parryableSince[player] = nil -- one parry per raise
	EnemyEffects.stun(attacker, BLOCK.ParryStun)
	EnemyEffects.recoil(attacker, BLOCK.ParryStun)
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
	local function onCharacter(player: Player, character: Model)
		-- All charges back on respawn.
		usedCharges[player] = 0
		chargeRound[player] = (chargeRound[player] or 0) + 1
		player:SetAttribute("Blocking", false)
		BlockService.refreshCharges(player)
		-- Drawing or putting away a one-handed weapon raises or lowers a worn shield.
		local function onToolChanged(child: Instance)
			if child:IsA("Tool") then
				BlockService.refreshCharges(player)
			end
		end
		character.ChildAdded:Connect(onToolChanged)
		character.ChildRemoved:Connect(onToolChanged)
	end
	local function onPlayerAdded(player: Player)
		usedCharges[player] = 0
		chargeRound[player] = 0
		player:SetAttribute("Blocking", false)
		BlockService.refreshCharges(player)
		player:GetAttributeChangedSignal("Shield"):Connect(function()
			BlockService.refreshCharges(player)
		end)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		parryableSince[player] = nil
		lastGuardRaise[player] = nil
		usedCharges[player] = nil
		chargeRound[player] = nil
	end)
	RemoteGuard.connect(blockRemote, onBlockRequest)
	HealthService.addDamageFilter(tryBlock)
end

return BlockService
