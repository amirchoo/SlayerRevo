--!strict
-- Chat bubbles over villagers' heads (workspace.Villagers, from VillagerService): whenever a
-- villager's "SayCount" attribute changes, their "Say" line pops up in a bubble for a few
-- seconds. Looks only.

local TweenService = game:GetService("TweenService")

local SHOW_TIME = 4.5 -- seconds a bubble stays up
local MAX_DISTANCE = 60 -- studs: further away, bubbles aren't drawn
local BUBBLE = Color3.fromRGB(250, 245, 230)
local TEXT = Color3.fromRGB(45, 35, 30)

local VillagerChat = {}

local function bubble(model: Model, text: string)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("ChatBubble")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChatBubble"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = MAX_DISTANCE
	gui.AlwaysOnTop = false
	gui.Parent = head

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.AutomaticSize = Enum.AutomaticSize.None
	frame.BackgroundColor3 = BUBBLE
	frame.BackgroundTransparency = 0.05
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = TEXT
	label.Text = text
	label.Parent = frame
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = label

	-- Pop in, then fade out.
	frame.Size = UDim2.fromScale(0.6, 0.6)
	TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(SHOW_TIME, function()
		if gui.Parent then
			local fade = TweenInfo.new(0.4)
			TweenService:Create(frame, fade, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
			task.wait(0.4)
			gui:Destroy()
		end
	end)
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("SayCount"):Connect(function()
		local text = model:GetAttribute("Say")
		if typeof(text) == "string" then
			bubble(model, text)
		end
	end)
end

function VillagerChat.start()
	local folder = workspace:WaitForChild("Villagers")
	folder.ChildAdded:Connect(watch)
	for _, child in folder:GetChildren() do
		watch(child)
	end
end

return VillagerChat
