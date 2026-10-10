--!strict
-- Combat tuning shared by the server (authoritative) and client (input gating/visuals).

return {
	Sword = {
		ToolName = "Sword",
		Damage = 25,
		Cooldown = 0.6, -- seconds between swings
		HitDelay = 0.15, -- seconds after the swing starts before the hit lands
		Range = 6, -- hitbox depth in front of the player, in studs
		Width = 6,
		Height = 6,
	},
}
