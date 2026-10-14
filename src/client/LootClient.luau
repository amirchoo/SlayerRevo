--!strict
-- Loot on the ground (workspace.Loot, from LootService): your own drops pop out of where the
-- animal fell, then hover there bobbing and turning with a soft glow; other players' loot is
-- hidden (each player gets their own). Walking close picks it up on the server, which tells
-- us (LootPickedUp remote): a copy flies into you and "+1 Cow Meat" floats up. Cooking uses
-- the same remote for the food coming out of the campfire (a ShopConfig consumable).
-- Looks only: the server decides what's dropped and who picks it up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MaterialConfig = require(ReplicatedStorage.Shared.Config.MaterialConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DamageNumbers = require(script.Parent.DamageNumbers)

local POP_TIME = 0.5 -- seconds to arc from where it fell to where it hovers
local POP_HEIGHT = 3 -- studs the arc rises
local BOB_HEIGHT = 0.25
local BOB_SPEED = 2.2 -- radians per second
local SPIN_SPEED = 1.6 -- radians per second
local TILT = math.rad(20) -- leaned back a little as it turns, so its face catches the light
local GLOW_COLOR = Color3.fromRGB(255, 225, 160)
local FLY_TIME = 0.3 -- seconds a picked-up item takes to fly into you
local POPUP_COLOR = Color3.fromRGB(255, 225, 160)

local pickedUpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LootPickedUp") :: RemoteEvent
local player = Players.LocalPlayer

local LootClient = {}

-- The name and model of a picked-up item: a material, or food from cooking.
local function itemInfo(itemId: string): (string?, string?)
	local material = MaterialConfig.item(itemId)
	if material then
		return material.Name, material.Model
	end
	local item = ShopConfig.item(itemId)
	if item then
		return item.Name, item.Model
	end
	return nil, nil
end

type Floating = { model: Model, rest: CFrame, from: Vector3, born: number, seed: number }
local floating: { [Model]: Floating } = {}
local random = Random.new()

local function setTransparency(model: Model, value: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = value
		end
	end
end

-- The model's biggest part, for the glow and sparkles.
local function largestPart(model: Model): BasePart?
	local best: BasePart?, bestSize = nil, -1
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Size.Magnitude > bestSize then
			best, bestSize = part, part.Size.Magnitude
		end
	end
	return best
end

local function addGlow(model: Model)
	local part = largestPart(model)
	if not part then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = GLOW_COLOR
	light.Brightness = 1
	light.Range = 7
	light.Parent = part
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(GLOW_COLOR)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.8, 1.2)
	sparkles.Rate = 4
	sparkles.Speed = NumberRange.new(0.6, 1.2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = part
end

local function watch(model: Model)
	if model:GetAttribute("Owner") ~= player.UserId then
		setTransparency(model, 1) -- someone else's
		return
	end
	local from = model:GetAttribute("From")
	floating[model] = {
		model = model,
		rest = model:GetPivot(),
		from = if typeof(from) == "Vector3" then from else model:GetPivot().Position,
		born = os.clock(),
		seed = random:NextNumber(0, math.pi * 2),
	}
	addGlow(model)
end

local function pose(item: Floating, now: number): CFrame
	local age = now - item.born
	local turn = CFrame.Angles(0, (now + item.seed) * SPIN_SPEED, 0) * CFrame.Angles(TILT, 0, 0)
	local rotation = item.rest.Rotation * turn
	if age < POP_TIME then
		-- Arcing out from where the animal fell.
		local t = age / POP_TIME
		local position = item.from:Lerp(item.rest.Position, t) + Vector3.new(0, math.sin(t * math.pi) * POP_HEIGHT, 0)
		return CFrame.new(position) * rotation
	end
	local bob = math.sin((now + item.seed) * BOB_SPEED) * BOB_HEIGHT
	return CFrame.new(item.rest.Position + Vector3.new(0, bob, 0)) * rotation
end

-- A copy of the picked-up item flying into the player, shrinking as it goes.
local function flyIn(itemId: string, from: Vector3)
	local _, modelName = itemInfo(itemId)
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	local source = if modelName and folder then folder:FindFirstChild(modelName) else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not source or not source:IsA("Model") or not root or not root:IsA("BasePart") then
		return
	end
	local copy = source:Clone()
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local _, size = copy:GetBoundingBox()
	local fullScale = copy:GetScale() * MaterialConfig.Loot.Size / math.max(size.X, size.Y, size.Z, 0.01)
	copy:ScaleTo(fullScale)
	copy:PivotTo(CFrame.new(from))
	copy.Parent = workspace
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - start) / FLY_TIME, 1)
		local eased = t * t
		local target = root.Position + Vector3.new(0, 1, 0)
		copy:ScaleTo(fullScale * math.max(1 - eased * 0.8, 0.05))
		copy:PivotTo(CFrame.new(from:Lerp(target, eased)) * CFrame.Angles(0, t * 6, 0))
		if t >= 1 then
			connection:Disconnect()
			copy:Destroy()
		end
	end)
end

function LootClient.start()
	local folder = workspace:WaitForChild("Loot")
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			watch(child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			floating[child] = nil
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			watch(child)
		end
	end

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, item in floating do
			item.model:PivotTo(pose(item, now))
		end
	end)

	pickedUpRemote.OnClientEvent:Connect(function(itemId: string, amount: number, position: Vector3)
		local name = itemInfo(itemId)
		flyIn(itemId, position)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if name and root and root:IsA("BasePart") then
			DamageNumbers.popup(root.Position + Vector3.new(0, 3, 0), `+{amount} {name}`, POPUP_COLOR)
		end
	end)
end

return LootClient
