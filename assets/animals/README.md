# Animal models

Synced to `ServerStorage.AnimalModels`. Each animal in `src/shared/Config/AnimalConfig.luau`
uses the model named in its `Model` setting (`Cow.rbxmx`, `Chicken.rbxmx`, `Cat.rbxmx`).

These are plain Parts, not imported meshes: the source models (`assets/source/animals/*.glb`)
are built only from boxes, so `tools/box_glb.py` turns each box into a Part of the same size,
place and color. No Studio step.

    python3 -I tools/box_glb.py assets/source/animals/Cow.glb assets/animals/Cow.rbxmx --turn-y 180

(`--turn-y 180`: the downloads face +Z; Roblox models face -Z.) The town cat's source,
`Cat.glb`, was written by a script in the same all-box style (orange tabby) and converted the
same way; replace it with a downloaded cat any time (same part names: `Body`, the four
`Leg...` groups, `Head`, `Tail`, `TailTip`). The meat items in
`assets/items` are made the same way.

AnimalService rigs a model when it spawns, so it needs:
- a Part named `Body` (the invisible HumanoidRootPart is put over it);
- each of the type's `Limbs` (AnimalConfig) as a sub-Model or Part of that name, e.g. the
  cow's `LegFrontLeft` group or the chicken's `WingLeft`. Their joints are placed from their
  bounds (legs at the hip, the head at the back of the neck), and the client animates them.
