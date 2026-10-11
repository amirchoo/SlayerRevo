--!strict
-- Blocking with a melee weapon (sword, mace, spear, or greatsword). While a player holds block with one out,
-- each hit has up to that weapon's block amount absorbed (the rest still gets through), using one of
-- BLOCK.MaxCharges charges; every used charge comes back BLOCK.RechargeTime seconds later.
-- Hits with no charges left go straight through.
-- The client only says whether it's holding block; the server decides every block, and
-- tells the blocker's client (GuardHit) which way to be knocked back. The client applies
-- the shove itself because it controls its own character's movement.
-- State lives in player attributes (Blocking, BlockCharges, MaxBlockCharges) for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local HealthService = require(script.Parent.HealthService)

local BLOCK = CombatConfig.Blocking -- charges, recharge, and knockback are shared by all blades

-- Weapons that can block, and how much damage each absorbs per block.
local BLOCK_AMOUNTS: { [string]: number } = {
	[CombatConfig.Sword.ToolName] = CombatConfig.Sword.Block.BlockAmount,
	[CombatConfig.Mace.ToolName] = CombatConfig.Mace.Block.BlockAmount,
	[CombatConfig.Spear.ToolName] = CombatConfig.Spear.Block.BlockAmount,
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

local function onBlockRequest(player: Player, wantsBlock: unknown)
	if typeof(wantsBlock) ~= "boolean" then
		return
	end
	local character = player.Character
	local canBlock = character ~= nil and HealthService.isAlive(character) and blockAmountInHand(character) ~= nil
	player:SetAttribute("Blocking", wantsBlock and canBlock)
end

local function rechargeOne(player: Player)
	task.delay(BLOCK.RechargeTime, function()
		local charges = player:GetAttribute("BlockCharges")
		if player.Parent and typeof(charges) == "number" then
			player:SetAttribute("BlockCharges", math.min(charges + 1, BLOCK.MaxCharges))
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
	return math.max(amount - blockAmount, 0)
end

function BlockService.start()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("MaxBlockCharges", BLOCK.MaxCharges)
		player:SetAttribute("BlockCharges", BLOCK.MaxCharges)
		player:SetAttribute("Blocking", false)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Blocking", false)
			player:SetAttribute("BlockCharges", BLOCK.MaxCharges)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	blockRemote.OnServerEvent:Connect(onBlockRequest)
	HealthService.addDamageFilter(tryBlock)
end

return BlockService
