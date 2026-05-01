local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local FINAL_PLAYER = 'O'

local LOSS_PUNISH 	= 0.1
local DRAW_REWARD 	= 0.05
local WIN_REWARD 	= 0.2

local MIN_PROB = 0.001  -- never let a move reach 0, keep some exploration
local MAX_PROB = 0.99  -- never let a move reach 1, keep some exploration
local GAMMA = 0.9 -- scalar describing learning decay

local EPSILON_START = 0.25 -- start: 25% random exploration
local EPSILON_MIN = 0.05   -- floor: always keep 5% exploration
-- to calculate the EPSILON_DECAY such that EPSILON hits the minimum by a specific number of games
-- use this formula
--      decay = (EPSILON_MIN / EPSILON) * (1/number of games you want the EPSILON to hit min by)
local EPSILON_DECAY = 0.999996  -- scalar describing exploration decay


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
        -- source cell (r,c) moves TO destination (nr,nc)
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
            c == 'X' and 'O' or
            c == 'O' and 'X' or '-')
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
    player.epsilon = EPSILON_START
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

    -- 2. Find valid moves on the colour-normalised board BEFORE canonicalizing.
    --    D4 transforms do not preserve move validity (a move that flips pieces
    --    in one orientation may flip nothing after rotation), so we must validate
    --    on the real board and then map indices into canonical space.
    local validRealIdcs = {}
    for i = 1, N * N do
        if self:IsValidMove(colourBoard, i, FINAL_PLAYER) then
            table.insert(validRealIdcs, i)
        end
    end

    if #validRealIdcs == 0 then
        error("GetMove called with no valid moves on board: " .. table.concat(colourBoard))
        --return -1  -- no valid moves; caller should not have invoked GetMove
    end

    -- 3. Canonicalize over D4
    local canonBoard, canonStr, appliedT = canonicalize(colourBoard)

    -- 4. Map valid real indices into canonical space for KB lookup/storage.
    local validCanonIdcs = {}
    for _, realI in ipairs(validRealIdcs) do
        table.insert(validCanonIdcs, transformIdx(appliedT, realI))
    end

    -- 5. Register unseen canonical state using canonical-space indices.
    if not KnowledgeBase.stateExists(canonStr) then
        KnowledgeBase.addNewState(canonStr, BuildProbPair(validCanonIdcs))
    end

    -- 6. Sample from KB, but restrict to moves that are valid RIGHT NOW
    --    (a prior visit may have stored indices that are now occupied).
    local validCanonSet = {}
    for _, ci in ipairs(validCanonIdcs) do
        validCanonSet[ci] = true
    end

    local validNow = {}
    local totalProb = 0
    for _, pair in ipairs(KnowledgeBase.data[canonStr]) do
        if validCanonSet[pair["Idx"]] then
            table.insert(validNow, pair)
            totalProb = totalProb + pair["Prob"]
        end
    end

    if #validNow == 0 then
        local realI  = validRealIdcs[math.random(#validRealIdcs)]
        local canonI = transformIdx(appliedT, realI)
        table.insert(self.history, { state = canonStr, idx = canonI })
        return realI
        --return -1  -- safety fallback
    end

    local canonIdx = nil
    if math.random() < self.epsilon then
        -- explore
        local candidates = {}
        for _, pair in ipairs(validNow) do
            if pair.Prob > 0 then
                table.insert(candidates, pair.Idx)
            end
        end
        canonIdx = candidates[math.random(#candidates)]
    else
        -- exploit
        local bestProb = -math.huge
        local bestIdcs = {}                                                                                                          
        for _, pair in ipairs(validNow) do
            if pair.Prob > bestProb then
                bestProb = pair.Prob                                                                                       
                bestIdcs = { pair.Idx }                                                                                         
            elseif pair.Prob == bestProb then                                                                                        
                table.insert(bestIdcs, pair.Idx)                                                                                   
            end
        end
        
        canonIdx = bestIdcs[math.random(#bestIdcs)] 
    end

    -- 7. Map chosen canonical index back to the real (colour-normalised) board.
    local realIdx = unTransformIdx(appliedT, canonIdx)

    -- 8. Store canonical state + canonical index for EndGame credit.
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
    for _, pair in ipairs(pairs) do total = total + pair["Prob"] end
    for _, pair in ipairs(pairs) do pair["Prob"] = pair["Prob"] / total end

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
        for _, pair in ipairs(pairs) do pair["Prob"] = pair["Prob"] / clampTotal end
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
    self.epsilon = math.max(EPSILON_MIN, self.epsilon * EPSILON_DECAY)
end

function AgentMethods.StopPlaying(self)
    KnowledgeBase.pruneUnlearned()
    KnowledgeBase.showStatesFound()
	KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)
