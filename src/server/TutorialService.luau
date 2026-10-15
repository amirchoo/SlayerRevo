--!strict
-- The training camp (TutorialConfig): every new player is trained in the training yard right
-- after picking their starter, before they're free in town, and can't leave until it's done.
-- Each player gets a sparring circle to themselves and goes through the steps for their
-- weapon one at a time; the server decides when each is done:
--   Intro       the cutscene (the client says when it's over)
--   Light/Heavy hits on the player's own training dummy; a hit counts as heavy while a heavy
--               attack runs ("HeavyAttacking", or the greatsword's charge) or just after it
--   LockOn      locked on to the sparring partner (the client says)
--   Dodge/Block/Parry  the sparring partner (a puppet orc, EnemyService.spawnPuppet) swings
--               with a long, glowing wind-up; this service resolves each swing itself: a dash
--               out of reach or through the hit is a dodge, BlockService.tryParry a parry, a
--               raised guard with charges left a block
--   SkillsOpen  the skill tree opened (the client says)
--   SkillsSpend a skill point spent (casters: their class and an element unlocked)
--   Spar        both sparring orcs (EnemyService.spawnSparring) defeated
-- Progress is published as the player's "TutorialStep", "TutorialCount" and "TutorialGoal"
-- attributes (and "TutorialWeapon", "TutorialReplay"); results and the end go out on the
-- TutorialEvent remote. A first-timer's step is saved (data.TutorialStep), so leaving picks up
-- there, and finishing saves data.Tutorial. In the camp the player never drops below 1 health.
-- Talking to the drill master again (NpcConfig Action "Training": the Replay action, from
-- beside him) runs the drills again (a replay: no cutscene; the Quit action leaves them).
-- While anyone trains in a circle, invisible walls round it keep dashes from carrying them out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local SkillTrees = require(ReplicatedStorage.Shared.Config.SkillTrees)
local BlockService = require(script.Parent.BlockService)
local DashService = require(script.Parent.DashService)
local DataService = require(script.Parent.DataService)
local EnemyAnimations = require(script.Parent.EnemyAnimations)
local EnemyEffects = require(script.Parent.EnemyEffects)
local EnemyService = require(script.Parent.EnemyService)
local HealthService = require(script.Parent.HealthService)
local HitEffects = require(script.Parent.HitEffects)
local RemoteGuard = require(script.Parent.RemoteGuard)

local PARTNER = TutorialConfig.Partner
local HEAVY_GRACE = 1.5 -- seconds after a heavy ends that its hits still land (slams, lunges, spells)
local STEP_PAUSE = 1.6 -- seconds between finishing a step and the next starting
local WATCH_TICK = 0.5
local PARTNER_TICK = 0.1
local DASH_SLACK = 0.15 -- a dash this long before the wind-up began still counts
local TRAINER_REACH = NpcConfig.CloseDistance + 4 -- how near a "Training" NPC the Replay action works

local COLORS = {
	Ring = Color3.fromRGB(150, 120, 80),
	Stake = Color3.fromRGB(105, 70, 45),
	Rope = Color3.fromRGB(200, 180, 130),
	Post = Color3.fromRGB(105, 70, 45),
	Sack = Color3.fromRGB(196, 170, 120),
}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("TutorialAction") :: RemoteEvent
local eventRemote = remotes:WaitForChild("TutorialEvent") :: RemoteEvent
local greatswordCharge = remotes:WaitForChild("GreatswordCharge") :: RemoteEvent
local greatswordRelease = remotes:WaitForChild("GreatswordRelease") :: RemoteEvent

local TutorialService = {}

type Session = {
	player: Player,
	weapon: string, -- the weapon being taught (a TutorialConfig.Weapons key)
	replay: boolean,
	order: { string },
	index: number,
	count: number,
	goal: number,
	station: number,
	token: number, -- bumped whenever the step changes or the session ends; older loops stop
	paused: boolean, -- a step's goal was reached: the drills hold still until the next step
	dummy: Model?,
	partner: Model?,
	sparring: { Model },
	heavySerial: number, -- counts heavy attacks started, so each lands for one credit
	heavyHeld: boolean,
	heavyGraceUntil: number,
	credited: { [number]: boolean },
	spentAtStart: number,
}

local sessions: { [Player]: Session } = {}
local partners: { [Model]: boolean } = {}

local folder = Instance.new("Folder")
folder.Name = "TrainingCamp"

local function part(props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part") :: any
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent or folder
	return instance
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The top of whatever is at X/Z (the yard's ground), ignoring characters and creatures.
local function groundAt(x: number, z: number): number
	local exclude: { Instance } = { folder }
	for _, name in { "Enemies", "Animals", "Townsfolk", "Villagers", "Loot" } do
		local other = workspace:FindFirstChild(name)
		if other then
			table.insert(exclude, other)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
	return if result then result.Position.Y else 0
end

local function stationOf(session: Session): TutorialConfig.Station
	return TutorialConfig.Stations[session.station]
end

-- A spot `forward` studs ahead of the session's stand and `side` studs to its right.
local function spotAhead(session: Session, forward: number, side: number): Vector2
	local station = stationOf(session)
	local facing = station.Facing.Unit
	local right = Vector2.new(-facing.Y, facing.X)
	return station.Stand + facing * forward + right * side
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function stepId(session: Session): string?
	return session.order[session.index]
end

local function healFull(player: Player)
	local character = player.Character
	if character then
		HealthService.heal(character, math.huge)
	end
end

-- The weapon to teach: the one in hand if `preferHeld` and it has a lesson, else the starter.
local function lessonWeapon(player: Player, data: DataService.Data, preferHeld: boolean): string?
	if preferHeld then
		local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
		if tool and TutorialConfig.Weapons[tool.Name] then
			return tool.Name
		end
	end
	local starter = data.Starter
	return if starter and TutorialConfig.Weapons[starter] then starter else nil
end

-- A free sparring circle (or the last one, shared, if they're all taken).
local function freeStation(): number
	local count = #TutorialConfig.Stations
	for index = 1, count do
		local taken = false
		for _, session in sessions do
			if session.station == index then
				taken = true
			end
		end
		if not taken then
			return index
		end
	end
	return count
end

local function publish(session: Session)
	local player = session.player
	player:SetAttribute("TutorialCount", session.count)
	player:SetAttribute("TutorialGoal", session.goal)
	player:SetAttribute("TutorialStep", stepId(session) or "")
end

-- Puts the player in their circle, facing the dummy. Yields while the spot streams in.
local function placePlayer(session: Session)
	local player = session.player
	local station = stationOf(session)
	local stand = Vector3.new(station.Stand.X, groundAt(station.Stand.X, station.Stand.Y), station.Stand.Y)
	pcall(player.RequestStreamAroundAsync, player, stand, 5)
	local character = player.Character
	if character and sessions[player] == session then
		local facing = Vector3.new(station.Facing.X, 0, station.Facing.Y)
		character:PivotTo(CFrame.lookAt(stand, stand + facing) + Vector3.new(0, 3.5, 0))
	end
end

-- Draws the taught weapon if nothing is in hand.
local function drawWeapon(session: Session)
	local character = session.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or character:FindFirstChildOfClass("Tool") then
		return
	end
	local backpack = session.player:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(session.weapon)
	if tool and tool:IsA("Tool") then
		humanoid:EquipTool(tool)
	end
end

-- The camp -----------------------------------------------------------------------------------

-- A ring of stakes joined by rope round each sparring circle, on a trodden dirt floor, and a
-- ring of invisible walls just inside the rope that's solid only while someone trains there
-- (so a dash can't carry them out; the rest of the time anyone can walk through the gap).
local WALL_SEGMENTS = 24
local WALL_HEIGHT = 12
local walls: { { BasePart } } = {} -- per station

local function buildCircles()
	local radius = TutorialConfig.CircleRadius
	for index, station in TutorialConfig.Stations do
		local facing = station.Facing.Unit
		local middle2 = station.Stand + facing * (TutorialConfig.TargetDistance / 2)
		local y = groundAt(middle2.X, middle2.Y)
		local middle = Vector3.new(middle2.X, y, middle2.Y)
		part({
			Name = `Circle{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, radius * 2 + 1, radius * 2 + 1),
			CFrame = CFrame.new(middle + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = COLORS.Ring,
			Material = Enum.Material.Ground,
			CanCollide = false,
			CanQuery = false,
		})
		local stakes = 14
		local tops: { Vector3 } = {}
		local toStand = Vector3.new(station.Stand.X - middle.X, 0, station.Stand.Y - middle.Z).Unit
		for i = 1, stakes do
			local angle = (i - 0.5) / stakes * math.pi * 2
			local at = middle + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
			-- Leave a gap toward the stand, so players walk in.
			if (at - middle).Unit:Dot(toStand) < 0.97 then
				part({ Name = "Stake", Size = Vector3.new(0.5, 2.6, 0.5), CFrame = CFrame.new(at + Vector3.new(0, 1.3, 0)), Color = COLORS.Stake, Material = Enum.Material.Wood })
				table.insert(tops, at + Vector3.new(0, 2.3, 0))
			else
				table.insert(tops, Vector3.new(math.huge, 0, 0)) -- the gap: no rope either side
			end
		end
		for i, top in tops do
			local nextTop = tops[i % #tops + 1]
			if top.X ~= math.huge and nextTop.X ~= math.huge then
				local length = (nextTop - top).Magnitude
				part({
					Name = "Rope",
					Size = Vector3.new(0.15, 0.15, length),
					CFrame = CFrame.lookAt((top + nextTop) / 2, nextTop),
					Color = COLORS.Rope,
					Material = Enum.Material.Fabric,
					CanCollide = false,
					CanQuery = false,
				})
			end
		end

		local ring: { BasePart } = {}
		local wallRadius = radius - 0.5
		local width = 2 * wallRadius * math.tan(math.pi / WALL_SEGMENTS) + 0.6
		for i = 1, WALL_SEGMENTS do
			local angle = (i - 0.5) / WALL_SEGMENTS * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local at = middle + out * (wallRadius + 0.5) + Vector3.new(0, WALL_HEIGHT / 2, 0)
			table.insert(ring, part({
				Name = "ArenaWall",
				Size = Vector3.new(width, WALL_HEIGHT, 1),
				CFrame = CFrame.lookAt(at, at + out),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false, -- out of the camera's and every raycast's way
				CanTouch = false,
			}))
		end
		walls[index] = ring
	end
end

-- Makes station `index`'s walls solid while anyone trains in it.
local function updateWalls(index: number)
	local occupied = false
	for _, session in sessions do
		if session.station == index then
			occupied = true
		end
	end
	for _, wall in walls[index] or {} do
		wall.CanCollide = occupied
	end
end

local function buildDummy(session: Session): Model
	local spot = spotAhead(session, TutorialConfig.TargetDistance, 0)
	local position = Vector3.new(spot.X, groundAt(spot.X, spot.Y), spot.Y)
	local model = Instance.new("Model")
	model.Name = "Training Dummy"
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X
	part({ Name = "Post", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 0.8, 0.8), CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * upright, Color = COLORS.Post, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 4.5, 0)) * upright, Color = COLORS.Sack, Material = Enum.Material.Fabric, Parent = model })
	local arms = part({ Name = "Arms", Size = Vector3.new(4.5, 0.6, 0.6), CFrame = CFrame.new(position + Vector3.new(0, 5.2, 0)), Color = COLORS.Post, Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, CFrame = CFrame.new(position + Vector3.new(0, 6.9, 0)), Color = COLORS.Sack, Material = Enum.Material.Fabric, Parent = model })
	model.PrimaryPart = arms -- unrotated, so the bounding box stays upright (damage numbers)
	model:SetAttribute("SparringOwner", session.player.UserId)
	model.Parent = folder
	HealthService.register(model, TutorialConfig.DummyHealth)
	return model
end

local function removeDummy(session: Session)
	if session.dummy then
		session.dummy:Destroy()
		session.dummy = nil
	end
end

local function removePartner(session: Session)
	local partner = session.partner
	if partner then
		partners[partner] = nil
		partner:Destroy()
		session.partner = nil
	end
end

local function removeSparring(session: Session)
	for _, orc in session.sparring do
		orc:Destroy()
	end
	table.clear(session.sparring)
end

local function clearAll(session: Session)
	removeDummy(session)
	removePartner(session)
	removeSparring(session)
end

-- Steps ------------------------------------------------------------------------------------

local enterStep: (Session) -> ()

local function finish(session: Session, completed: boolean)
	local player = session.player
	if sessions[player] ~= session then
		return
	end
	sessions[player] = nil
	session.token += 1
	clearAll(session)
	player:SetAttribute("TutorialStep", "")
	player:SetAttribute("TutorialReplay", nil)
	healFull(player)
	local data = DataService.data(player)
	if completed and data and not session.replay then
		data.Tutorial = true
		data.TutorialStep = nil
	end
	updateWalls(session.station)
	eventRemote:FireClient(player, if completed then "Complete" else "Left")
end

-- One more toward the step's goal; reaching it moves on (after a short pause).
local function progress(session: Session)
	if sessions[session.player] ~= session or session.count >= session.goal then
		return
	end
	session.count += 1
	publish(session)
	if session.count < session.goal then
		return
	end
	session.token += 1 -- the drills stop while the step wraps up
	session.paused = true
	local token = session.token
	eventRemote:FireClient(session.player, "StepDone")
	task.delay(STEP_PAUSE, function()
		if sessions[session.player] == session and session.token == token then
			session.index += 1
			enterStep(session)
		end
	end)
end

-- Whether the SkillsSpend step is done (or can't be done: no points to spend).
local function checkSkills(session: Session)
	if stepId(session) ~= "SkillsSpend" or session.count >= session.goal then
		return
	end
	local player = session.player
	local lesson = TutorialConfig.Weapons[session.weapon]
	if lesson and lesson.Caster then
		local caster = (SkillTrees.Casters :: { [string]: any })[session.weapon]
		if caster then
			for element in caster.ElementUnlocks do
				if SkillMath.spellUnlocked(player, session.weapon, element) then
					progress(session)
					return
				end
			end
		end
		return
	end
	local alloc = SkillMath.allocations(player)
	if SkillMath.spent(alloc) > session.spentAtStart or SkillMath.availablePoints(alloc, SkillMath.level(player)) <= 0 then
		progress(session)
	end
end

-- The sparring partner's swing: a long wind-up with a red glow, then this decides what
-- happened (dodged, parried, blocked or hit) and credits the drill it belongs to.
local function swing(session: Session, partner: Model, root: BasePart, track: AnimationTrack, highlight: Highlight, windup: number, token: number)
	local player = session.player
	local started = os.clock()
	track:Play(0.1, 1, PARTNER.AnimationHit / windup)
	partner:SetAttribute("Attacking", true)
	highlight.FillTransparency, highlight.OutlineTransparency = 1, 1
	TweenService:Create(highlight, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FillTransparency = 0.35, OutlineTransparency = 0 }):Play()
	task.wait(windup)
	partner:SetAttribute("Attacking", false)
	highlight.FillTransparency, highlight.OutlineTransparency = 1, 1

	local character = player.Character
	local target = rootOf(character)
	if session.token ~= token or not partner.Parent or EnemyEffects.isStunned(partner) or not character or not target or not HealthService.isAlive(character) then
		return
	end
	local id = stepId(session)
	local dashed = DashService.lastDash(player) >= started - DASH_SLACK
	local inReach = flat(target.Position - root.Position).Magnitude <= PARTNER.Reach + 1.5
	local result: string
	if not inReach then
		result = if dashed then "Dodge" else "Miss"
	elseif BlockService.tryParry(character, partner) then
		track:Stop(0.05)
		result = "Parry"
	else
		local guarded = player:GetAttribute("Blocking") == true
		local charges = player:GetAttribute("BlockCharges")
		local hadCharges = typeof(charges) == "number" and charges > 0
		local dealt = HealthService.damage(character, PARTNER.Damage, nil, root.Position)
		if dealt > 0 then
			local impact, direction = HitEffects.meleeImpactPoint(character, root.Position)
			HitEffects.broadcast(character, impact, direction, "DemonClaw", dealt)
		end
		if guarded then
			result = if not hadCharges then "GuardOut" elseif id == "Parry" then "Early" else "Block"
		elseif dealt <= 0 and dashed then
			result = "Dodge"
		else
			result = "Hit"
		end
	end
	eventRemote:FireClient(player, "Result", result)
	if result == id or (id == "Block" and result == "Parry") then
		progress(session)
	end
end

-- The sparring partner keeps close to the player, facing them, and swings during the drills.
local function runPartner(session: Session, partner: Model, token: number)
	local humanoid = partner:FindFirstChildOfClass("Humanoid")
	local root = rootOf(partner)
	if not humanoid or not root then
		return
	end
	local attackTrack = EnemyAnimations.start(partner, humanoid, TutorialConfig.SparringOrc)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = PARTNER.TelegraphColor
	highlight.OutlineColor = PARTNER.TelegraphColor
	highlight.FillTransparency, highlight.OutlineTransparency = 1, 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = partner

	local nextSwing = os.clock() + 1.5
	while partner.Parent and sessions[session.player] == session do
		local character = session.player.Character
		local target = rootOf(character)
		local id = stepId(session)
		if session.token == token and not session.paused and character and target and HealthService.isAlive(character) and not EnemyEffects.isStunned(partner) then
			local offset = flat(target.Position - root.Position)
			local distance = offset.Magnitude
			if distance > PARTNER.Reach - 0.5 and distance > 0.1 then
				humanoid:MoveTo(target.Position - offset.Unit * (PARTNER.Reach - 1.5))
			else
				humanoid:MoveTo(root.Position)
			end
			if distance > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(target.Position.X, root.Position.Y, target.Position.Z))
			end
			local windup = id and (PARTNER.Windup :: { [string]: number })[id]
			if windup and distance <= PARTNER.Reach + 2 and os.clock() >= nextSwing then
				swing(session, partner, root, attackTrack, highlight, windup, token)
				nextSwing = os.clock() + PARTNER.Interval
			end
		else
			humanoid:MoveTo(root.Position)
			if session.token ~= token and not session.paused then
				token = session.token -- a new step (the partner stays on for the next drill)
				nextSwing = os.clock() + PARTNER.Interval
			end
		end
		task.wait(PARTNER_TICK)
	end
end

local function spawnPartner(session: Session)
	local token = session.token
	task.spawn(function()
		local partner = EnemyService.spawnPuppet(spotAhead(session, TutorialConfig.TargetDistance, 0), TutorialConfig.SparringOrc, session.player)
		if not partner then
			return
		end
		if sessions[session.player] ~= session or session.token ~= token or session.partner then
			partner:Destroy() -- the step moved on while it loaded
			return
		end
		partners[partner] = true
		session.partner = partner
		runPartner(session, partner, token)
	end)
end

local function spawnSparring(session: Session)
	local token = session.token
	for i = 1, 2 do
		task.spawn(function()
			local side = if i == 1 then -TutorialConfig.SparSpread else TutorialConfig.SparSpread
			local orc = EnemyService.spawnSparring(spotAhead(session, TutorialConfig.TargetDistance + 3, side), TutorialConfig.SparringOrc, session.player)
			if not orc then
				return
			end
			if sessions[session.player] ~= session or session.token ~= token then
				orc:Destroy()
				return
			end
			table.insert(session.sparring, orc)
		end)
	end
end

local COMBAT_STEPS = { Light = true, Heavy = true, LockOn = true, Dodge = true, Block = true, Parry = true, Spar = true }
local PARTNER_STEPS = { LockOn = true, Dodge = true, Block = true, Parry = true }

function enterStep(session: Session)
	local player = session.player
	if sessions[player] ~= session then
		return
	end
	session.token += 1
	session.paused = false
	local id = stepId(session)
	if not id then
		finish(session, true)
		return
	end
	local step = TutorialConfig.step(id, session.weapon)
	session.count = 0
	session.goal = step.Goal or 1
	table.clear(session.credited)
	local data = DataService.data(player)
	if data and not session.replay then
		data.TutorialStep = id
	end
	healFull(player)
	publish(session)

	if id == "Light" or id == "Heavy" then
		if not session.dummy or not session.dummy.Parent then
			session.dummy = buildDummy(session)
		end
	else
		removeDummy(session)
	end
	if PARTNER_STEPS[id] then
		if not session.partner or not session.partner.Parent then
			removePartner(session)
			spawnPartner(session)
		end
	else
		removePartner(session)
	end
	removeSparring(session)
	if id == "Spar" then
		spawnSparring(session)
	end
	if COMBAT_STEPS[id] then
		drawWeapon(session)
	end
	if id == "SkillsSpend" then
		session.spentAtStart = SkillMath.spent(SkillMath.allocations(player))
		task.defer(checkSkills, session)
	end
end

-- Starts training `player` with `weapon`, from step `from` if given (a first-timer's saved step).
local function begin(player: Player, weapon: string, replay: boolean, from: string?)
	if sessions[player] then
		return
	end
	local order = table.clone(TutorialConfig.order(weapon))
	if replay then
		table.remove(order, table.find(order, "Intro") or #order + 1)
	end
	local session: Session = {
		player = player,
		weapon = weapon,
		replay = replay,
		order = order,
		index = (from and table.find(order, from)) or 1,
		count = 0,
		goal = 1,
		station = freeStation(),
		token = 0,
		paused = false,
		dummy = nil,
		partner = nil,
		sparring = {},
		heavySerial = 0,
		heavyHeld = false,
		heavyGraceUntil = 0,
		credited = {},
		spentAtStart = 0,
	}
	sessions[player] = session
	player:SetAttribute("TutorialWeapon", weapon)
	player:SetAttribute("TutorialReplay", replay)
	enterStep(session)
	task.spawn(function()
		placePlayer(session)
		if sessions[player] == session then
			updateWalls(session.station) -- once they're inside
		end
	end)
end

-- A first-timer (picked a starter, never finished) is put straight into training.
local function startIfNew(player: Player)
	local data = DataService.data(player)
	if not data or data.Tutorial or not data.Starter or sessions[player] then
		return
	end
	local weapon = lessonWeapon(player, data, false)
	if weapon then
		begin(player, weapon, false, data.TutorialStep)
	end
end

local function startReplay(player: Player)
	local data = DataService.data(player)
	if not data or sessions[player] then
		return
	end
	local weapon = lessonWeapon(player, data, true)
	if weapon then
		begin(player, weapon, data.Tutorial == true)
	end
end

-- Whether the player stands beside an NPC that runs the training (the drill master).
local function nearTrainer(player: Player): boolean
	local root = rootOf(player.Character)
	if not root then
		return false
	end
	for _, npc in NpcConfig.List do
		if npc.Action == "Training" and (Vector2.new(root.Position.X, root.Position.Z) - npc.Position).Magnitude <= TRAINER_REACH then
			return true
		end
	end
	return false
end

local CLIENT_STEPS = { Intro = true, LockOn = true, SkillsOpen = true }

local function onAction(player: Player, action: unknown)
	if action == "Replay" then
		if nearTrainer(player) then
			startReplay(player)
		end
		return
	end
	local session = sessions[player]
	if typeof(action) ~= "string" or not session then
		return
	end
	if action == "Quit" then
		if session.replay then
			finish(session, false)
		end
		return
	end
	-- Steps only the client can see (its cutscene, camera lock, open panels); nothing rides
	-- on them but getting on with the training.
	if CLIENT_STEPS[action] and stepId(session) == action and (action ~= "LockOn" or session.partner ~= nil) then
		progress(session)
	end
end

-- Hits on a player's own dummy: light or heavy, by whether a heavy is running (or just was).
local function onDummyHit(session: Session)
	local id = stepId(session)
	local heavy = session.heavyHeld or os.clock() <= session.heavyGraceUntil
	if id == "Light" and not heavy then
		progress(session)
	elseif id == "Heavy" and heavy and not session.credited[session.heavySerial] then
		session.credited[session.heavySerial] = true
		progress(session)
	end
end

local function heavyStarted(player: Player)
	local session = sessions[player]
	if session then
		session.heavySerial += 1
		session.heavyHeld = true
	end
end

local function heavyEnded(player: Player)
	local session = sessions[player]
	if session then
		session.heavyHeld = false
		session.heavyGraceUntil = os.clock() + HEAVY_GRACE
	end
end

-- Keeps first-timers in the camp, lets replayers walk out of it, and tops up low health.
local function watch()
	while true do
		task.wait(WATCH_TICK)
		for player, session in sessions do
			local character = player.Character
			local root = rootOf(character)
			if character and root and HealthService.isAlive(character) then
				local station = stationOf(session)
				local away = (Vector2.new(root.Position.X, root.Position.Z) - station.Stand).Magnitude
				if session.replay and away > TutorialConfig.QuitRadius then
					finish(session, false)
				elseif not session.replay and away > TutorialConfig.LeashRadius and stepId(session) ~= "Intro" then
					eventRemote:FireClient(player, "Result", "Leash")
					task.spawn(placePlayer, session)
				end
				local health, maxHealth = HealthService.getHealth(character)
				if health and maxHealth and health < maxHealth * TutorialConfig.HealBelow then
					healFull(player)
				end
			end
		end
	end
end

function TutorialService.start()
	folder.Parent = workspace
	buildCircles()

	HealthService.addDamageFilter(function(target: Model, amount: number, source: Player?): number
		if target.Parent == folder then -- a dummy: only its owner's hits count, and it never breaks
			local session = source and sessions[source]
			if not session or session.dummy ~= target then
				return 0
			end
			onDummyHit(session)
			local health = HealthService.getHealth(target)
			if health and health - amount < TutorialConfig.DummyHealth / 2 then
				task.defer(HealthService.heal, target, math.huge)
			end
			return amount
		end
		if partners[target] then
			return 0 -- the drill partner can't be hurt
		end
		local player = Players:GetPlayerFromCharacter(target)
		if player and sessions[player] then
			local health = HealthService.getHealth(target)
			if health then
				return math.min(amount, health - 1) -- never killed in training
			end
		end
		return amount
	end)

	HealthService.Died:Connect(function(model: Model)
		for _, session in sessions do
			local index = table.find(session.sparring, model)
			if index and stepId(session) == "Spar" then
				progress(session)
			end
		end
	end)

	local function onPlayerAdded(player: Player)
		player:GetAttributeChangedSignal("HeavyAttacking"):Connect(function()
			if player:GetAttribute("HeavyAttacking") == true then
				heavyStarted(player)
			else
				heavyEnded(player)
			end
		end)
		player:GetAttributeChangedSignal("Starter"):Connect(function()
			startIfNew(player)
		end)
		player:GetAttributeChangedSignal("Skills"):Connect(function()
			local session = sessions[player]
			if session then
				checkSkills(session)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			local session = sessions[player]
			if not session then
				return
			end
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2) -- let the other services set the new character up first
			if sessions[player] == session then
				placePlayer(session)
				enterStep(session) -- the step starts over (its dummy or orcs come back)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			sessions[player] = nil
			session.token += 1
			clearAll(session)
			updateWalls(session.station)
		end
	end)

	-- The greatsword's charge doesn't set "HeavyAttacking"; its own remotes say when it starts
	-- and ends (only a timestamp is kept, so a fake one just counts a heavy that didn't land).
	greatswordCharge.OnServerEvent:Connect(heavyStarted)
	greatswordRelease.OnServerEvent:Connect(heavyEnded)

	DataService.onLoaded(function(player)
		startIfNew(player)
	end)
	RemoteGuard.connect(actionRemote, onAction)
	task.spawn(watch)
end

return TutorialService
