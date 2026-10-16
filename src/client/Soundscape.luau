--!strict
-- Music and background ambience on this screen, by where you are (looks and sounds only):
--   * music: a shuffled playlist for each kind of place (Sounds.Music): Town in the safe zone,
--     Wilds outside it, Dungeon in a dungeon run, a boss fight's while a boss you're near is
--     awake (its own "Boss:<Id>" playlist if it has one, else Boss).
--     Moving between them crossfades; a track that ends is followed by the next in the list
--     after a short pause;
--   * ambience: wind out in the wilds, a low cave hum and trickling water in a dungeon (town
--     birds and crickets are TownAmbience's, which hushes them in a dungeon).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SafeZone = require(ReplicatedStorage.Shared.SafeZone)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local MUSIC_VOLUME = 0.4 -- the music's overall volume
local AMBIENCE_VOLUME = 1 -- the ambience's overall volume
local FADE_TIME = 2.5 -- seconds a crossfade takes
local TRACK_GAP = { 4, 10 } -- seconds of quiet between one track ending and the next
local CHECK_INTERVAL = 0.5 -- seconds between looking at where you are
local BOSS_RANGE = 160 -- studs: a boss this close that's awake means boss music

local player = Players.LocalPlayer

local Soundscape = {}

-- "Town", "Wilds", "Dungeon", "Boss" or "Boss:<Id>" (a Sounds.Music playlist).
type Place = string

local random = Random.new()
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = MUSIC_VOLUME
local ambienceGroup = Instance.new("SoundGroup")
ambienceGroup.Name = "Ambience"
ambienceGroup.Volume = AMBIENCE_VOLUME

local function inDungeon(): boolean
	return typeof(player:GetAttribute("Dungeon")) == "string"
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The playlist for an awake boss near you (in a dungeon run), if there is one.
local function bossFight(me: BasePart): Place?
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then
		return nil
	end
	for _, model in enemies:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Boss") then
			local state = model:GetAttribute("BossState")
			local root = rootOf(model)
			if (state == "Intro" or state == "Fight") and root and (root.Position - me.Position).Magnitude <= BOSS_RANGE then
				local own = `Boss:{model:GetAttribute("BossId")}`
				return if Sounds.Music[own] then own else "Boss"
			end
		end
	end
	return nil
end

local function isBoss(where: Place): boolean
	return string.sub(where, 1, 4) == "Boss"
end

local function currentPlace(): Place
	local me = rootOf(player.Character)
	if inDungeon() then
		return (if me then bossFight(me) else nil) or "Dungeon"
	end
	if me and not SafeZone.contains(me.Position) then
		return "Wilds"
	end
	return "Town"
end

-- Music ------------------------------------------------------------------------------------

type Playing = { sound: Sound, volume: number, place: Place }
local playing: Playing? = nil
local fading: { Playing } = {} -- old tracks fading out
local place: Place? = nil
local order: { [Place]: { number } } = {} -- each playlist's shuffled order, and where it's up to
local nextAt: number? = nil -- when the next track starts after one ended

local function nextTrack(where: Place): Sounds.Track?
	local list = Sounds.Music[where]
	if not list or #list == 0 then
		return nil
	end
	local queue = order[where]
	if not queue or #queue == 0 then
		queue = {}
		for i = 1, #list do
			table.insert(queue, random:NextInteger(1, #queue + 1), i)
		end
		order[where] = queue
	end
	return list[table.remove(queue, 1) :: number]
end

local function startTrack(where: Place)
	local track = nextTrack(where)
	if not track then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = where .. "Music"
	sound.SoundId = track.Id
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	local entry: Playing = { sound = sound, volume = track.Volume, place = where }
	sound.Ended:Connect(function()
		if playing == entry then
			playing = nil
			sound:Destroy()
			nextAt = os.clock() + random:NextNumber(TRACK_GAP[1], TRACK_GAP[2])
		end
	end)
	sound:Play()
	playing = entry
	nextAt = nil
end

local function setPlace(where: Place)
	if where == place then
		return
	end
	place = where
	if playing then
		table.insert(fading, playing)
		playing = nil
	end
	startTrack(where)
end

-- Ambience ---------------------------------------------------------------------------------

type Loop = { sound: Sound, volume: number, wanted: (Place) -> boolean }
local loops: { Loop } = {}

local function addLoop(name: string, wanted: (Place) -> boolean)
	local sound = Sounds.create(name, SoundService)
	if not sound then
		return
	end
	local volume = sound.Volume
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = ambienceGroup
	sound:Play()
	table.insert(loops, { sound = sound, volume = volume, wanted = wanted })
end

-- Fades `current` toward `target` at the crossfade's pace.
local function approach(current: number, target: number, dt: number, full: number): number
	local step = full * dt / FADE_TIME
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

function Soundscape.start()
	musicGroup.Parent = SoundService
	ambienceGroup.Parent = SoundService
	addLoop("WindWilds", function(where)
		return where == "Wilds"
	end)
	addLoop("CaveAmbience", function(where)
		return where == "Dungeon" or isBoss(where)
	end)
	addLoop("CaveTrickle", function(where)
		return where == "Dungeon"
	end)

	local since = math.huge
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= CHECK_INTERVAL then
			since = 0
			setPlace(currentPlace())
		end
		if not playing and nextAt and os.clock() >= nextAt and place then
			startTrack(place)
		end
		if playing then
			playing.sound.Volume = approach(playing.sound.Volume, playing.volume, dt, playing.volume)
		end
		for index = #fading, 1, -1 do
			local old = fading[index]
			old.sound.Volume = approach(old.sound.Volume, 0, dt, old.volume)
			if old.sound.Volume <= 0 then
				old.sound:Destroy()
				table.remove(fading, index)
			end
		end
		for _, loop in loops do
			local target = if place and loop.wanted(place) then loop.volume else 0
			loop.sound.Volume = approach(loop.sound.Volume, target, dt, loop.volume)
		end
	end)
end

return Soundscape
