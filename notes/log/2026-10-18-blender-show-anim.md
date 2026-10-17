# See an animation in Blender's window (show.sh)

**Asked:** "show me how you do your animation in Blender, I need to see the result in Blender".

**Changed**
- New `tools/blender/show.sh <Clip>` + `show_anim.py`: takes the rig `author.sh` saves
  (`build/anim_author/<Clip>.blend`) and makes `build/anim_author/<Clip>_show.blend`, then opens it in
  Blender. It adds the blocky R15 body and the sword on the bones, the ground, the blade tip's path
  (orange), timeline markers on every key and on the hit, names on the controls, and a view from
  behind like the lock-on camera. Space plays it, dragging the timeline scrubs it.
- Built for SwordSwing1, 2 and 3; Swing 1 was opened. The clip and its .rbxmx aren't touched.

**How the authoring works** (what the user sees in the file): the controls (SwordCtl, BladeTip,
EdgeAim, LWrist, the foot controls, elbow/knee poles, HeadAim) are what `tools/blender/sword_clips.py`
keys; Blender's IK solves the arms and legs from them; `author.sh` samples the result 60 times a second
into the Roblox clip.

**Checked:** rendered frames 0, 11 (hit) and 30 of Swing 1 from the file: body and sword sit right.
