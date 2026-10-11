--!strict
-- Level and XP on the HUD: an XP bar across the top centre of the screen, with the
-- level next to it, "+N XP" when you defeat something (floating up where it fell, and next
-- to the bar), and a "LEVEL UP!" popup (LevelUp remote) telling you how many skill
-- points you've gained. Display only: reads the "Level", "XP", and "XPToNext" attributes the
-- server sets (see ProgressionService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DamageNumbers = require(script.Parent.DamageNumbers)
local HudStyle = require(script.Parent.HudStyle)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local WIDTH = 460
local HEIGHT = 12
local TOP = 14 -- from the top of the screen (below Roblox's top bar)
local XP_COLOR = Color3.fromRGB(150, 110, 220)
local POPUP_TIME = 2.2

local levelUpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LevelUp") :: RemoteEvent
local xpRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("XPGained") :: RemoteEvent
local XP_TEXT_COLOR = Color3.fromRGB(200, 160, 255)
local player = Players.LocalPlayer

local ProgressionHud = {}

function ProgressionHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProgressionHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, TOP)
	bar.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	bar.BackgroundColor3 = HudStyle.EMPTY
	bar.Parent = HudStyle.holder(gui, Vector2.new(0.5, 0)) -- shrinks toward the top centre
	HudStyle.chunky(bar, 6, 2.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = XP_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = fill
	HudStyle.gloss(fill)
	-- The level, in a purple badge at the bar's left end.
	local badge = HudStyle.badge(bar, 40, XP_COLOR, "")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0, -4, 0.5, 0)
	badge.ZIndex = 2
	local level = HudStyle.caption(badge, "", 18)
	level.Size = UDim2.fromScale(1, 1)
	level.ZIndex = 3
	local caption = HudStyle.caption(bar, "LEVEL", 11)
	caption.AnchorPoint = Vector2.new(0, 1)
	caption.Position = UDim2.new(0, 22, 0, -1)
	caption.Size = UDim2.fromOffset(60, 12)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = Color3.fromRGB(210, 190, 240)

	local function update()
		local lvl = player:GetAttribute("Level")
		local xp = player:GetAttribute("XP")
		local toNext = player:GetAttribute("XPToNext")
		level.Text = if typeof(lvl) == "number" then tostring(lvl) else ""
		if typeof(xp) == "number" and typeof(toNext) == "number" and toNext > 0 then
			TweenService:Create(fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(math.clamp(xp / toNext, 0, 1), 1) }):Play()
		else
			fill.Size = UDim2.fromScale(1, 1)
		end
	end
	for _, attribute in { "Level", "XP", "XPToNext" } do
		player:GetAttributeChangedSignal(attribute):Connect(update)
	end
	update()

	-- "+N XP": floating up from what you defeated, and flashed next to the bar.
	local gain = HudStyle.caption(bar, "", 16)
	gain.AnchorPoint = Vector2.new(0, 0.5)
	gain.Position = UDim2.new(1, 8, 0.5, 0)
	gain.Size = UDim2.fromOffset(90, 18)
	gain.TextXAlignment = Enum.TextXAlignment.Left
	gain.TextColor3 = XP_TEXT_COLOR
	gain.TextTransparency = 1
	Instance.new("UIScale").Parent = gain
	local gainTotal, gainToken = 0, 0
	xpRemote.OnClientEvent:Connect(function(position: Vector3, amount: number)
		DamageNumbers.popup(position, `+{amount} XP`, XP_TEXT_COLOR)
		-- Kills close together add up on the bar's counter.
		gainToken += 1
		local mine = gainToken
		gainTotal += amount
		gain.Text = `+{gainTotal} XP`
		gain.TextTransparency = 0
		local stroke = gain:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
		HudStyle.pop(gain, 1.3)
		task.delay(1.6, function()
			if mine == gainToken then
				gainTotal = 0
				local fade = TweenInfo.new(0.5)
				TweenService:Create(gain, fade, { TextTransparency = 1 }):Play()
				if stroke then
					TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
				end
			end
		end)
	end)

	-- The popup.
	local popup = HudStyle.caption(HudStyle.holder(gui, Vector2.new(0.5, 0.5)), "", 46)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.3)
	popup.Size = UDim2.fromOffset(600, 60)
	popup.TextColor3 = Color3.fromRGB(255, 215, 90)
	popup.Visible = false
	Instance.new("UIScale").Parent = popup
	local subtitle = HudStyle.caption(popup, "", 20)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 1, 0)
	subtitle.Size = UDim2.fromOffset(600, 26)
	local token = 0
	levelUpRemote.OnClientEvent:Connect(function(newLevel: number, points: number)
		token += 1
		local mine = token
		popup.Text = "LEVEL UP!"
		subtitle.Text = `Level {newLevel}  ·  +{points} skill point{if points == 1 then "" else "s"}  (press K)`
		popup.TextTransparency, subtitle.TextTransparency = 0, 0
		popup.Visible = true
		HudStyle.pop(popup, 1.4)
		Sounds.play("ChargeLevel", workspace.CurrentCamera, 1.8)
		task.delay(POPUP_TIME, function()
			if mine == token then
				local fade = TweenInfo.new(0.4)
				TweenService:Create(popup, fade, { TextTransparency = 1 }):Play()
				TweenService:Create(subtitle, fade, { TextTransparency = 1 }):Play()
				task.delay(0.4, function()
					if mine == token then
						popup.Visible = false
					end
				end)
			end
		end)
	end)
end

return ProgressionHud
