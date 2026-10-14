--!strict
-- Shields: off-hand gear for one-handed weapons, shared by the server (ShieldService,
-- BlockService) and client (backpack, guard animation). A shield is worn in its own slot
-- (not the hotbar) and is optional. While a one-handed weapon is out it's held on the left
-- forearm and each block absorbs BlockBonus more damage, with ExtraCharges more block
-- charges; with any other weapon (or none) it's slung on the back and does nothing.

export type Shield = {
	Name: string,
	Rarity: string?, -- one of InventoryConfig.Rarities' Id; nil = "Common"
	StarterFor: string?, -- the weapon it goes with as a set (a label for now, like armor's)
	Description: string,
	BlockBonus: number, -- extra damage absorbed per block
	ExtraCharges: number, -- extra block charges
	Color: Color3, -- the placeholder's face (used until there's a model)
	TrimColor: Color3, -- the placeholder's rim and boss
}

local ShieldConfig = {}

-- Weapons (ToolName) that can be used with a shield.
ShieldConfig.OneHanded = { "Sword", "Emberfang", "Mace", "Axe", "Rapier" }

-- Played instead of the weapon's own guard while blocking with a shield, for a weapon whose
-- stance has no Guard yet (tools/shield_anims.py). Leave "" until published: the weapon's
-- guard is used meanwhile.
ShieldConfig.GuardAnimation = "rbxassetid://87055276993217" -- ShieldGuard

export type Stance = {
	Idle: string, -- loops instead of the weapon's idle while the shield is up
	Guard: string, -- played instead of GuardAnimation while blocking
}

-- Each one-handed weapon's (ToolName) idle and guard with a shield up (tools/shield_anims.py);
-- attacks stay the weapon's own. Leave "" until published: the weapon's idle and
-- GuardAnimation are used meanwhile.
ShieldConfig.Stances = {
	Sword = { Idle = "", Guard = "rbxassetid://90431531942999" }, -- SwordShieldIdle, SwordShieldGuard
	Mace = { Idle = "", Guard = "rbxassetid://137365984550648" }, -- MaceShieldIdle, MaceShieldGuard
	Axe = { Idle = "", Guard = "rbxassetid://126735171229166" }, -- AxeShieldIdle, AxeShieldGuard
	Rapier = { Idle = "", Guard = "rbxassetid://87465660980219" }, -- RapierShieldIdle, RapierShieldGuard
} :: { [string]: Stance }
ShieldConfig.Stances.Emberfang = ShieldConfig.Stances.Sword -- the sword's moves

ShieldConfig.Diameter = 2.6 -- studs across, whatever size the model comes in at
-- Studs between the body part's surface and the shield's back.
ShieldConfig.ArmGap = 0.05
ShieldConfig.BackGap = 0.1
ShieldConfig.ArmAlong = -0.15 -- studs along the forearm from its middle (- = toward the hand)
-- True if the model's face comes in pointing the wrong way (its front should be its -Z after
-- Import 3D, which turns models 180 degrees: tools/weapon_glb.py --info shows +Z).
ShieldConfig.FlipFace = false

ShieldConfig.Shields = {
	WardenShield = {
		Name = "Warden Shield",
		Rarity = "Uncommon",
		StarterFor = "Mace",
		Description = "A round iron-rimmed shield. With a one-handed weapon: blocks absorb more, and +1 block charge.",
		BlockBonus = 15, -- placeholder numbers, to tune
		ExtraCharges = 1,
		Color = Color3.fromRGB(95, 55, 30),
		TrimColor = Color3.fromRGB(90, 88, 100),
	},
} :: { [string]: Shield }

-- Shield ids in a fixed order (by name), e.g. for cycling through owned shields in the backpack.
ShieldConfig.Order = {} :: { string }
for id in ShieldConfig.Shields do
	table.insert(ShieldConfig.Order, id)
end
table.sort(ShieldConfig.Order)

-- True if `toolName` is a weapon a shield can be used with.
function ShieldConfig.canUseWith(toolName: string?): boolean
	return toolName ~= nil and table.find(ShieldConfig.OneHanded, toolName) ~= nil
end

-- The shield `player` has up (worn, with a one-handed weapon in hand), or nil.
-- "Shield" is set by the server only (see ShieldService), so this is safe to use there.
function ShieldConfig.active(player: Player): Shield?
	local id = player:GetAttribute("Shield")
	local shield = if typeof(id) == "string" then ShieldConfig.Shields[id] else nil
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if shield and tool and ShieldConfig.canUseWith(tool.Name) then shield else nil
end

return ShieldConfig
