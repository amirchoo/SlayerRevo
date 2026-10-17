# Fix: ground and trees missing on the phone (perf pass, after the first check)

**Reported:** the user's first phone test after the pass. No lag, but "the load is kinda broken":
- the Hunting Grounds had no trees, though the minimap showed plenty
- near Grimgorg's Lair the ground was missing round the player: grass models and the cave's rock
  slab floating over nothing
- standing still didn't bring either back

## Cause
- **Not missing from the game.** The saved place has terrain all round the cave mouth (a 17×17
  height grid, no holes). On the Studio client the ground there loads (Grass, LeafyGrass, Slate),
  and 815 trees are present.
- **The phone ran short of memory.** Workspace streaming was still on Roblox's defaults:
  - **target radius 1024 studs** (the client tries to hold most of the ~1,700-stud map:
    58,500 parts on the Studio client)
  - **guaranteed radius 64**
  - stream-out only when memory is low
  - Once the phone hits its memory limit, Roblox stops streaming new content in. Anything past
    the small guaranteed area that wasn't loaded yet (trees, then ground as you move) never
    arrives.
  - Nothing stopped the character from walking onto ground that hadn't loaded.
- The pass didn't cause this, but the settings were left for the user to set by hand (step 4's
  optional to-do), and they were never set.

## Fix
- The streaming settings now live in [default.project.json](../../default.project.json) (Workspace),
  so Rojo applies them and they're tracked in the repo:
  | Setting | Was | Now | Why |
  |---|---|---|---|
  | `StreamingTargetRadius` | 1024 | **768** | holds about half as much map; the fog hides past ~700 anyway |
  | `StreamingMinRadius` | 64 | **128** | the area always kept round you, ground included |
  | `StreamOutBehavior` | Default | **Opportunistic** | far content is let go early, so memory never fills up |
  | `StreamingIntegrityMode` | Default | **MinimumRadiusPause** | if the ground round you isn't in yet, you pause a moment instead of walking onto nothing |
- The mountain ring is a Persistent model, so the smaller radius doesn't hide it.
- Checked: `rojo build` writes all five with the right enum values (Opportunistic = 2,
  MinimumRadiusPause = 2).

## To do (user)
- **Reconnect Rojo** (it applies the new Workspace settings and adds the loading screen), save,
  publish.

## To check (phone)
- The Hunting Grounds have their trees again, including in the distance.
- Near Grimgorg's Lair the ground is there all round you, including after dashing about.
- The distant hills and mountains are still visible from town (if hills vanish, raise the target
  radius to 1024 and keep the rest).
- If you ever pause for a moment after a fast run, that's the integrity pause waiting for ground:
  rare is fine, often means the radius should come down.

## Open
- The user also says creature animation still isn't as smooth as they'd like. Look at it next
  (after this check), in [[perf-polish-handoff]].
