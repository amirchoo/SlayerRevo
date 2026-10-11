--!strict
-- Floating damage numbers above things you hit. Display only: the server reports
-- the damage it actually dealt (see WeaponService).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LIFETIME = 0.9
local RISE = 3 -- studs the number floats up
local JITTER = 1.5 -- random sideways offset so rapid hits don't stack exactly
local COLOR = Color3.fromRGB(255, 225, 90)
local KIND_COLORS: { [string]: Color3 } = {
	Bleed = Color3.fromRGB(230, 50, 50),
	Burn = Color3.fromRGB(255, 140, 40),
	Heal = Color3.fromRGB(110, 235, 120),
}

local damageRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt") :: RemoteEvent

local DamageNumbers = {}

local random = Random.new()

-- Floating text that rises and fades at `position`. Also used for other popups (e.g. "BLOCKED").
function DamageNumbers.popup(position: Vector3, text: string, color: Color3?)
	local anchor = Instance.new("Attachment")
	anchor.Parent = workspace.Terrain
	anchor.WorldPosition = position + Vector3.new(random:NextNumber(-JITTER, JITTER), 0, random:NextNumber(-JITTER, JITTER))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(100, 40)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 28
	label.TextColor3 = color or COLOR
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, RISE, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(LIFETIME * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, LIFETIME * 0.5), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, LIFETIME)
end

function DamageNumbers.start()
	-- `kind` (optional): "Bleed" or "Burn" for damage over time, "Heal" for healing (shown as
	-- "+N" in green). (A 4th argument, the model hit, is for HitFeel's hitstop.)
	damageRemote.OnClientEvent:Connect(function(position: Vector3, amount: number, kind: string?)
		local text = if kind == "Heal" then `+{math.round(amount)}` else tostring(math.round(amount))
		DamageNumbers.popup(position, text, if kind then KIND_COLORS[kind] else nil)
	end)
end

return DamageNumbers
