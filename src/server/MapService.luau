--!strict
-- Server-authoritative map actions, currently the Beginning Town waypoint teleport.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local HealthService = require(script.Parent.HealthService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local teleportRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapTeleport") :: RemoteEvent

local MapService = {}

local function groundAt(x: number, z: number): number
	local include: { Instance } = { workspace.Terrain }
	for _, name in { "Baseplate", "Town" } do
		local instance = workspace:FindFirstChild(name)
		if instance then
			table.insert(include, instance)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
	return if hit then hit.Position.Y else 4
end

local function onTeleport(player: Player, waypointId: unknown)
	if waypointId ~= MapConfig.TownWaypoint.Id then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart") and HealthService.isAlive(character)) then
		return
	end
	local spawn = TownConfig.Spawn
	local y = groundAt(spawn.X, spawn.Y)
	character:PivotTo(CFrame.new(spawn.X, y + 5, spawn.Y))
end

function MapService.start()
	RemoteGuard.connect(teleportRemote, onTeleport)
end

return MapService
