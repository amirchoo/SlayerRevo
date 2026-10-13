# Weapon models

Synced to `ServerStorage.WeaponModels`. A file here named after a weapon's ToolName replaces
that weapon's placeholder look: `Sword`, `Emberfang`, `Mace`, `Spear`, `Rapier`, `Grimoire`, `Axe`, `Greatsword`, `Bow`, `Staff` (`.rbxmx`).

Ready to import, in `assets/source/weapons/`:

| Weapon     | Import this             | Source                          |
|------------|-------------------------|---------------------------------|
| Sword      | `ShortSword.glb`        | Short Sword by joney_lol        |
| Emberfang  | `Emberfang.ready.glb`   | Original design (Slayer Revo)   |
| Mace       | `Mace.glb`              | Mace by joney_lol               |
| Spear      | `Spear.glb`             | Pike by joney_lol               |
| Greatsword | `Greatsword.ready.glb`  | Sword by Quaternius             |
| Bow        | `Bow.ready.glb`         | Bow by Zsky (`bow_01.obj`)      |
| Axe        | `Axe.ready.glb`         | Axe Small by Quaternius         |
| Staff      | `Staff.ready.glb`       | Staff by Quaternius             |
| Rapier     | `Rapier.ready.glb`      | Epee by AroniaStudios           |
| Grimoire   | `Grimoire.ready.glb`    | Grimoire (your download)        |

The `.ready.glb` files were made with `tools/weapon_glb.py` from color-only models (Studio
would import those grey): colors baked into a texture, put in the pose the game expects
(length along Y, handle at -Y, thin side along Z). The bow's string was left out on purpose;
the game draws it (resting and pulled).

Credit the authors if a model's license is CC-BY (check its Poly Pizza page).

1. In Studio: Import 3D (File > Import 3D, or the Avatar tab) the file from the table above.
   Keep the default settings.
2. Rename the imported Model after the weapon (e.g. `Sword`).
3. Right-click it > Save to File, into this folder, as `Sword.rbxmx`.

It's fitted automatically (see `src/server/WeaponModels.luau`): scaled to the weapon's length,
turned so the blade points the right way, and held by the handle. Tune it with the weapon's
`ModelFit` in `src/shared/Config/CombatConfig.luau`:

- `Length`: studs from the end of the handle to the tip.
- `GripFrom`: where the hand holds it, as a fraction of Length from the handle end
  (raise it to slide the hand up toward the blade).
- `FlipBlade = true`: if it comes out held by the tip.
- `FlipEdge = true`: turns it 180 degrees around the handle, e.g. if an axe's edge faces
  backwards (the Axe uses this).

Only the look changes; damage, reach, and animations don't.
