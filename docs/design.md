# Slayer Revo — Game Design Direction

> Source of truth for game direction. Read this before building any system.
> If a request conflicts with this doc, flag it before coding.
> Items marked **[TBD]** are undecided — ask before assuming.
> **Already-built systems take precedence where they differ from this doc** — see §12.

---

## 1. Vision

**Slayer Revo** is an open-world action RPG on Roblox, inspired by **Monster Hunter** (weapon-driven combat, hunting, gear from drops) and **Sword Art Online** (zone/floor progression, bosses as gates, guilds and parties).

Players progress through themed areas, each harder than the last, defeating monsters and bosses for XP and drops, building gear and skills to fit their playstyle, and hunting together with parties and guilds.

### Design pillars
1. **Combat skill matters** — timing (dodge, parry, block) beats stat-checking.
2. **Build freedom** — mix and match weapons, armor and skills; no single "correct" build.
3. **Hard but fair progression** — challenging enough to be rewarding, never a wall that makes players quit.
4. **Hunting is better together** — solo is viable, groups are faster and more fun.
5. **Every area feels distinct** — own aesthetic, atmosphere, monsters and drops.

---

## 2. Core Loop

```
Enter area → Hunt monsters → Earn XP + drops → Upgrade gear / skill tree
     ↑                                                      ↓
Unlock next area ← Defeat area bosses ← Get stronger ←──────┘
```

Session loop: log in → join party/guild → hunt a target (monster, boss, drop) → upgrade → log out with visible progress.

---

## 3. Combat

### Status
| System | Status |
|---|---|
| Dash | ✅ Built |
| Light attacks | ✅ Built |
| Heavy attacks | ✅ Built |
| Stamina | ✅ Built |
| Blocking | ✅ Built |
| Parrying | ✅ Built |
| Dash i-frames | ✅ Built |
| Hit feedback (hitstop, enemy flinch, hit FX/SFX) | ✅ Built |
| Remote validation + rate limiting | ✅ Built |

### Rules
- **Server-authoritative**: hit detection, damage, health, stamina spending validated on server.
- **Client**: input, animations, VFX, SFX, camera only.
- **Stamina** gates dash, heavy attacks, blocking. Regenerates when not spending. *(As built: see §12.)*
- **Block** reduces damage, drains stamina per hit; guard break when stamina hits 0. *(As built: see §12.)*
- **Parry** = short timing window at block start; success staggers attacker / opens punish window. Some boss attacks are unparryable (telegraphed clearly).
- **I-frames** on dash.
- Enemy attacks must be readable: wind-up telegraphs before damage frames.

### Weapons
Current: **One-Handed Sword, Greatsword, Mace, Spear, Axe, Bow, Staff.** More will be added — the weapon system must be **data-driven** so a new weapon = new config + animations, not new core code.

| Weapon | Identity (direction) |
|---|---|
| One-Handed Sword | Fast, balanced, good parry window |
| Greatsword | Slow, huge damage, charged heavies |
| Mace | Stagger/stun buildup, breaks guard |
| Spear | Reach, pokes, strong blocking |
| Axe | Aggressive, high damage, bleed-style |
| Bow | Ranged, weak up close, relies on dash positioning |
| Staff | Caster: five elements (Fire burn, Water slow, Earth knockback/stun, Electric chain, Faith heals allies); tap for missiles, hold to charge a blast |

Each weapon has: base stats, light combo, heavy attack, stamina costs, block/parry properties, and weapon-specific skill tree branch.

**Shields** are optional off-hand gear for the one-handed weapons (Sword, Emberfang, Mace, Axe, Rapier): a stronger guard (see §12).

---

## 4. Progression

### Player level
- XP from defeating enemies and bosses. Bosses give large XP chunks.
- Level gates area access (soft or hard gate **[TBD]**).
- Curve: early levels fast (hook players), mid-game steady, late-game slow but always visible progress.

### Skill tree
- Skill points earned per level.
- **General branch**: stats (HP, stamina, damage, defense, stamina regen).
- **Weapon branches**: one per weapon type — unlock new moves, combo extensions, weapon-specific bonuses.
- Respec allowed so experimenting with builds isn't punished: **free for now** (a cost can come once there's currency).
- **Rival branches**: General branches come in rival pairs (Mobility ↔ Guard, Vitality ↔ Might, Endurance ↔ Arcana); any point in one **hard-locks** its rival until respec.
- **Mana**: the staff's spells spend mana (its own bar), not stamina; the Arcana branch grows it, as the rival of stamina's Endurance.
- **Mage class**: the staff's tree is the Mage class. The staff can't cast until Mage is unlocked, and each element (Fire, Water, Earth, Lightning, Faith) is its own branch that must be unlocked before it can be used, with upgrades beyond.
- Skill points are **one pool shared by every tree** (General + every weapon), so no one can max everything.
- Each weapon tree ends in a **mastery fork**: two options, taking one locks the other.

### Gear
- **Armor slots**: Helmet, Chestplate, Armwear, Leggings, Boots *(as built)*.
- **Mix and match**: any armor with any weapon.
- **Rarity tiers**: Common → Uncommon → Rare → Epic → Legendary *(confirmed; see §12)*.
- **Armor sets** from the same area/boss give set bonuses (optional, so mixing is still viable).
- Gear sources: drops (monsters/bosses) and crafting from materials **[TBD — is there crafting?]**.

### Difficulty target
- A player should defeat each new area's first boss after a reasonable grind, not instantly and not after days of repetition.
- Skill should be able to beat moderate gear/level gaps.

---

## 5. World

### Structure
- Open world split into **areas** (zones), unlocked in order as players level up.
- Each area has: theme/aesthetic, level range, regular monsters, **a few bosses**, unique drops (materials + gear).
- A **hub town** for social, upgrades, party/guild management **[confirm]**.

### Area template (per area)
```
Name:
Level range:
Aesthetic / atmosphere:   (lighting, terrain, music, weather)
Regular monsters:          (3–5 types)
Bosses:                    (2–3, one final area boss gates the next area)
Unique drops:              (materials, weapon/armor set)
Unlock requirement:
```

### Example progression (placeholder — rename freely)
| # | Area | Theme | Levels |
|---|---|---|---|
| 1 | Starter forest | Green, calm, daylight | 1–10 |
| 2 | Highlands / plains | Open, windy | 10–20 |
| 3 | Swamp | Fog, toxic, dark | 20–30 |
| 4 | Volcanic region | Fire, red lighting, hazards | 30–40 |
| 5 | Frozen peaks | Snow, blizzard visibility | 40–50 |
| … | More areas later | | |

---

## 6. Enemies & Bosses

- **Regular monsters**: simple AI state machine (idle → patrol → aggro → attack → stagger → death). 2–4 attacks each.
- **Bosses**: multiple phases, telegraphed attack patterns, enrage at low HP, larger arenas.
- All enemies defined by **config** (HP, damage, defense, XP, drop table, attacks, level) so new monsters are mostly data + model + animations.
- Difficulty scales by area: more HP/damage, faster or more complex attack patterns, fewer safe punish windows.
- Group scaling: enemy HP scales with party size **[TBD]**.

### Drops
- Every enemy has a **drop table**: item, chance, quantity.
- Bosses: guaranteed drops + rare chance drops.
- Drop distribution in parties: individual loot per player (no loot fighting) *(confirmed; see §12)*.

---

## 7. Social

- **Party**: small group (size **[TBD]**, e.g. 4) for hunting together. Shared XP when nearby.
- **Guild**: persistent group with name, members, ranks (leader/officer/member). Guild features **[TBD]** (guild bank, guild level, guild hall).
- Friendly fire: off.

---

## 8. Technical Architecture

### Stack
- Luau with `--!strict`, synced via **Rojo**.
- `src/server` → ServerScriptService
- `src/client` → StarterPlayerScripts
- `src/shared` → ReplicatedStorage

### Principles
- **Data-driven**: weapons, armor, enemies, bosses, areas, drop tables, skill trees, XP curve live in config ModuleScripts under `src/shared/Config/`. Balance changes should not touch logic.
- **Server-authoritative** for anything that affects progression or combat outcomes. Never trust the client for damage, drops, XP or inventory.
- **ModuleScript systems**, one responsibility each (CombatService, StaminaService, EnemyService, LootService, InventoryService, ProgressionService, PartyService, GuildService, DataService).
- **RemoteEvents** in `ReplicatedStorage/Remotes`, clearly named, validated + rate-limited on server.
- **Persistence**: DataStore via a session-locking pattern (e.g. ProfileStore); save level, XP, skill points, inventory, equipped gear, unlocked areas, guild ID.

### Suggested folders
```
src/
  server/
    Services/      (combat, enemies, loot, progression, data, party, guild)
  client/
    Controllers/   (input, camera, combat FX, UI)
    UI/
  shared/
    Config/        (Weapons, Armor, Enemies, Bosses, Areas, DropTables, SkillTree, XPCurve)
    Types/
    Util/
docs/
  design.md        (this file)
```

---

## 9. Roadmap

| Phase | Goal | Contents |
|---|---|---|
| **1. Combat core** | Fighting feels good | ✅ dash (+ i-frames), light/heavy, 6 weapons, stamina, block, parry, hit feedback polish — **built, awaiting playtest** |
| **2. Skill tree** | Build identity | General tree with rival branches + one tree per weapon, free respec; brings forward XP/levels and DataStore saving — **built, awaiting playtest** |
| **3. First enemy** | Something worth fighting | Enemy AI state machine, 1 monster, 1 boss, test arena |
| **4. Progression core** | Reason to keep fighting | Drops, loot, equip from drops (XP/levels, inventory, saving already built) |
| **5. Area 1 vertical slice** | One complete area | Full area build, 3–5 monsters, 2–3 bosses, unique drops, area unlock |
| **6. Social** | Hunting together | Parties, then guilds |
| **7. Expansion** | Content | More areas, weapons, bosses, armor sets |

**Rule: finish and playtest each phase before starting the next.**

---

## 10. Open Questions [TBD]

- Crafting / upgrading gear from materials, or drops only?
- Currency and shops?
- Soft vs hard level gates for areas?
- Party size limit? Enemy scaling in parties?
- Guild features beyond membership?
- Death penalty (lose XP? drop items? just respawn)?
- PvP — ever, or PvE only?
- Monetization (gamepasses, cosmetics) — must not be pay-to-win **[confirm]**.

---

## 11. Instructions for Claude Code

- Read this doc and `CLAUDE.md` before starting a feature.
- Work **one system at a time**; propose a plan before large features.
- Put all tunable numbers in `src/shared/Config/`, never hardcoded in logic.
- When adding a weapon/enemy/area, follow the existing config pattern.
- Do not resolve **[TBD]** items yourself — ask.
- After finishing a feature, summarize what changed and how to test it in Studio.

---

## 12. Decisions: built systems win (2026-10-12)

Where the game was already built differently from this doc, **the built version stays**.
Everything in the doc that isn't built yet still applies.

| Topic | Doc said | As built (keep) |
|---|---|---|
| Dash cost | Spends stamina | 2 dash charges, each refills in 5 s; no stamina |
| Block cost | Drains stamina per hit; guard break at 0 stamina | 3 block charges, each refills in 5 s; a block absorbs the weapon's BlockAmount, the rest gets through |
| Light attacks | (no stamina cost mentioned) | Cost stamina per swing |
| Sword vs Spear parry | Sword: good parry window | Spear 0.30 s (easiest), Sword 0.25 s, Axe 0.20 s, Mace 0.18 s, Greatsword 0.12 s |
| Spear block | Strong blocking | Weakest block (absorbs 10); reach is its defense |
| Mace | Stun buildup, breaks guard | Stun on the 3rd combo hit; ground-pound heavy (no stun) |
| Axe | Bleed [TBD] | Bleed on the leaping-cleave heavy |
| Rapier | (not in doc) | Thrusting sword (Swords class, Common): 3 quick stabs (the third a lunge), long narrow reach; heavy charges a flurry of 3–8 rapid stabs (more with charge), last one knocks back; best sword parry (0.28 s), light guard |
| Dual Blade | (not in doc) | Swords class, Common, own skill tree (signature Relentless: longer rush; masteries Twin Fangs / Bladestorm). One blade in each hand. Light and fast: a 4-cut combo (right, left, spinning right sweep, crossing double cut that lunges and knocks back). Heavy: hold to gather (0.6 s), then it rushes in the walking direction (straight on if not walking), spinning and slashing all around while held, paying stamina per hit (max 3 s). Light guard (absorbs 12), parry 0.27 s. Starter armor: Prowler |
| Scythe | (not in doc) | Polearms class (with the Spear), Common, own skill tree (signature Grim Reach: longer hook; masteries Harvester / Death's Grasp). Two-handed and long (8 studs, taller than its wielder). Light combo is all area sweeps: a 200° forehand reap, a full 360° spin, then an overhead crescent (160°) that steps in and knocks back. Heavy (one press, not charged; letting go doesn't stop it): reaches 12 studs ahead and hooks every enemy it catches (small damage, held still), drags them in to 4 studs in front, then cuts all around (220°) and knocks them away. Guard absorbs 14, parry 0.2 s. Starter armor: Reaper |
| Hammer | (not in doc) | Blunt class (with the Mace), Common, own skill tree (signature Earthshaker: wider slam; masteries Bonecrusher / Cataclysm). A huge two-handed warhammer, heavy like the Greatsword: walk speed 12 while it's out. Light combo: an overhead pound into the ground in front (110°, dust shockwave), a wide sweep (220°), then a stepping crush (150°) that pounds the ground and knocks back hard. Heavy: hold to raise it high (a ring shows the reach, 7–14 studs by charge), release to slam the ground: 45–110 damage and a knockback that grows with the charge, throwing enemies far further than the Mace's. Guard absorbs 35, parry 0.12 s (like the Greatsword). Starter armor: Vanguard |
| Crossbow | (not in doc) | Ranged class (with the Bow), Common, own skill tree (signature Steady Hands: faster reload; masteries Piercer / Quickload). No draw: every bolt hits for 55 (the bow's full draw is 40) and flies faster and flatter, but it reloads after every shot (1.3 s, walking slower meanwhile; putting it away stops the reload). Hold right-click to aim (zoom, slow, face the aim, side-on stance); left-click fires, aiming or not. 20 bolts, refilled in the hub and training grounds. No armor set of its own |
| Blunderbuss | (not in doc) | Ranged class, Common, own skill tree (signature Quick Powder: faster reload; masteries Point Blank / Long Barrel). Works like the Crossbow (aim with right-click) but holds 3 shots, fired at least 0.5 s apart, then reloads (1.8 s); each shot is 8 pellets in a 7° spread, 10 damage each (80 if all hit). Pellets fly straight (no drop) and do no damage past 35 studs (Long Barrel: +30%). 12 shells, refilled in the hub and training grounds. Held one-handed like a big pistol (the left hand only joins in to reload: broken open, a shell thumbed in, flicked shut). No armor set of its own |
| Armor slots | Head, Chest, Arms, Legs | Helmet, Chestplate, Armwear, Leggings, Boots |
| Armor defense | Defense stat | Each piece negates a % of damage, summed, capped at 80% |
| Inventory | Phase 3 | Backpack plus a saved hotbar of one weapon per category: Primary (swords, axes, blunt, polearms), Magic (staff, grimoire), Ranged (bow, crossbow, blunderbuss), and 2 potion slots. Moving a weapon in swaps out the one in its category. The hotbar is an ornate bar at the bottom (Primary in the center ring), between the dash and block meters |
| Roadmap order | Skill tree was Phase 5 | Skill tree is Phase 2 (XP/levels and saving built with it) |
| Rarity | Tiers [confirm]; gear from drops | Five tiers confirmed. Each weapon has a fixed rarity for now (starter weapons Common). Emberfang (Epic): Sword moves, stronger stats, shares the Sword skill tree; everyone owns it until drops exist |
| Armor sets | (none named) | Iron (Common, 35% full set), Leather (Uncommon, 20%: the lowest protection tier; Sword starter) and Warhide (Uncommon, 24%; Greatsword starter), Woodcutter (Uncommon, 22% placeholder; Axe starter), Warden (Uncommon, 25% placeholder; Mace starter), Skirmisher (Uncommon, 21% placeholder; Spear starter), Apprentice (Uncommon, 16% placeholder; Staff starter), Duelist (Uncommon, 18% placeholder; Rapier starter), Prowler (Uncommon, 19% placeholder; Dual Blade starter), Reaper (Uncommon, 18% placeholder; Scythe starter), Vanguard (Uncommon, 26% placeholder; Hammer starter). A starter set per weapon; "starter" is only a label for now (shown in the Test Chest), not given out automatically. Every player has the same blocky R15 body (their face, skin colors, hats, hair and classic clothes kept; Rthro bodies, scaling and 3D clothing dropped), so armor fits everyone; a helmet hides hats, hair and face accessories |
| Shields | (not in doc) | Off-hand gear in its own backpack slot (optional, saved). Usable with the one-handed weapons only: Sword, Emberfang, Mace, Axe, Rapier. With one of those out it's held on the left forearm, and blocks absorb its bonus on top of the weapon's and give extra charges; otherwise it's slung on the back and does nothing. Blocking with it plays its own guard (ShieldGuard). Warden Shield (Uncommon, Mace set like the Warden armor; placeholder numbers): +15 absorbed per block, +1 block charge |
| Getting items | Drops | For testing: a Test Chest in the Training Grounds lists every item by category (weapon classes, Armor with the shields); weapons go to the hotbar, armor sets and shields are given and worn. Beside it, a row of armor stands (one per set, a mannequin wearing it and holding its weapon in one of that weapon's poses) gives and equips that set and weapon. A button in the sparring ring summons extra Orcs (up to 8 at once) that don't respawn. Not the final loot path |
| World around the hub | Areas unlocked by level | Beginning Town (fenced, 280 studs) inside the safe zone; forested hills on three sides with dirt paths, clearings, ruins and 12 treasure chests (scenery for now: loot [TBD]); a large open plain to the north as the hunting grounds (sized for mounts, planned), with a river and bridges; mountains along the map edge (whole mountains: they fall away again beyond it, where the terrain ends). Shape in Config/WorldConfig; terrain sculpted in edit mode (tools/generate_terrain.lua) and saved in the place; the town and the world's dressing (workspace.Town and workspace.World) are built from config by the same tools and saved in the place too, and the game plays with the saved copies, so hand edits in Studio stay (rerunning the tools replaces them) |
| New-player intro | (none) | A player who hasn't picked a starter sees a skippable, letterboxed cutscene flown over the real map (6 narrated shots: the Slayer Orders fell at the Great Arch a century ago, beasts roam the plains, Beginning Town keeps the last hall, a new slayer answers the call), a SLAYER REVO title card, then the Hall of Oaths: a floating temple high above the southern forest with a statue per starter class (mannequin in the set, holding the weapon, in the weapon's idle stance). A panel shows the class (name, the Order it's heir to, weapon + armor, lore, Damage/Speed/Reach/Defense/Difficulty bars, playstyle); crests pick it; confirm grants the weapon (drawn) and the armor set. Ten classes: Swordsman (Sword/Leather), Fencer (Rapier/Duelist), Stalker (Dual Blade/Prowler), Berserker (Greatsword/Warhide), Ravager (Axe/Woodcutter), Sentinel (Mace/Warden), Juggernaut (Hammer/Vanguard), Lancer (Spear/Skirmisher), Revenant (Scythe/Reaper), Mage (Staff/Apprentice). No starter class includes a shield. Text and shots in Config/IntroConfig. The guide's dialogue still offers the pick as a fallback |
| Training camp (tutorial) | (none) | Confirmed: right after the class pick a new player is put in Beginning Town's training yard and can't leave (walking off brings them back) until it's done; it can't be skipped, and there are no rewards. Drill Master Hode runs it: a short letterboxed cutscene (first time only), then one step at a time, each taught for the chosen weapon and finished only when the server sees it done: light hits and heavy attacks on a dummy, lock-on, dodging, blocking and parrying a sparring orc that swings with a slow, red-glowing wind-up, opening the skill tree and spending a point (casters do this first: they unlock the class and an element before they can cast), then beating two sparring orcs. Each player gets a roped sparring circle of their own (two, radius 11, between the yard's dummies and the pond; walled in by invisible walls while someone trains there, so dashes can't carry them out); sparring enemies fight only their owner (even in the safe zone), only they can hurt them, and they give nothing. The player can't drop below 1 health there, and dash charges refill in 0.3 s (TutorialConfig.DashRecharge). Progress is saved per step. Talking to Hode again runs the drills again any time with the weapon in hand (no cutscene; can be left). Text, positions and tuning in Config/TutorialConfig |
| Map | (none) | Minimap (top right, north up, place name under it) and a world map (M, or tap the minimap) drawn from a top-down capture of the world (assets/map/world.png, recaptured when the world changes); shows you, other players and place names |
| Enemy behaviour | State machine: idle → patrol → aggro → attack → stagger → death | Orcs live in packs of 4–6 (14 packs) roaming the whole map (forest and hunting grounds, short of the mountains; never within 60 studs of the safe zone) around camps; any member seeing (45 studs) or being hit by a player turns the whole pack; the 3 closest attack while the rest circle the target; leash 130 studs from camp (gives up, walks home, heals); a wiped pack re-forms at a new camp after 30 s. Stagger = existing flinch/stun. Tuning in EnemyConfig.Orc.Pack |
| Wildlife | (not in doc) | Non-hostile animals (Config/AnimalConfig): herds of Cows (2–4, 6 herds, 120 HP, 5 XP) and flocks of Chickens (3–5, 6 flocks, 30 HP, 2 XP) roam the whole map outside the safe zone, wandering round their homes. They never attack: one that's hit runs from the attacker (chickens zig-zag), and herd mates within 30 studs run too. No coins. On death the body tips over and fades, and a new one joins the herd later (60 s cows, 40 s chickens). Models are plain Parts made from all-box GLBs (tools/box_glb.py), rigged at spawn and animated on the client (legs, grazing/pecking head, flapping wings, tail) |
| Drops / loot | Individual loot per player [confirm] | Confirmed individual: a kill's drops are only for the killer (others don't see them). Drops float on the ground (pop out, bob, spin, glow) and are picked up by walking within 7 studs; uncollected loot vanishes after 120 s. Cows drop 1–2 Cow Meat, Chickens 1 Chicken Meat. Meat is a **material** (Config/MaterialConfig): saved counts shown in the backpack's Materials tab, cooked at the campfire (see Cooking) |
| Cooking | (not in doc) | Confirmed: the tavern-yard campfire has a pot on a tripod. Its Cook prompt crouches you by the fire (others see you cook and stir), zooms the camera in beside you, and opens a cooking panel in the backpack's style: pick a recipe (Cow Meat → Cooked Steak, heals 70 over 3 s; Chicken Meat → Roast Chicken, 35 over 2 s), how many (up to 20) and Cook; each piece takes 1.5 s and flies into you when done. Walking off, dying or closing the panel stops it and gives back unfinished meat raw (Config/CookingConfig). Food is a consumable (never sold): put it in a potion slot and eat it; only when hurt, one meal at a time |
| Hub town life | Hub for social, upgrades [confirm] | Beginning Town has a day/night cycle (a 20-minute day: 14 min of daylight, 6 of a not-too-dark night; Config/LightingConfig.DayCycle, same time for everyone), with lamps and windows lit after dark and a bell tolling at dawn and dusk. Villagers (Config/VillagerConfig) stroll set routes and say a line in a chat bubble when you walk up (no menus, can't be hurt). Tame chickens, cows and cats wander pens in town (AnimalConfig.TownPens; can't be hurt). Landmarks: a bell tower, two watchtowers at the arch, a windmill on the farm, plus bushes, planters, washing lines, flags and clutter (TownConfig.Decor). Swaying cloth, the turning windmill, chimney smoke, forge sparks, ambient birds/crickets/fire/anvil sounds, and little birds that fly off when you come close |
| Leaderboard | (not in doc) | Confirmed: a Hall of Hunters trophy board (orc heads on top) beside the Hunters' Guild lists the top 10 by level (XP breaks ties) across all servers, from an OrderedDataStore; it ranks the current server's players if the store can't be reached |
| Overhead bars | Enemy name and health bar | Small bars, few at once: the locked-on target shows its name, level and health; up to 3 others (the nearest hurt or close ones) show a bare bar. Wild animals show one only when hurt or locked on; nothing in town shows one |
| Controller / console | (not in doc) | Full controller support: R2/RT attack (hold for heavy), L2/LT block or aim, Circle/B dash, R3 lock-on, Cross/A jump, Square/X prompts, L1/R1 (LB/RB) cycle weapons, D-pad Up/Down potions, Triangle/Y staff element, touchpad/View backpack, D-pad Left map, D-pad Right skills. Menus are navigated with the D-pad (gold outline on the selection), Cross/A to pick, Circle/B to close; key hints show the controller's own button pictures. Aim goes to the screen centre. On consoles (TV) the HUD grows with the screen (about 1.7x at 1080p) and menus up to 1.6x |
