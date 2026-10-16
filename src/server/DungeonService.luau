--!strict
-- Runs the dungeons (DungeonConfig; the rules are at the top there). The cave mouth's "Enter"
-- prompt, or walking into its dark doorway, starts a run: a private copy of the dungeon (DungeonBuilder) in a free slot out past
-- the land, its boss standing dormant in the arena (BossService). Runs belong to the player
-- who entered; a party will share one once parties exist (Run.members is already a list).
--
-- A run starts with its orc patrols walking their routes (EnemyService.spawnOnFloor, finding
-- their way with DungeonGrid.route; no respawn, normal XP, coins and drops). Each run is
-- watched a few times a second: a member walking into a war room that isn't cleared seals its
-- gates and drops its orcs; once they're dead its gates open. If no member is alive in a room
-- that's being fought, its orcs are cleared away and its gates open again. Once every war room
-- is cleared the arena's gate opens; walking into the arena seals it and wakes the boss;
-- beating it opens the arena and a way out, and a wipe (BossService resets the boss) opens it
-- again. A chest gives every member coins (placeholder loot), once per run. A member who dies
-- comes back in the entry hall.
--
-- While in a run a player has a "Dungeon" attribute (the dungeon's DisplayName; ZoneBanner
-- shows it). Leaving by a way out puts them back at the cave mouth; teleporting away some
-- other way (the map, the admin panel) or leaving the game takes them out of the run too, and
-- a run with nobody left is torn down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossService = require(script.Parent.BossService)
local DungeonBuilder = require(script.Parent.DungeonBuilder)
local DungeonGrid = require(script.Parent.DungeonGrid)
local EnemyService = require(script.Parent.EnemyService)
local HealthService = require(script.Parent.HealthService)
local LootService = require(script.Parent.LootService)

local BossConfig = require(ReplicatedStorage.Shared.Config.BossConfig)
local DungeonConfig = require(ReplicatedStorage.Shared.Config.DungeonConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)

type Dungeon = DungeonConfig.Dungeon

local dungeonEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DungeonEvent") :: RemoteEvent

local WATCH_INTERVAL = 0.25
local DOOR_MARGIN = 3 -- studs past a room's edge before it counts as walking in
local SEAL_HINT_RANGE = 14 -- studs from the shut arena gate that say what's left to clear
local SEAL_HINT_EVERY = 6 -- seconds between those
local PATROL_STAGGER = 1.2 -- seconds between a patrol's members setting off
local ARENA_MARGIN = 10 -- studs inside the arena's wall before the boss wakes
local STRAY_DISTANCE = 700 -- a member this far from the run (alive) has left it some other way
local PROMPT_COOLDOWN = 2
local LID_DELAY = 0.35 -- seconds after a chest starts opening before its coins burst out
local chestRandom = Random.new()

type RoomState = {
	config: DungeonConfig.Room,
	gates: { DungeonBuilder.Gate },
	spawns: { Vector3 }, -- none: not a war room
	visited: boolean, -- someone has walked in (its name has been shown)
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
	grid: DungeonGrid.Grid,
	built: DungeonBuilder.Built,
	members: { Player },
	rooms: { RoomState },
	patrols: { Model },
	arenaOpen: boolean, -- every war room is cleared
	lastSealHint: number,
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
	local grid, config = run.grid, room.config
	local half = grid.cell / 2 - DOOR_MARGIN
	local low = DungeonGrid.position(grid, config.From.X, config.From.Y) - Vector3.new(half, 0, half)
	local high = DungeonGrid.position(grid, config.To.X, config.To.Y) + Vector3.new(half, 0, half)
	return position.X > low.X
		and position.X < high.X
		and position.Z > low.Z
		and position.Z < high.Z
		and math.abs(position.Y - run.origin.Y) < run.dungeon.RoomHeight
end

-- How a run's orcs find their way: round its walls, through its open gates.
local function roam(run: Run, route: { Vector3 }?, sight: boolean): EnemyService.Roam
	return {
		route = route,
		sight = sight,
		navigate = function(from: Vector3, to: Vector3): Vector3?
			return DungeonGrid.route(run.grid, from, to)
		end,
	}
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
	for _, orc in run.patrols do
		if orc.Parent then
			orc:Destroy()
		end
	end
	if run.fight then
		run.fight:destroy()
	end
	DungeonBuilder.clear(run.built)
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
	for _, gate in room.gates do
		DungeonBuilder.setGate(gate, false)
	end
	tell(run, "Banner", { text = room.config.Name, small = true })
	for i, spawn in room.spawns do
		task.delay(0.3 + i * 0.25, function()
			if run.ended or room.wave ~= wave then
				return
			end
			local orc = EnemyService.spawnOnFloor(spawn, EnemyConfig.Orc, roam(run, nil, false))
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
		if room.cleared and room.visited then
			continue
		end
		local someoneInside = false
		for _, player in run.members do
			local root = aliveRoot(player)
			if root and inRoom(run, room, root.Position) then
				someoneInside = true
			end
		end
		if someoneInside and not room.visited then
			room.visited = true
			if room.cleared then
				tell(run, "Banner", { text = room.config.Name, small = true }) -- not a war room
			end
		end
		if room.cleared then
			continue
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
				for _, gate in room.gates do
					DungeonBuilder.setGate(gate, true)
				end
				tell(run, "Banner", { text = `{room.config.Name} cleared`, small = true })
			elseif not someoneInside then
				-- Everyone fighting here fell: the room empties and opens again.
				room.fighting = false
				room.wave += 1
				clearOrcs(room)
				for _, gate in room.gates do
					DungeonBuilder.setGate(gate, true)
				end
			end
		elseif someoneInside then
			startRoom(run, room)
		end
	end

	-- The arena's gate: shut until every war room is cleared.
	if not run.arenaOpen then
		local left = {}
		for _, room in run.rooms do
			if not room.cleared then
				table.insert(left, room.config.Name)
			end
		end
		if #left == 0 then
			run.arenaOpen = true
			DungeonBuilder.setGate(run.built.arenaGate, true)
			local boss = BossConfig[run.dungeon.Boss] :: BossConfig.Boss?
			tell(run, "Banner", { text = `A gate grinds open: {if boss then boss.DisplayName else "the boss"} awaits` })
		elseif os.clock() - run.lastSealHint > SEAL_HINT_EVERY then
			local gateAt = run.built.arenaCenter + Vector3.new(0, 0, run.dungeon.Arena.Radius)
			for _, player in run.members do
				local root = aliveRoot(player)
				if root and (root.Position - gateAt).Magnitude < SEAL_HINT_RANGE then
					run.lastSealHint = os.clock()
					tell(run, "Banner", { text = `Sealed. Still to clear: {table.concat(left, ", ")}`, small = true })
					break
				end
			end
		end
	end

	local fight = run.fight
	if fight and run.arenaOpen and not run.beaten and fight.model:GetAttribute("BossState") == "Dormant" then
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

-- The layouts saved in the place (workspace.DungeonLayouts), by dungeon id, taken at start.
local layouts: { [string]: DungeonBuilder.Layout } = {}

-- Slots and players whose run is being built (carving its terrain takes a moment).
local building: { [number]: boolean } = {}
local entering: { [Player]: boolean } = {}

local function startRun(player: Player, dungeon: Dungeon)
	if runOf[player] or entering[player] then
		return
	end
	local slot
	for i = 1, DungeonConfig.Slots do
		if not runs[i] and not building[i] then
			slot = i
			break
		end
	end
	if not slot then
		dungeonEvent:FireClient(player, "Banner", { text = "The lair is full; try again soon", small = true })
		return
	end
	building[slot] = true
	entering[player] = true
	local origin = DungeonConfig.Origin + Vector3.new(DungeonConfig.Spacing * (slot - 1), 0, 0)
	local grid = DungeonGrid.new(dungeon, origin)
	local built = DungeonBuilder.build(dungeon, grid, `{dungeon.Id}Run{slot}`, layouts[dungeon.Id])
	building[slot] = nil
	entering[player] = nil
	if not player.Parent then -- left while it was being built
		DungeonBuilder.clear(built)
		return
	end
	local run: Run = {
		dungeon = dungeon,
		slot = slot,
		origin = origin,
		grid = grid,
		built = built,
		members = { player },
		rooms = {},
		patrols = {},
		arenaOpen = false,
		lastSealHint = 0,
		fight = nil,
		beaten = false,
		ended = false,
	}
	for i, room in dungeon.Rooms do
		local spawns = built.orcSpawns[i]
		table.insert(run.rooms, { config = room, gates = built.roomGates[i], spawns = spawns, visited = false, cleared = #spawns == 0, fighting = false, wave = 0, spawned = 0, orcs = {} })
	end
	runs[slot] = run
	runOf[player] = run
	built.folder.Parent = folder
	onExit(built.exitPrompt, run)

	-- Patrols set off along their routes, a little apart.
	for _, patrol in dungeon.Patrols do
		local route = {}
		for k = 1, #patrol.Route do
			local spot = DungeonGrid.find(grid, string.sub(patrol.Route, k, k))[1]
			if spot then
				table.insert(route, DungeonGrid.position(grid, spot.X, spot.Y))
			else
				warn(`[DungeonService] {dungeon.Id}: no waypoint {string.sub(patrol.Route, k, k)} on the map`)
			end
		end
		if #route == 0 then
			continue
		end
		for i = 1, patrol.Orcs do
			task.delay((i - 1) * PATROL_STAGGER, function()
				if run.ended then
					return
				end
				local orc = EnemyService.spawnOnFloor(route[1] + Vector3.new(0, 6, 0), EnemyConfig.Orc, roam(run, route, true))
				if orc and run.ended then
					orc:Destroy()
				elseif orc then
					table.insert(run.patrols, orc)
				end
			end)
		end
	end

	-- Chests, once per run: gold coins spill out for everyone in the run (each their own pile,
	-- worth their own random total), picked up by walking through them.
	local loot = dungeon.ChestCoins
	for _, chest in built.chests do
		local opened = false
		chest.prompt.Triggered:Connect(function(opener)
			if opened or runOf[opener] ~= run or not aliveRoot(opener) then
				return
			end
			opened = true
			chest.open()
			tell(run, "Banner", { text = "The chest spills gold!", small = true })
			task.delay(LID_DELAY, function()
				for _, member in run.members do
					LootService.dropCoins(member, chestRandom:NextInteger(loot.Min, loot.Max), chest.position + Vector3.new(0, 2, 0), chest.front, loot.Shown)
				end
			end)
		end)
	end

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

-- The cave mouth for `dungeon`: the one saved in the place (workspace.DungeonLayouts,
-- `<Id>Entrance`) if there is one, else built on the ground at its Entrance.
local function placeEntrance(dungeon: Dungeon)
	local saved = workspace:FindFirstChild("DungeonLayouts")
	local model = saved and saved:FindFirstChild(dungeon.Id .. "Entrance")
	local prompt, doorway, mouth
	if model then
		prompt, doorway, mouth = DungeonBuilder.savedEntrance(dungeon, model)
	end
	if not prompt or not doorway or not mouth then
		local x, z = dungeon.Entrance.X, dungeon.Entrance.Y
		local ground = Vector3.new(x, groundAt(x, z), z)
		prompt, doorway = DungeonBuilder.entrance(dungeon, ground, folder)
		mouth = CFrame.lookAt(ground, ground + Vector3.new(dungeon.EntranceFacing.X, 0, dungeon.EntranceFacing.Y))
	end
	local ground, facing = mouth.Position, mouth.LookVector
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
	local saved = workspace:FindFirstChild("DungeonLayouts")
	for _, dungeon in DungeonConfig.Dungeons do
		local layout = saved and saved:FindFirstChild(dungeon.Id)
		if layout then
			layouts[dungeon.Id] = DungeonBuilder.loadLayout(layout)
		end
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
