--!strict
-- Level of detail for the creatures posed in Lua every frame (AnimalAnimator, VillagerAnimator,
-- PetAnimator): near the camera they're posed every frame, further out less often, and off
-- screen only now and then (their pose still moves on, so they don't freeze mid-step when you
-- turn round). Distances scale with the quality tier (QualityConfig PoseDetail). Looks only.
--
-- Each animator keeps a PoseLod.Timer per creature and calls PoseLod.due(timer, position, dt)
-- every frame: it returns the time to step the pose by (the frames skipped added up), or nil to
-- skip this frame. Call PoseLod.frame() once per frame first (it reads the camera).

local Quality = require(script.Parent.Quality)

-- Bands by distance from the camera (studs, at PoseDetail 1) and how often a creature in them is
-- posed (seconds; 0 = every frame).
local BANDS = {
	{ within = 45, every = 0 },
	{ within = 90, every = 1 / 30 },
	{ within = math.huge, every = 1 / 15 },
}
local OFF_SCREEN_EVERY = 1 / 6
local SCREEN_MARGIN = 0.15 -- share of the screen's size counted as still on screen (a leg poking in)

export type Timer = { waited: number }

local PoseLod = {}

local eye = Vector3.zero
local camera: Camera? = nil
local viewport = Vector2.one
local detail = 1

function PoseLod.timer(): Timer
	-- Start at a random point so creatures in the same band don't all pose on the same frame.
	return { waited = math.random() * OFF_SCREEN_EVERY }
end

function PoseLod.frame()
	camera = workspace.CurrentCamera
	if camera then
		eye = camera.CFrame.Position
		viewport = camera.ViewportSize
	end
	detail = Quality.settings().PoseDetail
end

local function onScreen(position: Vector3): boolean
	local cam = camera
	if not cam then
		return true
	end
	local point, inFront = cam:WorldToViewportPoint(position)
	if not inFront then
		return false
	end
	local mx, my = viewport.X * SCREEN_MARGIN, viewport.Y * SCREEN_MARGIN
	return point.X >= -mx and point.X <= viewport.X + mx and point.Y >= -my and point.Y <= viewport.Y + my
end

-- The time to step a creature at `position` by this frame, or nil to skip it.
function PoseLod.due(timer: Timer, position: Vector3, dt: number): number?
	timer.waited += dt
	local distance = (position - eye).Magnitude
	local every = OFF_SCREEN_EVERY
	if onScreen(position) then
		for _, band in BANDS do
			if distance <= band.within * detail then
				every = band.every
				break
			end
		end
	end
	if timer.waited < every then
		return nil
	end
	local step = math.min(timer.waited, 0.5) -- after a long skip, don't jump a whole stride
	timer.waited = 0
	return step
end

-- Whether `position` is within `range` studs of the camera (as of PoseLod.frame).
function PoseLod.within(position: Vector3, range: number): boolean
	return (position - eye).Magnitude <= range
end

return PoseLod
