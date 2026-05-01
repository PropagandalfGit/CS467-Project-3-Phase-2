local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local PlayerMethods = {}
PlayerMethods.__index = PlayerMethods

local function CountFlipsInDir(board, idx, step, symbol, rowEdgeCheck)
	local opp = symbol == 'X' and 'O' or 'X'
	local count = 0
	local pos = idx + step
	while pos >= 1 and pos <= 36 and board[pos] == opp do
		count = count + 1
		pos = pos + step
	end
	-- only counts if terminated by own piece (not edge or empty)
	if pos >= 1 and pos <= 36 and board[pos] == symbol and count > 0 then
		return count
	end
	return 0
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
---@param xORo boolean
---@return table
function PlayerMethods.new(xORo)
	local self = {
		symbol = xORo,
		winCount = 0,
	}

	return setmetatable(self, PlayerMethods)
end

function PlayerMethods.CountFlips(self, board, idx, symbol)
	local row = (idx - 1) // 6
	local col = (idx - 1) %  6
	local up, down  = row > 0, row < 5
	local left, right = col > 0, col < 5

	local total = 0
	if left              then total = total + CountFlipsInDir(board, idx, -1, symbol) end
	if up   and left     then total = total + CountFlipsInDir(board, idx, -7, symbol) end
	if up                then total = total + CountFlipsInDir(board, idx, -6, symbol) end
	if up   and right    then total = total + CountFlipsInDir(board, idx, -5, symbol) end
	if right             then total = total + CountFlipsInDir(board, idx,  1, symbol) end
	if down and right    then total = total + CountFlipsInDir(board, idx,  7, symbol) end
	if down              then total = total + CountFlipsInDir(board, idx,  6, symbol) end
	if down and left     then total = total + CountFlipsInDir(board, idx,  5, symbol) end
	return total
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