# Animation style saved; remaking every weapon's animations is now priority 0

**Asked:** "save up all the blender animation preferences… I want to remake all weapon animation again in
this style. Save it up for future session and make this a number 0 priority."

**Changed**
- New `docs/animation-style.md`: the look (exaggerated like the battlegrounds video, with numbers), the
  tools (`author.sh`, `combo.sh`, `show.sh`, clip options), the loop for every clip (scratch run, report
  targets, previews, combo viewer, staging and publishing), the table of fixes that worked on the Sword,
  and how it fits with hit feel. Linked from Home.md and CLAUDE.md.
- New `notes/tasks/weapon-anim-remake.md`: the checklist of every weapon's clips (Sword combo done, Sword's
  rest next, then the Rapier first as the user's weapon), with what each weapon needs (port its old
  generator, add its model to weapon_model.py and combo.sh, new controls for dual blades, bows, guns, casting).
- Priorities: **0 the remake**, 1 the perf pass (was 0), 2 the main issue (was 1). Updated in CLAUDE.md,
  the backlog, the session handoff and the task notes; Claude's memory too.

**Open:** the user publishes the six staged Sword clips; then "do the animation remake" starts the Sword's
idle, guard and spin.
