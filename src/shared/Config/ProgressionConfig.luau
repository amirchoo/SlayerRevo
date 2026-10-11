--!strict
-- Player levels and skill points. Defeating enemies gives XP (each enemy's XP is in
-- EnemyConfig); each level gives skill points to spend in the skill trees (SkillTrees).
-- Early levels come fast, later ones take steadily longer.

local ProgressionConfig = {}

ProgressionConfig.MaxLevel = 60
ProgressionConfig.StartingPoints = 2 -- skill points a brand-new player has at level 1
ProgressionConfig.PointsPerLevel = 1

-- XP needed to go from `level` to the next: 30 at level 1, ~170 at 5, ~460 at 10, ~1260 at 20.
function ProgressionConfig.xpToNext(level: number): number
	return math.floor(30 + 20 * (level - 1) ^ 1.4)
end

-- Total skill points a player of `level` has earned.
function ProgressionConfig.totalPoints(level: number): number
	return ProgressionConfig.StartingPoints + (level - 1) * ProgressionConfig.PointsPerLevel
end

return ProgressionConfig
