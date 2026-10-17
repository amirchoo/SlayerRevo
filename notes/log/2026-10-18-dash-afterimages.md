# Dash afterimages: a trail of white copies behind every dash

**Asked:** "do the battlegrounds task": step 2 of [[battlegrounds-combat]], afterimages on dash
(see-through white copies trailing behind and fading out over about 0.2 s, as in
[[battlegrounds-combat-reference]]).

**Changed**
- `src/client/DashEffects.luau`: the single pale-blue afterimage left at the start of a dash is now a
  **trail**: one copy at the start, then one every 0.05 s while the dash travels (up to 4 over its
  0.21 s), each white, see-through, neon, fading out over 0.2 s. They're taken after the dash pose is
  laid on, so the copies show the low lean. Other players' dashes get the same trail (DashEffect remote).
- **Phone cost:** each character gets a pool of ghost bodies, cloned once on its first dash and reused
  after that (moved into place with one `BulkMoveTo` and faded by a single Heartbeat loop that
  disconnects when nothing is fading). Before, every dash cloned the whole body. A pool is rebuilt only
  when the character's parts change (armor or weapon swapped), and dropped when the character leaves.
  Parts hidden at the moment (Transparency 1) stay hidden in the copy.
- How many copies a dash leaves depends on the quality tier: new `Afterimages` in `QualityConfig`
  (Low 2, Medium 3, High 4).
- Tuning: `CombatConfig.Dash.Afterimages` (MaxCount, Interval, Fade, StartTransparency, Color).

**Checked:** syntax check passes; in edit mode, cloning the Rig's parts (15) and moving them with
`BulkMoveTo` works. Studio didn't have the new config yet (Rojo not synced), so nothing was pushed in.
**Not playtested** (per the skip-playtests rule). Added to [[perf-final-check]].

**Open:** whether white neon glows too much with bloom on (raise StartTransparency or tone the Color
down); the first dash per character clones its pool once (a small hitch is possible on the phone).
Next: step 3, a flinch per combo step and a knockback-and-ragdoll ender.
