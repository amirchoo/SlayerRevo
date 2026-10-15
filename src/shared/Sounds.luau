--!strict
-- Every sound the game plays, in one place. To upgrade one, find a sound in the Creator
-- Store (Toolbox > Audio, e.g. "sword hit", "metal clang", "blunt impact", "whoosh") and
-- paste its ID as "rbxassetid://123..." into Id. Set Id = "" to silence a sound.
--
-- The defaults are stand-ins built from the few sounds bundled with Roblox
-- (rbxasset://sounds/...), re-pitched to roughly fit, so everything makes some noise
-- until real sounds are picked.
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

local THUD = "rbxasset://sounds/action_jump_land.mp3"
local WHOOSH = "rbxasset://sounds/action_jump.mp3"
local TICK = "rbxasset://sounds/volume_slider.ogg"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"

local SPECS: { [string]: SoundSpec } = {
	-- Swings (played on the attacker's own screen as they swing).
	SwordSwing = { Id = WHOOSH, Pitch = 1.6, Volume = 0.4 },
	MaceSwing = { Id = WHOOSH, Pitch = 1.1, Volume = 0.45 },
	SpearSwing = { Id = WHOOSH, Pitch = 2.0, Volume = 0.35 },
	RapierSwing = { Id = WHOOSH, Pitch = 2.4, Volume = 0.3 },
	GreatswordSwing = { Id = WHOOSH, Pitch = 0.8, Volume = 0.5 },
	AxeSwing = { Id = WHOOSH, Pitch = 1.3, Volume = 0.45 },
	DualBladeSwing = { Id = WHOOSH, Pitch = 2.1, Volume = 0.35 },
	HammerSwing = { Id = WHOOSH, Pitch = 0.65, Volume = 0.6 },
	ScytheSwing = { Id = WHOOSH, Pitch = 0.95, Volume = 0.5 },
	StaffCast = { Id = WHOOSH, Pitch = 2.2, Volume = 0.4 },
	StaffBlast = { Id = BOOM, Pitch = 1.6, Volume = 0.45 },

	-- Impacts when an enemy is hit (heard by everyone nearby).
	SwordHit = { Id = THUD, Pitch = 1.5, Volume = 0.8 },
	MaceHit = { Id = THUD, Pitch = 0.7, Volume = 1 },
	SpearHit = { Id = THUD, Pitch = 1.9, Volume = 0.7 },
	RapierHit = { Id = THUD, Pitch = 2.2, Volume = 0.55 },
	GreatswordHit = { Id = BOOM, Pitch = 1.3, Volume = 0.5 },
	AxeHit = { Id = THUD, Pitch = 1.1, Volume = 0.9 },
	DualBladeHit = { Id = THUD, Pitch = 1.8, Volume = 0.6 },
	HammerHit = { Id = BOOM, Pitch = 0.9, Volume = 0.7 },
	ScytheHit = { Id = THUD, Pitch = 1.4, Volume = 0.75 },
	StaffFireHit = { Id = BOOM, Pitch = 1.8, Volume = 0.5 },
	StaffWaterHit = { Id = THUD, Pitch = 1.6, Volume = 0.7 },
	StaffEarthHit = { Id = THUD, Pitch = 0.8, Volume = 1 },
	StaffElectricHit = { Id = TICK, Pitch = 0.6, Volume = 1 },
	GrimoireFaithHit = { Id = TICK, Pitch = 1.4, Volume = 0.7 },
	GrimoireNecromancyHit = { Id = THUD, Pitch = 0.9, Volume = 0.8 },
	BowHit = { Id = THUD, Pitch = 2.3, Volume = 0.6 },
	CrossbowHit = { Id = THUD, Pitch = 1.8, Volume = 0.75 },
	BlunderbussHit = { Id = THUD, Pitch = 2.1, Volume = 0.35 }, -- per pellet, so quieter

	-- Movement.
	DashWhoosh = { Id = WHOOSH, Pitch = 1.9, Volume = 0.35 }, -- a dash (heard by everyone nearby)

	-- Other feedback.
	Block = { Id = THUD, Pitch = 1.8, Volume = 0.8 }, -- a blocked hit
	ParryHit = { Id = BOOM, Pitch = 2.2, Volume = 0.6 }, -- a parried hit (heard by everyone nearby)
	ChargeLevel = { Id = TICK, Pitch = 1, Volume = 0.8, Steady = true }, -- greatsword charge level reached (pitch rises per level)
	Heartbeat = { Id = THUD, Pitch = 0.5, Volume = 0.6 }, -- thumps while your health is low

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
	Eat = { Id = "", Pitch = 1, Volume = 0.6 }, -- eating cooked meat (no sound picked yet)
}

local Sounds = {}

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

-- Plays a kept sound (e.g. a weapon's SlashSound) again, at a slightly different pitch.
function Sounds.replay(sound: Sound)
	varied(sound)
	sound:Play()
end

return Sounds
