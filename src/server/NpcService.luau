--!strict
-- Spawns the townsfolk in NpcConfig: anchored R15 figures standing on whatever's under them
-- (plaza, road, ground), each with a "Talk" prompt (client Nameplates draws their name and title).
-- Talking is shown by the client (Dialogue), which finds the NPC from the prompt's "NpcId"
-- attribute; NPCs have no Health attribute, so they can't be hurt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)

local SKIN = Color3.fromRGB(234, 184, 146)

local NpcService = {}

local folder = Instance.new("Folder")
folder.Name = "Townsfolk"

-- Where an NPC at X/Z stands: the top of whatever's there (ignoring other NPCs and players).
local function groundAt(x: number, z: number): number
	local exclude: { Instance } = { folder }
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

local function spawnNpc(npc: NpcConfig.Npc)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.LeftArmColor = SKIN
	description.RightArmColor = SKIN
	description.TorsoColor = npc.Shirt
	description.LeftLegColor = npc.Pants
	description.RightLegColor = npc.Pants
	local ok, result = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn(`[NpcService] Couldn't make {npc.Name}:`, result)
		return
	end

	local model = result :: Model
	model.Name = npc.Name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = npc.Name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- the client draws name and title (Nameplates)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true

	local ground = Vector3.new(npc.Position.X, groundAt(npc.Position.X, npc.Position.Y), npc.Position.Y)
	local facing = Vector3.new(npc.Facing.X, 0, npc.Facing.Y)
	local base = if facing.Magnitude > 0.01 then CFrame.lookAt(ground, ground + facing) else CFrame.new(ground)
	model:PivotTo(base * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = npc.Name
	prompt.MaxActivationDistance = NpcConfig.TalkDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("NpcId", npc.Id)
	prompt.Parent = root

	model.Parent = folder
end

-- Where an NPC stands (on the ground), for range checks; nil if there's no such NPC.
function NpcService.position(id: string): Vector3?
	local npc = NpcConfig.get(id)
	if not npc then
		return nil
	end
	local model = folder:FindFirstChild(npc.Name)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else Vector3.new(npc.Position.X, 0, npc.Position.Y)
end

-- Call after the town is built, so NPCs stand on it.
function NpcService.start()
	folder.Parent = workspace
	for _, npc in NpcConfig.List do
		task.spawn(spawnNpc, npc) -- making a figure waits on Roblox
	end
end

return NpcService
