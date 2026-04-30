local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local FINAL_PLAYER = 'O'

local LOSS_PUNISH   = 0.1
local DRAW_REWARD   = 0.05
local WIN_REWARD    = 0.2

local MIN_PROB = 0.001
local MAX_PROB = 0.99
local GAMMA    = 0.9

local BasePlayer    = require('base-player')
local KnowledgeBase = require('knowledge-base')

local AgentMethods = {}
AgentMethods.__index = AgentMethods
setmetatable(AgentMethods, {__index = BasePlayer})

local N = 6

-------------------------------------------------------------------------------------
-- COLOUR NORMALISATION -------------------------------------------------------------
-------------------------------------------------------------------------------------

local function XORBoard(board)
    local flipped = {}
    for _, c in ipairs(board) do
        table.insert(flipped,
            c == 'X' and 'O' or
            c == 'O' and 'X' or '-')
    end
    return flipped
end

-------------------------------------------------------------------------------------
-- FEATURE EXTRACTION ---------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Instead of the raw board string, we describe the board with 5 cheap features.
-- Two boards with the same strategic situation share one KB entry and pool
-- their learning signal.
--
-- Features (all from O's perspective, after colour normalisation):
--   1. game_phase    : how full the board is (3 buckets)
--   2. piece_diff    : O_count - X_count, bucketed (5 buckets)
--   3. corner_diff   : O_corners - X_corners, exact (-4..4, 9 values)
--   4. frontier_diff : O_frontier - X_frontier, bucketed (3 buckets)
--   5. edge_diff     : O_edge - X_edge pieces, bucketed (3 buckets)
--
-- Total: 3 * 5 * 9 * 3 * 3 = 1,215 possible states
-- All features are O(n) scans — no validity checking, no inner loops per cell.
-- Mobility was removed: it required 72 IsValidMove calls per GetMove invocation,
-- making the loop in reversi.py extremely slow on boards with many empty cells.
-- Edge control is a good cheap proxy for mobility (edge pieces limit opponent moves).
-------------------------------------------------------------------------------------

-- Corner and edge indices on a 6x6 board (1-indexed)
local CORNERS = { 1, 6, 31, 36 }
-- Edge cells = top/bottom rows + left/right cols, excluding corners
local EDGES = { 2,3,4,5, 32,33,34,35, 7,13,19,25, 12,18,24,30 }

local CORNER_SET   = { [1]=true, [6]=true, [31]=true, [36]=true }
local X_SQUARE_SET = { [8]=true, [11]=true, [26]=true, [29]=true }
local C_SQUARE_SET = { [2]=true, [5]=true, [7]=true, [12]=true,
						[25]=true, [30]=true, [32]=true, [35]=true }

local MOVE_TYPES = {
	"corner",        -- the move IS a corner (positions 1, 6, 31, 36 1-indexed)
	"x_square",      -- diagonal-adjacent to a corner (8, 11, 26, 29)
	"c_square",      -- edge-adjacent to a corner (2, 5, 7, 12, 25, 30, 32, 35)
	"safe_edge",     -- on an edge, not a c_square
	"low_flip",      -- interior, flips ≤ 2 pieces
	"high_flip",     -- interior, flips ≥ 3 pieces
}

local function bucket(val, thresholds, labels)
    for i, t in ipairs(thresholds) do
        if val <= t then return labels[i] end
    end
    return labels[#labels]
end

local function countFrontier(board, symbol)
    -- Frontier: pieces of `symbol` adjacent to at least one empty cell (unstable).
    local STEPS = { -7, -6, -5, -1, 1, 5, 6, 7 }
    local count = 0
    for i, c in ipairs(board) do
        if c == symbol then
            for _, step in ipairs(STEPS) do
                local nb = i + step
                if nb >= 1 and nb <= N * N and board[nb] == '-' then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

---@param board table  colour-normalised 1-indexed board
---@return string      feature key
local function extractFeatures(board)
    local oCount, xCount = 0, 0
    local oCorners, xCorners = 0, 0
    local oEdges, xEdges = 0, 0

    -- Single pass: piece counts
    for _, c in ipairs(board) do
        if     c == 'O' then oCount = oCount + 1
        elseif c == 'X' then xCount = xCount + 1 end
    end
    local total = oCount + xCount

    -- Corner counts
    for _, ci in ipairs(CORNERS) do
        if     board[ci] == 'O' then oCorners = oCorners + 1
        elseif board[ci] == 'X' then xCorners = xCorners + 1 end
    end

    -- Edge counts
    for _, ei in ipairs(EDGES) do
        if     board[ei] == 'O' then oEdges = oEdges + 1
        elseif board[ei] == 'X' then xEdges = xEdges + 1 end
    end

    -- 1. Game phase
    local phase = bucket(total, { 16, 28, N*N }, { "early", "mid", "late" })

    -- 2. Piece differential (O - X), bucketed
    local pieceDiff = bucket(oCount - xCount,
        { -6, -2, 2, 6, math.huge },
        { "lose_big", "lose", "close", "win", "win_big" })

    -- 3. Corner differential, exact (-4..4)
    local cornerDiff = tostring(oCorners - xCorners)

    -- 4. Frontier differential, bucketed (fewer frontier pieces = more stable = better)
    local oFrontier = countFrontier(board, 'O')
    local xFrontier = countFrontier(board, 'X')
    local frontDiff = bucket(oFrontier - xFrontier,
        { -3, 3, math.huge },
        { "stable", "even", "exposed" })

    -- 5. Edge differential, bucketed
    local edgeDiff = bucket(oEdges - xEdges,
        { -3, 3, math.huge },
        { "behind", "even", "ahead" })

    return table.concat({phase, pieceDiff, cornerDiff, frontDiff, edgeDiff}, "|")
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

function AgentMethods.ClassifyMove(self, board, idx, symbol)
	if CORNER_SET[idx]   then return "corner"   end
	if X_SQUARE_SET[idx] then return "x_square" end
	if C_SQUARE_SET[idx] then return "c_square" end

	local row = (idx - 1) // 6
	local col = (idx - 1) % 6
	if row == 0 or row == 5 or col == 0 or col == 5 then
		return "safe_edge"
	end

	local flipped = self:CountFlips(board, idx, symbol)  -- you need this; reuse Flips logic
	return flipped <= 2 and "low_flip" or "high_flip"
end

function AgentMethods.GetMove(self, gameboard)
    -- 1. Normalise colour: always reason as O
    local colourBoard = (self.symbol ~= FINAL_PLAYER) and XORBoard(gameboard) or gameboard

    -- 2. Find valid moves on the colour-normalised board
    local validIdcs = {}
    for i, _ in ipairs(colourBoard) do
        if self:IsValidMove(colourBoard, i, FINAL_PLAYER) then
            table.insert(validIdcs, i)
        end
    end

    if #validIdcs == 0 then
        return -1  -- no valid moves; caller should not have invoked GetMove
    end

    -- 3. Build feature key (orientation-independent, so no D4 needed)
    local featureKey = extractFeatures(colourBoard)

    local validSet = {}
    for _, i in ipairs(validIdcs) do validSet[i] = true end

    local weights = KnowledgeBase.data[featureKey]
	if not weights then
		weights = {}
		for _, t in ipairs(MOVE_TYPES) do
			weights[t] = 1 / #MOVE_TYPES
		end

		KnowledgeBase.addNewState(featureKey, weights)
	end

	local dist = {}
	local total = 0
	for _, idx in ipairs(validIdcs) do
		local cat = self:ClassifyMove(colourBoard, idx, FINAL_PLAYER)

		local w = weights[cat]
		table.insert(dist, { Idx = idx, Cat = cat, Prob = w })
		total = total + w
	end

	-- sample from dist as before, but record the category in history, not the square
	local rand = math.random() * total
	local chosenIdx, chosenCat
	for _, e in ipairs(dist) do
		if rand < e.Prob then chosenIdx, chosenCat = e.Idx, e.Cat; break end
		rand = rand - e.Prob
	end
	chosenIdx  = chosenIdx  or dist[#dist].Idx
	chosenCat  = chosenCat  or dist[#dist].Cat

    -- 7. Record (featureKey, chosenIdx) for EndGame credit
    table.insert(self.history, { state = featureKey, idx = chosenIdx, cat = chosenCat })
    return chosenIdx
end

function AgentMethods.AdjustProb(self, weights, targetCat, delta)
	-- 1. Apply the reward/punishment to the chosen category    
	weights[targetCat] = weights[targetCat] + delta

	-- 2. Normalize so the distribution sums to 1
	local total = 0
	for _, t in ipairs(MOVE_TYPES) do total = total + weights[t] end
	for _, t in ipairs(MOVE_TYPES) do weights[t] = weights[t] / total end

	-- 3. Clamp out-of-range values, then renormalize if anything was clamped
	local clampTotal, clampedCount = 0, 0
	for _, t in ipairs(MOVE_TYPES) do
		if     weights[t] < MIN_PROB then weights[t] = MIN_PROB; clampedCount = clampedCount + 1
		elseif weights[t] > MAX_PROB then weights[t] = MAX_PROB; clampedCount = clampedCount + 1
		end
		clampTotal = clampTotal + weights[t]
	end
	
	if clampedCount > 0 then
		for _, t in ipairs(MOVE_TYPES) do weights[t] = weights[t] / clampTotal end
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
            self:AdjustProb(pairs, move.cat, factor * discount)
        end
    end

    self.history = {}
end

function AgentMethods.StopPlaying(self)
    KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)