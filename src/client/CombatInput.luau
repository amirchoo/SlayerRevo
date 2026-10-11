--!strict
-- The one place combat input comes from, so every device fights the same way. Weapons and
-- the dash listen to these events instead of reading the mouse or keyboard themselves:
--   Attack (held): left mouse button, or the touch Attack button
--   Block (held): right mouse button, or the touch Block button
--   Dash: the dash key (V), or the touch Dash button
--   Lock: the lock-on key (Q), or the touch Lock button (toggles the lock-on)
-- The touch buttons (TouchControls) call press/release directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

export type Action = "Attack" | "Block" | "Dash" | "Lock"

local CombatInput = {}

local attackBegan = Instance.new("BindableEvent")
local attackEnded = Instance.new("BindableEvent")
local blockBegan = Instance.new("BindableEvent")
local blockEnded = Instance.new("BindableEvent")
local dash = Instance.new("BindableEvent")
local lock = Instance.new("BindableEvent")
CombatInput.AttackBegan = attackBegan.Event
CombatInput.AttackEnded = attackEnded.Event
CombatInput.BlockBegan = blockBegan.Event
CombatInput.BlockEnded = blockEnded.Event
CombatInput.Dash = dash.Event
CombatInput.Lock = lock.Event

local held: { [string]: boolean } = {}

function CombatInput.press(action: Action)
	if action == "Dash" then
		dash:Fire()
		return
	elseif action == "Lock" then
		lock:Fire()
		return
	end
	if held[action] then
		return
	end
	held[action] = true
	if action == "Attack" then
		attackBegan:Fire()
	else
		blockBegan:Fire()
	end
end

function CombatInput.release(action: Action)
	if not held[action] then
		return
	end
	held[action] = false
	if action == "Attack" then
		attackEnded:Fire()
	elseif action == "Block" then
		blockEnded:Fire()
	end
end

function CombatInput.isHeld(action: Action): boolean
	return held[action] == true
end

function CombatInput.start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return -- e.g. clicking a button or typing in chat
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatInput.press("Attack")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			CombatInput.press("Block")
		elseif input.KeyCode == CombatConfig.Dash.Key then
			CombatInput.press("Dash")
		elseif input.KeyCode == CombatConfig.LockOn.Key then
			CombatInput.press("Lock")
		end
	end)
	-- Releases count even over a button, so nothing gets stuck held.
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatInput.release("Attack")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			CombatInput.release("Block")
		end
	end)
end

return CombatInput
