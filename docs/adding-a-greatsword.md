# Adding a new greatsword-type weapon

Step by step, from the `.glb` your friend delivers to a new weapon in game that **moves like
the Greatsword** (same sweeps, charged slam and guard) but has its own model, name, rarity and
stats, the way Emberfang is a stronger Sword.

> **Placeholder name:** this guide calls the new weapon **`MyGreatsword`**. Pick the real name
> (PascalCase, no spaces, e.g. `Dreadcleaver`) and use it **everywhere** `MyGreatsword` appears:
> file names, `ToolName`, config keys. It must be identical in every place.

General model steps are also in `docs/adding-a-weapon.md`. This file is the complete,
greatsword-specific version.

---

## Why a greatsword needs more work than an Emberfang-style weapon

Most melee weapons (Sword, Emberfang, Mace...) share one system, `WeaponService` +
`ComboWeaponClient`, which already handles any number of weapons. **The Greatsword doesn't.**
It has its own system written for exactly one weapon:

- `src/server/GreatswordService.luau`: `local GREATSWORD = CombatConfig.Greatsword`
- `src/client/GreatswordClient.luau`: the same, and it only reacts to a tool named `"Greatsword"`

So step 7 changes both files to handle a **list** of greatsword-type weapons (the same way
`CombatConfig.Casters` lets the Staff and Grimoire share `StaffService`). Once that's done, any
later greatsword-type weapon only needs a config entry.

The three greatsword remotes (`GreatswordCharge`, `GreatswordRelease`, `GreatswordSwing`) are
**shared**, not copied: a player holds only one weapon at a time, and the server works out
which one from the tool in their hand. So `NetworkConfig.luau` and the Remotes folder don't
change.

---

## Overview

| # | Step | Who | Files |
|---|---|---|---|
| 1 | Check the delivered model | You | |
| 2 | Add it to the repo | You or Claude | `assets/source/weapons/` |
| 3 | Inspect it | Claude | `tools/weapon_glb.py --info` |
| 4 | Bake colors and pose | Claude | `tools/weapon_glb.py` |
| 5 | Import into Studio and save | **You (Studio)** | `assets/weapons/MyGreatsword.rbxmx` |
| 6 | Weapon config | Claude | `CombatConfig.luau` |
| 7 | Let the greatsword system handle several weapons | Claude | `GreatswordService.luau`, `GreatswordClient.luau` |
| 8 | Blocking and parry | Claude | `BlockService.luau`, `ParryWindow.luau` |
| 9 | Inventory, rarity, shop | Claude | `InventoryConfig.luau` |
| 10 | Skill tree, tutorial, hit effects, sound | Claude | `SkillTrees.luau`, `TutorialConfig.luau`, `HitEffectsClient.luau`, `Sounds.luau` |
| 11 | Docs | Claude | `assets/weapons/README.md`, `docs/design.md`, `docs/combat-breakdown.md` |
| 12 | Syntax check, test in game, commit | Both | |

**Decide before starting** (they're your calls, not defaults):

- The name
- The **rarity** (Common / Uncommon / Rare / Epic / Legendary). This decides whether it's sold:
  only **Common** weapons appear at Blacksmith Bram (300 coins). Anything rarer can only be
  obtained through the admin Test Chest until drops exist.
- Roughly how it should differ from the Greatsword (stronger? faster? bigger guard?)
- Its trail/hit color (the theme color from the design)

---

## 1. Check the delivered model

It should follow `docs/model-brief.md`. For a greatsword:

- [ ] **One `.glb`** named `MyGreatsword.glb`
- [ ] Length along **+Y**: pommel/handle at the bottom (-Y), tip at the top (+Y)
- [ ] Blade thickness along **Z** (thinnest side), blade width along **X**
- [ ] Handle centered on X = 0, Z = 0
- [ ] The grip is its own material (`gripWrap`, `leather`, `wood`): a two-hand grip, so long
- [ ] Flat colors only, 3 to 8 named materials, no image textures
- [ ] Around **8.9 studs long** (the current Greatsword); the game rescales it anyway
- [ ] **Under 8,000 triangles** (hard limit 20,000)
- [ ] No floating glows or effects (the game draws trails and the charge glow itself)
- [ ] Your friend told you: triangle count, size (X, Y, Z), material names + colors

If any of these fail, send it back: that's cheaper than fixing it after import.

## 2. Add it to the repo

```
assets/source/weapons/MyGreatsword.glb
```

## 3. Inspect it

```sh
python3 -I tools/weapon_glb.py assets/source/weapons/MyGreatsword.glb /dev/null --info
```

Note down:

- **Size along Y**: the length, handle end to tip
- **The grip material's Y range**: where the hands go
- **Triangle count**: over 20,000 → shrink it with `tools/decimate_glb.py` (headless
  Blender) and inspect again

## 4. Bake the colors and set the pose

```sh
python3 -I tools/weapon_glb.py assets/source/weapons/MyGreatsword.glb assets/source/weapons/MyGreatsword.ready.glb
```

Studio would import a flat-color model grey; this bakes the colors into a texture and puts it
in the pose the game expects. **Don't** pass `--turn-y 180` (that's for characters; Studio's
import already turns GLBs 180° around Y). A greatsword is two-edged and symmetric, so the turn
doesn't matter for it.

## 5. Import into Studio and save (you)

1. Studio > **File > Import 3D** > `assets/source/weapons/MyGreatsword.ready.glb`. Keep the
   default settings.
2. In the Explorer, **rename** the imported Model to exactly `MyGreatsword`.
3. Right-click it > **Save to File** > `assets/weapons/MyGreatsword.rbxmx`.
4. Delete the imported copy from Workspace. The game takes it from
   `ServerStorage.WeaponModels`, which Rojo fills from `assets/weapons/`.
5. **Check it synced:** `ServerStorage > WeaponModels > MyGreatsword` should exist, and its
   MeshPart should have a `MeshId`. Rojo often fails to sync new mesh models (the Dagger never
   showed up; others came in as checkered boxes). If it's missing or checkered, ask Claude
   Code to rebuild it in Studio with `CreateMeshPartAsync` from the `.rbxmx`'s MeshId.

The weapon still works if the model is missing: it falls back to the parts-built placeholder
blade from `GreatswordService`.

---

## 6. Weapon config: `src/shared/Config/CombatConfig.luau`

### 6a. Move the Greatsword out of the return table

Today the Greatsword's config sits **inside** the `return { ... }` table at the bottom of the
file (`Greatsword = { ToolName = "Greatsword", ... }`). Cut that whole block out and put it
**above** the `return`, as a local, followed by an exported type:

```lua
-- Two-handed greatsword: hold left-click to charge (feet planted), release to slam.
-- The charge level reached decides damage; level 2+ knocks enemies back.
local Greatsword = {
	ToolName = "Greatsword",
	-- ... everything that was there, unchanged ...
	ModelFit = { Length = 8.9, GripFrom = 0.18 },
}

-- A weapon on the greatsword's system (GreatswordService, GreatswordClient).
export type GreatswordWeapon = typeof(Greatsword)
```

### 6b. Add the new weapon's entry

Right after that, paste this and fill it in. **Every field must be present**: it's typed as
`GreatswordWeapon`, so a missing or misspelled field is a type error.

The numbers below are an **example for an Epic weapon**, scaled like Emberfang is from the
Sword (about 30% more damage, a bit less stamina, a sturdier guard, a slightly kinder parry).
Tune them to the rarity you chose.

```lua
-- MyGreatsword (Epic): the greatsword's moves and animations, hitting about 30% harder for a
-- little less stamina, with a sturdier guard. Uses the Greatsword's skill tree
-- (SkillTrees.SharedTrees).
local MyGreatsword: GreatswordWeapon = {
	ToolName = "MyGreatsword", -- must match assets/weapons/MyGreatsword.rbxmx and InventoryConfig
	Hand = "Right",
	WalkSpeed = 12, -- while equipped (the Greatsword: 12)

	-- The Greatsword's animations (same moves). Only change these if it gets its own.
	IdleAnimation = Greatsword.IdleAnimation,
	ChargeAnimation = Greatsword.ChargeAnimation,
	SlamAnimation = Greatsword.SlamAnimation,
	GuardAnimation = Greatsword.GuardAnimation,

	HoldTime = 0.25, -- tap shorter than this = sweep; hold longer = charge a slam

	-- Combo sweeps. Keep Animation and HitDelay as the Greatsword's (they match the animations);
	-- tune Damage, Radius (reach in studs), Arc (degrees; 360 = all round) and Knockback.
	Combo = ({
		{ Animation = Greatsword.Combo[1].Animation, Damage = 32, Cooldown = 0.6, HitDelay = Greatsword.Combo[1].HitDelay, Radius = 10, Arc = 200 },
		{ Animation = Greatsword.Combo[2].Animation, Damage = 39, Cooldown = 0.6, HitDelay = Greatsword.Combo[2].HitDelay, Radius = 10, Arc = 200 },
		{ Animation = Greatsword.Combo[3].Animation, Damage = 58, Cooldown = 1.0, HitDelay = Greatsword.Combo[3].HitDelay, Radius = 11, Arc = 360, Knockback = 30 },
	} :: { GreatswordSwing }),
	ComboWindow = 0.8, -- seconds after a swing's cooldown to click again before the combo resets
	SwingWalkSpeed = 6, -- while swinging
	SwingStamina = 12, -- per sweep (the Greatsword: 14)
	SlamStamina = 22, -- to start charging a slam (the Greatsword: 25)

	-- Charge levels, reached after holding for Time seconds. Keep the Times; tune the rest.
	ChargeLevels = {
		{ Time = 0, Damage = 45, Knockback = 0 },
		{ Time = 0.5, Damage = 70, Knockback = 0 },
		{ Time = 1.0, Damage = 105, Knockback = 35 },
		{ Time = 1.6, Damage = 155, Knockback = 60 },
	},
	KnockbackTime = 0.25,
	HitDelay = Greatsword.HitDelay, -- when the slam lands after release (matches the animation)
	Recovery = 0.9, -- seconds after a slam before you can charge again

	-- The slam's hitbox in front of you, in studs.
	Range = 10,
	Width = 9,
	Height = 8,

	BlockAmount = 45, -- damage absorbed per block (the Greatsword: 35)
	ParryWindow = 0.14, -- seconds after raising the guard that a hit is parried (the Greatsword: 0.12)

	-- Fitting the model in the hand (see step 6c).
	ModelFit = { Length = 8.9, GripFrom = 0.18 },
}
```

### 6c. `ModelFit`: fitting the model in the hand

`src/server/WeaponModels.luau` scales and turns the model automatically. You only set:

| Field | Meaning | How to get it |
|---|---|---|
| `Length` | Studs from the handle end to the tip. The model is scaled to exactly this | The Y size from step 3, or the length you want in game (Greatsword 8.9) |
| `GripFrom` | Where the right hand holds it, as a fraction of `Length` from the handle end | (middle of the grip material along Y, measured from the handle end) ÷ length. A two-hand grip: put it near the **top** of the grip, under the crossguard (Greatsword 0.18) |
| `FlipBlade = true` | Only if it comes out held by the tip | Look in game |
| `FlipEdge = true` | Turns it 180° around the handle | Not needed for a symmetric two-edged blade. Only if it has a one-sided feature facing the wrong way |
| `Shift` | Moves the hand off the center line | Only for an off-center grip. **Negate** X/Z from `--info` (Studio flips them on import) |

Example: length 9.0, grip material from Y = 0.3 to Y = 1.9 (from the handle end). The hand
goes near the top of the grip, about 1.6 → `GripFrom = 1.6 / 9.0 ≈ 0.18`.

### 6d. Export it

In the `return { ... }` table at the bottom, add these next to the other weapons:

```lua
	Greatsword = Greatsword,
	MyGreatsword = MyGreatsword,
	-- Every weapon on the greatsword's system (GreatswordService, GreatswordClient).
	Greatswords = { Greatsword, MyGreatsword },
```

**From now on, a further greatsword-type weapon only needs its own entry (6b) and to be added
to `Greatswords`.**

---

## 7. Let the greatsword system handle several weapons

These two files are rewritten so everything reads the config of **the greatsword-type weapon
in hand** instead of the one fixed `GREATSWORD`. When done, this should find nothing:

```sh
grep -n "GREATSWORD\|LEVELS" src/server/GreatswordService.luau src/client/GreatswordClient.luau
```

### 7a. Server: `src/server/GreatswordService.luau`

**Replace** these two lines:

```lua
local GREATSWORD = CombatConfig.Greatsword
local LEVELS = GREATSWORD.ChargeLevels
```

with:

```lua
type GreatswordWeapon = CombatConfig.GreatswordWeapon

-- Every weapon on this system, by ToolName. They share the remotes: a player only holds one
-- at a time, and the server checks which one it is.
local CONFIGS: { [string]: GreatswordWeapon } = {}
for _, config in CombatConfig.Greatswords do
	CONFIGS[config.ToolName] = config
end
```

**Replace** the three state tables:

```lua
local chargeStarted: { [Player]: number } = {}
local lastSlam: { [Player]: number } = {}
local comboStates: { [Player]: { step: number, time: number } } = {}
```

with (each one remembers which weapon it was for):

```lua
local chargeStarted: { [Player]: { time: number, config: GreatswordWeapon } } = {}
local recoveredAt: { [Player]: number } = {} -- when the last slam's recovery ends
local comboStates: { [Player]: { step: number, time: number, config: GreatswordWeapon } } = {}
```

**`createGreatsword`**: give it the config, and name the tool from it:

```lua
local function createGreatsword(config: GreatswordWeapon): Tool
	local tool = Instance.new("Tool")
	tool.Name = config.ToolName
	-- ... the rest unchanged ...
```

**Replace `holdingGreatsword` and `midSwing`** with:

```lua
-- The config of the greatsword-type weapon in hand, or nil.
local function heldConfig(character: Model): GreatswordWeapon?
	local tool = character:FindFirstChildOfClass("Tool")
	return if tool then CONFIGS[tool.Name] else nil
end

local function midSwing(player: Player, now: number): boolean
	local previous = comboStates[player]
	return previous ~= nil and now - previous.time < previous.config.Combo[previous.step].Cooldown - TIMING_SLACK
end
```

**Replace `onSwing`** with:

```lua
local function onSwing(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end
	local config = heldConfig(character)
	if not config then
		return
	end
	if player:GetAttribute("Blocking") == true or chargeStarted[player] then
		return
	end
	local now = os.clock()
	if now < (recoveredAt[player] or 0) - TIMING_SLACK or midSwing(player, now) then
		return -- still recovering from a slam or the last swing
	end

	-- Same rule as the client: the next step if clicked soon enough after the last swing (with
	-- the same weapon), otherwise back to the first.
	local combo = config.Combo
	local step = 1
	local previous = comboStates[player]
	if previous and previous.config == config and previous.step < #combo then
		local window = combo[previous.step].Cooldown + config.ComboWindow + TIMING_SLACK
		if now - previous.time <= window then
			step = previous.step + 1
		end
	end
	if not StaminaService.spend(player, SkillMath.staminaCost(player, config.ToolName, config.SwingStamina, "Light")) then
		return -- too tired
	end
	comboStates[player] = { step = step, time = now, config = config }

	local move = combo[step]
	task.delay(move.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) or heldConfig(character) ~= config then
			return
		end
		local damage = SkillMath.damage(player, config.ToolName, move.Damage, "Light")
		for _, hit in MeleeHitbox.strikeArc(player, character, root, move.Radius, move.Arc, damage, config.ToolName) do
			if move.Knockback and HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, move.Knockback, config.KnockbackTime)
			end
		end
	end)
end
```

**Replace `onCharge`** with:

```lua
local function onCharge(player: Player)
	local character = player.Character
	if not character or not HealthService.isAlive(character) then
		return
	end
	local config = heldConfig(character)
	if not config or player:GetAttribute("Blocking") == true then
		return
	end
	local now = os.clock()
	if now < (recoveredAt[player] or 0) - TIMING_SLACK or midSwing(player, now) then
		return -- still recovering from the last slam or swing
	end
	if not StaminaService.spend(player, SkillMath.staminaCost(player, config.ToolName, config.SlamStamina, "Heavy")) then
		return -- too tired
	end
	chargeStarted[player] = { time = now, config = config }
	comboStates[player] = nil -- a slam ends the combo
end
```

**Replace `onRelease`** with:

```lua
local function onRelease(player: Player)
	local charge = chargeStarted[player]
	chargeStarted[player] = nil
	local character = player.Character
	if not charge or not character or not HealthService.isAlive(character) or heldConfig(character) ~= charge.config then
		return
	end
	local config = charge.config

	-- The highest level reached, from the server's own timing of the charge.
	local now = os.clock()
	-- Swift Charge and the like make each level come sooner (see SkillTrees).
	local held = (now - charge.time) * (1 + SkillMath.weapon(player, config.ToolName, "ChargeSpeed"))
	local level = config.ChargeLevels[1]
	for _, candidate in config.ChargeLevels do
		if held >= candidate.Time then
			level = candidate
		end
	end
	recoveredAt[player] = now + config.Recovery

	task.delay(config.HitDelay, function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or not HealthService.isAlive(character) then
			return
		end
		local size = Vector3.new(config.Width, config.Height, config.Range)
		local damage = SkillMath.damage(player, config.ToolName, level.Damage, "Heavy")
		for _, hit in MeleeHitbox.strike(player, character, root, size, damage, config.ToolName) do
			if level.Knockback > 0 and HealthService.isAlive(hit.model) then
				EnemyEffects.knockBack(hit.model, root.Position, level.Knockback, config.KnockbackTime)
			end
		end
	end)
end
```

**`giveGreatsword`**: take the config for the hand:

```lua
local function giveGreatsword(player: Player, template: Tool, config: GreatswordWeapon)
	local greatsword = template:Clone()
	greatsword.Equipped:Connect(function()
		local character = greatsword.Parent
		if character and character:IsA("Model") then
			HandGrip.attach(greatsword, character, config.Hand :: HandGrip.Hand, "GreatswordGrip")
		end
	end)
	-- ... Unequipped and InventoryService.give unchanged ...
```

**`GreatswordService.start`**: build and give one of each:

```lua
function GreatswordService.start()
	local templates: { { tool: Tool, config: GreatswordWeapon } } = {}
	for _, config in CombatConfig.Greatswords do
		local template = createGreatsword(config)
		WeaponModels.apply(template, config.ModelFit) -- a real model, if one's been added (assets/weapons)
		table.insert(templates, { tool = template, config = config })
	end

	local function giveAll(player: Player)
		for _, entry in templates do
			giveGreatsword(player, entry.tool, entry.config)
		end
	end

	local function onPlayerAdded(player: Player)
		-- The Backpack is reset on every respawn, so hand out fresh ones each time.
		player.CharacterAdded:Connect(function()
			giveAll(player)
		end)
		if player.Character then
			giveAll(player)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		chargeStarted[player] = nil
		recoveredAt[player] = nil
		comboStates[player] = nil
	end)

	RemoteGuard.connect(chargeRemote, onCharge)
	RemoteGuard.connect(releaseRemote, onRelease)
	RemoteGuard.connect(swingRemote, onSwing)
end
```

Every player gets every greatsword-type tool; `InventoryService.give` parks the ones they
don't own out of reach, so nothing about ownership changes here.

### 7b. Client: `src/client/GreatswordClient.luau`

**Replace** these two lines:

```lua
local GREATSWORD = CombatConfig.Greatsword
local LEVELS = GREATSWORD.ChargeLevels
```

with:

```lua
type GreatswordWeapon = CombatConfig.GreatswordWeapon
```

**Replace** the animation constants (`IDLE_ANIMATION` ... the `SWING_ANIMATIONS` loop, just
after `makeAnimation`) with one set per weapon:

```lua
type Animations = {
	idle: Animation?,
	charge: Animation?,
	slam: Animation?,
	guard: Animation?,
	swings: { Animation? },
}

-- Every weapon on this system, and its animations, by ToolName.
local CONFIGS: { [string]: GreatswordWeapon } = {}
local ANIMATIONS: { [string]: Animations } = {}
for _, config in CombatConfig.Greatswords do
	CONFIGS[config.ToolName] = config
	local swings: { Animation? } = {}
	for index, move in config.Combo do
		swings[index] = makeAnimation(move.Animation)
	end
	ANIMATIONS[config.ToolName] = {
		idle = makeAnimation(config.IdleAnimation),
		charge = makeAnimation(config.ChargeAnimation),
		slam = makeAnimation(config.SlamAnimation),
		guard = makeAnimation(config.GuardAnimation),
		swings = swings,
	}
end
```

**Replace** `tracksByHumanoid` and `getTracks` (tracks are now cached per weapon too):

```lua
local tracksByHumanoid: { [Humanoid]: { [string]: Tracks } } = setmetatable({}, { __mode = "k" }) :: any

local function getTracks(humanoid: Humanoid, config: GreatswordWeapon): Tracks
	local byWeapon = tracksByHumanoid[humanoid]
	if not byWeapon then
		byWeapon = {}
		tracksByHumanoid[humanoid] = byWeapon
	end
	local cached = byWeapon[config.ToolName]
	if cached then
		return cached
	end
	local animations = ANIMATIONS[config.ToolName]
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local tracks: Tracks = { swings = {} }
	if animator then
		-- Priorities set here so it doesn't matter how each animation was published.
		tracks.idle = load(animator, animations.idle, Enum.AnimationPriority.Idle, true)
		tracks.charge = load(animator, animations.charge, Enum.AnimationPriority.Action, false)
		tracks.slam = load(animator, animations.slam, Enum.AnimationPriority.Action, false)
		tracks.guard = load(animator, animations.guard, Enum.AnimationPriority.Action, true)
		for index, animation in animations.swings do
			local track = load(animator, animation, Enum.AnimationPriority.Action, false)
			if track then
				tracks.swings[index] = track
			end
		end
	end
	byWeapon[config.ToolName] = tracks
	return tracks
end
```

**Add `config` to the `Equipped` type:**

```lua
type Equipped = {
	tool: Tool,
	config: GreatswordWeapon,
	humanoid: Humanoid,
	-- ... the rest unchanged ...
}
```

**Inside the functions, swap `GREATSWORD` for the equipped weapon's config.** Each of these
functions already has `state` (or gets it from `equipped`):

| Function | Change |
|---|---|
| `walkSpeedFor(state)` | `GREATSWORD.SwingWalkSpeed` → `state.config.SwingWalkSpeed`, `GREATSWORD.WalkSpeed` → `state.config.WalkSpeed` |
| `swing(state)` | Add `local config = state.config` at the top; every `GREATSWORD.` → `config.` |
| `startCharge(state)` | Add `local config = state.config` at the top; every `GREATSWORD.` → `config.`; the `for index, candidate in LEVELS do` loop → `in config.ChargeLevels do`. This covers `stopCharge` inside it too (`config.HitDelay`, `config.Recovery`) |
| `onAttackBegan()` | `GREATSWORD.HoldTime`, `.Recovery`, `.ToolName`, `.SlamStamina` → `state.config.…` |
| `onAttackEnded()` | `held < GREATSWORD.HoldTime` → `held < state.config.HoldTime` |

**`onEquipped`**: look up the weapon in hand:

```lua
local function onEquipped(tool: Tool, character: Model)
	local config = CONFIGS[tool.Name]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not config or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	HandGrip.attachLocal(tool, character, config.Hand :: HandGrip.Hand, "GreatswordGrip")

	local state: Equipped = {
		tool = tool,
		config = config,
		humanoid = humanoid,
		root = root,
		tracks = getTracks(humanoid, config),
		baseWalkSpeed = StarterPlayer.CharacterWalkSpeed,
	}
	-- ... the rest unchanged ...
```

**`hookTool`**: react to any greatsword-type tool:

```lua
	if not child:IsA("Tool") or not CONFIGS[child.Name] then
		return
	end
```

**`GreatswordClient.start`**: preload every weapon's animations:

```lua
	task.spawn(function()
		local preload: { Instance } = {}
		for _, animations in ANIMATIONS do
			for _, animation in { animations.idle, animations.charge, animations.slam, animations.guard } do
				if animation then
					table.insert(preload, animation)
				end
			end
			for _, animation in animations.swings do
				if animation then
					table.insert(preload, animation)
				end
			end
		end
		if #preload > 0 then
			ContentProvider:PreloadAsync(preload)
		end
	end)
```

`init.server.luau` and `init.client.luau` **don't change**: `GreatswordService.start()` and
`GreatswordClient.start()` now cover every weapon in `CombatConfig.Greatswords`.

---

## 8. Blocking and parry

The guard is the shared block system; it needs to know the new weapon can block.

**`src/server/BlockService.luau`**, in `BLOCK_AMOUNTS`, under the Greatsword line:

```lua
	[CombatConfig.MyGreatsword.ToolName] = CombatConfig.MyGreatsword.BlockAmount,
```

**`src/shared/ParryWindow.luau`**, in `BASE`, under the Greatsword line:

```lua
	[CombatConfig.MyGreatsword.ToolName] = CombatConfig.MyGreatsword.ParryWindow,
```

(Without these it can't block or parry at all.)

## 9. Inventory, rarity and shop: `src/shared/Config/InventoryConfig.luau`

In `InventoryConfig.Weapons`, under the Greatsword:

```lua
	{ Name = "MyGreatsword", Class = "Swords", Rarity = "Epic", Description = "A <theme> greatsword: the greatsword's sweeps and slam, hitting harder. Shares the Greatsword skill tree." },
```

- `Name` must equal the `ToolName`.
- `Class = "Swords"` puts it in the Primary hotbar slot, like the Greatsword.
- `Rarity`: leave it out (or `"Common"`) and it's **sold at the Blacksmith for 300 coins**
  automatically (`ShopConfig.luau`). Any other rarity keeps it **out of the shop**; players get
  it from the admin Test Chest for now.

In `InventoryConfig.PrimaryFilters`, add it to the Two-Handed filter:

```lua
	{ Id = "Two-Handed", Weapons = { "Greatsword", "MyGreatsword", "Hammer", "DualBlade" } },
```

## 10. Skill tree, tutorial, hit effects and sound

**`src/shared/Config/SkillTrees.luau`**: share the Greatsword's tree (points spent there
count for both; Swift Charge, Executioner etc. work on it automatically):

```lua
SkillTrees.SharedTrees = {
	Emberfang = "Sword",
	MyGreatsword = "Greatsword",
} :: { [string]: string }
```

Don't add it to `SkillTrees.WeaponOrder` (that's the tabs; it has no tab of its own).

**`src/shared/Config/TutorialConfig.luau`**: after the `TutorialConfig.Weapons = { ... }`
table closes, teach it like the Greatsword:

```lua
TutorialConfig.Weapons.MyGreatsword = TutorialConfig.Weapons.Greatsword -- the greatsword's moves
```

**`src/client/HitEffectsClient.luau`**: in `LOOKS`, its impact (style, theme color, size; the
Greatsword is 1.6):

```lua
	MyGreatsword = { style = "Slash", color = Color3.fromRGB(255, 200, 120), size = 1.6 },
```

**`src/shared/Sounds.luau`**: hit sounds are looked up as `<ToolName>Hit`, and a weapon
without one plays the **Sword's** hit. The Greatsword's is deliberately silent (its swing and
slam sounds already land with the hit), so copy that:

```lua
	MyGreatswordHit = { Id = "", Pitch = 1, Volume = 0.5 }, -- silent, like GreatswordHit
```

The swing (`GreatswordSwing`) and slam (`GreatswordSlam`) sounds are shared automatically.

**Optional:**

- `src/server/TrainingStands.luau`: a mannequin holding it (copy the Greatsword's line).
- `IntroConfig.luau` and `ArmorConfig.luau` (`StarterFor`) **don't** change: the Berserker
  class still starts with the plain Greatsword.
- `ShieldConfig.luau` doesn't change: two-handed weapons can't use shields.

## 11. Docs

- `assets/weapons/README.md`: add `MyGreatsword` to the list of names, and a row to the table
  (`MyGreatsword.ready.glb`, source: your friend's name / "Original design").
- `docs/design.md` §12: a line saying what was built (name, rarity, "the Greatsword's moves,
  stronger, shares its tree", whether it's sold).
- `docs/combat-breakdown.md` §4: a row in the weapon overview table, the stats table, and a
  short section like "Emberfang (Epic): the Sword, stronger".

## 12. Check, test, commit

1. **Syntax check** (one syntax error stops every script loading in Studio):
   ```sh
   sh tools/check_syntax.sh
   ```
2. **Check the old Greatsword still works.** Step 7 rewrote its system; tap sweeps, the
   charged slam (all four levels), guard and parry should all behave as before.
3. **Get the new one in game:** the Test Chest in the admin-only Training Grounds hands out
   any weapon (or buy it at the Blacksmith if it's Common). Check:
   - [ ] Held by the grip, both hands near the top of the grip, blade pointing the right way
   - [ ] The right size next to the character
   - [ ] Sweeps, combo finisher knockback, charged slam and glow, guard and parry all work
   - [ ] Its damage numbers match its config (not the Greatsword's)
   - [ ] It appears under Primary > Two-Handed in the backpack, in its rarity color
   - [ ] Skill points in the Greatsword tree affect it
   - [ ] Switching between the Greatsword and it mid-combo doesn't carry the combo over

   If the fit is off, adjust `ModelFit` (step 6c) and look again.
4. **Commit everything together:** `MyGreatsword.glb`, `MyGreatsword.ready.glb`,
   `MyGreatsword.rbxmx`, and all the code and docs changes.

---

## Shortcut: have Claude Code do it

You only have to do step 5 (Studio import). Paste:

> My friend delivered `<path>/<Name>.glb`. Add it as a new greatsword-type weapon following
> `docs/adding-a-greatsword.md`. Name: **<Name>**. Rarity: **<rarity>**. Compared with the
> Greatsword it should be **<e.g. 30% stronger, slightly faster stamina, bigger guard>**.
> Theme color: **<color>**. Description: "<one line>".

Claude Code does steps 2 to 4, stops for you to import and save it in Studio, then does 6 to
12.
