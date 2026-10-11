--!strict
-- Every sound the game plays, in one place. To upgrade one, find a sound in the Creator
-- Store (Toolbox > Audio, e.g. "sword hit", "metal clang", "blunt impact", "whoosh") and
-- paste its ID as "rbxassetid://123..." into Id. Set Id = "" to silence a sound.
--
-- The defaults are stand-ins built from the few sounds bundled with Roblox
-- (rbxasset://sounds/...), re-pitched to roughly fit, so everything makes some noise
-- until real sounds are picked.

export type SoundSpec = {
	Id: string,
	Pitch: number, -- playback speed: below 1 = deeper/heavier, above 1 = higher/sharper
	Volume: number,
}

local THUD = "rbxasset://sounds/action_jump_land.mp3"
local WHOOSH = "rbxasset://sounds/action_jump.mp3"
local TICK = "rbxasset://sounds/volume_slider.ogg"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"

local SPECS: { [string]: SoundSpec } = {
	-- Swings (played on the attacker's own screen as they swing).
	SwordSwing = { Id = WHOOSH, Pitch = 1.6, Volume = 0.4 },
	MaceSwing = { Id = WHOOSH, Pitch = 1.1, Volume = 0.45 },
	SpearSwing = { Id = WHOOSH, Pitch = 2.0, Volume = 0.35 },
	GreatswordSwing = { Id = WHOOSH, Pitch = 0.8, Volume = 0.5 },
	AxeSwing = { Id = WHOOSH, Pitch = 1.3, Volume = 0.45 },

	-- Impacts when an enemy is hit (heard by everyone nearby).
	SwordHit = { Id = THUD, Pitch = 1.5, Volume = 0.8 },
	MaceHit = { Id = THUD, Pitch = 0.7, Volume = 1 },
	SpearHit = { Id = THUD, Pitch = 1.9, Volume = 0.7 },
	GreatswordHit = { Id = BOOM, Pitch = 1.3, Volume = 0.5 },
	AxeHit = { Id = THUD, Pitch = 1.1, Volume = 0.9 },
	BowHit = { Id = THUD, Pitch = 2.3, Volume = 0.6 },

	-- Other feedback.
	Block = { Id = THUD, Pitch = 1.8, Volume = 0.8 }, -- a blocked hit
	ParryHit = { Id = BOOM, Pitch = 2.2, Volume = 0.6 }, -- a parried hit (heard by everyone nearby)
	ChargeLevel = { Id = TICK, Pitch = 1, Volume = 0.8 }, -- greatsword charge level reached (pitch rises per level)
}

local Sounds = {}

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
	sound.Parent = parent
	return sound
end

-- Plays `name` once from `parent` (3D if it's a part or attachment) and cleans it up after.
function Sounds.play(name: string, parent: Instance, pitchScale: number?)
	local sound = Sounds.create(name, parent, pitchScale)
	if not sound then
		return
	end
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

return Sounds
