--!strict
-- How open a pet's eyes are, as the X rotation of its eyelid bones ("LidL" and "LidR"),
-- between its NpcConfig Lids angles: Open, Half, Shut. PetAnimator puts that angle into the
-- lids of each frame's pose, so it wins over whatever the clip does to them.
--
--     local eyes = PetEyes.new(config.Lids)
--     eyes:set(0)          -- close them (0 shut, 0.5 half, 1 open), easing there
--     eyes:set(1, true)    -- open them at once
--     eyes:blink()         -- a quick blink, then back to how open they were
--     eyes:step(dt)        -- every frame
--     eyes:angle()         -- the lid angle to show now

local EASE = 8 -- how quickly the lids move toward their target (per second)
local BLINK_CLOSE = 0.07 -- seconds to shut for a blink
local BLINK_HOLD = 0.05
local BLINK_OPEN = 0.12

export type Lids = { Open: number, Half: number, Shut: number }

local PetEyes = {}
PetEyes.__index = PetEyes

export type PetEyes = typeof(setmetatable(
	{} :: { lids: Lids, openness: number, target: number, shown: number, blinkStart: number? },
	PetEyes
))

function PetEyes.new(lids: Lids): PetEyes
	return setmetatable({ lids = lids, openness = 1, target = 1, shown = 1, blinkStart = nil }, PetEyes)
end

-- How open the eyes should be: 0 shut .. 0.5 half .. 1 open. `now`: jump there at once.
function PetEyes.set(self: PetEyes, openness: number, now: boolean?)
	self.target = math.clamp(openness, 0, 1)
	if now then
		self.openness = self.target
		self.shown = self.target
	end
end

function PetEyes.blink(self: PetEyes)
	if not self.blinkStart then
		self.blinkStart = os.clock()
	end
end

function PetEyes.step(self: PetEyes, dt: number)
	self.openness += (self.target - self.openness) * math.min(dt * EASE, 1)
	local shown = self.openness
	local blinkStart = self.blinkStart
	if blinkStart then
		local t = os.clock() - blinkStart
		local closed -- 0..1: how far the blink has shut them
		if t < BLINK_CLOSE then
			closed = t / BLINK_CLOSE
		elseif t < BLINK_CLOSE + BLINK_HOLD then
			closed = 1
		elseif t < BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN then
			closed = 1 - (t - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN
		else
			closed = 0
			self.blinkStart = nil
		end
		shown *= 1 - closed
	end
	self.shown = shown
end

-- The lid X angle (radians) for how open the eyes are now, through Half at 0.5.
function PetEyes.angle(self: PetEyes): number
	local lids = self.lids
	local openness = self.shown
	if openness <= 0.5 then
		return lids.Shut + (lids.Half - lids.Shut) * (openness / 0.5)
	end
	return lids.Half + (lids.Open - lids.Half) * ((openness - 0.5) / 0.5)
end

return PetEyes
