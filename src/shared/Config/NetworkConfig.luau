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
		BowShoot = 12,
		GreatswordCharge = 12,
		GreatswordRelease = 12,
		GreatswordSwing = 12,
		ArmorEquip = 10,
		InventoryMove = 10,
		DashStart = 10,
	} :: { [string]: number },
}
