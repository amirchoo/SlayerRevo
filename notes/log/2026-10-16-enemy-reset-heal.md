# Enemies heal when they give up

2026-10-16 · not playtested

## Asked
When enemies stop chasing you (past their radius), they should heal to full right away, so they
reset at full health.

## Found
Packs already healed when they gave up. But on the walk home they could still be hit without
fighting back, so they arrived hurt. Single enemies (spawn points, the Training Grounds) never healed.

## Changed
- [EnemyService.luau](../../src/server/EnemyService.luau):
  - Packs heal to full the moment they give up.
  - They can't be hurt on the way home; hits deal 0 and show nothing.
  - They heal again once they're back at camp.
  - Single enemies heal to full when they lose their target. Sparring orcs are left alone.
- [EnemyConfig.luau](../../src/shared/Config/EnemyConfig.luau) comment and the §12 Enemy behaviour row in [design.md](../../docs/design.md)

## Tuning
- `Pack.LeashRange` (130 studs from camp) sets when a pack gives up.
- `AggroRange` sets when a single enemy loses you.
