# Hits land harder: shake, zoom punch, impact frame

**Asked:** step 1 of [[battlegrounds-combat-reference]] (after the user's battlegrounds reference video).
Also: the user's PvP plan is on-the-spot duels from an "interact" button on another player
(recorded in docs/design.md §10 and the backlog; not built).

**Changed**
- `src/client/HitFeel.luau`: on every hit you land (the server's DamageDealt) it now also
  - shakes the camera a little (Humanoid.CameraOffset, like the other shakes), scaled by damage and by
    how close the hit is (none for far-off bow shots);
  - punches the view in (field of view narrows, then eases back), added on top of the current field of
    view so the bow and single-shot aim zooms aren't fought;
  - on **heavy** hits shakes twice as hard, punches 4° instead of 1.2°, and shows an **impact frame**:
    0.07 s of a grey, harsh screen (a ColorCorrectionEffect on the camera) with the target as a black
    silhouette with a red outline (a Highlight), at most one every 0.5 s.
- A hit is heavy when it kills (the target's Health attribute already reads 0) or lands during a
  heavy window. `HitFeel.setHeavyWindow` is called by the weapon scripts: ComboWeaponClient on each
  swing (the last combo step is heavy, others clear it), on a quake/thrust/flurry release and on a reap;
  GreatswordClient on the finisher and the charged slam. Spins and rushes aren't marked (they'd flash nonstop).
- Tuning: `CombatConfig.HitImpact` (HeavySlack, Shake, Zoom, ImpactFrame incl. `Enabled`).

**Not playtested** (per the skip-playtests rule). Syntax check passes.

**Open:** whether the impact frame is too strong/weak on the phone; a player-facing setting to turn off
flashes (ImpactFrame.Enabled is config only). Next: step 2, afterimages on dash.
