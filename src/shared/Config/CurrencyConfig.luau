--!strict
-- Currency tuning: starting values, colors, and formatting helpers.

local CurrencyConfig = {}

CurrencyConfig.StartingCoins = 0
CurrencyConfig.CoinName = "Coins"
CurrencyConfig.Color = Color3.fromRGB(255, 215, 65)
CurrencyConfig.DarkColor = Color3.fromRGB(200, 150, 40)
CurrencyConfig.TextColor = Color3.fromRGB(255, 235, 140)

-- Formats a number with comma separators (e.g. 1250 -> "1,250").
function CurrencyConfig.format(amount: number): string
	local formatted = tostring(math.max(0, math.floor(amount)))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

return CurrencyConfig
