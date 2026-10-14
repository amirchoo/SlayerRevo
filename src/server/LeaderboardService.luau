--!strict
-- The Hall of Hunters: the trophy board by the Hunters' Guild (TownBuilder's "trophies" prop)
-- lists the top 10 hunters by level, across every server. Each player's level (with their XP
-- as the tie-break) is kept in an OrderedDataStore, written now and then while they play and
-- when they leave. If the store can't be reached (e.g. Studio without API access), the board
-- ranks the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "HunterLevels_v1"
local BOARD_SIZE = 10
local INTERVAL = 90 -- seconds between writing players' scores and re-reading the top 10
local XP_SCALE = 1e7 -- score = level * XP_SCALE + XP, so XP only breaks ties
local TEXT = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(255, 205, 90)
local DIM = Color3.fromRGB(200, 180, 150)

local LeaderboardService = {}

type Entry = { userId: number, name: string, level: number }

local store: OrderedDataStore? = nil
local saved: { [number]: number } = {} -- the score last written for each player
local names: { [number]: string } = {}
local rows: { TextLabel } = {}

local function score(player: Player): number?
	local level, xp = player:GetAttribute("Level"), player:GetAttribute("XP")
	if typeof(level) ~= "number" then
		return nil
	end
	return math.floor(level) * XP_SCALE + math.clamp(math.floor(if typeof(xp) == "number" then xp else 0), 0, XP_SCALE - 1)
end

local function save(player: Player)
	local value = score(player)
	if not store or not value or saved[player.UserId] == value then
		return
	end
	local ok = pcall(function()
		(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
	end)
	if ok then
		saved[player.UserId] = value
	end
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local found = if player then player.DisplayName elseif ok then name else "Hunter"
	names[userId] = found
	return found
end

-- The top hunters from the store, or from this server's players if it can't be read.
local function topHunters(): { Entry }
	local entries: { Entry } = {}
	local ok = store ~= nil and pcall(function()
		local pages = (store :: OrderedDataStore):GetSortedAsync(false, BOARD_SIZE)
		for _, item in pages:GetCurrentPage() do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, { userId = userId, name = "", level = math.floor(item.value / XP_SCALE) })
			end
		end
	end)
	if not ok then
		entries = {}
		local ranked: { { player: Player, score: number } } = {}
		for _, player in Players:GetPlayers() do
			local value = score(player)
			if value then
				table.insert(ranked, { player = player, score = value })
			end
		end
		table.sort(ranked, function(a, b)
			return a.score > b.score
		end)
		for index = 1, math.min(BOARD_SIZE, #ranked) do
			local player = ranked[index].player
			table.insert(entries, { userId = player.UserId, name = player.DisplayName, level = math.floor(ranked[index].score / XP_SCALE) })
		end
	end
	for _, entry in entries do
		if entry.name == "" then
			entry.name = nameOf(entry.userId)
		end
	end
	return entries
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, align: Enum.TextXAlignment): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Size = size
	item.Position = position
	item.Font = Enum.Font.Fantasy
	item.TextScaled = true
	item.TextColor3 = color
	item.TextXAlignment = align
	item.TextStrokeTransparency = 0.6
	item.Text = text
	item.Parent = parent
	return item
end

-- The board's SurfaceGui: a heading and BOARD_SIZE rows.
local function buildBoard(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	gui.MaxDistance = 120
	gui.Parent = board
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(0.9, 0.92)
	frame.Position = UDim2.fromScale(0.05, 0.04)
	frame.Parent = gui
	label(frame, "Top Hunters by Level", UDim2.fromScale(1, 0.12), UDim2.fromScale(0, 0), GOLD, Enum.TextXAlignment.Center)
	local rowHeight = 0.86 / BOARD_SIZE
	for index = 1, BOARD_SIZE do
		local y = 0.14 + (index - 1) * rowHeight
		local row = label(frame, "", UDim2.fromScale(1, rowHeight * 0.9), UDim2.fromScale(0, y), if index <= 3 then GOLD else TEXT, Enum.TextXAlignment.Left)
		table.insert(rows, row)
	end
end

local function refresh()
	local entries = topHunters()
	for index, row in rows do
		local entry = entries[index]
		row.Text = if entry then `{index}.  {entry.name}  ·  Lv {entry.level}` else `{index}.  —`
		row.TextColor3 = if not entry then DIM elseif index <= 3 then GOLD else TEXT
	end
end

function LeaderboardService.start()
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, STORE_NAME)
	store = if ok then result else nil

	local town = workspace:FindFirstChild("Town")
	local board = town and town:FindFirstChild("TrophyBoard", true)
	if board and board:IsA("BasePart") then
		buildBoard(board)
	else
		warn("[LeaderboardService] No TrophyBoard in workspace.Town; the leaderboard isn't shown")
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		saved[player.UserId] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(INTERVAL)
			for _, player in Players:GetPlayers() do
				save(player)
			end
		end
	end)
	-- A new player shows up on the board soon after joining (not a full interval later).
	Players.PlayerAdded:Connect(function(player)
		task.delay(10, function()
			save(player)
			refresh()
		end)
	end)
end

return LeaderboardService
