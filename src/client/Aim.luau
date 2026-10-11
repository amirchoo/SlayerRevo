--!strict
-- Where a ranged attack (bow, staff) should go: straight at the lock-on target if there is
-- one; otherwise at whatever the mouse points at, or the screen centre on touch screens
-- (where the crosshair is).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LockOn = require(script.Parent.LockOn)

local AIM_DISTANCE = 1000

local player = Players.LocalPlayer

local Aim = {}

-- The point to aim at. `ignore` lists things the aim ray should pass through (e.g. arrows).
function Aim.point(ignore: { Instance }?): Vector3
	local locked = LockOn.target()
	if locked and locked.Parent then
		return locked:GetBoundingBox().Position
	end

	local camera = workspace.CurrentCamera
	local screenPoint = if UserInputService.MouseEnabled then UserInputService:GetMouseLocation() else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local exclude: { Instance } = { camera }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	for _, instance in ignore or {} do
		table.insert(exclude, instance)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
	return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
end

return Aim
