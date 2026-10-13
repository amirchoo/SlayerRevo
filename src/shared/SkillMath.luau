--!strict
-- Skill tree rules and stat bonuses, shared by the server (which enforces them) and the
-- client (which shows them and predicts costs). Reads a player's state from attributes the
-- server sets: "Level", and "Skills" (JSON: { [treeId]: { [nodeId]: rank } }, where treeId
-- is "General" or a weapon's name). See SkillTrees for the data and SkillService for the server.

local HttpService = game:GetService("HttpService")

local ProgressionConfig = require(script.Parent.Config.ProgressionConfig)
local SkillTrees = require(script.Parent.Config.SkillTrees)

export type Allocations = { [string]: { [string]: number } }
type Node = SkillTrees.Node

local SkillMath = {}

-- Lookups built once from the data: General node -> its branch, and every tree's nodes by id.
local branchOfNode: { [string]: SkillTrees.Branch } = {}
local branchById: { [string]: SkillTrees.Branch } = {}
local nodesByTree: { [string]: { [string]: Node } } = { General = {} }
for _, branch in SkillTrees.General do
	branchById[branch.Id] = branch
	for _, node in branch.Nodes do
		branchOfNode[node.Id] = branch
		nodesByTree.General[node.Id] = node
	end
end
for weapon, nodes in SkillTrees.Weapons do
	nodesByTree[weapon] = {}
	for _, node in nodes do
		nodesByTree[weapon][node.Id] = node
	end
end

function SkillMath.node(treeId: string, nodeId: string): Node?
	local tree = nodesByTree[treeId]
	return if tree then tree[nodeId] else nil
end

function SkillMath.branchOf(nodeId: string): SkillTrees.Branch?
	return branchOfNode[nodeId]
end

-- The skill tree a weapon (its ToolName) uses: its own, or the one it shares (SharedTrees).
function SkillMath.treeOf(weapon: string): string
	return SkillTrees.SharedTrees[weapon] or weapon
end

function SkillMath.isTree(treeId: string): boolean
	return nodesByTree[treeId] ~= nil
end

-- Reading a player's allocations (cached per attribute value, so it's cheap per hit).
local cache: { [string]: Allocations } = {}
function SkillMath.decode(json: string?): Allocations
	if not json or json == "" then
		return {}
	end
	local cached = cache[json]
	if cached then
		return cached
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	local result: Allocations = if ok and typeof(decoded) == "table" then decoded else {}
	cache[json] = result
	return result
end

function SkillMath.allocations(player: Player): Allocations
	local json = player:GetAttribute("Skills")
	return SkillMath.decode(if typeof(json) == "string" then json else nil)
end

function SkillMath.level(player: Player): number
	local level = player:GetAttribute("Level")
	return if typeof(level) == "number" then level else 1
end

local function rankOf(alloc: Allocations, treeId: string, nodeId: string): number
	local tree = alloc[treeId]
	return if tree then tree[nodeId] or 0 else 0
end
SkillMath.rank = rankOf

-- Points spent in one tree (or all trees), and in one General branch.
function SkillMath.spent(alloc: Allocations, treeId: string?): number
	local total = 0
	for id, tree in alloc do
		if treeId == nil or id == treeId then
			for _, rank in tree do
				total += rank
			end
		end
	end
	return total
end

function SkillMath.spentInBranch(alloc: Allocations, branchId: string): number
	local branch = branchById[branchId]
	local total = 0
	if branch then
		for _, node in branch.Nodes do
			total += rankOf(alloc, "General", node.Id)
		end
	end
	return total
end

function SkillMath.availablePoints(alloc: Allocations, level: number): number
	return ProgressionConfig.totalPoints(level) - SkillMath.spent(alloc)
end

-- Whether one more rank of `nodeId` in `treeId` can be bought, and why not if it can't.
function SkillMath.check(alloc: Allocations, level: number, treeId: string, nodeId: string): (boolean, string?)
	local node = SkillMath.node(treeId, nodeId)
	if not node then
		return false, "Unknown skill"
	end
	if rankOf(alloc, treeId, nodeId) >= node.MaxRank then
		return false, "Maxed"
	end
	if treeId == "General" then
		local branch = branchOfNode[nodeId]
		if branch.Rival and SkillMath.spentInBranch(alloc, branch.Rival) > 0 then
			return false, `Locked by {branch.Rival}`
		end
		local need = SkillTrees.GeneralTierPoints[node.Tier] or 0
		if SkillMath.spentInBranch(alloc, branch.Id) < need then
			return false, `Needs {need} points in {branch.Name}`
		end
	else
		local need = SkillTrees.WeaponTierPoints[node.Tier] or 0
		if SkillMath.spent(alloc, treeId) < need then
			return false, `Needs {need} points in {treeId}`
		end
	end
	if node.Requires and rankOf(alloc, treeId, node.Requires) == 0 then
		local required = SkillMath.node(treeId, node.Requires)
		return false, `Needs {if required then required.Name else node.Requires}`
	end
	if node.Exclusive and rankOf(alloc, treeId, node.Exclusive) > 0 then
		local other = SkillMath.node(treeId, node.Exclusive)
		return false, `Can't take with {if other then other.Name else node.Exclusive}`
	end
	if SkillMath.availablePoints(alloc, level) <= 0 then
		return false, "No skill points"
	end
	return true, nil
end

-- Removes anything invalid (unknown or over-max nodes, broken rules) from saved
-- allocations, e.g. after the trees changed. Keeps as much as it legally can.
function SkillMath.sanitize(raw: any, level: number): Allocations
	local clean: Allocations = {}
	if typeof(raw) ~= "table" then
		return clean
	end
	-- Re-buy every saved rank in tier order, keeping only what the rules allow.
	local wanted: { { tree: string, node: Node, rank: number } } = {}
	for treeId, tree in raw do
		if typeof(treeId) == "string" and typeof(tree) == "table" and nodesByTree[treeId] then
			for nodeId, rank in tree do
				local node = typeof(nodeId) == "string" and SkillMath.node(treeId, nodeId)
				if node and typeof(rank) == "number" and rank >= 1 then
					table.insert(wanted, { tree = treeId, node = node, rank = math.min(math.floor(rank), node.MaxRank) })
				end
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.node.Tier < b.node.Tier
	end)
	for _, entry in wanted do
		for _ = 1, entry.rank do
			if not SkillMath.check(clean, level, entry.tree, entry.node.Id) then
				break
			end
			clean[entry.tree] = clean[entry.tree] or {}
			clean[entry.tree][entry.node.Id] = rankOf(clean, entry.tree, entry.node.Id) + 1
		end
	end
	return clean
end

-- Stat totals --------------------------------------------------------------------------

local function treeStat(alloc: Allocations, treeId: string, stat: string): number
	local total = 0
	local tree = alloc[treeId]
	if tree then
		for nodeId, rank in tree do
			local node = SkillMath.node(treeId, nodeId)
			local perRank = node and node.Effects[stat]
			if perRank then
				total += perRank * rank
			end
		end
	end
	return total
end

-- A General stat bonus for `player` (e.g. "MaxHealth" -> +30).
function SkillMath.general(player: Player, stat: string): number
	return treeStat(SkillMath.allocations(player), "General", stat)
end

-- A weapon tree stat bonus for `player` with `weapon` (its ToolName).
function SkillMath.weapon(player: Player, weapon: string, stat: string): number
	return treeStat(SkillMath.allocations(player), SkillMath.treeOf(weapon), stat)
end

-- `base` damage after the player's skills, for a "Light" (combo, arrow) or "Heavy" attack.
function SkillMath.damage(player: Player, weapon: string, base: number, kind: "Light" | "Heavy"): number
	local alloc = SkillMath.allocations(player)
	local tree = SkillMath.treeOf(weapon)
	local multiplier = 1
		+ treeStat(alloc, "General", "Damage")
		+ treeStat(alloc, tree, "Damage")
		+ treeStat(alloc, tree, kind .. "Damage")
	return math.round(base * multiplier)
end

-- `base` stamina cost after the player's skills (never below 30% of it).
function SkillMath.staminaCost(player: Player, weapon: string, base: number, kind: "Light" | "Heavy"): number
	local alloc = SkillMath.allocations(player)
	local tree = SkillMath.treeOf(weapon)
	local multiplier = 1 + treeStat(alloc, tree, "StaminaCost") + treeStat(alloc, tree, kind .. "StaminaCost")
	return base * math.max(multiplier, 0.3)
end

-- Has `player` unlocked caster `weapon`'s class (e.g. the staff's Mage) and, given an
-- element name, that element? (See SkillTrees.Casters.)
function SkillMath.spellUnlocked(player: Player, weapon: string, element: string?): boolean
	local caster = SkillTrees.Casters[weapon]
	if not caster then
		return false
	end
	local alloc = SkillMath.allocations(player)
	if rankOf(alloc, weapon, caster.Class) == 0 then
		return false
	end
	if element == nil then
		return true
	end
	local unlock = caster.ElementUnlocks[element]
	return unlock ~= nil and rankOf(alloc, weapon, unlock) > 0
end

-- A caster's spell damage after skills, including that element's own upgrades
-- (e.g. Inferno for Fire).
function SkillMath.spellDamage(player: Player, weapon: string, element: string, base: number, kind: "Light" | "Heavy"): number
	local bonus = treeStat(SkillMath.allocations(player), weapon, `{element}Damage`)
	return math.round(SkillMath.damage(player, weapon, base, kind) * (1 + bonus))
end

return SkillMath
