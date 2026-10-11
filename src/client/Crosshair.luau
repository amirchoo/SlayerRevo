--!strict
-- Minecraft-style "+" crosshair that replaces the mouse cursor while a weapon is equipped.
-- It sits exactly at the mouse position, which is where the bow aims (see BowClient).
-- The normal cursor comes back when no tool is out or the Roblox menu is open.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LENGTH = 20 -- pixels, end to end
local THICKNESS = 2
local OUTLINE = 1 -- dark edge so it reads on bright backgrounds
local COLOR = Color3.new(1, 1, 1)
local OUTLINE_COLOR = Color3.new(0, 0, 0)
local OUTLINE_TRANSPARENCY = 0.6

local player = Players.LocalPlayer

local Crosshair = {}

local function bar(parent: Frame, size: Vector2, color: Color3, transparency: number, zIndex: number)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
end

local function createCrosshair(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- so pixel positions match UserInputService:GetMouseLocation()
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(LENGTH + OUTLINE * 2, LENGTH + OUTLINE * 2)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	-- Outline bars underneath, white bars on top, so the center of the + stays clean.
	local edge = OUTLINE * 2
	bar(holder, Vector2.new(LENGTH + edge, THICKNESS + edge), OUTLINE_COLOR, OUTLINE_TRANSPARENCY, 1)
	bar(holder, Vector2.new(THICKNESS + edge, LENGTH + edge), OUTLINE_COLOR, OUTLINE_TRANSPARENCY, 1)
	bar(holder, Vector2.new(LENGTH, THICKNESS), COLOR, 0, 2)
	bar(holder, Vector2.new(THICKNESS, LENGTH), COLOR, 0, 2)

	return holder
end

local function weaponEquipped(): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChildOfClass("Tool") ~= nil
end

function Crosshair.start()
	local holder = createCrosshair()

	RunService.RenderStepped:Connect(function()
		local show = weaponEquipped() and UserInputService.MouseEnabled and not GuiService.MenuIsOpen
		holder.Visible = show
		UserInputService.MouseIconEnabled = not show
		if show then
			local mouse = UserInputService:GetMouseLocation()
			holder.Position = UDim2.fromOffset(math.round(mouse.X), math.round(mouse.Y))
		end
	end)
end

return Crosshair
