-- Studio Command Bar snippet: builds the dungeons in edit mode into workspace.DungeonLayouts, to
-- edit by hand and save with the place. The game plays with the saved copies:
--   <Id>          the dungeon, at DungeonConfig.LayoutOrigin (X 2200, Y 300). Everything in it is
--                 copied into every run as saved, like workspace.Town:
--                   its terrain (sculpt it with the terrain tools);
--                   Decor (torches, rocks, crates...: add, move, restyle or delete anything);
--                   Working (the gates, chests and the way out: move, restyle, copy or delete
--                   them too). The game finds them by their attributes: a Gate (Room, Squares,
--                   Lift; what lifts is its Door, saved shut), a Chest (its Lid swings about
--                   the lid's pivot) and the Exit. A copied chest is another chest. The orcs
--                   still walk the Map's squares, and a gate's Squares say which ones it closes.
--   <Id>Entrance  the cave mouth in the world: move it, reshape it, add to it. Keep the parts
--                 named Opening (the dark doorway: walking in enters) and PromptAnchor.
-- WARNING: rebuilding throws away the hand edits to what it rebuilds. Set the flags below:
-- REBUILD_WORKING alone redoes only the gates, chests and way out (keeping terrain and Decor).
-- Studio caches required modules between runs, so this builds from fresh copies.
local REBUILD_DUNGEON = true
local REBUILD_WORKING = false -- only if REBUILD_DUNGEON is false
local REBUILD_ENTRANCE = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local server = game:GetService("ServerScriptService").Server
local shared = ReplicatedStorage.Shared
local fresh = shared:Clone()
shared.Parent = nil
fresh.Parent = ReplicatedStorage
local modules = Instance.new("Folder")
for _, name in { "DungeonBuilder", "DungeonGrid", "DungeonTerrain" } do
	server[name]:Clone().Parent = modules
end
modules.Parent = game:GetService("ServerStorage")

local ok, err = pcall(function()
	local DungeonBuilder = require(modules.DungeonBuilder)
	local DungeonGrid = require(modules.DungeonGrid)
	local DungeonConfig = require(fresh.Config.DungeonConfig)
	local layouts = workspace:FindFirstChild("DungeonLayouts")
	if not layouts then
		layouts = Instance.new("Folder")
		layouts.Name = "DungeonLayouts"
		layouts.Parent = workspace
	end
	for _, dungeon in DungeonConfig.Dungeons do
		if REBUILD_DUNGEON then
			local old = layouts:FindFirstChild(dungeon.Id)
			if old then
				local region = DungeonBuilder.layoutRegion(old)
				if region then
					workspace.Terrain:FillBlock(region.cframe, region.size, Enum.Material.Air)
				end
				old:Destroy()
			end
			local grid = DungeonGrid.new(dungeon, DungeonConfig.LayoutOrigin)
			DungeonBuilder.buildLayout(dungeon, grid).Parent = layouts
			print(`{dungeon.DisplayName}: layout built at {DungeonConfig.LayoutOrigin}`)
		elseif REBUILD_WORKING then
			local saved = layouts:FindFirstChild(dungeon.Id)
			local origin = saved and saved:GetAttribute("Origin")
			if not saved or typeof(origin) ~= "Vector3" then
				warn(`{dungeon.DisplayName}: no saved layout to redo the working parts of`)
			else
				for _, name in { "Working", "Guide" } do
					local old = saved:FindFirstChild(name)
					if old then
						old:Destroy()
					end
				end
				local working = DungeonBuilder.buildWorking(dungeon, DungeonGrid.new(dungeon, origin))
				for _, prompt in working:GetDescendants() do
					if prompt:IsA("ProximityPrompt") then
						prompt:Destroy()
					end
				end
				working.Parent = saved
				print(`{dungeon.DisplayName}: working parts rebuilt`)
			end
		end
		if REBUILD_ENTRANCE then
			local old = layouts:FindFirstChild(dungeon.Id .. "Entrance")
			if old then
				old:Destroy()
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { workspace.Terrain }
			local x, z = dungeon.Entrance.X, dungeon.Entrance.Y
			local hit = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
			local ground = Vector3.new(x, if hit then hit.Position.Y else 0, z)
			DungeonBuilder.entrance(dungeon, ground, layouts)
			print(`{dungeon.DisplayName}: entrance built at {ground}`)
		end
	end
end)
modules:Destroy()
fresh:Destroy()
shared.Parent = ReplicatedStorage
if ok then
	print("Dungeon layouts built; save the place to keep them")
else
	warn("Dungeon layout failed:", err)
end
