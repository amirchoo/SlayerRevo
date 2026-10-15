--!strict
-- Server-authoritative map actions: unlocking waypoints and teleporting to them
-- (MapConfig.Waypoints). A waypoint with Discover unlocks once the player comes that close to
-- it: saved in their data (DataService Waypoints), shown as a "Waypoint_<Id>" attribute on the
-- player (the world map shows its button), with a banner. Teleports only go to waypoints the
-- player has unlocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local DataService = require(script.Parent.DataService)
local DungeonService = require(script.Parent.DungeonService)
local HealthService = require(script.Parent.HealthService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotes:WaitForChild("MapTeleport") :: RemoteEvent
local bannerRemote = remotes:WaitForChild("DungeonEvent") :: RemoteEvent -- DungeonHud shows its banners anywhere

local DISCOVER_INTERVAL = 0.5 -- seconds between checks for waypoints reached

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

local function waypointById(id: unknown): MapConfig.Waypoint?
	for _, waypoint in MapConfig.Waypoints do
		if waypoint.Id == id then
			return waypoint
		end
	end
	return nil
end

local function destination(waypoint: MapConfig.Waypoint): CFrame
	if waypoint.Dungeon then
		local outside = DungeonService.outsideOf(waypoint.Dungeon)
		if outside then
			return outside
		end
	end
	if waypoint == MapConfig.TownWaypoint then
		local spawn = TownConfig.Spawn
		return CFrame.new(spawn.X, groundAt(spawn.X, spawn.Y) + 5, spawn.Y)
	end
	local at = waypoint.Position
	return CFrame.new(at.X, groundAt(at.X, at.Y) + 5, at.Y)
end

local function onTeleport(player: Player, waypointId: unknown)
	local waypoint = waypointById(waypointId)
	if not waypoint or not MapConfig.unlocked(player, waypoint) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart") and HealthService.isAlive(character)) then
		return
	end
	local goal = destination(waypoint)
	pcall(player.RequestStreamAroundAsync, player, goal.Position, 5)
	if player.Character == character then
		character:PivotTo(goal)
	end
end

local function unlock(player: Player, waypoint: MapConfig.Waypoint, announce: boolean)
	player:SetAttribute("Waypoint_" .. waypoint.Id, true)
	local data = DataService.data(player)
	if data then
		data.Waypoints = data.Waypoints or {}
		;(data.Waypoints :: { [string]: boolean })[waypoint.Id] = true
	end
	if announce then
		bannerRemote:FireClient(player, "Banner", { text = `Waypoint unlocked: {waypoint.Name}`, small = true })
	end
end

local function checkDiscoveries()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not DataService.data(player) then
			continue
		end
		for _, waypoint in MapConfig.Waypoints do
			local radius = waypoint.Discover
			if radius and not MapConfig.unlocked(player, waypoint) then
				local offset = Vector2.new(root.Position.X, root.Position.Z) - waypoint.Position
				if offset.Magnitude <= radius then
					unlock(player, waypoint, true)
				end
			end
		end
	end
end

function MapService.start()
	RemoteGuard.connect(teleportRemote, onTeleport)
	DataService.onLoaded(function(player, data)
		for id in data.Waypoints or {} do
			local waypoint = waypointById(id)
			if waypoint then
				unlock(player, waypoint, false)
			end
		end
	end)
	task.spawn(function()
		while true do
			checkDiscoveries()
			task.wait(DISCOVER_INTERVAL)
		end
	end)
end

return MapService
