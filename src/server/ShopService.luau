--!strict
-- Server-authoritative shops: merchant consumables, blacksmith weapons, armorer armor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ArmorService = require(script.Parent.ArmorService)
local ConsumableService = require(script.Parent.ConsumableService)
local CurrencyService = require(script.Parent.CurrencyService)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local NpcService = require(script.Parent.NpcService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopBuy") :: RemoteEvent

local ShopService = {}

local function atSeller(player: Player, sellerId: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local seller = NpcService.position(sellerId)
	if not (character and root and root:IsA("BasePart") and seller and HealthService.isAlive(character)) then
		return false
	end
	local flat = Vector3.new(root.Position.X - seller.X, 0, root.Position.Z - seller.Z)
	return flat.Magnitude <= NpcConfig.CloseDistance
end

local function onBuy(player: Player, sellerId: unknown, itemId: unknown)
	if typeof(sellerId) ~= "string" or typeof(itemId) ~= "string" or not atSeller(player, sellerId) then
		return
	end
	local item = ShopConfig.item(itemId)
	if not item or item.Seller ~= sellerId then
		return
	end
	if item.Weapon then
		if not InventoryConfig.weapon(item.Weapon) or InventoryService.owns(player, item.Weapon) then
			return
		end
		if CurrencyService.spend(player, item.Price) then
			InventoryService.grant(player, item.Weapon)
		end
	elseif item.ArmorSet then
		if not ArmorService.ownsSet(player, item.ArmorSet) and CurrencyService.spend(player, item.Price) then
			ArmorService.giveSet(player, item.ArmorSet)
		end
	elseif ShopConfig.consumable(item.Id) and CurrencyService.spend(player, item.Price) then
		ConsumableService.grant(player, item.Id, 1)
	end
end

function ShopService.start()
	RemoteGuard.connect(buyRemote, onBuy)
end

return ShopService
