--!strict
-- How often each client may fire each RemoteEvent (see server RemoteGuard). Requests over
-- the limit are dropped, so a modified client can't flood the server. Limits are bursts per
-- second: far above anything real play does, so normal players never hit them.

return {
	DefaultPerSecond = 15,
	PerSecond = {
		MeleeSwing = 12,
		HeavyAttack = 12,
		SwordBlock = 20,
		BowDraw = 12,
		CrossbowShoot = 12,
		BlunderbussShoot = 12,
		BowShoot = 12,
		GreatswordCharge = 12,
		GreatswordRelease = 12,
		GreatswordSwing = 12,
		ArmorEquip = 10,
		ShieldEquip = 10,
		InventoryMove = 10,
		TestChestTake = 5,
		StarterChoose = 3,
		DashStart = 10,
		SkillSpend = 10,
		SkillRespec = 3,
		StaffElement = 10,
		StaffCast = 12,
		StaffCharge = 12,
		StaffRelease = 12,
		ShopBuy = 5,
		ConsumableUse = 8,
		QuestStart = 3,
		QuestCancel = 3,
		QuestTrack = 6,
		MapTeleport = 2,
		Cooking = 6,
		TutorialAction = 5,
	} :: { [string]: number },
}
