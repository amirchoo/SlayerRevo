# Perf pass: the final check (do once, after step 8)

One publish, one session on the **iPhone 14** (first) and one on the **Mac**. Tick as you go.
Note anything odd next to the box, and Claude will fix it. Shift+F5 shows FPS; the Developer
Console (F9, or the menu on the phone) shows the `[Quality]` line.
Claude adds each step's checks here as it finishes ([[perf-polish]], [[perf-polish-handoff]]).

## Before you start (Studio, once)
- [ ] **Reconnect Rojo** (Disconnect, then Connect in the Rojo plugin). A changed project file needs
  a reconnect: it adds the loading screen to ReplicatedFirst and applies the Workspace streaming
  settings ([streaming fix](../log/2026-10-17-streaming-fix.md)).
- [ ] The place is saved (Cmd+S), then published.
- [ ] Before you start, write down the FPS in town, in the forest and in a dungeon room, on the
  phone if you remember it, to compare against.

## Step 1: quality tiers ([log](../log/2026-10-17-quality-tiers.md))
- [ ] The console shows `[Quality] Medium (start)` on the phone (Automatic graphics) and
  `High (start)` on the Mac.
- [ ] If the FPS stays low for a while, it drops a tier (a new `[Quality]` line) and the game keeps working.

## Step 2: ShadowMap and the look ([log](../log/2026-10-17-shadowmap-art-direction.md))
- [ ] Day, night and the dungeon look as intended: sun shadows crisp, distant hills fade into haze.
- [ ] Torch light and the parry flash on the floor still look good (ShadowMap lights are softer).

## Step 3: startup cleanup ([log](../log/2026-10-17-startup-bake-cleanup.md))
- [ ] Hall of Oaths (new player intro): every statue holds its weapon straight away.
- [ ] Training Grounds: all 11 stands hold their weapons, each arriving whole.
- [ ] **Grimgorg dungeon:** has walls and floor, torches, gates, chests and the boss. (No walls or
  floor = the saved terrain didn't survive; tell Claude.)
- [ ] The Destroyed house is still there.
- [ ] Joining a fresh server takes the same time or less.

## Step 4: streaming and density ([log](../log/2026-10-17-streaming-density.md), [fix](../log/2026-10-17-streaming-fix.md))
- [ ] **The Hunting Grounds have trees, near and far** (the first test had none).
- [ ] **Near Grimgorg's Lair the ground is there all round you**, also after dashing about.
- [ ] From town, the distant hills and mountains are still there.
- [ ] Trees and town props pop in whole, never half-built.
- [ ] Meadows on the phone still look full (Medium keeps about 75% of small plants).
- [ ] Arrows and spells pass through leaves and grass; tree trunks still block you.
- [ ] No crash or memory warning after a long session on the phone.

## Step 5: lights and particles ([log](../log/2026-10-17-lights-particles.md))
- [ ] Day: trees still drop a canopy shadow; grass and paths don't.
- [ ] Night in town: lamps near you are lit. Walk a road: lamps ahead fade in, lamps behind fade
  out, no popping.
- [ ] Dungeon on the phone: torches still look like fire. Walking a corridor, torch lights ahead
  come on smoothly.
- [ ] Dungeon on the Mac (High): torches have smoke, glow and flicker.

## Step 6: animation level of detail ([log](../log/2026-10-17-pose-lod.md))
- [ ] Villagers and animals near you walk smoothly (far ones a bit choppier is fine, but it shouldn't stand out).
- [ ] Turn round fast: nothing behind you is frozen mid-step.
- [ ] Your pet looks the same as before.
- [ ] Low health drains the colours; they come back after healing.

## Step 7: far creatures sleep ([log](../log/2026-10-17-dormancy.md))
- [ ] Walk out to an orc pack: they notice you and fight as before.
- [ ] Run back to town and out again: the pack is where you left it, or back at its camp.
- [ ] Cows and chickens in the wilds graze, and run when hit, as before.
- [ ] Fighting several packs in a row stays smooth (no rising ping or rubber-banding).

## Step 8: loading ([log](../log/2026-10-17-loading.md))
- [ ] Join: the "Slayer Revo" loading screen shows instead of Roblox's, then fades into the game
  (or the intro for a new player), with no half-loaded town behind it.
- [ ] Joining on the phone takes the same time or less.
- [ ] Your first swing and first hit play their sounds on time.
- [ ] Grimgorg's roar plays when his fight starts.

## The result
- [ ] FPS now, phone: town ___ forest ___ dungeon ___ (before: ___ / ___ / ___)
- [ ] FPS now, Mac: town ___ forest ___ dungeon ___
- [ ] Sword: walk while swinging. The legs walk (no sliding), you walk at half speed while swinging; standing still, the swing's stance plays. ([log](../log/2026-10-18-sword-walk-while-swinging.md))
