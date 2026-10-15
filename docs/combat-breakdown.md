# Slayer Revo — Combat, Weapons & Armor Breakdown

A full reference of the combat system **as it's built**, pulled from the configs:
`src/shared/Config/CombatConfig.luau`, `ArmorConfig.luau`, `ShieldConfig.luau`, `BuffConfig.luau`,
`PlayerConfig.luau`, `ProgressionConfig.luau`, `SkillTrees.luau`, `EnemyConfig.luau`, and the
server services that apply them. If a number here disagrees with a config, the config wins.

Numbers marked *placeholder* in the configs are still to be tuned.

---

## 1. Core player stats

| Stat | Value | Notes |
|---|---|---|
| Max health | 150 | +15/rank Toughness, +40 Juggernaut |
| Health regen | 10/s | only after 15 s without taking damage |
| Max stamina | 100 | +10/rank Deep Lungs |
| Stamina regen | 30/s | after 0.8 s without spending; not while spinning or charging a heavy |
| Max mana | 100 | casters only; +15/rank Wellspring, +40 Archmage |
| Mana regen | 6/s | after 1.5 s without spending; not while charging a blast |
| Max level | 60 | XP to next level: `30 + 20 × (level − 1)^1.4` |
| Skill points | 2 at level 1, +1 per level | one pool shared by every tree |

---

## 2. Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Light attack (combo) | Tap left-click | Tap R2 / RT |
| Heavy attack | Hold left-click (0.2–0.25 s) | Hold R2 / RT |
| Block / parry | Hold right-click | L2 / LT |
| Aim / draw (ranged) | Hold right-click | L2 / LT |
| Dash | V | Circle / B |
| Lock-on | Q | R3 |
| Switch element (casters) | R | Triangle / Y |
| Backpack / armor | G | Touchpad / View |

---

## 3. Combat mechanics

### 3.1 Server authority
The server decides every hit, all damage, health, stamina, mana and loot. The client only
sends intent (attack, block, dash) and plays animations and effects. Remotes are validated
and rate-limited (`RemoteGuard`).

### 3.2 Stamina
Every melee swing, heavy, arrow and shot costs stamina (each weapon's cost is below). The
server refuses an attack you can't afford; the client checks first and flashes the bar.
Dashing and blocking **don't** cost stamina (they use charges).

### 3.3 Dash
| | |
|---|---|
| Charges | 2 (+1 with Extra Dash) |
| Recharge | 5 s per charge (−8%/rank Fleet Foot) |
| Speed / duration | 60 studs/s for 0.18 s (~11 studs) |
| Min gap between dashes | 0.25 s |
| **I-frames** | 0.25 s from the dash start (+0.05 s/rank Ghost Step) |

A hit during the i-frames is dodged completely, and a dodged hit never counts as blocked.

### 3.4 Blocking
| | |
|---|---|
| Charges | 3 (+1 Extra Guard, +shield's ExtraCharges) |
| Recharge | 5 s per used charge |
| Walk speed while blocking | 8 |
| Shove on a blocked hit | 22 studs/s for 0.15 s |

Each blocked hit uses a charge and absorbs the weapon's **BlockAmount**; the rest gets through.
With no charges left, hits go straight through.

**Block absorbed = weapon BlockAmount + Bulwark (5/rank) + Guardcraft (4/rank) + weapon mastery + shield BlockBonus**

### 3.5 Parrying
- A hit landing within the weapon's **ParryWindow** of raising the guard is negated completely,
  uses **no charge**, and stuns the attacker for **0.5 s**.
- Raising the guard again within **0.5 s** of the last raise gets no parry window (mashing doesn't work).
- The guard-raise time is the server's own, so it can't be faked.
- Window bonuses: Riposte +0.03 s/rank, Guardcraft +0.02 s/rank, Phalanx (spear) +0.05 s.

### 3.6 Hit feel
- **Hitstop**: attacker and target freeze for `0.03 + damage × 0.0008` s, clamped to 0.04–0.1 s.
- **Enemy flinch** on hit, hit sparks and sounds; parries flash.
- **Damage feedback** (your screen): red flash + camera shake scaled by the share of health lost;
  below 30% health a pulsing vignette, drained colours and a heartbeat.

### 3.7 Lock-on
Q toggles. Picks a target within 60 studs and 75° of view centre; lets go past 90 studs. The
camera sits over your right shoulder framing you and the target.

### 3.8 Status effects
| Effect | What it does | Sources |
|---|---|---|
| **Stun** | Enemy stops moving; its wind-up attack is cancelled | Mace combo finisher (1.5 s), Parry (0.5 s), Earth boulder (0.6 s, +0.2/rank Tremor), Scythe hook (held while dragged) |
| **Knockback** | Pushed away (studs/s) | Many finishers and heavies (see weapons) |
| **Bleed** | Damage every interval; reapplying restarts it (no stacking) | Axe cleave: 5 per 0.5 s for 3 s = 30 |
| **Burn** | Damage over time | Fire wave: 4 per 0.5 s for 3 s = 24 |
| **Slow** | Movement multiplied | Water missile (×0.6, 2 s), Thunder (×0.5, 3 s) |
| **Chain** | Jumps to more enemies | Electric missile: 2 jumps within 12 studs at 60% damage |

### 3.9 Damage pipeline (incoming damage to a player)
Filters run in this order on the server (`HealthService.damage`):

1. **Parry check** (enemy calls it before dealing damage) → hit negated.
2. **Dash i-frames** → hit dodged (0 damage).
3. **Block** → `damage − block absorbed` (floored at 0), uses a charge.
4. **Armor** → `× (1 − protection)`, protection capped at 80%.
5. **Buffs** → `× DamageTaken` (e.g. Bonnie's Grace × 0.9).

**Worked example** — an Orc hit (30) on a Sword user in full Leather with Bonnie's Grace:
blocked: 30 − 20 = 10 → armor: 10 × 0.80 = 8 → buff: 8 × 0.9 = **7.2**.
Unblocked: 30 × 0.80 × 0.9 = **21.6**.

### 3.10 Outgoing damage (skills)
- **Melee / arrows**: `round(base × (1 + General Damage + weapon Damage + Light/HeavyDamage))`.
- **Spells**: the above, then `× (1 + <Element>Damage)` (e.g. Inferno for Fire).
- **Stamina cost**: `base × max(1 + StaminaCost + Light/HeavyStaminaCost, 0.3)` (never below 30%).

---

## 4. Weapons

### 4.1 Overview
| Weapon | Class | Hotbar slot | Rarity | Hands | Light combo | Heavy |
|---|---|---|---|---|---|---|
| Sword | Swords | Primary | Common | 1H | 3 hits | Spin |
| Emberfang | Swords | Primary | **Epic** | 1H | 3 hits (Sword moves) | Spin |
| Rapier | Swords | Primary | Common | 1H | 3 thrusts | Flurry |
| Dual Blade | Swords | Primary | Common | dual | 4 cuts | Rush |
| Greatsword | Swords | Primary | Common | 2H | 3 sweeps | Charged slam |
| Axe | Axes | Primary | Common | 1H | 3 chops | Leaping cleave + bleed |
| Mace | Blunt | Primary | Common | 1H | 3 hits (stun finisher) | Quake |
| Hammer | Blunt | Primary | Common | 2H | 3 blows | Quake (bigger) |
| Spear | Polearms | Primary | Common | 2H | 3 thrusts | Piercing lunge |
| Scythe | Polearms | Primary | Common | 2H | 3 reaps | Hook & cut |
| Bow | Ranged | Ranged | Common | — | draw & release | — |
| Crossbow | Ranged | Ranged | Common | — | single bolt + reload | — |
| Blunderbuss | Ranged | Ranged | Common | 1H | 3-shot clip of pellets | — |
| Staff | Magic | Magic | Common | — | elemental missiles | charged blast |
| Grimoire | Magic | Magic | Common | left hand | undead hands / healing | charged spell |

Hotbar holds one weapon per slot (Primary, Magic, Ranged) plus 2 potion slots.

### 4.2 Melee at a glance
"Combo total" is the full combo's damage on one target; "combo time" is the sum of the swing
cooldowns (a rough lower bound; hit delays and the combo window add a little).

| Weapon | Combo dmg | Combo total | Combo time | ~DPS ceiling | Stamina/swing | Hitbox | Block | Parry | Walk speed |
|---|---|---|---|---|---|---|---|---|---|
| Sword | 20 / 25 / 40 | 85 | 1.2 s | ~71 | 8 | box 6×6×6 | 20 | 0.25 s | normal |
| Emberfang | 26 / 32 / 52 | 110 | 1.2 s | ~92 | 7 | box 6.5×6×6 | 25 | 0.25 s | normal |
| Rapier | 14 / 16 / 28 | 58 | 1.07 s | ~54 | 6 | box 8.5 deep × 3 wide | 14 | **0.28 s** | normal |
| Dual Blade | 12 / 12 / 15 / 26 | 65 | 1.09 s | ~60 | 5 | box 5.5×6.5×6 | 12 | 0.27 s | normal |
| Greatsword | 25 / 30 / 45 | 100 | 2.2 s | ~45 (AoE) | 14 | sweeps r10–11 | **35** | 0.12 s | 12 (6 swinging) |
| Axe | 22 / 26 / 42 | 90 | 1.55 s | ~58 | 10 | box 6.5×6×6 | 22 | 0.20 s | normal |
| Mace | 25 / 30 / 55 | 110 | 1.55 s | ~71 | 12 | box 6×7×6 | 25 | 0.18 s | normal |
| Hammer | 30 / 34 / 55 | 119 | 2.4 s | ~50 (AoE) | 14 | sweeps r8–10 | **35** | 0.12 s | 12 |
| Spear | 18 / 20 / 32 | 70 | 1.3 s | ~54 | 7 | box **11 deep** × 3.5 wide | 10 | **0.30 s** | normal |
| Scythe | 18 / 20 / 34 | 72 | 1.67 s | ~43 (AoE) | 8 | sweeps r9–10 | 14 | 0.20 s | normal |

Combo window (time to click again before the combo resets): 0.8 s (Dual Blade 0.7 s).

### 4.3 Melee weapons in detail

#### Sword — fast, balanced
- **Combo**: 20 → 25 → 40 (cooldowns 0.3 / 0.3 / 0.6).
- **Heavy — Spin**: hold to spin, hitting everything within 8 studs every 0.5 s for up to 3 s.
  15 dmg and 6 stamina per hit (max 6 hits = 90 dmg / 36 stamina). Walk 8 while spinning, 0.6 s recovery.
- **Guard**: absorbs 20, parry 0.25 s. Can use a shield.

#### Emberfang (Epic) — the Sword, stronger
- Sword's moves and animations, ~30% harder: **26 → 32 → 52**, 7 stamina/swing, reach 6.5, ember trail.
- **Spin**: 20 per hit, radius 8.5 (max 120 dmg).
- **Guard**: absorbs 25, parry 0.25 s. Shield-capable. Shares the **Sword skill tree**.

#### Rapier — duelist's thrusts, timing reward
- **Combo**: 14 → 16 → 28; the 3rd lunges forward (32 studs/s) and knocks back (12). Long narrow line (8.5 × 3).
- **Heavy — Flurry**: hold up to 1.1 s; releases **3–8 stabs** by charge (+Finesse/Thousand Cuts), 9 dmg each,
  0.09 s apart on a 9-stud line, creeping forward; last stab knocks back (20). 22 stamina. Max 72 dmg base.
- **Guard**: absorbs 14, **best sword parry 0.28 s**. Shield-capable.

#### Dual Blade — light and fast, gets in close
- **Combo (4 cuts)**: 12 (R) → 12 (L) → 15 (spinning R) → 26 (crossing double cut, lunges 24 & knocks back 15).
- **Heavy — Rush**: gather 0.6 s, then rush at 24 studs/s in your walking direction, slashing everything within
  7 studs every 0.3 s for up to 3 s. 10 dmg and 5 stamina per hit (max 10 hits = 100 dmg / 50 stamina). Releasing before the rush cancels it.
- **Guard**: absorbs 12, parry 0.27 s.

#### Greatsword — slow, huge damage, charged slam
- **Combo** (wide sweeps): 25 (r10, 200°) → 30 (r10, 200°) → 45 (r11, **360°**, knockback 30). 14 stamina per swing.
- **Heavy — Charged slam**: hold to charge (feet planted), 25 stamina to start. Charge levels:

  | Held | Damage | Knockback |
  |---|---|---|
  | 0 s | 35 | — |
  | 0.5 s | 55 | — |
  | 1.0 s | 80 | 35 |
  | 1.6 s | **120** | 60 |

  Hitbox 10 deep × 9 wide, 0.9 s recovery.
- **Guard**: absorbs 35 (sturdiest), parry 0.12 s (hardest). Walk speed 12 while equipped.

#### Axe — aggressive, bleed
- **Combo**: 22 → 26 → 42 (3rd knocks back 25). 10 stamina/swing.
- **Heavy — Leaping cleave**: hold up to 1 s; leap 3–9 studs and chop a 6-wide box for **30–60**, knockback 15,
  then **bleed 5 every 0.5 s for 3 s (+30)**. 22 stamina. Bleed +1/tick per Deep Cuts rank, +3 Butcher.
- **Guard**: absorbs 22, parry 0.20 s. Shield-capable.

#### Mace — stuns
- **Combo** (sword animations at 0.8× speed): 25 → 30 → 55; finisher knocks back 30 and **stuns 1.5 s**. 12 stamina/swing.
- **Heavy — Quake**: hold to raise (ring shows reach), release to smash: **30–70 dmg, radius 5–10**, knockback 25.
  Full charge 1.2 s, auto-smash at 2.5 s. 25 stamina, 1 s recovery.
- **Guard**: absorbs 25, parry 0.18 s. Shield-capable.

#### Hammer — heaviest, crushing AoE
- **Combo**: Pound 30 (r8, 110°, KB 15, shockwave) → Swing 34 (r9.5, 220°, KB 25) → Crush 55 (r10, 150°, KB 45, lunge, shockwave). 14 stamina/blow.
- **Heavy — Quake**: full charge 1.5 s (auto at 3 s): **45–110 dmg, radius 7–14**, knockback 40–80 for 0.35 s
  (throws enemies 3–6× as far as the Mace). 30 stamina, 1.3 s recovery.
- **Guard**: absorbs 35, parry 0.12 s. Walk speed 12 while equipped.

#### Spear — reach
- **Combo**: 18 → 20 → 32 (3rd lunges 40 studs/s, knockback 18). Box **11 deep** × 3.5 wide: aim the point. 7 stamina.
- **Heavy — Piercing lunge**: hold up to 1 s; lunge **4–14 studs** plus 8 studs reach, **25–55 dmg**, knockback 20. 20 stamina.
- **Guard**: weakest, absorbs 10; **easiest parry 0.30 s**. Reach is its defense.

#### Scythe — wide reaps, hook & drag
- **Combo** (all sweeps): 18 (r9, 200°) → 20 (r9, **360°**) → 34 (r10, 160°, lunge 20, KB 18). 8 stamina.
- **Heavy — Reap** (one press, no charge, 22 stamina): hook reaches **12 studs** ahead, every enemy caught takes 8,
  is held and dragged to 4 studs in front over 0.3 s; at 0.78 s cut all around (r8, 220°) for **40** and knockback 32.
  Whole move 1.15 s; walk speed 2 during it.
- **Guard**: absorbs 14, parry 0.20 s.

### 4.4 Ranged weapons

| | Bow | Crossbow | Blunderbuss |
|---|---|---|---|
| Damage | 10–40 (by draw) | 55 per bolt | 10 × 8 pellets (80 max) |
| Projectile speed | 90–200 (by draw) | 230 | 180 |
| Fire mechanic | Hold right-click to draw (1 s to full) | Left-click fires; reload after every shot | 3-shot clip, 0.5 s apart, then reload |
| Cooldown / reload | 0.3 s between shots | 1.3 s reload | 1.8 s reload |
| Stamina per shot | 6 | 8 | 10 |
| Ammo | 30 arrows | 20 bolts | 12 shells |
| Drop (gravity) | 40 | 25 (flatter) | 0 (straight) |
| Max range | 300 | 350 | 50 (no damage past **35**) |
| Spread | — | — | 7° |
| Aim zoom (FOV) | 50 at full draw | 45 | 55 |
| Walk speed | 8 drawing | 8 aiming, 10 reloading | 9 aiming, 10 reloading |

Ammo refills in the hub and the training grounds. Ranged weapons have no block.

### 4.5 Casters

Tap to fire a missile (at aim or lock-on target); hold to charge a heavy spell. R switches element.
**Spells spend mana, not stamina.** The class must be unlocked in the skill tree before the weapon
can cast at all, and each element separately.

| | Staff | Grimoire |
|---|---|---|
| Class (skill tree root) | Mage | Occultist |
| Light cast | 15 mana, 0.45 s cooldown | 14 mana, 0.45 s cooldown |
| Charge | 40 mana, full in 1.4 s, auto at 3 s | 40 mana, full in 1.3 s, auto at 3 s |
| Recovery after a blast | 0.8 s | 0.8 s |
| Missile range | 140 studs | 140 studs |
| Guard | absorbs 12, parry 0.22 s | absorbs 10, parry 0.22 s |

**Staff elements**

| Element | Light missile | Heavy (by charge) |
|---|---|---|
| Fire | 14 dmg, fast | **Fire Wave**: wall of fire rolls 28 studs (9 wide), 25–55 + **burn** 4/0.5 s for 3 s |
| Water | 12 dmg + **slow** ×0.6 for 2 s | **Water Blast**: torrent 26 long × 7 wide, 25–55, knockback 40 |
| Earth | 18 dmg, slow & heavy, knockback 15 | **Boulder**: thrown in an arc, crashes r8, **40–90**, knockback 25, **stun 0.6 s** |
| Electric | 10 dmg, fastest, **chains** to 2 more (60%) | **Thunder**: strikes aim point (≤70 studs) after 0.35 s, r10, 30–65, **slow** ×0.5 for 3 s |

**Grimoire schools**

| School | Light missile | Heavy (by charge) |
|---|---|---|
| Necromancy | Undead hand, 15 dmg, slow (35 studs/s), big | **Homing**: 2–3 hands (+1/rank Horde) seek your lock-on target or the nearest enemy (≤70 studs), 18–32 each |
| Faith | Heals the ally it hits for 12 (6 to enemies) | **Heal Burst**: heals you and every player within 15 studs for 10–30 |

---

## 5. Shields

Off-hand gear in its own backpack slot (optional, saved). Works **only with one-handed weapons**:
Sword, Emberfang, Mace, Axe, Rapier. With one of those out it's on your left forearm and adds to
every block; otherwise it's slung on your back and does nothing.

| Shield | Rarity | Set | Block bonus | Extra charges |
|---|---|---|---|---|
| Warden Shield | Uncommon | Mace (Warden) | +15 per block | +1 (4 total) |

*Placeholder numbers.* Example: Mace + Warden Shield blocks 25 + 15 = **40** per block, with 4 charges.

---

## 6. Armor

### 6.1 How it works
- **5 slots**: Helmet, Chestplate, Armwear, Leggings, Boots. Mix and match freely across sets.
- Each piece negates a **% of incoming damage**; pieces add up, **capped at 80%**.
- Armor applies **after** blocking (it reduces what gets through a block).
- Example: a 0.12 chestplate turns a 50-damage hit into 44.
- Everyone has the same blocky R15 body so armor fits all players; a helmet hides hats, hair and face accessories.
- Manage it in the backpack (G).

### 6.2 Sets

| Set | Rarity | Starter for | Helmet | Chest | Armwear | Leggings | Boots | **Full set** | Material |
|---|---|---|---|---|---|---|---|---|---|
| Iron | Common | — | 6% | 12% | 5% | 8% | 4% | **35%** | Metal |
| Vanguard* | Uncommon | Hammer | 4% | 9% | 4% | 6% | 3% | **26%** | Metal |
| Warden* | Uncommon | Mace | 5% | 9% | 3% | 5% | 3% | **25%** | Fabric |
| Warhide | Uncommon | Greatsword | 4% | 9% | 3% | 5% | 3% | **24%** | Fabric |
| Woodcutter* | Uncommon | Axe | 4% | 8% | 3% | 4% | 3% | **22%** | Fabric |
| Skirmisher* | Uncommon | Spear | 4% | 7% | 3% | 4% | 3% | **21%** | Fabric |
| Leather | Uncommon | Sword | 4% | 7% | 3% | 4% | 2% | **20%** | Fabric |
| Prowler* | Uncommon | Dual Blade | 3% | 7% | 3% | 4% | 2% | **19%** | Fabric |
| Duelist* | Uncommon | Rapier | 3% | 7% | 3% | 3% | 2% | **18%** | Fabric |
| Reaper* | Uncommon | Scythe | 3% | 7% | 3% | 3% | 2% | **18%** | Fabric |
| Apprentice* | Uncommon | Staff | 3% | 6% | 2% | 3% | 2% | **16%** | Fabric |

\* placeholder numbers, to tune.

The design idea: heavier, slower weapons get thicker armor (they can't dodge as much); light,
mobile or ranged weapons get lighter armor. The Bow, Crossbow, Blunderbuss and shields have no set
of their own; the Grimoire is planned to share the Staff's Apprentice set. "Starter" is a label
for now (sets aren't handed out automatically except through the class pick).

### 6.3 Starting classes (Hall of Oaths)
| Class | Weapon | Armor |
|---|---|---|
| Swordsman | Sword | Leather |
| Fencer | Rapier | Duelist |
| Stalker | Dual Blade | Prowler |
| Berserker | Greatsword | Warhide |
| Ravager | Axe | Woodcutter |
| Sentinel | Mace | Warden |
| Juggernaut | Hammer | Vanguard |
| Lancer | Spear | Skirmisher |
| Revenant | Scythe | Reaper |
| Mage | Staff | Apprentice |

### 6.4 Rarity tiers
Common → Uncommon → Rare → Epic → Legendary. Each weapon has a fixed rarity for now.

---

## 7. Buffs

| Buff | Source | Effect | Duration |
|---|---|---|---|
| Bonnie's Grace | Petting Bonnie, the inn's cat | 10% damage negation (× 0.9, after armor and block) | 300 s |

Buffs don't stack (getting one again restarts it), are kept through death, and are lost on leaving.

---

## 8. Skill trees

Skill points are one shared pool across every tree, so nobody can max everything.

### 8.1 General tree (rival branches)
Putting **any** point in a branch hard-locks its rival until respec. Tiers need 0 / 3 / 5 points
already in that branch.

| Branch | Rival | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| **Mobility** | Guard | Fleet Foot: dash recharge −8% (×3) | Extra Dash: +1 charge | Ghost Step: +0.05 s i-frames (×2) |
| **Guard** | Mobility | Bulwark: +5 block (×3) | Extra Guard: +1 block charge | Riposte: +0.03 s parry (×2) |
| **Vitality** | Might | Toughness: +15 HP (×5) | Recovery: +3 HP/s regen (×2) | Juggernaut: +40 HP |
| **Might** | Vitality | Power: +4% damage (×5) | Brutality: +5% damage (×2) | Executioner: +8% damage |
| **Endurance** | Arcana | Deep Lungs: +10 stamina (×5) | Second Breath: +5 stamina/s (×3) | — |
| **Arcana** | Endurance | Wellspring: +15 mana (×5) | Flow: +2 mana/s (×3) | Archmage: +40 mana |

Maxed: Might = +34% damage with every weapon; Vitality = +115 HP and +6 HP/s regen.

### 8.2 Weapon trees (melee & ranged)
Tiers need 0 / 3 / 7 / 10 points in that tree. Every tree shares this shape:

| Tier | Node | Effect |
|---|---|---|
| 1 | Sharpness (×5) | +5% damage per rank |
| 2 | Efficiency (×3) | −6% stamina cost per rank |
| 2 | *Signature* (×3) | weapon-specific (below) |
| 3 | Heavy Training (×3) + Guardcraft (×2) | +8% heavy dmg / +4 block, +0.02 s parry (ranged: one damage node instead) |
| 4 | *Mastery fork* | pick **one** of two |

| Weapon | Signature (per rank) | Mastery A | Mastery B |
|---|---|---|---|
| Sword | Whirlwind: spin +0.5 s | Blademaster: +15% combo dmg, −20% combo stamina | Cyclone: +20% spin dmg, +1 s spin |
| Greatsword | Swift Charge: charge levels 10% sooner | Executioner: +25% slam dmg, 15% faster charge | Sweeper: +20% sweep dmg, −20% sweep stamina |
| Mace | Aftershock: quake +10% radius | Crusher: +20% quake dmg, +20% radius | Brawler: +15% combo dmg, −20% combo stamina |
| Hammer | Earthshaker: slam +10% radius | Bonecrusher: +15% combo dmg, −20% combo stamina | Cataclysm: +20% slam dmg, +20% radius |
| Spear | Long Lunge: +15% lunge distance | Phalanx: +10 block, +0.05 s parry | Skewer: +20% lunge dmg, +25% distance |
| Scythe | Grim Reach: hook +10% reach | Harvester: +15% combo dmg, −20% combo stamina | Death's Grasp: +20% hook-and-cut dmg, +20% reach |
| Rapier | Finesse: +1 flurry stab | Duelist: +15% thrust dmg, −20% thrust stamina | Thousand Cuts: +2 stabs, +15% flurry dmg |
| Dual Blade | Relentless: rush +0.5 s | Twin Fangs: +15% combo dmg, −20% combo stamina | Bladestorm: +20% rush dmg, +1 s rush |
| Axe | Deep Cuts: bleed +1/tick | Butcher: bleed +3/tick | Berserker: +15% combo dmg, +10% cleave dmg |
| Bow | Quick Draw: full draw 10% sooner | Deadeye: +20% arrow dmg | Rapid Fire: full draw 25% sooner |
| Crossbow | Steady Hands: reload 8% faster | Piercer: +20% bolt dmg | Quickload: reload 25% faster |
| Blunderbuss | Quick Powder: reload 8% faster | Point Blank: +20% pellet dmg | Long Barrel: pellets do damage 30% further |

Emberfang uses the Sword tree.

### 8.3 Caster trees (Staff = Mage, Grimoire = Occultist)
Unlock the class first (until then the weapon only blocks), then each element's branch:

| Branch | Unlock | Upgrade (×3) | Special (×2) |
|---|---|---|---|
| Pyromancy (Fire) | Fire | Inferno: +10% Fire dmg | Scorch: burn +1/tick |
| Hydromancy (Water) | Water | Torrent: +10% Water dmg | Undertow: +25% knockback |
| Geomancy (Earth) | Earth | Bedrock: +10% Earth dmg | Tremor: boulder stun +0.2 s |
| Electromancy | Lightning | Storm: +10% Lightning dmg | Overload: thunder +15% radius |
| Necromancy | Necromancy | Grave Strength: +10% dmg | Horde: +1 homing hand |
| Faith | Faith | Devotion: +10% healing | Sanctuary: burst +15% radius |
| Arcane (both) | — | Efficiency: −6% mana → Overcharge: 12% faster charge → Spellweaver: +8% heavy spell dmg (each ×3) | |

---

## 9. Enemies (current)

| Enemy | Level | HP | Damage | Wind-up | Cooldown | Range | XP | Coins |
|---|---|---|---|---|---|---|---|---|
| Orc | 3 | 200 | 30 | 0.4 s | 1.5 s | 5 | 15 | 5 |
| Lesser Demon *(disabled: model not rigged)* | 8 | 600 | 45 | 0.4 s | 1.8 s | 6.5 | 60 | 25 |

**Orc packs**: 14 packs of 4–6 roaming the whole map (never within 60 studs of the safe zone).
Any member seeing you (45 studs) or being hit turns the whole pack; the 3 closest attack while the
rest circle at 11 studs; leash at 130 studs from camp (they walk home and heal); a wiped pack
re-forms at a new camp after 30 s.

Enemy attacks have a readable wind-up before the damage frame — that wind-up is your parry/dash cue.
Stunning an enemy cancels its wind-up.

**Wildlife** (Cows 120 HP / 5 XP, Chickens 30 HP / 2 XP) never fight back; they flee and drop meat.

---

## 10. Quick comparisons

**Easiest → hardest to parry with:** Spear 0.30 · Rapier 0.28 · Dual Blade 0.27 · Sword/Emberfang 0.25 ·
Staff/Grimoire 0.22 · Axe/Scythe 0.20 · Mace 0.18 · Greatsword/Hammer 0.12

**Sturdiest → weakest block:** Greatsword/Hammer 35 · Mace/Emberfang 25 · Axe 22 · Sword 20 ·
Rapier/Scythe 14 · Dual Blade/Staff 12 · Spear/Grimoire 10 (one-handers +15 with the Warden Shield)

**Biggest single hits:** Greatsword full slam 120 · Hammer full quake 110 · Earth boulder 90 ·
Crossbow bolt 55 + (×1.2 Piercer) · Hammer crush / Mace finisher 55

**Best crowd control:** Hammer (huge knockback quake) · Scythe (hook + 360° spin) · Mace (1.5 s stun) ·
Greatsword (360° finisher) · Staff Thunder/Water (slow)
