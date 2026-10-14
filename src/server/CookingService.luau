--!strict
-- Cooking at the tavern-yard campfire (CookingConfig). Pressing its prompt opens a cooking
-- session: the "Cooking" character attribute goes on (everyone's client crouches that player by
-- the fire: CookingPose) and the player's client opens the panel (Cooking remote: "open").
-- The client then asks to cook ("cook", food Id, count): the raw meat is taken up front, the
-- player stirs ("Stirring" attribute) and every CookTime one piece is done and handed over
-- (flying out of the fire: LootPickedUp remote). Walking off, dying, or closing the panel ends
-- the session; pieces not yet cooked are given back raw. All decided here.
--
-- Cooking remote, server to client: ("open"), ("close"), ("started", foodId, count, cookTime),
-- ("finished", foodId, cooked). Client to server: ("close"), ("cook", foodId, count).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CookingConfig = require(ReplicatedStorage.Shared.Config.CookingConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local ConsumableService = require(script.Parent.ConsumableService)
local HealthService = require(script.Parent.HealthService)
local MaterialService = require(script.Parent.MaterialService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local STATION = CookingConfig.Station
local WATCH_INTERVAL = 0.5 -- seconds between checking cooks are still at the fire

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cookingRemote = remotes:WaitForChild("Cooking") :: RemoteEvent
local pickedUpRemote = remotes:WaitForChild("LootPickedUp") :: RemoteEvent

local CookingService = {}

type Session = { character: Model, busy: boolean, ended: boolean }
local sessions: { [Player]: Session } = {}
local spot: BasePart

local function groundAt(position: Vector2): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain, workspace:FindFirstChild("Town") or workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(position.X, 300, position.Y), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position.Y else 0
end

-- Whether the player is alive and at the fire.
local function atFire(player: Player, character: Model): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	return player.Character == character
		and HealthService.isAlive(character)
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - spot.Position).Magnitude <= STATION.Range
end

local function endSession(player: Player, tellClient: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	session.ended = true
	sessions[player] = nil
	session.character:SetAttribute("Cooking", nil)
	session.character:SetAttribute("Stirring", nil)
	if tellClient and player.Parent then
		cookingRemote:FireClient(player, "close")
	end
end

local function open(player: Player)
	local character = player.Character
	if not character or sessions[player] or not atFire(player, character) then
		return
	end
	sessions[player] = { character = character, busy = false, ended = false }
	character:SetAttribute("Cooking", true)
	cookingRemote:FireClient(player, "open")
end

-- Cooks `count` of the recipe one piece at a time, handing each over as it's done.
local function cook(player: Player, session: Session, recipe: CookingConfig.Recipe, count: number)
	session.busy = true
	local character = session.character
	character:SetAttribute("Stirring", true)
	cookingRemote:FireClient(player, "started", recipe.To, count, CookingConfig.CookTime)
	Sounds.play("Sizzle", spot)
	local cooked = 0
	for _ = 1, count do
		task.wait(CookingConfig.CookTime)
		if session.ended or not atFire(player, character) then
			break
		end
		ConsumableService.grant(player, recipe.To, 1)
		pickedUpRemote:FireClient(player, recipe.To, 1, spot.Position)
		cooked += 1
	end
	if cooked < count and player.Parent then
		MaterialService.grant(player, recipe.From, count - cooked) -- not cooked yet: given back raw
	end
	session.busy = false
	if not session.ended then
		character:SetAttribute("Stirring", nil)
	end
	if player.Parent then
		cookingRemote:FireClient(player, "finished", recipe.To, cooked)
	end
end

local function onRequest(player: Player, action: unknown, foodId: unknown, count: unknown)
	local session = sessions[player]
	if action == "close" then
		endSession(player, false)
	elseif action == "cook" and session and not session.busy and typeof(foodId) == "string" and typeof(count) == "number" then
		local recipe = CookingConfig.recipe(foodId)
		if not recipe or not atFire(player, session.character) then
			return
		end
		local wanted = math.clamp(math.floor(count), 0, CookingConfig.MaxBatch)
		local taken = MaterialService.take(player, recipe.From, wanted)
		if taken > 0 then
			task.spawn(cook, player, session, recipe, taken)
		end
	end
end

function CookingService.start()
	local folder = Instance.new("Folder")
	folder.Name = "Cooking"
	spot = Instance.new("Part")
	spot.Name = "CookingSpot"
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.Transparency = 1
	spot.Size = Vector3.new(1, 1, 1)
	spot.Position = Vector3.new(STATION.Position.X, groundAt(STATION.Position) + STATION.Height, STATION.Position.Y)
	spot.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Cook"
	prompt.ObjectText = "Campfire"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = STATION.Range
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
	folder.Parent = workspace

	prompt.Triggered:Connect(open)
	RemoteGuard.connect(cookingRemote, onRequest)
	Players.PlayerRemoving:Connect(function(player)
		endSession(player, false)
	end)

	-- Ends sessions whose cook has died, respawned or wandered off.
	task.spawn(function()
		while true do
			task.wait(WATCH_INTERVAL)
			for player, session in sessions do
				if not atFire(player, session.character) then
					endSession(player, true)
				end
			end
		end
	end)
end

return CookingService
