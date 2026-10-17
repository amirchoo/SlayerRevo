--!strict
-- Puts the server-moved creatures far from every player to sleep (EnemyService's orcs and
-- packs, AnimalService's animals): they stand still with their root anchored, so the server
-- spends no physics on them and has no movement to send to clients, and their AI only checks
-- every SLEEP.Tick seconds whether to wake. A player coming within SLEEP.WakeRange wakes them
-- (they doze off again past SLEEP.SleepRange; the gap stops them flickering at the edge). No
-- weapon reaches past CombatConfig's 140-stud missiles, so nothing can hit a sleeping creature.
-- Their animations keep playing (an anchored orc still breathes in its idle).

local Players = game:GetService("Players")

local Dormancy = {}

Dormancy.Config = {
	WakeRange = 220, -- studs from the nearest player character: closer wakes a sleeper
	SleepRange = 280, -- further than this from every player puts an awake one to sleep
	Tick = 1, -- seconds between a sleeper's checks
}

-- Whether any player's character is within `range` studs of `position`.
function Dormancy.playerNear(position: Vector3, range: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude < range then
			return true
		end
	end
	return false
end

-- Stops a creature where it stands and anchors it once it's on the ground (not mid-jump or
-- falling; call again next tick until it's down). Safe to call every tick.
function Dormancy.sleep(humanoid: Humanoid, root: BasePart)
	if root.Anchored then
		return
	end
	humanoid:MoveTo(root.Position)
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
	end
end

-- Lets it move again, with the server moving it (anchoring loses the network owner).
function Dormancy.wake(root: BasePart)
	if not root.Anchored then
		return
	end
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end

return Dormancy
