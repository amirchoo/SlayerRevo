--!strict
-- The game's look: lighting, atmosphere and post effects, applied by server LightingSetup at
-- start (and in edit mode by tools/apply_lighting.lua). Warm afternoon sun, soft shadows,
-- gentle color, and a cool haze that fades the far hills and mountains: bright and friendly
-- in town, with depth across the big world. The lighting tech is set in the place, not here:
-- LightingStyle Realistic with PrioritizeLightingQuality off (the old Technology = ShadowMap):
-- crisp sun and moon shadows, the cheapest option with real sun shadows (the target is an average or weak phone). The look comes from art direction, not lighting tech: the
-- colour grade, contrast, fog that fades the distance, and a few strong lights.

local LightingConfig = {}

LightingConfig.Lighting = {
	ClockTime = 14.5,
	GeographicLatitude = 35,
	Brightness = 2.6,
	ExposureCompensation = 0,
	Ambient = Color3.fromRGB(90, 85, 100),
	OutdoorAmbient = Color3.fromRGB(150, 140, 130),
	ColorShift_Top = Color3.fromRGB(255, 235, 205), -- warm sunlight
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.5,
	GlobalShadows = true,
	ShadowSoftness = 0.2, -- crisp ShadowMap sun shadows (0.35 looked smeared)
}

-- Fog that fades the far forest into a cool haze, so the near scene reads as the stage (and the
-- far world that streams in late doesn't pop).
LightingConfig.Atmosphere = {
	Density = 0.3,
	Offset = 0.25,
	Color = Color3.fromRGB(215, 215, 210),
	Decay = Color3.fromRGB(150, 165, 190),
	Glare = 0.2,
	Haze = 0.8,
}

LightingConfig.Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 }
LightingConfig.ColorCorrection = {
	Saturation = 0.25,
	Contrast = 0.15,
	Brightness = 0.02,
	TintColor = Color3.fromRGB(255, 248, 235),
}
LightingConfig.SunRays = { Intensity = 0.04, Spread = 0.5 }

-- Soft clouds drifting over the land (Terrain.Clouds).
LightingConfig.Clouds = { Cover = 0.62, Density = 0.45, Color = Color3.fromRGB(255, 255, 255) }

-- Day and night (the client's DayCycle turns the clock; every player sees the same time).
-- A full day takes DayMinutes + NightMinutes of real time: the sun is up from Dawn to Dusk
-- (hours), and the night between runs faster. At night the light shifts toward the Night
-- values (a moonlit blue, kept bright enough to play in), and lamps and windows light up.
-- Night also grades the picture like a moonlit duel: cooler and punchier color, crisper moon
-- shadows and shinier surfaces, so lit characters and hit flashes stand out against the blue.
LightingConfig.DayCycle = {
	DayMinutes = 14,
	NightMinutes = 6,
	Dawn = 6,
	Dusk = 18.5,
	Fade = 1, -- hours the light takes to shift at dawn and dusk
	LightsOn = 0.35, -- how far into the night (0..1) lamps and windows switch on
	Night = {
		Brightness = 1.2,
		Ambient = Color3.fromRGB(70, 80, 115),
		OutdoorAmbient = Color3.fromRGB(95, 110, 150),
		ColorShift_Top = Color3.fromRGB(150, 170, 230),
		ExposureCompensation = 0.25,
		ShadowSoftness = 0.12,
		EnvironmentSpecularScale = 1,
		ColorCorrection = {
			Saturation = 0.3,
			Contrast = 0.22,
			Brightness = 0,
			TintColor = Color3.fromRGB(220, 230, 255),
		},
		-- A cold blue-indigo fog closing in at night, so lamps, torches and hit flashes glow
		-- warm against it (the duel-night look).
		Atmosphere = {
			Density = 0.36,
			Offset = 0.25,
			Color = Color3.fromRGB(70, 85, 130),
			Decay = Color3.fromRGB(35, 45, 85),
			Glare = 0,
			Haze = 1.2,
		},
	},
	WindowGlow = Color3.fromRGB(255, 190, 110), -- windows at night
}

-- Inside a dungeon run (the client's DayNight switches to these while the player has the
-- "Dungeon" attribute, and back after): grim, dull and dark. No sun or sky light, a dim cold
-- ambient so the torches do the lighting, washed-out colour, more contrast, a murky haze.
LightingConfig.Dungeon = {
	Lighting = {
		Brightness = 0,
		Ambient = Color3.fromRGB(68, 64, 72),
		OutdoorAmbient = Color3.fromRGB(52, 50, 58),
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 0.15,
		EnvironmentSpecularScale = 0.15,
	},
	Atmosphere = {
		Density = 0.38, -- far corridors sink into murk; the torch-lit space near you is the stage
		Offset = 0,
		Color = Color3.fromRGB(52, 49, 56),
		Decay = Color3.fromRGB(22, 21, 24),
		Glare = 0,
		Haze = 1.6,
	},
	Bloom = { Intensity = 0.25, Size = 20, Threshold = 1.6 },
	ColorCorrection = {
		Saturation = -0.35,
		Contrast = 0.18,
		Brightness = -0.03,
		TintColor = Color3.fromRGB(225, 228, 235),
	},
	SunRays = { Intensity = 0, Spread = 0.5 },
}

-- A warm glow carried by every player (client PlayerLight; looks only, no shadows, so it's
-- cheap): full in a dungeon run, and out of town at night (DayCycle's night, 0..1). In town at
-- night it's TownNight of that. Only the MaxLit nearest characters get one.
LightingConfig.PlayerLight = {
	Color = Color3.fromRGB(255, 185, 120),
	Range = 26,
	Brightness = 1.4,
	Offset = Vector3.new(0, 1.5, -1), -- from the HumanoidRootPart: chest height, a little ahead
	TownNight = 0.4,
	MaxLit = 8,
	FadeSpeed = 1.5, -- of full brightness per second
}

-- The sky kept (by name, in Lighting); any other Sky is removed.
LightingConfig.Sky = "Sky"

return LightingConfig
