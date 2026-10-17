# Arcane Atelier: reference video breakdown

The user's reference video, 2026-10-18: a 75 s TikTok from **@arcane_atelier** of an in-development
Roblox game, *Arcane Atelier* (file: `~/Downloads/v14025g50000db7m62nog65gbal20gu0.MP4`, vertical
576×1246). The user likes "the whole style and environment", the attack animations and the walk.
Analysed from frames only (sound not checked). The wizard-hat logo banner at the top is an edit overlay,
not part of the game. Task: [[arcane-atelier-look]].

## Environment
- **Bright, painterly fantasy** (Breath of the Wild / Ghibli feel): very saturated green grass, an
  anime-painted sky with big cumulus clouds, a **sea horizon** behind the trees (an island).
- **The ground is layered, not plain terrain:**
  - chunky 3D grass clumps everywhere (mesh tufts, not just terrain grass decoration)
  - irregular brown dirt patches cut into the grass
  - **broken pale flagstone paths**: cracked beige tiles, some loose, scattered or tilted
  - white flower clusters and clover
- **Low-poly grey rocks and cliffs** (big flat faces) and **ruined stone walls**.
- **Trees:** round, blobby, clustered canopies on dark trunks, in dense groves around open clearings.
- **Post-processing does a lot of it:** strong **depth of field** (background heavily blurred, player
  sharp), **bloom** on the sun and VFX, high saturation, almost no fog. That is why plain blocky avatars
  still look cozy and polished.

## Combat
- An over-the-shoulder camera close behind the player; a sword combo, a dodge roll, group fights (2–3).
- **Hit VFX:** big white/yellow crescent slash arcs, a **ring shockwave** at the impact point, green
  wind streaks, a blade trail with a rainbow (chromatic) edge, a bright flash.
- **Red damage numbers** (5, 6, 10, 12) in a serif font, popping over the target.
- **An impact frame:** one frame white with the fighters as black silhouettes (we already have this,
  `CombatConfig.HitImpact`).
- Enemies are **knocked flying and ragdoll**, drop their weapons, stay down on the ground.
- Enemy NPC swordsmen with personality: one shouts "En garde!" in a speech bubble; name tags are small
  parchment banners above the head.

## Animation: why it looks smooth
- **The VFX hide the body during a hit.** Frame by frame (10 fps around 5.6 s), the crescent arcs, the
  ring and the flash cover the character on almost every frame of a swing; the body is only clearly
  visible between swings, in a held pose. So the eye reads the *arc* as the motion, not the limbs:
  a pop or a stiff joint mid-swing never shows. The VFX also carry the shape of the cut (the arc *is*
  the swing path), so the animation only needs a clear wind-up pose and a clear end pose.
- The user's read (2026-10-18), and it matches the frames: "the effects pretty much hide the details of
  flaw in the animation making it look smooth".
- What that means for us: our clips are already clean (the AUTHOR checks), so VFX would add on top
  rather than cover flaws. Slash crescents are already planned ([[battlegrounds-combat]]); this video
  argues for **big, bright, opaque-ish arcs timed to the cut** (not thin trails), plus a ring at the
  impact point.

## The walk: the sword feels heavy
- Walking with the sword out, the **sword hangs low in the right hand, tip down and trailing behind**,
  near the ground; the arm hangs back and the blade sways with the steps instead of being held up in
  a guard. The enemy swordsmen carry theirs the same way. It reads as a heavy blade being dragged along,
  relaxed between fights. (Seen from behind at small size; the exact arm swing is not readable frame by
  frame, but the low trailing blade is clear in every walking shot.)
- **What we do now:** the weapon's idle clip (`IdleAnimation`, Idle priority, in `ComboWeaponClient`)
  plays over the default walk, so the arms hold the idle stance while the legs walk. There is **no
  weapon walk/carry clip**.
- To get this look: a per-weapon **walk (carry) clip**: upper body only, sword low and trailing, the
  arm swinging back with the steps and the blade lagging behind the hand (overlap), played instead of
  the idle while moving and blending back to the idle stance when you stop. Heavier weapons (hammer,
  greatsword, axe) would drag lower and sway more. [TBD: ask the user before building; it adds a clip
  per weapon to the remake.]

## UI: ornate dark fantasy on a bright world
- **Health bar:** red, with a gothic silver filigree frame and a heart emblem in the middle; a second
  dark bar under it with an orange-yellow fill in some frames (stamina or posture?).
- **5 round skill medallions** above the bar.
- **3 hotbar slots shaped like stone tablets**, numbered 1–3: "Splintered Longsword", "Splintered Axe",
  "Spellbook".
- **Top strip:** "Exp +102", a quest tracker ("The Weakest Swordsman … 254/300"), a second tracker
  ("Hunt4Glory 47 (15%)"), a session timer.
- **Dialogue box:** parchment with an ornate border, the NPC's name on a tab, reply choices listed below.
- Serif fonts throughout. One consistent theme; the contrast with the bright world looks deliberate.

## Cost on our baseline phone
Heavy depth of field and thousands of grass clumps are expensive on a low-end phone
([[baseline-device-low-end-phone]]). Copying the look needs a lighter tier there: no DoF, fewer and
closer grass clumps, bloom kept small.
