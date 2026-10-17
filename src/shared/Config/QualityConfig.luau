--!strict
-- Effects quality on each screen (client Quality picks the tier; looks only, never gameplay).
-- A tier is chosen from the device (touch or not) and the player's Roblox graphics level, and
-- drops a step live when the frame rate stays low (then may climb back, up to the device's
-- tier). Every effects system reads its tier's settings below.

export type Tier = "Low" | "Medium" | "High"
export type Settings = {
	Particles: number, -- multiplier on particle counts and emitter rates (hit sparks, dust, torches, smoke)
	PlayerLights: number, -- characters carrying PlayerLight's glow at once (nearest first)
	HitLights: number, -- impact lights at once (0: hits flash without lighting the ground)
	ParryLight: boolean, -- a parry's gold flash lights the floor
	Trails: boolean, -- weapon swing trails
	Bloom: boolean,
	SunRays: boolean,
	AmbienceRange: number, -- studs from the camera that town cloth sways and the windmill turns (0: still)
	Birds: boolean, -- the town's little bird flocks
	Decor: number, -- share of the world's grass, small flowers and bushes drawn, 0..1 (client WorldDensity)
	-- A dungeon torch's emitters (the Torch asset: Fire1-3, Smoke, CandleLight) → share of each
	-- one's own rate, on top of Particles. Unlisted ones are off. Fire1 is a 500/s flicker core,
	-- most of a torch's cost, so it only comes back (thinned) on High.
	TorchFlames: { [string]: number },
	WorldLights: number, -- torch lights and town lamps lit at once, nearest the camera first (client LightBudget)
	PoseDetail: number, -- scales the distances animals, villagers and pets are posed every frame (client PoseLod)
	Afterimages: number, -- copies of a dashing character left trailing behind it (client DashEffects)
}

local QualityConfig = {}

QualityConfig.Order = { "Low", "Medium", "High" } :: { Tier }

QualityConfig.Tiers = {
	Low = {
		Particles = 0.35,
		PlayerLights = 2,
		HitLights = 0,
		ParryLight = true,
		Trails = false,
		Bloom = false,
		SunRays = false,
		AmbienceRange = 0,
		Birds = false,
		Decor = 0.4,
		TorchFlames = { Fire3 = 0.6 },
		WorldLights = 6,
		PoseDetail = 0.6,
		Afterimages = 2,
	},
	Medium = {
		Particles = 0.65,
		PlayerLights = 4,
		HitLights = 3,
		ParryLight = true,
		Trails = true,
		Bloom = true,
		SunRays = false,
		AmbienceRange = 90,
		Birds = true,
		Decor = 0.75,
		TorchFlames = { Fire3 = 0.5, Fire2 = 0.5, Smoke = 1 },
		WorldLights = 12,
		PoseDetail = 0.85,
		Afterimages = 3,
	},
	High = {
		Particles = 1,
		PlayerLights = 8,
		HitLights = 6,
		ParryLight = true,
		Trails = true,
		Bloom = true,
		SunRays = true,
		AmbienceRange = 180,
		Birds = true,
		Decor = 1,
		TorchFlames = { Fire3 = 0.5, Fire2 = 0.5, Smoke = 1, CandleLight = 1, Fire1 = 0.2 },
		WorldLights = 24,
		PoseDetail = 1,
		Afterimages = 4,
	},
} :: { [Tier]: Settings }

-- The starting (and highest automatic) tier from Roblox's graphics level (1-10; 0 = Automatic).
-- Phones and tablets (touch, no keyboard) get High only when the player turns graphics up by
-- hand (Roblox can't tell a strong phone from a weak one, and the target is an average or weak phone).
QualityConfig.Device = {
	TouchAutomatic = "Medium" :: Tier, -- a phone left on Automatic graphics
	TouchMediumFrom = 5, -- a phone at graphics level 5+ gets Medium, below that Low
	TouchHighFrom = 8, -- a phone at graphics level 8+ gets High
	PcAutomatic = "High" :: Tier,
	PcMediumFrom = 4, -- a computer at graphics level 4-6 gets Medium, 1-3 Low
	PcHighFrom = 7,
}

-- Watching the frame rate.
QualityConfig.Fps = {
	Grace = 15, -- seconds after joining before it starts judging (the world is still loading)
	DropBelow = 40, -- average FPS under this ...
	DropAfter = 5, -- ... for this many seconds in a row drops one tier
	RaiseAbove = 57, -- average FPS at or above this ...
	RaiseAfter = 60, -- ... for this many seconds in a row climbs one tier (never above the device's tier)
	MaxRaises = 2, -- climbs per session, so it can't keep flip-flopping
}

return QualityConfig
