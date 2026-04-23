local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local PlayerMethods = {}
PlayerMethods.__index = PlayerMethods

---comment
---@param xORo boolean
---@return table
function PlayerMethods.new(xORo)
	local self = {
		symbol = xORo,
		winCount = 0,
	}

	return setmetatable(self, PlayerMethods)
end

local function Flips(board, index, step, symbol)
	local other = (symbol == 'X') and 'O' or 'X'

	-- is an opponent's piece in first spot that way?
	local here = index + step
	if here < 1 or here > 36 or board[here] ~= other then
		return false
	end
		
	if math.abs(step) == 1  then -- moving left or right along row
		while (here - 1) // 6 == (index - 1) // 6 and board[here] == other do
			here = here + step
		end

		-- are we still on the same row and did we find a matching endpiece?
		return (here - 1) // 6 == (index - 1) // 6 
			and here > 0 and here <= 36
			and board[here] == symbol
	else -- moving up or down (possibly with left/right tilt)
		while here > 0 and here <= 36 and board[here] == other do
			here = here + step
		end
		-- are we still on the board and did we find a matching endpiece?
		return here > 0 and here <= 36 and board[here] == symbol
	end
end
---comment
---@param self table
---@param board table<number, string>
---@param idx number
---@return boolean
function PlayerMethods.IsValidMove(self, board, idx, symbol)
    if idx < 1 or idx > 36 then
		return false
	end
          
	if board[idx] ~= '-' then
		return false
	end

	-- otherwise, check for flipping pieces
    local row = (idx - 1) // 6
	local col = (idx - 1)  % 6

	local up    = row > 0
	local down  = row < 5
	local left  = col > 0
	local right = col < 5

	return (
		   (left 		   and Flips(board, idx, -1, symbol)) -- left
		or (up   and left  and Flips(board, idx, -7, symbol)) -- up/left
		or (up             and Flips(board, idx, -6, symbol)) -- up
		or (up   and right and Flips(board, idx, -5, symbol)) -- up/right
		or (         right and Flips(board, idx,  1, symbol)) -- right
		or (down and right and Flips(board, idx,  7, symbol)) --down/right
		or (down           and Flips(board, idx,  6, symbol)) -- down
		or (down and left  and Flips(board, idx,  5, symbol)) -- down/left
	)
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