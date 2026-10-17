--!strict
-- Lights only the nearest few of the world's many small lights on this screen (QualityConfig
-- WorldLights): dungeon torch lights, and town lamps at night (DayNight hands those over). The
-- rest stay dark; their flames and lanterns still glow (Neon, particles), only the light on the
-- walls and ground goes. A light coming on or going off fades over FADE seconds, so walking down
-- a corridor doesn't pop. Looks only. Fires' lights (braziers, the campfire) aren't budgeted.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Quality = require(script.Parent.Quality)

local UPDATE_INTERVAL = 0.5 -- seconds between picking the nearest lights
local FADE = TweenInfo.new(0.4, Enum.EasingStyle.Sine)

type Entry = {
	wanted: boolean, -- lit if near enough (a town lamp only at night)
	on: boolean,
	brightness: number, -- its own brightness, faded to and from
	tween: Tween?,
}

local LightBudget = {}

local entries: { [Light]: Entry } = {}

local function positionOf(light: Light): Vector3?
	local parent = light.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function switch(light: Light, entry: Entry, on: boolean)
	if entry.on == on then
		return
	end
	entry.on = on
	if entry.tween then
		entry.tween:Cancel()
	end
	if on then
		light.Brightness = 0
		light.Enabled = true
	end
	local tween = TweenService:Create(light, FADE, { Brightness = if on then entry.brightness else 0 })
	entry.tween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not entry.on then
			light.Enabled = false
		end
	end)
	tween:Play()
end

-- Puts `light` under the budget (it decides Enabled from now on). `wanted`: whether it should be
-- lit when near enough (false: always dark, like a town lamp by day).
function LightBudget.add(light: Light, wanted: boolean)
	if entries[light] then
		LightBudget.setWanted(light, wanted)
		return
	end
	entries[light] = { wanted = wanted, on = false, brightness = light.Brightness }
	light.Enabled = false -- the next update lights it if it's near enough
end

function LightBudget.setWanted(light: Light, wanted: boolean)
	local entry = entries[light]
	if entry then
		entry.wanted = wanted
		if not wanted then
			switch(light, entry, false)
		end
	end
end

function LightBudget.remove(light: Light)
	local entry = entries[light]
	if entry and entry.tween then
		entry.tween:Cancel()
	end
	entries[light] = nil
end

local function update()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local near: { { light: Light, distance: number } } = {}
	for light, entry in entries do
		local position = if entry.wanted then positionOf(light) else nil
		if position then
			table.insert(near, { light = light, distance = (position - eye).Magnitude })
		elseif entry.on then
			switch(light, entry, false)
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	local budget = Quality.settings().WorldLights
	for index, item in near do
		switch(item.light, entries[item.light], index <= budget)
	end
end

-- A dungeon torch's light: on a Torch model, or the stand-in's "Flame" part (DungeonBuilder).
local function isTorchLight(light: Light): boolean
	local parent = light.Parent
	return light:FindFirstAncestor("Torch") ~= nil or (parent ~= nil and parent:IsA("BasePart") and parent.Name == "Flame")
end

function LightBudget.start()
	task.spawn(function()
		local dungeons = workspace:WaitForChild("Dungeons")
		local function watch(descendant: Instance)
			if descendant:IsA("Light") and isTorchLight(descendant) then
				LightBudget.add(descendant, true)
			end
		end
		dungeons.DescendantAdded:Connect(watch) -- runs are copied in, parts stream in
		dungeons.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("Light") then
				LightBudget.remove(descendant)
			end
		end)
		for _, descendant in dungeons:GetDescendants() do
			watch(descendant)
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= UPDATE_INTERVAL then
			since = 0
			update()
		end
	end)
end

return LightBudget
