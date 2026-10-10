--!strict
-- Server-authoritative health for any Model (player characters and monsters).
-- Health lives in the model's "Health" and "MaxHealth" attributes, which replicate
-- to clients so UI can read them. Only the server should ever change them.

local Players = game:GetService("Players")

local PLAYER_MAX_HEALTH = 150
local PLAYER_REGEN_PER_SECOND = 10
local REGEN_DELAY = 15 -- seconds without taking damage before regen starts
local REGEN_TICK = 0.25

local HealthService = {}

local diedEvent = Instance.new("BindableEvent")
-- Fires (model: Model, killer: Player?) once when a registered model reaches 0 health.
HealthService.Died = diedEvent.Event

-- Weak keys so destroyed models don't leak.
local regenRates: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastDamaged: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Mirror our health onto the Humanoid (if any) so Roblox's death/respawn still works.
local function syncHumanoid(model: Model, health: number, maxHealth: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = maxHealth
		humanoid.Health = health
	end
end

-- regenPerSecond (optional): health regained per second after REGEN_DELAY without damage.
function HealthService.register(model: Model, maxHealth: number, regenPerSecond: number?)
	assert(maxHealth > 0, "maxHealth must be positive")
	regenRates[model] = regenPerSecond
	lastDamaged[model] = nil
	model:SetAttribute("MaxHealth", maxHealth)
	model:SetAttribute("Health", maxHealth)
	syncHumanoid(model, maxHealth, maxHealth)
end

function HealthService.getHealth(model: Model): (number?, number?)
	return model:GetAttribute("Health") :: number?, model:GetAttribute("MaxHealth") :: number?
end

function HealthService.isAlive(model: Model): boolean
	local health = HealthService.getHealth(model)
	return health ~= nil and health > 0
end

-- Returns the damage actually dealt (0 if the target is dead or unregistered).
function HealthService.damage(target: Model, amount: number, source: Player?): number
	local health, maxHealth = HealthService.getHealth(target)
	-- `not (amount > 0)` also rejects NaN
	if health == nil or maxHealth == nil or health <= 0 or not (amount > 0) then
		return 0
	end

	local dealt = math.min(amount, health)
	local newHealth = health - dealt
	lastDamaged[target] = os.clock()
	target:SetAttribute("Health", newHealth)
	syncHumanoid(target, newHealth, maxHealth)

	if newHealth <= 0 then
		diedEvent:Fire(target, source)
	end
	return dealt
end

-- Returns the amount actually healed. Dead models can't be healed.
function HealthService.heal(target: Model, amount: number): number
	local health, maxHealth = HealthService.getHealth(target)
	if health == nil or maxHealth == nil or health <= 0 or not (amount > 0) then
		return 0
	end

	local healed = math.min(amount, maxHealth - health)
	local newHealth = health + healed
	target:SetAttribute("Health", newHealth)
	syncHumanoid(target, newHealth, maxHealth)
	return healed
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	HealthService.register(character, PLAYER_MAX_HEALTH, PLAYER_REGEN_PER_SECOND)

	-- Deaths we didn't cause (e.g. falling into the void) still need to be recorded.
	humanoid.Died:Connect(function()
		local health = HealthService.getHealth(character)
		if health and health > 0 then
			character:SetAttribute("Health", 0)
			diedEvent:Fire(character, nil)
		end
	end)

	-- Remove Roblox's default passive regen so only the server decides health.
	local regen = character:WaitForChild("Health", 5)
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end
end

function HealthService.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			task.spawn(onCharacterAdded, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			local now = os.clock()
			for model, rate in regenRates do
				if now - (lastDamaged[model] or 0) >= REGEN_DELAY then
					HealthService.heal(model, rate * REGEN_TICK)
				end
			end
			task.wait(REGEN_TICK)
		end
	end)
end

return HealthService
