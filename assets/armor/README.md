# Armor models

Synced to `ServerStorage.ArmorModels`. Each set gets a folder named after its id in
`src/shared/Config/ArmorConfig.luau` (e.g. `Iron/`), holding one file per slot, named after the slot:

    Iron/Helmet.rbxmx
    Iron/Chestplate.rbxmx
    Iron/Armwear.rbxmx      both arms
    Iron/Leggings.rbxmx     both legs
    Iron/Boots.rbxmx        both boots

Each file is either a single Accessory, or a Model holding several Accessories. Use a Model for
pieces that cover more than one body part: an Accessory sticks to one body point, so a pair of
boots is two Accessories (one on each foot) grouped into one Model named "Boots", and each boot
moves with its own foot.

Each Accessory needs a part named `Handle` with an Attachment named like the body attachment it
sits on. Roblox's own ones work (`HatAttachment`, `BodyFrontAttachment`, `LeftFootAttachment`, ...,
already set up on Marketplace and Toolbox accessories), and the game also gives every body part an
`Armor<PartName>` attachment at its center (`ArmorLeftUpperLeg`, `ArmorRightLowerArm`, ...), so a
piece can sit on any body part, including the legs and lower arms.

A whole set delivered as one GLB (docs/model-brief.md): run `tools/armor_glb.py` on it, import the
`.ready.glb` with Import 3D, then run `tools/fit_armor_set.lua` in the Command Bar (set SET at the
top). It fits every piece onto a blocky `workspace.Rig` and makes `Workspace.<Set>Armor` with the
five slots, ready to save. Files can be `.rbxmx` or `.rbxm`; `tools/decode_rbxm_export.py` writes
them from a base64 export, so they can be saved without clicking Save to File.

To make your own: build the piece from parts where it should sit on `workspace.Rig`, then run
`tools/make_armor_accessory.lua` in the Command Bar (set BODY_PART and NAME at the top first).
It turns the selected parts into an Accessory on the right `Armor<PartName>` attachment.

To save from Studio: put the Accessory (or select both of a pair and press Ctrl+G to group them
into a Model) and rename it after the slot, then right-click > Save to File into the set's folder.

Every player has the same blocky R15 body (src/server/AvatarService.luau), so fit pieces on a
blocky R15 rig (Rig Builder > Block). The Handle's `FitSize` attribute (set by the tool) is the
size of the body part it was fitted on; if a wearer's body part ever differs, the game stretches
the piece to match (a fallback: on the blocky body nothing changes).

Any slot without a file uses the placeholder built in `src/server/ArmorService.luau`.
Protection always comes from ArmorConfig, not the model.
