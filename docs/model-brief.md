# Slayer Revo: 3D model brief

Paste the **Brief** section into Claude Design at the start of every model request, then fill in
one **Request** template below it. Everything here comes from what has and hasn't imported
cleanly into Roblox Studio so far (Emberfang: clean; the first Lesser Demon: failed to rig).

---

## Brief

You are designing 3D models for **Slayer Revo**, a Monster Hunter-style action RPG on Roblox.
Every model is imported into Roblox Studio, so it must follow these rules exactly.

### Look
- Stylized and readable from a distance: clear silhouettes, chunky shapes, slightly
  exaggerated proportions. Not realistic, not noisy. The town is stylized medieval
  (timber-framed houses, stone, warm colors).
- Big shapes over small detail. A detail smaller than about 3% of the model's height won't be
  seen in game; leave it out.
- Flat colors only: one solid color per material, no image textures, no gradients, no
  normal maps. 3 to 8 materials per model.
- Give every material a short descriptive name (`steel`, `darkMetal`, `ember`, `gripWrap`,
  `hide`, `wingMembrane`). Never reuse one name for two different colors.
- Accent color by rarity, where it fits the design (a glow, an inlay, an edge, a gem):

  | Rarity    | Accent        |
  |-----------|---------------|
  | Common    | none (plain materials) |
  | Uncommon  | green `#64DC6E` |
  | Rare      | blue `#50A0FF` |
  | Epic      | purple `#BE64FF`, or the item's own theme color (Emberfang uses ember `#DE5615`) |
  | Legendary | gold-orange `#FFAF32` |

### File
- One **.glb** file, named in PascalCase after the item: `Emberfang.glb`, `LesserDemon.glb`.
- Units: **1 unit = 1 Roblox stud** (about 0.28 m of a person's height: a person is ~5 studs).
- Y is up. The model's **front faces +Z**.
- Apply all transforms (no rotated, scaled, or offset nodes needed to look right).
- Closed meshes only: no stray single faces, no zero-area faces, no duplicate overlapping
  copies of the same surface, nothing hidden inside other geometry.
- **Hard limit: 20,000 triangles for the whole model.** Stay well under the budgets below.

### Weapons
- Pose: **length along +Y**, handle at the bottom (-Y), tip at the top (+Y).
- The blade's flat side faces Z: its **thinnest dimension is along Z**, its width (edge to
  edge, or a head's reach) along X. For one-edged weapons (axe, scythe), the cutting edge
  points to **+X**.
- Center the handle on the Y axis (X = 0, Z = 0).
- The grip is a clearly separate material (`gripWrap`, `leather`, `wood`) so the hand
  position is obvious.
- Size: the game scales it to fit, but keep real proportions. Reference lengths (handle end to
  tip, in studs): Sword 5.2, Emberfang 5.4, Axe 4.4, Mace 3.8, Bow 5.6, Staff 6, Spear 8.3,
  Greatsword 8.9.
- Budget: **under 8,000 triangles** (Emberfang is 7,600).
- Leave out anything the game draws itself: bowstrings, magic effects, trails, glows that float
  in the air.

### Characters and enemies
These are rigged automatically by Roblox's Avatar Auto Setup, which is strict. A model that
breaks these rules gets stuck at "rigging body".

- **One single connected body mesh**: head, torso, arms, hands, legs, and feet are one
  continuous closed surface. Armor, plates, belts, and spikes are **part of that surface**
  (merged and sculpted in), never separate floating pieces sitting on top of it.
- **A-pose**: standing straight, arms out to the sides about 45 degrees down from horizontal,
  elbows almost straight, palms facing down. Legs straight, feet shoulder-width apart, flat on
  the ground. **Not** arms hanging at the sides, crouched, or mid-action.
- Clear gaps: arms don't touch the torso, legs don't touch each other, fingers can be one
  mitten shape or 3 to 4 thick fingers spread slightly apart.
- Humanoid proportions: two arms, two legs, one head, roughly human joint positions (the rig
  needs shoulders, elbows, wrists, hips, knees, ankles). Monsters can be bulky, hunched in
  shape, or long-armed, but the pose is still an A-pose.
- Feet on the ground: the lowest point is at **Y = 0**, centered on X = 0, Z = 0.
- Height: **4 to 6 studs** for human-sized enemies (the Orc is about 4.2). The game scales
  bigger enemies up in code, so design them at this size too.
- **Extras go in separate objects**: wings, tails, capes, horns that stick far out, and held
  weapons are each their own object in the file, named `Extra_Wings`, `Extra_Tail`, etc.,
  each a closed mesh positioned where it attaches. They're attached after rigging; the body
  must make sense without them.
- Budget: **under 10,000 triangles** for the body, under 3,000 for all extras together.

### Armor
- One file per piece, named after its set and slot: `IronHelmet.glb`, `IronChestplate.glb`,
  `IronBoots.glb`. Slots: Helmet, Chestplate, Armwear, Leggings, Boots.
- Built to fit a standard 5-stud Roblox character standing at the origin in A-pose: the piece
  sits exactly where it would be worn.
- Pairs (arms, legs, boots) have one closed object per side, named `Left` and `Right`.
- Budget: **under 3,000 triangles** per piece.

### Buildings and props
- Ground level at Y = 0, centered on the origin, front facing +Z.
- Real scale in studs (a door is about 7 studs tall and 4 wide).
- Budget: **under 15,000 triangles**. Split big buildings into parts (walls, roof, details)
  as separate objects.

### When you deliver
State the model's triangle count, its size in studs (X, Y, Z), its material names with their
colors, and (for characters) the list of `Extra_` objects.

---

## Request template

Copy one of these after the brief and fill it in.

**Weapon**

    Make a weapon.
    Name: <PascalCase, e.g. Emberfang>
    Type: <sword / axe / mace / spear / bow / staff / greatsword / new type>
    Rarity: <Common / Uncommon / Rare / Epic / Legendary>
    Length: <studs, or "same as the Sword">
    Theme: <a few words: "a demon hunter's blade, black steel with ember cracks">
    Must have: <details that matter, e.g. "a crossguard shaped like wings">

**Enemy**

    Make an enemy (Avatar Auto Setup rules apply).
    Name: <PascalCase, e.g. LesserDemon>
    Tier: <how tough: "the first enemy players meet" / "level 8, a step above the Orc">
    Theme: <a few words: "a winged imp in black plate, ember eyes">
    Extras: <e.g. "wings and a tail, as Extra_ objects", or "none">
    Must have: <silhouette notes, e.g. "big shoulders, small head">

**Armor**

    Make an armor set: <Name, e.g. Ember>
    Pieces: <Helmet, Chestplate, Armwear, Leggings, Boots>
    Rarity: <...>
    Theme: <...>

---

## Into the game (for Claude Code)

What happens to a delivered `.glb`, so it can be repeated:

1. Copy it into `assets/source/weapons/`, `assets/source/enemies/`, or the armor/town
   equivalent, named after the item.
2. Check it: `python3 -I tools/weapon_glb.py <file> /dev/null --info` (size per axis,
   triangles and color per material). Over 20,000 triangles: decimate first with
   `tools/decimate_glb.py` (headless Blender).
3. Bake the colors and set the pose: `python3 -I tools/weapon_glb.py <file> <Name>.ready.glb`,
   plus `--turn-y 180` for characters (they're designed facing +Z; the rig wants -Z).
4. The user imports `<Name>.ready.glb` in Studio (Import 3D). Characters then go through
   Avatar Setup > Auto Setup. Save as `.rbxmx` into `assets/weapons/`, `assets/enemies/`,
   etc. (see the README in each folder).
5. Hook it up in config: a weapon's `ModelFit` in `CombatConfig.luau` (length and grip from
   the `--info` output), an enemy's `Model` in `EnemyConfig.luau`, an armor set's folder
   name in `ArmorConfig.luau`. Playtest and screenshot it in game.
