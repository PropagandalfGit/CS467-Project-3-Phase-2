local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local FINAL_PLAYER = 'O'

local LOSS_PUNISH 	= 0.1
local DRAW_REWARD 	= 0.05
local WIN_REWARD 	= 0.2

local MIN_PROB = 0.001  -- never let a move reach 0, keep some exploration
local MAX_PROB = 0.99  -- never let a move reach 1, keep some exploration
local GAMMA = 0.9 -- scalar describing learning decay

local EPSILON     = 0.25   -- start: 25% random exploration
local EPSILON_MIN = 0.05   -- floor: always keep 5% exploration
-- to calculate the EPSILON_DECAY such that EPSILON hits the minimum by a specific number of games
-- use this formula
--      decay = (EPSILON_MIN / EPSILON) * (1/number of games you want the EPSILON to hit min by)
local EPSILON_DECAY = 0.999996  -- scalar describing exploration decay


local BasePlayer = require('base-player')
local KnowledgeBase = require('knowledge-base')

local AgentMethods = {}
AgentMethods.__index = AgentMethods
setmetatable(AgentMethods, {__index = BasePlayer})

local function XORBoard(board)
	local XORB = {}
	for _, c in pairs(board) do
		table.insert(XORB, c == '-' and '-' or (c == 'X' and 'O' or 'X'))
	end

	return XORB
end

---comment
---@param xORo boolean
---@return table
function AgentMethods.new(xORo, filePath)
	KnowledgeBase.new(filePath)
	local player = BasePlayer.new(xORo)
	player.history = {}

	return setmetatable(player, AgentMethods)
end

---comment
---@param idces table
---@return table
local function BuildProbPair(idces)
	local pairs = {}
	local ratio = 1 / #idces

	for _, c in ipairs(idces) do
		table.insert(pairs, {["Idx"] = tonumber(c), ["Prob"] = tonumber(ratio)})
	end

	return pairs
end

---comment
---@param self table
---@param gameboard table
---@return integer
function AgentMethods.GetMove(self, gameboard)
	local flipBoard = self.symbol ~= FINAL_PLAYER and XORBoard(gameboard) or gameboard
	local boardStr = table.concat(flipBoard)

	if not KnowledgeBase.stateExists(boardStr) then
		local usedIdcs = {} do
			for i, _ in ipairs(flipBoard) do
				if self:IsValidMove(flipBoard, i, FINAL_PLAYER) then
					table.insert(usedIdcs, i)
				end
			end
		end

		KnowledgeBase.addNewState(boardStr, BuildProbPair(usedIdcs))
	end

	--[[
    local chosenIdx = nil
	local rand = math.random()
	for _, pair in ipairs(KnowledgeBase.data[boardStr]) do
		local w = pair["Prob"]

		if rand < w then
			chosenIdx = pair["Idx"]
		 	break
		end

		rand = rand - w
	end

	if not chosenIdx then
		error("This should not happen", 2)
	end
    ]]
    local chosenIdx
    if math.random() < EPSILON then
        -- explore
        local candidates = {}
        for _, pair in ipairs(KnowledgeBase.data[boardStr]) do
            if pair.Prob > 0 then
                table.insert(candidates, pair.Idx)
            end
        end
        chosenIdx = candidates[math.random(#candidates)]
    else
        -- exploit
        local bestProb = -1
        for _, pair in ipairs(KnowledgeBase.data[boardStr]) do
            if pair.Prob > bestProb then
                bestProb  = pair.Prob
                chosenIdx = pair.Idx
            end
        end
    end

    EPSILON = math.max(EPSILON_MIN, EPSILON * EPSILON_DECAY)
	table.insert(self.history, 1, {state = boardStr, idx = chosenIdx})
	return chosenIdx
end

function AgentMethods.AdjustProb(self, pairs, targetIdx, delta)
    -- Find and adjust the target move
    for _, pair in ipairs(pairs) do
        if pair["Idx"] == targetIdx then
			local prob = pair["Prob"] + delta
			if prob <= MIN_PROB then
				prob = MIN_PROB
			elseif prob >= MAX_PROB then
				prob = MAX_PROB
			end
			
            pair["Prob"] = prob
            break
        end
    end

    -- Renormalize so all probs sum to 1
    local total = 0
    for _, pair in ipairs(pairs) do
        total = total + pair["Prob"]
    end

    for _, pair in ipairs(pairs) do
        pair["Prob"] = pair["Prob"] / total
    end
end

---comment
---@param self table
---@param status integer
function AgentMethods.EndGame(self, status)
	if status == 1 then
		self.winCount = self.winCount + 1
	end

	local discount = 1.0
	local factor = 
		(status == 1 and WIN_REWARD) or 
		(status == 0 and DRAW_REWARD) or 
		(status == -1 and -LOSS_PUNISH) or 
		error("BAD STATUS")

	for _, move in ipairs(self.history) do
		local pairs = KnowledgeBase.data[move.state]
		if pairs then
			self:AdjustProb(pairs, move.idx, factor * discount)
		end

		discount = discount * GAMMA
	end

	self.history = {}
end

function AgentMethods.StopPlaying(self)
    KnowledgeBase.pruneUnlearned()
    KnowledgeBase.showStatesFound()
	KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)
