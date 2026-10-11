--!strict
-- Keeps the full-screen panels (backpack, skills) to one at a time: opening one closes the
-- others, and the hotbar hides while any is open.

local Hotbar = require(script.Parent.Hotbar)

local Panels = {}

local closers: { [string]: () -> () } = {}
local openPanel: string? = nil

-- `close` closes the panel called `name` (it should then call Panels.closed).
function Panels.register(name: string, close: () -> ())
	closers[name] = close
end

function Panels.opened(name: string)
	for other, close in closers do
		if other ~= name then
			close()
		end
	end
	openPanel = name
	Hotbar.setHidden(true)
end

function Panels.closed(name: string)
	if openPanel == name then
		openPanel = nil
		Hotbar.setHidden(false)
	end
end

return Panels
