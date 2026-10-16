# Grimgorg: sounds, boss music, 5 parries to stun

**Asked:** sounds for Grimgorg (attacks, when hit, when furious...), a boss track, and he
should need 5 parries before he's stunned.

## Parries
[BossService](../../src/server/BossService.luau) `land`: a parry on a Parryable blow (only the
Combo) now deflects it for that player (no damage; BlockService's parry clang/sparks as before)
and counts (`boss.parries`, attribute "Parries"); the parrying player sees a small banner
"Parried! n/5". The `ParriesToStun`-th (5, [BossConfig](../../src/shared/Config/BossConfig.luau))
staggers him ("Grimgorg is staggered!") and stops the attack. The count is shared across
attacks and players and goes back to 0 after any stagger (poise too) or a wipe. Poise stagger
is unchanged.

## Sounds
New client [BossSounds](../../src/client/BossSounds.luau), driven by the attributes BossService
already sets (no new remotes); sounds play from his root (heard to 260 studs):
- BossConfig `Sounds`: Roar (Intro), Enrage (each phase change: furious, enraged), Hurt (health
  drops, at most every 0.9 s, not mid-attack or stunned), Stunned, Death.
- Each attack's `Sounds` cues (At seconds into the clip, scaled by its speed; a new action
  cancels pending cues): Combo growl + 3 claw swooshes; Overhead growl + slam boom; TailSwipe
  growl + 2 tail whooshes; Beam growl + 2 fire bursts.
- Ids in [Sounds.luau](../../src/shared/Sounds.luau) (`Grimgorg*`): Pro Sound Effects creature
  voices (giant creature roar 9113980319, Goliath growl 9114628321, lion growl 9113973119) pitched
  down, "large monster roar" 114600180172960 for the enrage, existing swing/slam sounds re-pitched,
  Flame Licks 9114463219 for the beam. All load in Studio; not listened to.

## Music
`Sounds.Music["Boss:Grimgorg"]`: Edge Of Extinction (APM, orchestra and choir), Drums of
Combat. [Soundscape](../../src/client/Soundscape.luau) plays a boss's own "Boss:<Id>"
playlist when it has one, else the generic Boss list.

## Open
- Not playtested or listened to. Tune volumes/pitches in Sounds.luau, cue times in BossConfig.
- Only the Combo is parryable, so all 5 parries come from his combos (up to 3 per combo).
