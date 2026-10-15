--!strict
-- Runs the dungeons (DungeonConfig; the rules are at the top there). The cave mouth's "Enter"
-- prompt, or walking into its dark doorway, starts a run: a private copy of the dungeon (DungeonBuilder) in a free slot out past
-- the land, its boss standing dormant in the arena (BossService). Runs belong to the player
-- who entered; a party will share one once parties exist (Run.members is already a list).
--
-- Each run is watched a few times a second: a member walking into an orc room that isn't
-- cleared seals it and drops its orcs (EnemyService.spawnOnFloor: no respawn, normal XP,
-- coins and drops); once they're dead both doors open. If no member is alive in a room that's
-- being fought, its orcs are cleared away and its entrance opens again. Walking into the arena
-- seals it and wakes the boss; beating it opens the arena and a way out, and a wipe (BossService
-- resets the boss) opens it again. A member who dies comes back in the entry hall.
--
-- While in a run a player has a "Dungeon" attribute (the dungeon's DisplayName; ZoneBanner
-- shows it). Leaving by a way out puts them back at the cave mouth; teleporting away some
-- other way (the map, the admin panel) or leaving the game takes them out of the run too, and
-- a run with nobody left is torn down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossService = require(script.Parent.BossService)
local DungeonBuilder = require(script.Parent.DungeonBuilder)
local EnemyService = require(script.Parent.EnemyService)
local HealthService = require(script.Parent.HealthService)

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local DungeonConfig = require(ReplicatedStorage.Shared.Config.DungeonConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)

type Dungeon = DungeonConfig.Dungeon

local dungeonEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DungeonEvent") :: RemoteEvent

local WATCH_INTERVAL = 0.25
local DOOR_MARGIN = 6 -- studs past a room's doorway before it counts as walking in
local ARENA_MARGIN = 10 -- studs inside the arena's wall before the boss wakes
local STRAY_DISTANCE = 700 -- a member this far from the run (alive) has left it some other way
local PROMPT_COOLDOWN = 2

type RoomState = {
	config: DungeonConfig.Room,
	gates: { entry: DungeonBuilder.Gate, exit: DungeonBuilder.Gate },
	spawns: { Vector3 },
	cleared: boolean,
	fighting: boolean,
	wave: number, -- bumped each time the room starts or resets, so late spawns of an old wave are dropped
	spawned: number, -- orcs of this wave dropped in so far (or failed to)
	orcs: { Model },
}

type Run = {
	dungeon: Dungeon,
	slot: number,
	origin: Vector3,
	built: DungeonBuilder.Built,
	members: { Player },
	rooms: { RoomState },
	fight: BossService.Fight?,
	beaten: boolean,
	ended: boolean,
}

local DungeonService = {}

local folder = Instance.new("Folder")
folder.Name = "Dungeons"
local runs: { [number]: Run } = {} -- by slot
local runOf: { [Player]: Run } = {}
local lastPrompt: { [Player]: number } = {}
-- Members on their way back to the entry hall after dying (they spawn in town first): not
-- counted as having left.
local respawning: { [Player]: boolean } = {}
local entrances: { [string]: CFrame } = {} -- each dungeon's cave mouth (on the ground, facing out)

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local root = rootOf(player)
	return if character and root and HealthService.isAlive(character) then root else nil
end

local function tell(run: Run, kind: string, data: { [string]: any })
	for _, player in run.members do
		dungeonEvent:FireClient(player, kind, data)
	end
end

-- Moves `player` to `destination`, loading the area around it first (streaming).
local function moveTo(player: Player, destination: CFrame)
	pcall(player.RequestStreamAroundAsync, player, destination.Position, 5)
	local character = player.Character
	if character then
		character:PivotTo(destination)
	end
end

local function groundAt(x: number, z: number): number
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	for _, name in { "Enemies", "World" } do -- the cave stands on the land, not on a tree
		local other = workspace:FindFirstChild(name)
		if other then
			table.insert(exclude, other)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	return if result then result.Position.Y else 0
end

-- In front of the cave mouth, facing away from it.
local function outside(dungeon: Dungeon): CFrame
	local mouth = entrances[dungeon.Id]
	if not mouth then
		return CFrame.new(0, 20, 0)
	end
	local spot = (mouth * CFrame.new(0, 0, 14)).Position -- behind the look into the cave: outside
	local standing = Vector3.new(spot.X, groundAt(spot.X, spot.Z) + 4, spot.Z)
	return CFrame.lookAt(standing, standing - mouth.LookVector)
end

local function inRoom(run: Run, room: RoomState, position: Vector3): boolean
	local offset = position - run.origin
	local c, size = room.config.Center, room.config.Size
	return math.abs(offset.X - c.X) < size.X / 2
		and offset.Z < c.Y + size.Y / 2 - DOOR_MARGIN
		and offset.Z > c.Y - size.Y / 2
		and math.abs(offset.Y) < room.config.Height
end

local function inArena(run: Run, position: Vector3): boolean
	local arena = run.dungeon.Arena
	local center = run.built.arenaCenter
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	return flat.Magnitude < arena.Radius - ARENA_MARGIN and math.abs(position.Y - center.Y) < arena.Height
end

local function clearOrcs(room: RoomState)
	for _, orc in room.orcs do
		if orc.Parent and HealthService.isAlive(orc) then
			orc:Destroy()
		end
	end
	table.clear(room.orcs)
end

local function endRun(run: Run)
	if run.ended then
		return
	end
	run.ended = true
	runs[run.slot] = nil
	for _, room in run.rooms do
		clearOrcs(room)
	end
	if run.fight then
		run.fight:destroy()
	end
	run.built.folder:Destroy()
end

-- Takes `player` out of their run (back to the cave mouth if `toEntrance`).
local function leave(player: Player, toEntrance: boolean)
	local run = runOf[player]
	if not run then
		return
	end
	runOf[player] = nil
	player:SetAttribute("Dungeon", nil)
	local index = table.find(run.members, player)
	if index then
		table.remove(run.members, index)
	end
	if toEntrance then
		moveTo(player, outside(run.dungeon))
	end
	if #run.members == 0 then
		endRun(run)
	end
end

local function startRoom(run: Run, room: RoomState)
	room.fighting = true
	room.wave += 1
	room.spawned = 0
	local wave = room.wave
	DungeonBuilder.setGate(room.gates.entry, false)
	tell(run, "Banner", { text = room.config.Name, small = true })
	for i, spawn in room.spawns do
		task.delay(0.3 + i * 0.25, function()
			if run.ended or room.wave ~= wave then
				return
			end
			local orc = EnemyService.spawnOnFloor(spawn, EnemyConfig.Orc)
			if run.ended or room.wave ~= wave then
				if orc then
					orc:Destroy()
				end
				return
			end
			room.spawned += 1
			if orc then
				table.insert(room.orcs, orc)
			end
		end)
	end
end

local function watch(run: Run)
	-- Members who went somewhere else.
	for _, player in table.clone(run.members) do
		local root = aliveRoot(player)
		if root and not respawning[player] and (root.Position - run.origin).Magnitude > STRAY_DISTANCE then
			leave(player, false)
		end
	end
	if run.ended then
		return
	end

	for _, room in run.rooms do
		if room.cleared then
			continue
		end
		local someoneInside = false
		for _, player in run.members do
			local root = aliveRoot(player)
			if root and inRoom(run, room, root.Position) then
				someoneInside = true
			end
		end
		if room.fighting then
			local spawned = room.spawned >= #room.spawns
			local alive = 0
			for _, orc in room.orcs do
				if orc.Parent and HealthService.isAlive(orc) then
					alive += 1
				end
			end
			if spawned and alive == 0 then
				room.fighting = false
				room.cleared = true
				table.clear(room.orcs)
				DungeonBuilder.setGate(room.gates.entry, true)
				DungeonBuilder.setGate(room.gates.exit, true)
				tell(run, "Banner", { text = "The way is open", small = true })
			elseif not someoneInside then
				-- Everyone fighting here fell: the room empties and opens again.
				room.fighting = false
				room.wave += 1
				clearOrcs(room)
				DungeonBuilder.setGate(room.gates.entry, true)
			end
		elseif someoneInside then
			startRoom(run, room)
		end
	end

	local fight = run.fight
	if fight and not run.beaten and fight.model:GetAttribute("BossState") == "Dormant" then
		for _, player in run.members do
			local root = aliveRoot(player)
			if root and inArena(run, root.Position) then
				DungeonBuilder.setGate(run.built.arenaGate, false)
				fight:engage()
				break
			end
		end
	end
end

local function onExit(prompt: ProximityPrompt, run: Run)
	prompt.Triggered:Connect(function(player)
		if runOf[player] == run then
			leave(player, true)
		end
	end)
end

local function startRun(player: Player, dungeon: Dungeon)
	if runOf[player] then
		return
	end
	local slot
	for i = 1, DungeonConfig.Slots do
		if not runs[i] then
			slot = i
			break
		end
	end
	if not slot then
		dungeonEvent:FireClient(player, "Banner", { text = "The lair is full; try again soon", small = true })
		return
	end
	local origin = DungeonConfig.Origin + Vector3.new(DungeonConfig.Spacing * (slot - 1), 0, 0)
	local built = DungeonBuilder.build(dungeon, origin, `{dungeon.Id}Run{slot}`)
	local run: Run = {
		dungeon = dungeon,
		slot = slot,
		origin = origin,
		built = built,
		members = { player },
		rooms = {},
		fight = nil,
		beaten = false,
		ended = false,
	}
	for i, room in dungeon.Rooms do
		table.insert(run.rooms, { config = room, gates = built.roomGates[i], spawns = built.orcSpawns[i], cleared = (room.Orcs or 0) == 0, fighting = false, wave = 0, spawned = 0, orcs = {} })
	end
	runs[slot] = run
	runOf[player] = run
	built.folder.Parent = folder
	onExit(built.exitPrompt, run)

	local boss = BossConfig[dungeon.Boss] :: BossConfig.Boss?
	if boss then
		local fight = BossService.spawn(boss, built.bossSpot, function()
			return run.members
		end, built.arenaCenter, dungeon.Arena.Radius)
		if fight then
			run.fight = fight
			fight.onWipe = function()
				DungeonBuilder.setGate(built.arenaGate, true)
			end
			fight.onDefeated = function()
				run.beaten = true
				DungeonBuilder.setGate(built.arenaGate, true)
				tell(run, "Banner", { text = `{boss.DisplayName} defeated!` })
				if not run.ended then
					onExit(DungeonBuilder.victoryPortal(built, dungeon), run)
				end
			end
		end
	end

	player:SetAttribute("Dungeon", dungeon.DisplayName)
	moveTo(player, built.spawn)
	task.spawn(function()
		while not run.ended do
			watch(run)
			task.wait(WATCH_INTERVAL)
		end
	end)
end

-- The cave mouth for `dungeon`, on the ground at its Entrance.
local function placeEntrance(dungeon: Dungeon)
	local x, z = dungeon.Entrance.X, dungeon.Entrance.Y
	local ground = Vector3.new(x, groundAt(x, z), z)
	local prompt, doorway = DungeonBuilder.entrance(dungeon, ground, folder)
	local facing = Vector3.new(dungeon.EntranceFacing.X, 0, dungeon.EntranceFacing.Y).Unit
	entrances[dungeon.Id] = CFrame.lookAt(ground, ground - facing) -- looking into the cave
	local function enter(player: Player)
		local now = os.clock()
		if now - (lastPrompt[player] or 0) < PROMPT_COOLDOWN then
			return
		end
		lastPrompt[player] = now
		if player.Character and HealthService.isAlive(player.Character) then
			startRun(player, dungeon)
		end
	end
	prompt.Triggered:Connect(enter)
	-- Walking into the dark of the mouth goes in too.
	doorway.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and not runOf[player] then
			enter(player)
		end
	end)
end

-- Where to stand outside `dungeonId`'s cave mouth, facing away from it (the map's waypoint).
function DungeonService.outsideOf(dungeonId: string): CFrame?
	for _, dungeon in DungeonConfig.Dungeons do
		if dungeon.Id == dungeonId and entrances[dungeonId] then
			return outside(dungeon)
		end
	end
	return nil
end

function DungeonService.start()
	folder.Parent = workspace
	for _, dungeon in DungeonConfig.Dungeons do
		task.spawn(placeEntrance, dungeon)
	end

	local function onPlayer(player: Player)
		-- A member who dies comes back in the run's entry hall.
		player.CharacterAdded:Connect(function(character)
			local run = runOf[player]
			if not run then
				return
			end
			respawning[player] = true
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait() -- after the spawn location has placed them
			if runOf[player] == run and player.Character == character then
				moveTo(player, run.built.spawn)
			end
			if player.Character == character then
				respawning[player] = nil
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		leave(player, false)
		lastPrompt[player] = nil
		respawning[player] = nil
	end)
end

return DungeonService
