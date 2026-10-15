--!strict
-- Server-authoritative shops: merchant consumables, blacksmith weapons, armorer armor, and
-- the butcher's meat (bought, and sold back for less: ShopSell).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Config.InventoryConfig)
local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ArmorService = require(script.Parent.ArmorService)
local ConsumableService = require(script.Parent.ConsumableService)
local CurrencyService = require(script.Parent.CurrencyService)
local HealthService = require(script.Parent.HealthService)
local InventoryService = require(script.Parent.InventoryService)
local MaterialService = require(script.Parent.MaterialService)
local NpcService = require(script.Parent.NpcService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyRemote = remotes:WaitForChild("ShopBuy") :: RemoteEvent
local sellRemote = remotes:WaitForChild("ShopSell") :: RemoteEvent

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
	if not item or item.Seller ~= sellerId or item.Category == ShopConfig.SellCategory then
		return -- not this shop's, or only bought back (Orc Skin)
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
	elseif item.Material then
		if MaterialConfig.item(item.Material) and CurrencyService.spend(player, item.Price) then
			if not MaterialService.grant(player, item.Material, 1) then
				CurrencyService.add(player, item.Price)
			end
		end
	elseif ShopConfig.consumable(item.Id) and CurrencyService.spend(player, item.Price) then
		ConsumableService.grant(player, item.Id, 1)
	end
end

-- Sells up to `amount` of an item back to the seller (as many as the player has).
local function onSell(player: Player, sellerId: unknown, itemId: unknown, amount: unknown)
	if typeof(sellerId) ~= "string" or typeof(itemId) ~= "string" or typeof(amount) ~= "number" or not atSeller(player, sellerId) then
		return
	end
	local item = ShopConfig.sellable(sellerId, itemId)
	if not (item and item.Material and item.SellPrice) then
		return
	end
	-- `amount == amount` rejects NaN.
	local count = if amount == amount then math.clamp(math.floor(amount), 0, ShopConfig.MaxSell) else 0
	local sold = MaterialService.take(player, item.Material, count)
	if sold > 0 then
		CurrencyService.add(player, sold * item.SellPrice)
	end
end

function ShopService.start()
	RemoteGuard.connect(buyRemote, onBuy)
	RemoteGuard.connect(sellRemote, onSell)
end

return ShopService
