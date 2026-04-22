local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local PlayerMethods = {}
PlayerMethods.__index = PlayerMethods

---comment
---@param isX boolean
---@return table
function PlayerMethods.new(isX)
	local self = {
		symbol = isX and 'X' or 'O',
		winCount = 0,
	}

	return setmetatable(self, PlayerMethods)
end

---comment
---@param self table
---@param gameboard table
---@return integer
function PlayerMethods.GetMove(self, gameboard)
    return 1
end

function PlayerMethods.EndGame(self, status, gameboard)
	if status == 1 then
		self.winCount = self.winCount + 1
	end
end

function PlayerMethods.StopPlaying(self)
	return 1
end

return tHelp.freeze(PlayerMethods)