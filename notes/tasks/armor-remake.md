# Armor remake: tiered, painted low tiers, more 3D as tiers rise (priority 1)

Opened 2026-10-18. **Priority 1**: starts once every weapon's animations are remade
([[weapon-anim-remake]], deadline 2026-10-25), before the Arcane Atelier look ([[arcane-atelier-look]]).
Say **"do the armor remake"**: Claude reads this note, does the next unticked set, ticks it here with a
link to its log note. Models are made by Claude in Blender ([[blender-for-art]], docs/model-brief.md).

## Why
The Sword guard went through the armor in a playtest: several sets are much bulkier than the body
(measured per side over the bare body part: Duelist forearms 0.32, Apprentice forearms 0.44, Vanguard/Reaper
chest 0.30, Reaper/Apprentice helmets 0.52-0.55; Leather and Skirmisher are already slim). Research and the
user's references: good Roblox armor is a hybrid: thin plates hugging the body, cloth/leather/straps
painted on as textures, chunky 3D only in a few places (shoulders). Full log:
[the guard log](../log/2026-10-18-guard-armor-clearance.md).

## The rule (the user's call, 2026-10-18)
- **Low tiers: minimal 3D, mostly painted.** The armor is a texture on thin shells (or on the body), so it
  still reads as armor but adds almost no thickness.
- **Higher tiers: more 3D parts**, so they look more expensive and stronger (pauldrons, raised plates,
  crests, layered pieces).
- **Keep the weapons' paths clear at every tier** (proposed budget, confirm with the user): forearms ≤ 0.1
  per side, chest front ≤ 0.15, upper arms ≤ 0.2 (big pauldrons go up and out, not forward), helmets
  ≤ 0.25 over the head. Extra 3D on high tiers goes where blades rarely pass: shoulders' tops, the back,
  the hips' sides.
- After each set: re-measure, and update `ARMOR` in `tools/blender/author_anim.py` (the weapon clearance
  check) to the bulkiest set's real sizes.

## Sets (tiers from InventoryConfig rarity; confirm the order with the user first)
- [ ] Decide the tier of each set and the 3D allowance per tier (ask).
- [ ] Apprentice, Woodcutter, Leather, Skirmisher (likely low tier)
- [ ] Prowler, Warhide, Warden, Duelist
- [ ] Vanguard, Reaper, Iron (check which tier)

## Related, done
- 2026-10-18: players' own avatar accessories (hats, hair, face items) are no longer put on: only the
  game's armor goes on the body (src/server/AvatarService.luau).
