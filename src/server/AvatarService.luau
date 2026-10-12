--!strict
-- Every player gets the same blocky R15 body, so armor (built for that body) fits everyone.
-- Roblox's own avatar loading is off (StarterPlayer.LoadCharacterAppearance = false in
-- default.project.json), so characters spawn plain and blocky; this then puts on the parts
-- of each player's avatar that don't change their shape: face, skin colors, hats and hair,
-- classic shirt/pants/t-shirt, and animations. Body parts (Rthro, dynamic heads), body
-- scaling, and 3D layered clothing are left out.
-- AvatarService.onApplied(callback) runs after each character gets its look (ArmorService
-- re-dresses then, since applying a description replaces accessories).

local Players = game:GetService("Players")

local AvatarService = {}

local BODY_PARTS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local FETCH_ATTEMPTS = 3

local descriptions: { [Player]: HumanoidDescription } = {}
local appliedCallbacks: { (Player, Model) -> () } = {}

-- The player's avatar, reduced to what fits on the blocky body.
local function blockyDescription(player: Player): HumanoidDescription
	local description: HumanoidDescription? = nil
	for attempt = 1, FETCH_ATTEMPTS do
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(math.max(player.UserId, 1)) -- test players in Studio have ids <= 0
		end)
		if ok then
			description = result
			break
		elseif attempt == FETCH_ATTEMPTS then
			warn(`AvatarService: couldn't load {player.Name}'s avatar, using a plain one:`, result)
		else
			task.wait(attempt)
		end
	end
	local blocky = description or Instance.new("HumanoidDescription")

	for _, part in BODY_PARTS do
		(blocky :: any)[part] = 0 -- the default blocky part
	end
	blocky.HeightScale = 1
	blocky.WidthScale = 1
	blocky.DepthScale = 1
	blocky.HeadScale = 1
	blocky.BodyTypeScale = 0
	blocky.ProportionScale = 0

	-- Keep rigid accessories (hats, hair, face items); drop layered clothing.
	local rigid = {}
	for _, accessory in blocky:GetAccessories(true) do
		if not accessory.IsLayered then
			table.insert(rigid, accessory)
		end
	end
	blocky:SetAccessories(rigid, true)
	return blocky
end

local function applyTo(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local description = descriptions[player]
	if not (humanoid and humanoid:IsA("Humanoid") and description) then
		return
	end
	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not ok then
		warn(`AvatarService: couldn't apply {player.Name}'s look:`, err)
	end
	if player.Character ~= character then
		return -- respawned while applying
	end
	for _, callback in appliedCallbacks do
		task.spawn(callback, player, character)
	end
end

-- `callback(player, character)` runs each time a character has been given its look.
function AvatarService.onApplied(callback: (Player, Model) -> ())
	table.insert(appliedCallbacks, callback)
end

function AvatarService.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			applyTo(player, character)
		end)
		descriptions[player] = blockyDescription(player)
		if player.Character then
			applyTo(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local description = descriptions[player]
		if description then
			description:Destroy()
		end
		descriptions[player] = nil
	end)
end

return AvatarService
