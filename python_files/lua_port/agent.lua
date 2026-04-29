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

function AgentMethods.GetMove(self, gameboard)
	 assert(gameboard[0] == nil, "gameboard is 0-indexed (got board[0])")
  assert(gameboard[1] ~= nil and gameboard[36] ~= nil, "gameboard not 1..36")
  local seen = 0
  for k, _ in pairs(gameboard) do seen = seen + 1 end
  assert(seen == 36, "gameboard has "..seen.." entries, expected 36")
    -- 1. Normalise colour: always reason as O
    local colourBoard = (self.symbol ~= FINAL_PLAYER) and XORBoard(gameboard) or gameboard

    -- 2. Find valid moves on the colour-normalised board
    local validIdcs = {}
    for i = 1, N * N do
        if self:IsValidMove(colourBoard, i, FINAL_PLAYER) then
            table.insert(validIdcs, i)
        end
    end

    if #validIdcs == 0 then
        return -1  -- no valid moves; caller should not have invoked GetMove
    end

    -- 3. Build feature key (orientation-independent, so no D4 needed)
    local featureKey = extractFeatures(colourBoard)

    -- 4. Register unseen feature state.
    --    Move indices stored here are on the colour-normalised real board.
    if not KnowledgeBase.stateExists(featureKey) then
        KnowledgeBase.addNewState(featureKey, BuildProbPair(validIdcs))
    end

    -- 5. Sample from KB restricted to moves valid RIGHT NOW.
    --    A prior visit to the same feature state had different valid moves
    --    (different board, same features), so we intersect with current valid set.
    local validSet = {}
    for _, i in ipairs(validIdcs) do validSet[i] = true end

    local validNow = {}
	local totalProb = 0
	for _, pair in ipairs(KnowledgeBase.data[featureKey]) do
		if self:IsValidMove(colourBoard, pair.Idx, FINAL_PLAYER) then
			table.insert(validNow, pair)
			totalProb = totalProb + pair.Prob
		end
	end

	if #validNow == 0 then
		validNow = BuildProbPair(validIdcs)
		totalProb = 1.0
	end

    -- If no stored moves match current valid moves, fall back to uniform over valid moves.
    -- This happens when the feature state was seen before with a completely different
    -- set of valid board positions (same features, different actual board layout).
    local kbPairs = KnowledgeBase.data[featureKey]
	local known = {}
	for _, p in ipairs(kbPairs) do
		known[p.Idx] = true
	end

	for _, idx in ipairs(validIdcs) do
		if not known[idx] then
			table.insert(kbPairs, { Idx = idx, Prob = MIN_PROB })
		end
	end

    -- 6. Sample a move
    local chosenIdx = nil
    local rand = math.random() * totalProb
    for _, pair in ipairs(validNow) do
        if rand < pair["Prob"] then
            chosenIdx = pair["Idx"]
            break
        end
        rand = rand - pair["Prob"]
    end

    if not chosenIdx then
        chosenIdx = validNow[#validNow]["Idx"]
    end

	local stillValid = self:IsValidMove(colourBoard, chosenIdx, FINAL_PLAYER)
	if colourBoard[chosenIdx] ~= '-' or not stillValid then
		print("=== invalid move chosen ===")
		print("symbol=", self.symbol, "chosenIdx=", chosenIdx, "type=", type(chosenIdx))
		print("colourBoard[chosenIdx]=", tostring(colourBoard[chosenIdx]))
		print("stillValid=", stillValid)
		print("validIdcs=", table.concat(validIdcs, ","))
		print("featureKey=", featureKey)
		print("path=", #validNow == #validIdcs and "fallback" or "kb-filter")
		print("kb-pairs:")
		for _, p in ipairs(KnowledgeBase.data[featureKey]) do
			print("  ", p.Idx, type(p.Idx), p.Prob)
		end
		print("colourBoard:")
		for r = 0, 5 do
			local row = {}
			for c = 1, 6 do row[c] = tostring(colourBoard[r*6 + c]) end
			print("  "..table.concat(row, " "))
		end
		error("invalid move")
	end

    -- 7. Record (featureKey, chosenIdx) for EndGame credit
    table.insert(self.history, { state = featureKey, idx = chosenIdx })

    -- chosenIdx is already on the real board (no un-transform needed)
    return chosenIdx
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
end

function AgentMethods.StopPlaying(self)
    KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)