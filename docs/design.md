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
Current: **One-Handed Sword, Greatsword, Mace, Spear, Axe, Bow.** More will be added — the weapon system must be **data-driven** so a new weapon = new config + animations, not new core code.

| Weapon | Identity (direction) |
|---|---|
| One-Handed Sword | Fast, balanced, good parry window |
| Greatsword | Slow, huge damage, charged heavies |
| Mace | Stagger/stun buildup, breaks guard |
| Spear | Reach, pokes, strong blocking |
| Axe | Aggressive, high damage, bleed-style |
| Bow | Ranged, weak up close, relies on dash positioning |

Each weapon has: base stats, light combo, heavy attack, stamina costs, block/parry properties, and weapon-specific skill tree branch.

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
- **Rival branches**: General branches come in rival pairs (Mobility ↔ Guard, Vitality ↔ Might); any point in one **hard-locks** its rival until respec. Endurance has no rival.
- Skill points are **one pool shared by every tree** (General + every weapon), so no one can max everything.
- Each weapon tree ends in a **mastery fork**: two options, taking one locks the other.

### Gear
- **Armor slots**: Helmet, Chestplate, Armwear, Leggings, Boots *(as built)*.
- **Mix and match**: any armor with any weapon.
- **Rarity tiers**: Common → Uncommon → Rare → Epic → Legendary **[confirm]**.
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
- Drop distribution in parties: individual loot per player (no loot fighting) **[confirm]**.

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
| Armor slots | Head, Chest, Arms, Legs | Helmet, Chestplate, Armwear, Leggings, Boots |
| Armor defense | Defense stat | Each piece negates a % of damage, summed, capped at 80% |
| Inventory | Phase 3 | Backpack with a 5-weapon hotbar is built and saved |
| Roadmap order | Skill tree was Phase 5 | Skill tree is Phase 2 (XP/levels and saving built with it) |
