--!strict
-- The time of day (LightingConfig.DayCycle), worked out from the server clock so the server
-- and every client agree without sending anything. Hours run 0..24; the day (Dawn to Dusk)
-- takes DayMinutes of real time and the night NightMinutes.

local LightingConfig = require(script.Parent.Config.LightingConfig)

local CYCLE = LightingConfig.DayCycle
local DAY_HOURS = CYCLE.Dusk - CYCLE.Dawn
local NIGHT_HOURS = 24 - DAY_HOURS
local DAY_SECONDS = CYCLE.DayMinutes * 60
local NIGHT_SECONDS = CYCLE.NightMinutes * 60

local DayCycle = {}

-- The clock (0..24) at server time `now` (default: now).
function DayCycle.clock(now: number?): number
	local t = (now or workspace:GetServerTimeNow()) % (DAY_SECONDS + NIGHT_SECONDS)
	if t < DAY_SECONDS then
		return CYCLE.Dawn + t / DAY_SECONDS * DAY_HOURS
	end
	return (CYCLE.Dusk + (t - DAY_SECONDS) / NIGHT_SECONDS * NIGHT_HOURS) % 24
end

-- How deep into night `clock` is: 0 in full day, 1 in full night, easing over Fade hours
-- either side of dawn and dusk.
function DayCycle.night(clock: number): number
	local fade = CYCLE.Fade
	-- Hours past dusk and before dawn, each signed (-12..12), so the fades straddle them.
	local sinceDusk = (clock - CYCLE.Dusk + 12) % 24 - 12
	local untilDawn = (CYCLE.Dawn - clock + 12) % 24 - 12
	local amount = math.clamp(math.min(sinceDusk, untilDawn) / fade + 0.5, 0, 1)
	return amount * amount * (3 - 2 * amount) -- smoothstep
end

function DayCycle.isNight(clock: number?): boolean
	return DayCycle.night(clock or DayCycle.clock()) >= CYCLE.LightsOn
end

return DayCycle
