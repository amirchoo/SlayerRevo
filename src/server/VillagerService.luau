--!strict
-- Villagers (VillagerConfig): plain townsfolk strolling their routes round Beginning Town.
-- Each is an R15 figure in workspace.Villagers that walks point to point (pausing at Stops);
-- the client animates their stroll (VillagerAnimator). When a player walks up, the villager
-- stops, turns to them and says a greeting; at stops they sometimes mutter to themselves.
-- What they say is set as the "Say" attribute (with a "SayCount" that changes every time, so
-- the same line twice still shows); the client draws it as a chat bubble (VillagerChat).
-- They have no Health attribute, so they can't be hurt or locked on to.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VillagerConfig = require(ReplicatedStorage.Shared.Config.VillagerConfig)
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)

local SKIN_TONES = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105), Color3.fromRGB(160, 105, 75), Color3.fromRGB(245, 205, 175) }
local TICK = 0.3 -- seconds between each villager's checks
local REACH = 2.5 -- studs from a point that counts as there
local STUCK_TIME = 4 -- seconds without getting any closer to a point before skipping it

local VillagerService = {}

local folder = Instance.new("Folder")
folder.Name = "Villagers"
local random = Random.new()

local function groundAt(point: Vector2): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain, workspace:FindFirstChild("Town") or workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(point.X, 300, point.Y), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position else Vector3.new(point.X, 0, point.Y)
end

local function pick(list: { string }): string
	return list[random:NextInteger(1, #list)]
end

local function say(model: Model, text: string)
	model:SetAttribute("Say", text)
	model:SetAttribute("SayCount", ((model:GetAttribute("SayCount") :: number?) or 0) + 1)
end

-- The nearest player within TalkRange of `position`, who this villager hasn't greeted lately.
local function playerToGreet(position: Vector3, greeted: { [Player]: number }): Player?
	local now = os.clock()
	local best: Player?, bestDistance = nil, VillagerConfig.TalkRange
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance and now >= (greeted[player] or 0) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function makeFigure(villager: VillagerConfig.Villager, index: number): (Model?, Humanoid?, BasePart?)
	local skin = villager.Skin or SKIN_TONES[(index - 1) % #SKIN_TONES + 1]
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = villager.Shirt
	description.LeftLegColor = villager.Pants
	description.RightLegColor = villager.Pants
	local ok, result = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[VillagerService] Couldn't make a villager:", result)
		return nil, nil, nil
	end
	local model = result :: Model
	model.Name = "Villager"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- reaches clients whole, joints and all
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy() -- the default Animate script; the client animates them (VillagerAnimator)
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = VillagerConfig.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy() -- no animation tracks: the client poses their joints (VillagerAnimator)
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	return model, humanoid, root
end

local function run(villager: VillagerConfig.Villager, index: number)
	local model, humanoid, root = makeFigure(villager, index)
	if not model or not humanoid or not root then
		return
	end
	local route = villager.Route
	local at = random:NextInteger(1, #route)
	local start = groundAt(route[at].At)
	model:PivotTo(CFrame.new(start + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.2, 0)))
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local greeted: { [Player]: number } = {}
	local pauseUntil = 0
	local goalSince = os.clock() -- when it last got closer to the point it's heading for
	local closest = math.huge -- its closest distance to that point so far
	while model.Parent do
		local now = os.clock()
		local target = playerToGreet(root.Position, greeted)
		if target then
			-- Stop, face them and say hello.
			greeted[target] = now + VillagerConfig.TalkCooldown
			local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			humanoid:MoveTo(root.Position)
			if targetRoot and targetRoot:IsA("BasePart") then
				local look = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
				if (look - root.Position).Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(root.Position, look)
				end
			end
			say(model, pick(if DayCycle.isNight() then VillagerConfig.NightGreetings else VillagerConfig.Greetings))
			pauseUntil = math.max(pauseUntil, now + VillagerConfig.TalkTime)
			goalSince = pauseUntil -- the time talking doesn't count as stuck
			closest = math.huge
		elseif now >= pauseUntil then
			local point = route[at]
			local goal = groundAt(point.At)
			local flat = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
			if flat.Magnitude < closest - 0.5 then
				closest = flat.Magnitude
				goalSince = now
			end
			if flat.Magnitude <= REACH or now - goalSince > STUCK_TIME then
				-- Arrived (or stuck): pause if it's a stop, then on to the next point.
				if point.Stop and flat.Magnitude <= REACH then
					humanoid:MoveTo(root.Position)
					pauseUntil = now + random:NextNumber(VillagerConfig.StopTime[1], VillagerConfig.StopTime[2])
					if random:NextNumber() < VillagerConfig.MutterChance then
						say(model, pick(VillagerConfig.Mutters))
					end
				end
				at = at % #route + 1
				goalSince = math.max(now, pauseUntil)
				closest = math.huge
			else
				humanoid:MoveTo(goal)
			end
		end
		for player in greeted do
			if player.Parent == nil then
				greeted[player] = nil
			end
		end
		task.wait(TICK)
	end
end

-- Call after the town is built (they walk on it).
function VillagerService.start()
	folder.Parent = workspace
	for index, villager in VillagerConfig.List do
		task.spawn(run, villager, index) -- making a figure waits on Roblox
	end
end

return VillagerService
