--!strict
-- Welds a tool into a chosen hand. Roblox's automatic tool grip only uses the right hand
-- and plays its "holding a tool" arm pose, which fights custom weapon animations. Tools
-- using this set RequiresHandle = false and name their grip part GRIP_NAME instead of
-- "Handle", so Roblox does neither. The server attaches the real (replicated) weld; the
-- client adds a local one so the tool doesn't drop for a moment while the server's arrives.

local HandGrip = {}

export type Hand = "Left" | "Right"

HandGrip.GRIP_NAME = "GripPart"
-- A dual-wielded weapon's second grip part, held in the other hand (see CombatConfig DualWield).
HandGrip.OFFHAND_NAME = "OffhandGripPart"

-- The other hand.
function HandGrip.opposite(hand: Hand): Hand
	return if hand == "Left" then "Right" else "Left"
end

-- `gripName` picks which grip part to weld (GRIP_NAME unless given, e.g. OFFHAND_NAME).
function HandGrip.attach(tool: Tool, character: Model, hand: Hand, weldName: string, gripName: string?): Weld?
	local handPart = character:FindFirstChild(`{hand}Hand`)
	local attachment = handPart and handPart:FindFirstChild(`{hand}GripAttachment`)
	local grip = tool:FindFirstChild(gripName or HandGrip.GRIP_NAME)
	if
		not handPart
		or not handPart:IsA("BasePart")
		or not attachment
		or not attachment:IsA("Attachment")
		or not grip
		or not grip:IsA("BasePart")
	then
		return nil
	end

	local existing = grip:FindFirstChild(weldName)
	if existing then
		existing:Destroy()
	end
	-- Same offsets Roblox uses for its own tool grip.
	local weld = Instance.new("Weld")
	weld.Name = weldName
	weld.Part0 = handPart
	weld.Part1 = grip
	weld.C0 = attachment.CFrame
	weld.C1 = tool.Grip
	weld.Parent = grip
	return weld
end

-- Client side: weld the tool in locally right away (named "Local" .. serverWeldName), and
-- switch off the server's replicated weld on this client only, now or when it arrives.
-- That way the local weld alone holds the tool on this screen and can be adjusted (e.g. a
-- guard pose) without two welds fighting. Other players still see the server's weld.
function HandGrip.attachLocal(tool: Tool, character: Model, hand: Hand, serverWeldName: string, gripName: string?): Weld?
	local weld = HandGrip.attach(tool, character, hand, "Local" .. serverWeldName, gripName)
	local grip = tool:FindFirstChild(gripName or HandGrip.GRIP_NAME)
	if not weld or not grip then
		return weld
	end

	local function disableServerWeld(child: Instance)
		if child.Name == serverWeldName and child:IsA("Weld") then
			child.Enabled = false
		end
	end
	for _, child in grip:GetChildren() do
		disableServerWeld(child)
	end
	local connection = grip.ChildAdded:Connect(disableServerWeld)
	weld.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return weld
end

function HandGrip.detach(tool: Tool, weldName: string, gripName: string?)
	local grip = tool:FindFirstChild(gripName or HandGrip.GRIP_NAME)
	local weld = grip and grip:FindFirstChild(weldName)
	if weld then
		weld:Destroy()
	end
end

return HandGrip
