-- Studio Command Bar snippet: fits an imported armor set onto workspace.Rig and turns every
-- piece into an armor Accessory, ready to save (see assets/armor/README.md).
-- 1. Import <SET>ArmorSet.ready.glb (from tools/armor_glb.py) with Import 3D, mesh merging off.
-- 2. Have a blocky R15 rig named "Rig" in Workspace (Avatar > Rig Builder > Block).
-- 3. Set SET below and run this. It makes Workspace.<SET>Armor with one entry per slot:
--    Helmet, Chestplate (Accessories) and Armwear, Leggings, Boots (Models of Accessories).
-- Fitting, for models made to docs/model-brief.md's 5-stud character:
--   helmet, leggings, boots keep their designed height (leggings 0.1 up); leg pieces are made
--   at least 1.1 studs wide and centered on the rig's legs, so the leg can't poke through;
--   the chestplate keeps its top and is shortened to end at the waist; shoulder pads sit on
--   top of the upper arm (wide ones nudged outward, off the torso), bracers on the forearm.
local SET = "Woodcutter"

local WAIST = 1.9 -- studs above the feet where the chestplate should end
local LEG_WIDTH = 1.1

local rig = workspace:FindFirstChild("Rig")
assert(rig, "No Rig in Workspace: insert one with Avatar > Rig Builder (R15, Block) first")
local set = workspace:FindFirstChild(SET .. "ArmorSet.ready")
assert(set, "No " .. SET .. "ArmorSet.ready in Workspace: import it first")

local function piece(name: string): MeshPart?
	return set:FindFirstChild(name, true) :: MeshPart?
end
local function place(part: BasePart, position: Vector3)
	part.Anchored = true
	part.CFrame = CFrame.new(position)
end

-- Where the design's feet and center line are, and where the rig's are.
local boots = assert(piece("LeftBoots") or piece("RightBoots"), "the set has no boots to measure from")
local helmet = piece("Helmet")
local center = if helmet then helmet.Position else boots.Position
local designBase = Vector3.new(center.X, boots.Position.Y - boots.Size.Y / 2, center.Z)
local foot = rig.LeftFoot
local rigBase = Vector3.new(rig.UpperTorso.Position.X, foot.Position.Y - foot.Size.Y / 2, rig.UpperTorso.Position.Z)

if helmet then
	place(helmet, rigBase + (helmet.Position - designBase))
end
for _, side in { "Left", "Right" } do
	local legX = rig[side .. "UpperLeg"].Position.X
	for _, name in { side .. "Leggings", side .. "Boots" } do
		local part = piece(name)
		if part then
			local rel = part.Position - designBase
			if string.find(name, "Leggings") then
				rel += Vector3.new(0, 0.1, 0)
			end
			part.Size = Vector3.new(math.max(part.Size.X, LEG_WIDTH), part.Size.Y, math.max(part.Size.Z, LEG_WIDTH))
			place(part, Vector3.new(legX, rigBase.Y + rel.Y, rigBase.Z + rel.Z))
		end
	end
end
local chest = piece("Chestplate")
if chest then
	local top = (chest.Position - designBase).Y + chest.Size.Y / 2
	local height = math.min(chest.Size.Y, top - WAIST)
	chest.Size = Vector3.new(chest.Size.X, height, chest.Size.Z)
	local rel = chest.Position - designBase
	place(chest, rigBase + Vector3.new(rel.X, top - height / 2, rel.Z))
end
for _, side in { "Left", "Right" } do
	local upper, lower = rig[side .. "UpperArm"], rig[side .. "LowerArm"]
	local outward = if side == "Left" then -1 else 1 -- the rig's left arm is at -X
	local pad, bracer = piece(side .. "UpperArm"), piece(side .. "LowerArm")
	if pad then
		local nudge = math.max(0, (pad.Size.X - 1.2) / 2)
		place(pad, upper.Position + Vector3.new(nudge * outward, upper.Size.Y / 2 - pad.Size.Y / 2 + 0.08, 0))
	end
	if bracer then
		place(bracer, lower.Position + Vector3.new(0, -0.05, 0))
	end
end

-- Accessories: same steps as tools/make_armor_accessory.lua, one per piece.
local function makeAccessory(part: BasePart, bodyName: string, name: string): Accessory
	local body = rig[bodyName] :: BasePart
	local attachmentName = "Armor" .. bodyName
	local bodyAttachment = body:FindFirstChild(attachmentName) or Instance.new("Attachment")
	bodyAttachment.Name = attachmentName
	bodyAttachment.CFrame = CFrame.new()
	bodyAttachment.Parent = body
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Name = "Handle"
	local handleAttachment = Instance.new("Attachment")
	handleAttachment.Name = attachmentName
	handleAttachment.CFrame = part.CFrame:ToObjectSpace(body.CFrame)
	handleAttachment.Parent = part
	part:SetAttribute("FitSize", body.Size)
	local accessory = Instance.new("Accessory")
	accessory.Name = name
	part.Parent = accessory
	return accessory
end

local folder = Instance.new("Folder")
folder.Name = SET .. "Armor"
local function single(name: string, bodyName: string)
	local part = piece(name)
	if part then
		makeAccessory(part, bodyName, name).Parent = folder
	end
end
local function group(slot: string, entries: { { string } })
	local model = Instance.new("Model")
	model.Name = slot
	for _, entry in entries do
		local part = piece(entry[1])
		if part then
			makeAccessory(part, entry[2], entry[1]).Parent = model
		end
	end
	if #model:GetChildren() > 0 then
		model.Parent = folder
	end
end
single("Helmet", "Head")
single("Chestplate", "UpperTorso")
group("Armwear", { { "LeftUpperArm", "LeftUpperArm" }, { "LeftLowerArm", "LeftLowerArm" }, { "RightUpperArm", "RightUpperArm" }, { "RightLowerArm", "RightLowerArm" } })
group("Leggings", { { "LeftLeggings", "LeftUpperLeg" }, { "RightLeggings", "RightUpperLeg" } })
group("Boots", { { "LeftBoots", "LeftLowerLeg" }, { "RightBoots", "RightLowerLeg" } })
folder.Parent = workspace

local left = 0
for _, descendant in set:GetDescendants() do
	if descendant:IsA("BasePart") then
		left += 1
	end
end
if left == 0 then
	set:Destroy() -- only empty import models left
end
game:GetService("Selection"):Set({ folder })
print(`Fitted {SET}: {#folder:GetChildren()} slots in Workspace.{folder.Name}; right-click each slot > Save to File into assets/armor/{SET}/`)
