local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local FINAL_PLAYER = 'O'

local LOSS_PUNISH 	= 0.15
local DRAW_REWARD 	= 0.05
local WIN_REWARD 	= 0.25

local MIN_PROB = 0.05  -- never let a move reach 0, keep some exploration
local MAX_PROB = 0.95  -- never let a move reach 1, keep some exploration
local GAMMA = 0.9 -- scalar describing learning decay

local BasePlayer    = require('base-player')
local KnowledgeBase = require('knowledge-base')

local AgentMethods = {}
AgentMethods.__index = AgentMethods
setmetatable(AgentMethods, {__index = BasePlayer})

-------------------------------------------------------------------------------------
-- SYMMETRY UTILITIES ---------------------------------------------------------------
-------------------------------------------------------------------------------------
-- The board is 6x6, stored as a 1-indexed flat array (row-major).
-- Index mapping: idx -> row = (idx-1)//6,  col = (idx-1)%6
-- Inverse:       (row, col) -> idx = row*6 + col + 1
--
-- The 8 elements of D4 on a 6x6 grid are:
--   0: identity
--   1: rotate 90  clockwise      (r,c) -> (c, 5-r)
--   2: rotate 180                (r,c) -> (5-r, 5-c)
--   3: rotate 270 clockwise      (r,c) -> (5-c, r)
--   4: reflect horizontal axis   (r,c) -> (5-r, c)
--   5: reflect vertical axis     (r,c) -> (r, 5-c)
--   6: reflect main diagonal     (r,c) -> (c, r)
--   7: reflect anti-diagonal     (r,c) -> (5-c, 5-r)
-------------------------------------------------------------------------------------

local N = 6

local function transformRC(t, r, c)
    if     t == 0 then return r,       c
    elseif t == 1 then return c,       N-1-r
    elseif t == 2 then return N-1-r,   N-1-c
    elseif t == 3 then return N-1-c,   r
    elseif t == 4 then return N-1-r,   c
    elseif t == 5 then return r,       N-1-c
    elseif t == 6 then return c,       r
    elseif t == 7 then return N-1-c,   N-1-r
    end
end

local function idxToRC(idx)
    local i = idx - 1
    return i // N, i % N
end

local function rcToIdx(r, c)
    return r * N + c + 1
end

local function transformBoard(t, board)
    local out = {}
    for idx = 1, N * N do
        local r, c   = idxToRC(idx)
        local nr, nc = transformRC(t, r, c)
        out[rcToIdx(nr, nc)] = board[idx]
    end
    return out
end

local function transformIdx(t, idx)
    local r, c   = idxToRC(idx)
    local nr, nc = transformRC(t, r, c)
    return rcToIdx(nr, nc)
end

-- Inverse of each D4 element:
-- reflections are self-inverse; R90 and R270 swap.
local INVERSE_T = { [0]=0, [1]=3, [2]=2, [3]=1, [4]=4, [5]=5, [6]=6, [7]=7 }

-- Return the canonical (lex-smallest) board string across all 8 transforms,
-- along with the board table and the transform index that produced it.
local function canonicalize(board)
    local bestStr   = nil
    local bestT     = 0
    local bestBoard = nil

    for t = 0, 7 do
        local tb  = transformBoard(t, board)
        local str = table.concat(tb)
        if bestStr == nil or str < bestStr then
            bestStr   = str
            bestT     = t
            bestBoard = tb
        end
    end

    return bestBoard, bestStr, bestT
end

-- Map a canonical-board index back to the real board using the inverse transform.
local function unTransformIdx(appliedT, canonicalIdx)
    return transformIdx(INVERSE_T[appliedT], canonicalIdx)
end

-------------------------------------------------------------------------------------
-- COLOUR NORMALISATION -------------------------------------------------------------
-------------------------------------------------------------------------------------

local function XORBoard(board)
    local flipped = {}
    for _, c in pairs(board) do
        table.insert(flipped,
            (c == 'X' and 'O') or
            (c == 'O' and 'X') or '-')
    end
    return flipped
end

-------------------------------------------------------------------------------------
-- AGENT ----------------------------------------------------------------------------
-------------------------------------------------------------------------------------

function AgentMethods.new(xORo, filePath)
    KnowledgeBase.new(filePath)
    local player = BasePlayer.new(xORo)
    player.history = {}
    return setmetatable(player, AgentMethods)
end

local function BuildProbPair(idces)
    local result = {}
    local ratio  = 1 / #idces
    for _, c in ipairs(idces) do
        table.insert(result, { ["Idx"] = tonumber(c), ["Prob"] = tonumber(ratio) })
    end
    return result
end

function AgentMethods.GetMove(self, gameboard)
    -- 1. Normalise colour: always reason as O
    local colourBoard = (self.symbol ~= FINAL_PLAYER) and XORBoard(gameboard) or gameboard

    -- 2. Canonicalize over D4
    local canonBoard, canonStr, appliedT = canonicalize(colourBoard)

    -- 3. Register unseen canonical state
    if not KnowledgeBase.stateExists(canonStr) then
        local validIdcs = {}
        for i = 1, N * N do
            if self:IsValidMove(canonBoard, i, FINAL_PLAYER) then
                table.insert(validIdcs, i)
            end
        end

		if #validIdcs == 0 then
        	return -1  -- no valid moves; caller should not have invoked GetMove
    	end
        KnowledgeBase.addNewState(canonStr, BuildProbPair(validIdcs))
    end

        -- 4. Sample a move on the canonical board, restricted to currently valid moves.
    -- KB entries may include cells now occupied (state seen earlier when they were free).
    local validNow = {}
    local totalProb = 0
    for _, pair in ipairs(KnowledgeBase.data[canonStr]) do
        if self:IsValidMove(canonBoard, pair["Idx"], FINAL_PLAYER) then
            table.insert(validNow, pair)
            totalProb = totalProb + pair["Prob"]
        end
    end
 
    if #validNow == 0 then
        return -1  -- no valid moves; caller should not have invoked GetMove
    end
 
    local canonIdx = nil
    local rand = math.random() * totalProb
    for _, pair in ipairs(validNow) do
        if rand < pair["Prob"] then
            canonIdx = pair["Idx"]
            break
        end
        rand = rand - pair["Prob"]
    end

    if not canonIdx then
        canonIdx = validNow[#validNow]["Idx"]
    end

    -- 5. Map canonical index back to the real board
    local realIdx = unTransformIdx(appliedT, canonIdx)

    -- 6. Store canonical state + canonical index for EndGame credit
    table.insert(self.history, { state = canonStr, idx = canonIdx })

    return realIdx
end

function AgentMethods.AdjustProb(self, pairs, targetIdx, delta)
    for _, pair in ipairs(pairs) do
        if pair["Idx"] == targetIdx then
            pair["Prob"] = pair["Prob"] + delta
            break
        end
    end

    local total = 0
    for _, pair in ipairs(pairs) do 
		total = total + pair["Prob"] 
	end

    for _, pair in ipairs(pairs) do 
		pair["Prob"] = pair["Prob"] / total
	end

    local clampTotal, clampedCount = 0, 0
    for _, pair in ipairs(pairs) do
        if pair["Prob"] < MIN_PROB then
            pair["Prob"] = MIN_PROB; clampedCount = clampedCount + 1
        elseif pair["Prob"] > MAX_PROB then
            pair["Prob"] = MAX_PROB; clampedCount = clampedCount + 1
        end

        clampTotal = clampTotal + pair["Prob"]
    end

    if clampedCount > 0 then
        for _, pair in ipairs(pairs) do 
			pair["Prob"] = pair["Prob"] / clampTotal 
		end
    end
end

function AgentMethods.EndGame(self, status)
    if status == 1 then self.winCount = self.winCount + 1 end

    local factor =
        (status ==  1 and  WIN_REWARD)  or
        (status ==  0 and  DRAW_REWARD) or
        (status == -1 and -LOSS_PUNISH) or
        error("BAD STATUS: " .. tostring(status))

    local n = #self.history
    for i, move in ipairs(self.history) do
        local discount = GAMMA ^ (n - i)
        local pairs    = KnowledgeBase.data[move.state]
        if pairs then
            self:AdjustProb(pairs, move.idx, factor * discount)
        end
    end

    self.history = {}
end

function AgentMethods.StopPlaying(self)
    KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)
