--!strict
-- Server-authoritative quests: accepts quests from the town board, tracks kills, lets players
-- choose which active quest is tracked, and grants rewards. Quest state is saved in DataService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcConfig = require(ReplicatedStorage.Shared.Config.NpcConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)
local ProgressionService = require(script.Parent.ProgressionService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boardRemote = remotes:WaitForChild("QuestBoardOpen") :: RemoteEvent
local startRemote = remotes:WaitForChild("QuestStart") :: RemoteEvent
local cancelRemote = remotes:WaitForChild("QuestCancel") :: RemoteEvent
local trackRemote = remotes:WaitForChild("QuestTrack") :: RemoteEvent

local BOARD_NAME = "QuestBoard"
local BOARD_RANGE = NpcConfig.CloseDistance
local BOARD_COLOR = Color3.fromRGB(78, 48, 28)
local PAPER_COLOR = Color3.fromRGB(235, 225, 190)
local PIN_COLOR = Color3.fromRGB(160, 55, 45)

local QuestService = {}

local function firstActive(data: DataService.Data): string?
	for _, quest in QuestConfig.Quests do
		if data.Quests.Active[quest.Id] then
			return quest.Id
		end
	end
	return nil
end

local function trackingId(data: DataService.Data): string?
	local tracking = data.Quests.Tracking
	if tracking and data.Quests.Active[tracking] then
		return tracking
	end
	local first = firstActive(data)
	data.Quests.Tracking = first
	return first
end

local function progressOf(progress: { [string]: number }, target: QuestConfig.Target): number
	return math.clamp(progress[QuestConfig.targetKey(target)] or 0, 0, target.Count)
end

local function totalProgress(progress: { [string]: number }, quest: QuestConfig.Quest): number
	local total = 0
	for _, target in quest.Targets do
		total += progressOf(progress, target)
	end
	return total
end

local function progressDetail(progress: { [string]: number }, quest: QuestConfig.Quest): string
	local parts: { string } = {}
	for _, target in quest.Targets do
		table.insert(parts, `{QuestConfig.targetKey(target)}={progressOf(progress, target)}`)
	end
	return table.concat(parts, ",")
end

local function activeList(data: DataService.Data): string
	local ids: { string } = {}
	for _, quest in QuestConfig.Quests do
		if data.Quests.Active[quest.Id] then
			table.insert(ids, quest.Id)
		end
	end
	return table.concat(ids, ",")
end

local function activeProgressList(data: DataService.Data): string
	local entries: { string } = {}
	for _, quest in QuestConfig.Quests do
		local progress = data.Quests.Active[quest.Id]
		if progress then
			table.insert(entries, `{quest.Id};{progressDetail(progress, quest)}`)
		end
	end
	return table.concat(entries, "|")
end

local function publish(player: Player)
	local data = DataService.data(player)
	local tracked = data and trackingId(data)
	local quest = tracked and QuestConfig.quest(tracked)
	local progress = if data and tracked then data.Quests.Active[tracked] else nil
	local completed: { string } = {}
	if data then
		for id, done in data.Quests.Completed do
			if done then
				table.insert(completed, id)
			end
		end
	end
	player:SetAttribute("QuestActive", tracked)
	player:SetAttribute("QuestActiveList", if data then activeList(data) else "")
	player:SetAttribute("QuestActiveProgress", if data then activeProgressList(data) else "")
	player:SetAttribute("QuestProgress", if progress and quest then totalProgress(progress, quest) else 0)
	player:SetAttribute("QuestTarget", quest and QuestConfig.totalTarget(quest) or 0)
	player:SetAttribute("QuestTitle", quest and quest.Title or "")
	player:SetAttribute("QuestProgressDetail", if progress and quest then progressDetail(progress, quest) else "")
	player:SetAttribute("QuestTargetPosition", if quest then Vector3.new(quest.TargetPosition.X, 0, quest.TargetPosition.Y) else nil)
	player:SetAttribute("QuestCompleted", table.concat(completed, ","))
end

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
	return if hit then hit.Position.Y else 0
end

local function boardCFrame(): CFrame
	local board = QuestConfig.Board
	local pos = board.Position
	local y = groundAt(pos.X, pos.Y)
	local facing = Vector3.new(board.Facing.X, 0, board.Facing.Y)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.new(pos.X, y, pos.Y), Vector3.new(pos.X, y, pos.Y) + facing)
end

local function atBoard(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart") and HealthService.isAlive(character)) then
		return false
	end
	local pos = QuestConfig.Board.Position
	local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Y)
	return flat.Magnitude <= BOARD_RANGE
end

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
	instance.Parent = props.Parent
	return instance
end

local function addText(target: BasePart, text: string, size: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.Parent = target

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.Text = text
	label.TextSize = size
	label.TextScaled = false
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(60, 38, 24)
	label.Parent = gui
end

local function addPaper(parent: Model, origin: CFrame, offset: Vector3, rotation: number, quest: QuestConfig.Quest)
	local paper = part({ Name = `QuestPaper_{quest.Id}`, Size = Vector3.new(2.55, 2.85, 0.08), CFrame = origin * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(rotation)), Color = PAPER_COLOR, Material = Enum.Material.SmoothPlastic, Parent = parent })
	addText(paper, `{quest.Title}\n{quest.Description}\n{quest.RewardXP} XP / {quest.RewardCoins} coins`, 19)
	for _, pinOffset in { Vector3.new(-1.02, 1.2, -0.055), Vector3.new(1.02, 1.2, -0.055) } do
		part({ Name = "Pin", ClassName = "Part", Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18), CFrame = paper.CFrame * CFrame.new(pinOffset), Color = PIN_COLOR, Material = Enum.Material.Metal, Parent = parent })
	end
end

local function findTownBoard(): BasePart?
	local town = workspace:FindFirstChild("Town")
	if not town then
		return nil
	end
	local notice = town:FindFirstChild("NoticeBoard")
	if notice then
		local part = notice:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part
		end
	end
	local fallback = town:FindFirstChild("QuestBoard", true)
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end
	return nil
end

local function buildBoard()
	local old = workspace:FindFirstChild(BOARD_NAME)
	if old then
		old:Destroy()
	end

	local boardPart = findTownBoard()
	if not boardPart then
		local model = Instance.new("Model")
		model.Name = BOARD_NAME
		local origin = boardCFrame()
		part({ Name = "LeftPost", Size = Vector3.new(0.5, 6.6, 0.5), CFrame = origin * CFrame.new(-3.6, 3.3, 0.25), Color = BOARD_COLOR, Material = Enum.Material.Wood, Parent = model })
		part({ Name = "RightPost", Size = Vector3.new(0.5, 6.6, 0.5), CFrame = origin * CFrame.new(3.6, 3.3, 0.25), Color = BOARD_COLOR, Material = Enum.Material.Wood, Parent = model })
		part({ Name = "Header", Size = Vector3.new(8.2, 0.5, 0.5), CFrame = origin * CFrame.new(0, 6.25, 0.25), Color = BOARD_COLOR, Material = Enum.Material.Wood, Parent = model })
		part({ Name = "Footer", Size = Vector3.new(8, 0.42, 0.45), CFrame = origin * CFrame.new(0, 1.7, 0.25), Color = BOARD_COLOR, Material = Enum.Material.Wood, Parent = model })
		local board = part({ Name = "Board", Size = Vector3.new(7.6, 4.25, 0.35), CFrame = origin * CFrame.new(0, 3.95, 0), Color = Color3.fromRGB(105, 68, 38), Material = Enum.Material.Wood, Parent = model })
		local sign = part({ Name = "BoardTitle", Size = Vector3.new(3.6, 0.55, 0.08), CFrame = origin * CFrame.new(0, 5.8, -0.24), Color = Color3.fromRGB(190, 150, 85), Material = Enum.Material.Wood, Parent = model })
		addText(sign, "QUEST BOARD", 24)
		local paperOffsets = { Vector3.new(-1.9, 4.05, -0.25), Vector3.new(1.8, 3.8, -0.25) }
		for index, quest in QuestConfig.Quests do
			addPaper(model, origin, paperOffsets[index] or Vector3.new(0, 3.35, -0.25), if index % 2 == 0 then 4 else -3, quest)
		end
		model.Parent = workspace
		boardPart = board
	end

	local prompt = boardPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "View Quests"
		prompt.ObjectText = "Quest Board"
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = boardPart
		prompt.Triggered:Connect(function(player)
			boardRemote:FireClient(player)
		end)
	end
end

local function reward(player: Player, quest: QuestConfig.Quest)
	CurrencyService.add(player, quest.RewardCoins)
	ProgressionService.addXP(player, quest.RewardXP)
end

local function complete(player: Player, data: DataService.Data, quest: QuestConfig.Quest)
	data.Quests.Active[quest.Id] = nil
	if data.Quests.Tracking == quest.Id then
		data.Quests.Tracking = firstActive(data)
	end
	reward(player, quest)
end

local function onStart(player: Player, questId: unknown)
	if typeof(questId) ~= "string" or not atBoard(player) then
		return
	end
	local quest = QuestConfig.quest(questId)
	local data = DataService.data(player)
	if not quest or not data or data.Quests.Active[quest.Id] then
		return
	end
	data.Quests.Active[quest.Id] = {}
	data.Quests.Tracking = data.Quests.Tracking or quest.Id
	publish(player)
end

local function onCancel(player: Player, questId: unknown)
	if typeof(questId) ~= "string" then
		return
	end
	local data = DataService.data(player)
	if not data or not data.Quests.Active[questId] then
		return
	end
	data.Quests.Active[questId] = nil
	if data.Quests.Tracking == questId then
		data.Quests.Tracking = firstActive(data)
	end
	publish(player)
end

local function onTrack(player: Player, questId: unknown)
	if typeof(questId) ~= "string" then
		return
	end
	local data = DataService.data(player)
	if not data or not data.Quests.Active[questId] then
		return
	end
	data.Quests.Tracking = questId
	publish(player)
end

local function onTargetDied(model: Model, killer: Player?)
	if not killer or Players:GetPlayerFromCharacter(model) then
		return
	end
	local data = DataService.data(killer)
	if not data then
		return
	end
	local killedKind = if model:GetAttribute("EnemyId") then "Enemy" elseif model:GetAttribute("Animal") then "Animal" else nil
	local killedId = model:GetAttribute("EnemyId") or model:GetAttribute("Animal")
	if typeof(killedKind) ~= "string" or typeof(killedId) ~= "string" then
		return
	end
	local completed: { QuestConfig.Quest } = {}
	for questId, progress in data.Quests.Active do
		local quest = QuestConfig.quest(questId)
		if not quest then
			continue
		end
		local matched: QuestConfig.Target? = nil
		for _, target in quest.Targets do
			if target.Kind == killedKind and target.Id == killedId then
				matched = target
				break
			end
		end
		if not matched then
			continue
		end
		local key = QuestConfig.targetKey(matched)
		progress[key] = math.min(matched.Count, (progress[key] or 0) + 1)
		local completeAll = true
		for _, target in quest.Targets do
			if progressOf(progress, target) < target.Count then
				completeAll = false
				break
			end
		end
		if completeAll then
			table.insert(completed, quest)
		end
	end
	if #completed == 0 then
		publish(killer)
		return
	end
	for _, quest in completed do
		complete(killer, data, quest)
	end
	publish(killer)
end

function QuestService.start()
	DataService.onLoaded(function(player)
		publish(player)
	end)
	Players.PlayerAdded:Connect(publish)
	for _, player in Players:GetPlayers() do
		publish(player)
	end
	RemoteGuard.connect(startRemote, onStart)
	RemoteGuard.connect(cancelRemote, onCancel)
	RemoteGuard.connect(trackRemote, onTrack)
	HealthService.Died:Connect(onTargetDied)
	buildBoard()
end

return QuestService
