--!strict
-- Plays a rigged model's animation clips on its Bones from data made by tools/npc_clips.py
-- (src/shared/PetClips/<Model>.luau for pets, src/shared/EnemyClips for bosses), instead of uploaded animations: Studio's Import 3D
-- puts the bones in the mesh's bind pose and its converted clips came out scrambled for
-- Bonnie, so the file's own keys are played here.
--
-- A pose is each bone's transform relative to its parent bone, as in the file. A bone's
-- Transform is then Bind^-1 * pose (the imported Bone.CFrame is its bind pose), with
-- positions scaled to the model (Model:ScaleTo).
--
--     local rig = RigClips.rig(model, data)
--     local pose = RigClips.sample(data, "Idle", time)       -- { [bone]: CFrame }
--     RigClips.blend(pose, RigClips.sample(data, "Sleeping", t2), 0.3)  -- 30% of the way
--     RigClips.apply(rig, pose)
--
-- Shared so the server can read clip lengths (BossService).

export type Track = { PT: { number }?, P: { number }?, RT: { number }?, R: { number }? }
export type Clip = { Length: number, Tracks: { [string]: Track } }
export type Data = { Bind: { [string]: { number } }, Rest: { [string]: { number } }, Clips: { [string]: Clip } }
export type Pose = { [string]: CFrame }
export type Rig = { bones: { [string]: Bone }, bindInverse: { [string]: CFrame }, scale: number }

local RigClips = {}

local function cframe(v: { number }, scale: number): CFrame
	return CFrame.new(v[1] * scale, v[2] * scale, v[3] * scale, v[4], v[5], v[6], v[7])
end

-- Finds the model's bones and its scale (from how far apart the bones are now vs. in the file).
function RigClips.rig(model: Model, data: Data): Rig
	local bones: { [string]: Bone } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Bone") and data.Bind[descendant.Name] then
			bones[descendant.Name] = descendant
		end
	end
	local scale, measured = 0, 0
	for name, bone in bones do
		local bind = data.Bind[name]
		local length = Vector3.new(bind[1], bind[2], bind[3]).Magnitude
		if length > 0.05 then
			scale += bone.CFrame.Position.Magnitude
			measured += length
		end
	end
	scale = if measured > 0 then scale / measured else 1
	local bindInverse: { [string]: CFrame } = {}
	for name in bones do
		bindInverse[name] = cframe(data.Bind[name], scale):Inverse()
	end
	return { bones = bones, bindInverse = bindInverse, scale = scale }
end

-- The keyed value at `time` (linear between keys), as a list of `width` numbers.
local function at(times: { number }, values: { number }, width: number, time: number): { number }
	local count = #times
	if count == 1 or time <= times[1] then
		return table.move(values, 1, width, 1, {})
	end
	if time >= times[count] then
		return table.move(values, (count - 1) * width + 1, count * width, 1, {})
	end
	local hi = 2
	while times[hi] < time do
		hi += 1
	end
	local lo = hi - 1
	local f = (time - times[lo]) / (times[hi] - times[lo])
	local out = table.create(width, 0)
	local a, b = (lo - 1) * width, (hi - 1) * width
	for i = 1, width do
		out[i] = values[a + i] + (values[b + i] - values[a + i]) * f
	end
	return out
end

-- The clip's pose at `time` seconds (looped), with every bone the data knows. Positions are
-- in the file's units (RigClips.apply scales them).
function RigClips.sample(data: Data, clipName: string, time: number): Pose
	local clip = data.Clips[clipName]
	local pose: Pose = {}
	local t = if clip and clip.Length > 0 then time % clip.Length else 0
	for name, rest in data.Rest do
		local track = clip and clip.Tracks[name]
		local p = if track and track.PT and track.P then at(track.PT, track.P, 3, t) else { rest[1], rest[2], rest[3] }
		local r = if track and track.RT and track.R then at(track.RT, track.R, 4, t) else { rest[4], rest[5], rest[6], rest[7] }
		-- Linear blending of quaternion keys: renormalise (CFrame.new does) for a valid rotation.
		local length = math.sqrt(r[1] * r[1] + r[2] * r[2] + r[3] * r[3] + r[4] * r[4])
		pose[name] = CFrame.new(p[1], p[2], p[3], r[1] / length, r[2] / length, r[3] / length, r[4] / length)
	end
	return pose
end

-- Moves `pose` toward `other` by `alpha` (0..1), in place.
function RigClips.blend(pose: Pose, other: Pose, alpha: number)
	if alpha <= 0 then
		return
	end
	for name, cf in pose do
		local target = other[name]
		if target then
			pose[name] = if alpha >= 1 then target else cf:Lerp(target, alpha)
		end
	end
end

-- Puts the bones in `pose`.
function RigClips.apply(rig: Rig, pose: Pose)
	local scale = rig.scale
	for name, bone in rig.bones do
		local cf = pose[name]
		if cf then
			bone.Transform = rig.bindInverse[name] * (cf - cf.Position + cf.Position * scale)
		end
	end
end

return RigClips
