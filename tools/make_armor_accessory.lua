-- Studio Command Bar snippet: turns the selected parts into an armor Accessory.
-- 1. Build the piece out of parts (or MeshParts) right where it should sit on workspace.Rig.
-- 2. Set BODY_PART (the body part it moves with) and NAME below.
-- 3. Select the piece's parts (or the Model holding them) and run this in the Command Bar.
-- The parts stay anchored here so nothing falls while you save; the game unanchors them.
local BODY_PART = "Head" -- Head, UpperTorso, LowerTorso, Left/RightUpperArm, Left/RightLowerArm,
-- Left/RightHand, Left/RightUpperLeg, Left/RightLowerLeg, Left/RightFoot
local NAME = "Helmet" -- the slot (Helmet, Chestplate, ...), or e.g. LeftBoot for one of a pair

local rig = workspace:FindFirstChild("Rig")
assert(rig, "No Rig in Workspace: insert one with Avatar > Rig Builder (R15) first")
local body = rig:FindFirstChild(BODY_PART)
assert(body and body:IsA("BasePart"), "The Rig has no body part called " .. BODY_PART)

local parts, seen = {}, {}
local function add(part)
	if part:IsA("BasePart") and not seen[part] then
		seen[part] = true
		table.insert(parts, part)
	end
end
for _, item in game:GetService("Selection"):Get() do
	add(item)
	for _, descendant in item:GetDescendants() do
		add(descendant)
	end
end
assert(#parts > 0, "Select the piece's parts first")

-- The body part's anchor point (the game adds the same one to every player).
local attachmentName = "Armor" .. BODY_PART
local bodyAttachment = body:FindFirstChild(attachmentName) or Instance.new("Attachment")
bodyAttachment.Name = attachmentName
bodyAttachment.CFrame = CFrame.new()
bodyAttachment.Parent = body

-- The first part becomes the Handle; the rest are welded to it, keeping where they are.
local handle = parts[1]
for _, part in parts do
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	if part ~= handle then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
		part.Parent = handle
	end
end
handle.Name = "Handle"
local handleAttachment = Instance.new("Attachment")
handleAttachment.Name = attachmentName
handleAttachment.CFrame = handle.CFrame:ToObjectSpace(body.CFrame) -- lines up with the body part, so the piece stays exactly where you placed it
handleAttachment.Parent = handle

local accessory = Instance.new("Accessory")
accessory.Name = NAME
handle.Parent = accessory
accessory.Parent = workspace
game:GetService("Selection"):Set({ accessory })
print("Made Accessory", NAME, "attached to", BODY_PART, "- right-click it > Save to File")
