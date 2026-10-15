# Adding a new weapon from a delivered model

What to do once a friend (or Claude Design) hands over a weapon model, all the way to it being
usable in game. Model rules for the person making it are in `docs/model-brief.md`; this
covers what happens after.

There are two kinds of new weapon, and they cost very different amounts of work:

| Kind | Example | What's new | Work |
|---|---|---|---|
| **A. New item of an existing type** | Emberfang (moves like the Sword, hits harder) | Model, name, stats, rarity | Small: config only |
| **B. New weapon type** | Dagger (its own combo, heavy and guard) | Model, animations, moves, skill tree, tutorial | Large: a whole system |

Decide which one it is **before** starting (and for type B, read `docs/design.md` first, since
it's a new system: one at a time, and don't decide its [TBD] items without asking).

---

## 0. Before you start: check the file

Ask your friend for **one `.glb`** that follows the brief. Quick checklist:

- [ ] Named in PascalCase after the weapon: `Frostbite.glb`
- [ ] Length along **+Y**, handle at the bottom, tip at the top
- [ ] Thinnest side (blade thickness) along **Z**; one-edged blades have the edge toward **+X**
- [ ] Handle centered on X = 0, Z = 0
- [ ] Grip is its own material (`gripWrap`, `leather`, `wood`)
- [ ] Flat colors only, 3 to 8 named materials, no textures
- [ ] **Under 8,000 triangles** (hard limit 20,000)
- [ ] They told you: triangle count, size in studs (X, Y, Z), material names and colors

If it's wrong, it's much cheaper to send it back now than to fix it in Studio later.

---

## 1. Put the file in the repo

Copy it into:

```
assets/source/weapons/<Name>.glb
```

## 2. Check it

```sh
python3 -I tools/weapon_glb.py assets/source/weapons/<Name>.glb /dev/null --info
```

This prints its size per axis, its triangle count, and the color of each material. Write down
the **Y size** (its length) and **where the grip material starts and ends** along Y: you need
both for `ModelFit` in step 5.

Over 20,000 triangles? Shrink it first with `tools/decimate_glb.py` (headless Blender).

## 3. Bake the colors and set the pose

```sh
python3 -I tools/weapon_glb.py assets/source/weapons/<Name>.glb assets/source/weapons/<Name>.ready.glb
```

Studio would import flat-color models grey; this bakes the colors into a texture and puts the
model in the pose the game expects. **Don't** use `--turn-y 180` for weapons (Studio's import
already turns GLBs 180° around Y; use `FlipEdge` in config instead, step 5).

**Shields are different:** see `assets/shields/README.md` and `ShieldConfig.luau`.

## 4. Import it in Studio (you do this part)

1. Studio > File > **Import 3D** > pick `<Name>.ready.glb`. Keep the default settings.
2. Rename the imported Model to the weapon's exact name (its `ToolName`, e.g. `Frostbite`).
3. Right-click it > **Save to File** > `assets/weapons/<Name>.rbxmx`.
4. Delete the copy you imported into the place (the game loads it from
   `ServerStorage.WeaponModels`, which Rojo fills from `assets/weapons/`).

**If it doesn't show up:** Rojo often fails to sync new mesh models (the Dagger never appeared
in `ServerStorage.WeaponModels`, others came in as checkered boxes). Check that
`ServerStorage.WeaponModels.<Name>` exists and its MeshPart has a MeshId. If not, ask Claude
Code to rebuild it in Studio with `CreateMeshPartAsync` from the `.rbxmx`'s MeshId.

Add a row for it to the table in `assets/weapons/README.md`.

## 5. Fit it in the hand: `ModelFit`

In `src/shared/Config/CombatConfig.luau`, on the weapon's entry:

```lua
ModelFit = { Length = 5.4, GripFrom = 0.12 },
```

| Field | Meaning | Where it comes from |
|---|---|---|
| `Length` | Studs from handle end to tip; the model is scaled to this | Y size from `--info`, or the length you want in game |
| `GripFrom` | Where the hand holds it, as a fraction of Length from the handle end | Middle of the grip material along Y ÷ total length |
| `FlipBlade = true` | It came in held by the tip | Only if it looks wrong |
| `FlipEdge = true` | Turns it 180° around the handle | **Expect this for any one-edged blade** (axe, dual blade, scythe) |
| `Shift` | Moves the hand off the center line (fractions of Length, X and Z) | Off-center grips (bows). **Negate** the X/Z from `--info`: Studio flips them on import |

Reference lengths: Dagger ~2, Mace 3.8, Axe 4.4, Sword 5.2, Emberfang 5.4, Bow 5.6, Staff 6,
Hammer 7.2, Spear 8.3, Greatsword 8.9.

Fitting itself is automatic (`src/server/WeaponModels.luau`); only the numbers above need
tuning. If it looks off in game, tweak these and look again.

---

## 6A. New item of an existing type (like Emberfang)

Use this when it **moves exactly like a weapon that already exists**. Every place below is
where Emberfang is wired in; search for `Emberfang` and add the new weapon next to it.

**Config**

1. `src/shared/Config/CombatConfig.luau`
   - Add a new `ComboWeapon` entry (copy Emberfang's): `ToolName`, `ModelFit`,
     `TrailColor`, stats (`Damage`, `Stamina`, `Range`, `Block.BlockAmount`,
     `Block.ParryWindow`, `Heavy`...), reusing the base weapon's animation ids.
   - Add it to the table returned at the bottom of the file (next to `Emberfang = Emberfang`).
2. `src/shared/Config/InventoryConfig.luau`
   - Add it to `InventoryConfig.Weapons` with `Class`, `Rarity` and a one-line `Description`.
     **Any rarity other than Common keeps it out of the Blacksmith shop** (only Common
     weapons are sold, `ShopConfig.luau`).
   - Add it to the right `PrimaryFilters` list (One-Handed / Two-Handed / Polearms).
3. `src/shared/Config/SkillTrees.luau`: add it to `SkillTrees.SharedTrees`
   (`<Name> = "<BaseWeapon>"`) so it uses the base weapon's tree.
4. `src/shared/Config/TutorialConfig.luau`: `<Name> = SWORD` (or the base weapon's lesson).
5. One-handed? `src/shared/Config/ShieldConfig.luau`: add to `ShieldConfig.OneHanded` and
   `ShieldConfig.Stances.<Name> = ShieldConfig.Stances.<Base>`.

**Server**

6. `src/server/WeaponService.luau`: a placeholder `create<Name>()` (used only if the model is
   missing), and add it to `CREATORS` and `COMBO_WEAPONS`.
7. `src/server/init.server.luau`: `WeaponService.give(CombatConfig.<Name>)`.
8. `src/server/BlockService.luau` and `src/shared/ParryWindow.luau`: add its block amount and
   parry window lines.

**Client**

9. `src/client/init.client.luau`: `ComboWeaponClient.new(CombatConfig.<Name>).start()`.
10. `src/client/HitEffectsClient.luau`: its hit effect style, color and size.

**Docs**

11. `docs/design.md` §12 (what's built), and `docs/combat-breakdown.md` §4 (the weapon table
    and stats).

**Greatsword-type weapons are different:** the Greatsword has its own system built for one
weapon, so follow `docs/adding-a-greatsword.md` instead.

Ranged weapons (bow/crossbow/blunderbuss style) and casters (staff/grimoire style) go through
`BowService`/`SingleShotService`/`StaffService` instead of `WeaponService`; look at how the
Crossbow or Grimoire is wired and copy that.

---

## 6B. New weapon type (like the Dagger)

Everything in 6A, **plus** the parts that make it its own weapon. The Dagger commit
(`git show --stat c2932dd`) is the best map of everything touched. Before building, decide
(with the design doc, and ask about anything [TBD]):

- Class and hotbar slot, one- or two-handed, dual-wield or not
- The light combo (how many hits, what each one does), the heavy, the guard
- Its skill tree (or which tree it shares)
- Whether a class starts with it, and whether it gets its own armor set
  (see the planned weapons list)

Then:

1. **Animations.** Write `tools/<name>_anims.py` (copy `tools/dagger_anims.py`, built on
   `tools/sword_anims.py`) and run it:
   ```sh
   python3 tools/<name>_anims.py assets/animations
   ```
   This writes `<Name>Idle`, `<Name>Slash1...`, `<Name>Guard`, `<Name>WindUp`, the heavy, etc.
   as `.rbxmx` KeyframeSequences.
2. **Publish the animations (you do this part).** In Studio, publish each KeyframeSequence to
   Roblox (Animation Editor > Publish to Roblox) and send Claude Code the asset ids. Until
   then, the ids in config are blank.
3. **CombatConfig**: the new entry's own animation ids (`IdleAnimation`, each `Combo` step's
   `Animation`, `Block.Animation`, `Heavy`...). Keep each move's `HitDelay` in sync with the
   "hit" time in the animation script.
4. **Heavy attack**: if its `Heavy.Kind` is new, it needs code in `WeaponService.luau` (server:
   hits, damage) and `ComboWeaponClient.luau` (client: input, animation).
5. **Sounds**: `src/shared/Sounds.luau`: `<Name>Swing` and `<Name>Hit` (Creator Store audio ids),
   and `addSwingSound(grip, "<Name>Swing")` in its placeholder.
6. **Skill tree**: its own `weaponTree(...)` in `SkillTrees.luau` instead of a SharedTrees line,
   and add it to `SkillTrees.WeaponOrder` (the tabs in the skill screen).
7. **Tutorial**: its own `Light` / `Heavy` lesson text in `TutorialConfig.luau`.
8. **Starter weapon?** `InventoryConfig.StarterSidearms` / `StarterService.luau`, and
   `IntroConfig.luau` if a class shows it.
9. **Training stand?** `src/server/TrainingStands.luau` (a mannequin posed with it).

---

## 7. Finish

1. Run the syntax check (a syntax error stops every script from loading in Studio):
   ```sh
   sh tools/check_syntax.sh
   ```
2. Get it in game (the Test Chest in the admin-only Training Grounds hands out any weapon)
   and check: held by the grip, edge leading the swing, right size next to the character.
   Tweak `ModelFit` if not.
3. Commit the `.glb`, `.ready.glb`, `.rbxmx`, any animations, and the code together.

---

## Shortcut: asking Claude Code to do it

Steps 1 to 3 and 5 to 7 can be done by Claude Code; you only need to do the Studio parts
(step 4, and publishing animations for a new type). Paste something like:

> My friend delivered `Frostbite.glb` (in ~/Downloads). Add it as a new weapon following
> `docs/adding-a-weapon.md`.
> Kind: **A**, a new item of the **Sword** type.
> Rarity: **Rare**. Stats: a bit faster than the Sword, slightly less damage, ice-blue trail.
> Description: "A blade of frozen steel..."

For a new type (B), also describe the combo, heavy, guard and skill tree you want, or ask
Claude Code to propose them first.
