--!strict
-- Every sound the game plays, in one place. To upgrade one, find a sound in the Creator
-- Store (Toolbox > Audio, e.g. "sword hit", "metal clang", "blunt impact", "whoosh") and
-- paste its ID as "rbxassetid://123..." into Id. Set Id = "" to silence a sound.
--
-- Most are free Creator Store sounds (Pro Sound Effects where it had a fit). ChargeLevel
-- is still a sound bundled with Roblox (rbxasset://sounds/...), re-pitched per level.
--
-- One-shot sounds (play, replay) vary their pitch a little each time (PITCH_VARIATION) so
-- repeated hits and swings don't grate; a spec with Steady = true always plays exactly.

export type SoundSpec = {
	Id: string,
	Pitch: number, -- playback speed: below 1 = deeper/heavier, above 1 = higher/sharper
	Volume: number,
	Steady: boolean?, -- true: never vary the pitch (its pitch carries meaning)
}

local PITCH_VARIATION = 0.1 -- one-shots play up to 10% higher or lower

local TICK = "rbxasset://sounds/volume_slider.ogg"

local SPECS: { [string]: SoundSpec } = {
	-- Swings (played on the attacker's own screen on every attack, hit or miss). The
	-- bladed weapons slash; the blunt ones and the spear whoosh.
	SwordSwing = { Id = "rbxassetid://75603792288640", Pitch = 1, Volume = 0.6 },
	MaceSwing = { Id = "rbxassetid://127747416982963", Pitch = 0.85, Volume = 0.55 },
	SpearSwing = { Id = "rbxassetid://128213617026859", Pitch = 1.15, Volume = 0.45 },
	RapierSwing = { Id = "rbxassetid://137418191870543", Pitch = 1, Volume = 0.5 }, -- also each stab of the flurry, faster with charge
	GreatswordSwing = { Id = "rbxassetid://137628815514180", Pitch = 1, Volume = 0.6 },
	GreatswordSlam = { Id = "rbxassetid://140277245983305", Pitch = 1, Volume = 0.8 }, -- the charged slam, as it lands
	AxeSwing = { Id = "rbxassetid://72106360544198", Pitch = 0.75, Volume = 0.6 },
	DaggerSwing = { Id = "rbxassetid://140180249061198", Pitch = 1.3, Volume = 0.5 },
	DualBladeSwing = { Id = "rbxassetid://7118966167", Pitch = 1.2, Volume = 0.5 },
	HammerSwing = { Id = "rbxassetid://101266427032050", Pitch = 0.8, Volume = 0.7 },
	ScytheSwing = { Id = "rbxassetid://75603792288640", Pitch = 0.8, Volume = 0.65 },
	StaffCast = { Id = "rbxassetid://106456870308007", Pitch = 1.3, Volume = 0.4 },
	StaffBlast = { Id = "rbxassetid://139681553729333", Pitch = 1.1, Volume = 0.5 },

	-- Impacts when an enemy is hit (heard by everyone nearby): plain impacts with no voices,
	-- since the swing already carries the slash.
	SwordHit = { Id = "rbxassetid://116062165012558", Pitch = 1.1, Volume = 0.8 },
	MaceHit = { Id = "rbxassetid://9113568548", Pitch = 0.75, Volume = 1 },
	SpearHit = { Id = "rbxassetid://79890059692096", Pitch = 1.15, Volume = 0.75 },
	RapierHit = { Id = "rbxassetid://137127080014551", Pitch = 1, Volume = 0.6 },
	GreatswordHit = { Id = "", Pitch = 1, Volume = 0.5 }, -- silent: the swing and slam sounds already land with the hit
	AxeHit = { Id = "rbxassetid://115144773187007", Pitch = 0.85, Volume = 0.9 },
	DaggerHit = { Id = "rbxassetid://83174011180310", Pitch = 1, Volume = 0.6 },
	DualBladeHit = { Id = "rbxassetid://121630173864664", Pitch = 1, Volume = 0.6 },
	HammerHit = { Id = "rbxassetid://9113225986", Pitch = 0.8, Volume = 1 },
	ScytheHit = { Id = "rbxassetid://116062165012558", Pitch = 0.9, Volume = 0.8 },
	StaffFireHit = { Id = "rbxassetid://139681553729333", Pitch = 1.3, Volume = 0.55 },
	StaffWaterHit = { Id = "rbxassetid://9125703168", Pitch = 1, Volume = 0.8 },
	StaffEarthHit = { Id = "rbxassetid://9118627392", Pitch = 0.85, Volume = 1 },
	StaffElectricHit = { Id = "rbxassetid://9114277757", Pitch = 1.1, Volume = 0.7 },
	GrimoireFaithHit = { Id = "rbxassetid://137715760191944", Pitch = 1, Volume = 0.6 },
	GrimoireNecromancyHit = { Id = "rbxassetid://131653988627020", Pitch = 0.9, Volume = 0.7 },
	BowHit = { Id = "rbxassetid://129822254617682", Pitch = 1.1, Volume = 0.7 },
	CrossbowHit = { Id = "rbxassetid://131010454040062", Pitch = 0.85, Volume = 0.85 },
	BlunderbussHit = { Id = "rbxassetid://133794731281686", Pitch = 1.1, Volume = 0.35 }, -- per pellet, so quieter

	-- Movement.
	DashWhoosh = { Id = "rbxassetid://104835897489348", Pitch = 1.2, Volume = 0.4 }, -- a dash (heard by everyone nearby)

	-- Other feedback.
	Block = { Id = "rbxassetid://136623299198321", Pitch = 1, Volume = 0.8 }, -- a blocked hit
	ParryHit = { Id = "rbxassetid://137580087669661", Pitch = 1, Volume = 0.8 }, -- a parried hit, every weapon (heard by everyone nearby)
	ChargeLevel = { Id = TICK, Pitch = 1, Volume = 0.8, Steady = true }, -- greatsword charge level reached (pitch rises per level)
	Heartbeat = { Id = "rbxassetid://176554627", Pitch = 1, Volume = 0.6 }, -- thumps while your health is low

	-- Town and wildlife (Pro Sound Effects and other free Creator Store sounds).
	BirdsDay = { Id = "rbxassetid://9112742473", Pitch = 1, Volume = 0.35 }, -- loop: daytime birdsong over town
	CricketsNight = { Id = "rbxassetid://9112764040", Pitch = 1, Volume = 0.3 }, -- loop: crickets after dark
	FireCrackle = { Id = "rbxassetid://9112780438", Pitch = 1, Volume = 0.6 }, -- loop: campfire and forge
	AnvilClang = { Id = "rbxassetid://9113445305", Pitch = 1, Volume = 0.45 }, -- the blacksmith at work
	AnvilClang2 = { Id = "rbxassetid://9113447116", Pitch = 1, Volume = 0.45 },
	AnvilClang3 = { Id = "rbxassetid://9113447467", Pitch = 1, Volume = 0.45 },
	BellToll = { Id = "rbxassetid://9113804436", Pitch = 1, Volume = 0.5 }, -- the bell tower at dawn and dusk
	WingFlaps = { Id = "rbxassetid://9113444620", Pitch = 1.3, Volume = 0.4 }, -- town birds taking off
	ChickenCluck = { Id = "rbxassetid://77584650945481", Pitch = 1, Volume = 0.5 },
	CowMoo = { Id = "rbxassetid://138223429", Pitch = 1, Volume = 0.5 },
	Sizzle = { Id = "rbxassetid://6383276435", Pitch = 1, Volume = 0.6 }, -- meat cooking on the campfire
	Eat = { Id = "rbxassetid://6830313781", Pitch = 1, Volume = 0.6 }, -- eating cooked meat

	-- Loot.
	CoinPickup = { Id = "rbxassetid://113730061669739", Pitch = 1.1, Volume = 0.45 }, -- each gold coin picked up (alternatives: 4612374807, 93529351909119)

	-- Grimgorg (BossSounds plays them from him: BossConfig.Grimgorg Sounds and attack cues).
	-- Pro Sound Effects creature voices, pitched down for a big brute.
	GrimgorgRoar = { Id = "rbxassetid://9113980319", Pitch = 0.8, Volume = 1 }, -- waking up for the fight
	GrimgorgEnrage = { Id = "rbxassetid://114600180172960", Pitch = 0.85, Volume = 1 }, -- "Grimgorg is furious!" / "enraged!"
	GrimgorgAttack = { Id = "rbxassetid://9114628321", Pitch = 0.8, Volume = 0.8 }, -- a growl as an attack winds up
	GrimgorgHurt = { Id = "rbxassetid://9113973119", Pitch = 0.7, Volume = 0.75 }, -- a grunt when he's struck
	GrimgorgStunned = { Id = "rbxassetid://9114628321", Pitch = 0.6, Volume = 0.9 }, -- a dazed groan, knocked down
	GrimgorgDeath = { Id = "rbxassetid://9113980319", Pitch = 0.6, Volume = 1 }, -- a long dying roar
	GrimgorgSwing = { Id = "rbxassetid://127747416982963", Pitch = 0.6, Volume = 0.7 }, -- his claws through the air
	GrimgorgTail = { Id = "rbxassetid://127747416982963", Pitch = 0.45, Volume = 0.8 }, -- the tail sweeping round
	GrimgorgSlam = { Id = "rbxassetid://140277245983305", Pitch = 0.7, Volume = 1 }, -- both fists into the ground
	GrimgorgBeam = { Id = "rbxassetid://9114463219", Pitch = 0.7, Volume = 1 }, -- the fire he breathes

	-- Ambience loops (Soundscape fades them in and out by where you are).
	WindWilds = { Id = "rbxassetid://5799870105", Pitch = 1, Volume = 0.35 }, -- out in the wilds, away from town
	CaveAmbience = { Id = "rbxassetid://273398061", Pitch = 1, Volume = 0.55 }, -- a dungeon's low cave hum
	CaveTrickle = { Id = "rbxassetid://9120505297", Pitch = 0.9, Volume = 0.25 }, -- water trickling in the dungeon
}

-- Music (Soundscape): a playlist for each kind of place, shuffled, crossfading when you move
-- between them. A boss can have its own ("Boss:<Id>"), else the fight plays Boss. Free licensed tracks from the Creator Store (DistroKid and APM catalogues).
-- Swap an Id for any other track; Volume is relative to the music's overall volume.
export type Track = { Id: string, Volume: number }
local MUSIC: { [string]: { Track } } = {
	Town = { -- Beginning Town (the safe zone)
		{ Id = "rbxassetid://130353416723748", Volume = 1 }, -- The Miller's Drowsy Afternoon
		{ Id = "rbxassetid://99458479340541", Volume = 1 }, -- Leaves on the Old Bridge
		{ Id = "rbxassetid://103096106070474", Volume = 1 }, -- Fog Along the Village Path
	},
	Wilds = { -- the hills, plain and mountains outside town
		{ Id = "rbxassetid://1846227339", Volume = 1 }, -- Soaring Wings E
		{ Id = "rbxassetid://113669032614533", Volume = 1 }, -- sweeping
	},
	Dungeon = { -- inside a dungeon run
		{ Id = "rbxassetid://79559833217506", Volume = 1 }, -- burial
		{ Id = "rbxassetid://73717467615712", Volume = 1 }, -- Disturb
		{ Id = "rbxassetid://110872532745784", Volume = 1 }, -- Grave for a mage
	},
	Boss = { -- a boss fight (a boss without a playlist of its own)
		{ Id = "rbxassetid://128007000574959", Volume = 1 }, -- Epic Boss Battle
		{ Id = "rbxassetid://84099904594509", Volume = 1 }, -- First Phase
	},
	["Boss:Grimgorg"] = { -- fighting Grimgorg ("Boss:" .. its BossConfig Id)
		{ Id = "rbxassetid://9043171470", Volume = 1 }, -- Edge Of Extinction (orchestra, choir, pounding drums)
		{ Id = "rbxassetid://1841476670", Volume = 1 }, -- Drums of Combat a
	},
}

local Sounds = {}

Sounds.Music = MUSIC

local random = Random.new()

local function varied(sound: Sound)
	local base = sound:GetAttribute("BasePitch")
	if typeof(base) == "number" then
		sound.PlaybackSpeed = base * (1 + random:NextNumber(-PITCH_VARIATION, PITCH_VARIATION))
	end
end

-- A new Sound for `name` parented to `parent`, or nil if that sound is silenced.
-- `pitchScale` multiplies the configured pitch (e.g. to rise with charge level).
function Sounds.create(name: string, parent: Instance, pitchScale: number?): Sound?
	local spec = SPECS[name]
	assert(spec, `Unknown sound "{name}"`)
	if spec.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.Id
	sound.PlaybackSpeed = spec.Pitch * (pitchScale or 1)
	sound.Volume = spec.Volume
	if not spec.Steady then
		sound:SetAttribute("BasePitch", sound.PlaybackSpeed) -- what replay varies around
	end
	sound.Parent = parent
	return sound
end

-- Plays `name` once from `parent` (3D if it's a part or attachment) and cleans it up after.
function Sounds.play(name: string, parent: Instance, pitchScale: number?)
	local sound = Sounds.create(name, parent, pitchScale)
	if not sound then
		return
	end
	varied(sound)
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- Loads every sound's audio up front (call once on the client), so none starts late the first
-- time it plays (e.g. a parry's clang).
function Sounds.preload()
	local ContentProvider = game:GetService("ContentProvider")
	local list: { Instance } = {}
	for _, spec in SPECS do
		if spec.Id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = spec.Id
			table.insert(list, sound)
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
end

-- Plays a kept sound (e.g. a weapon's SlashSound) again, at a slightly different pitch.
function Sounds.replay(sound: Sound)
	varied(sound)
	sound:Play()
end

-- Plays a copy of a kept sound once, `pitchScale` times faster, without cutting off the sound
-- itself or other copies (for rapid repeats like the rapier's flurry).
function Sounds.playCopy(sound: Sound, pitchScale: number)
	local copy = sound:Clone()
	local base = sound:GetAttribute("BasePitch")
	copy:SetAttribute("BasePitch", (if typeof(base) == "number" then base else sound.PlaybackSpeed) * pitchScale)
	varied(copy)
	copy.Parent = sound.Parent
	copy.Ended:Connect(function()
		copy:Destroy()
	end)
	copy:Play()
end

return Sounds
