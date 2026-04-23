local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local FINAL_PLAYER = 'O'

local LOSS_PUNISH 	= 0.15
local DRAW_REWARD 	= 0.05
local WIN_REWARD 	= 0.1

local MIN_PROB = 0.001  -- never let a move reach 0, keep some exploration
local MAX_PROB = 0.99  -- never let a move reach 0, keep some exploration
local GAMMA = 0.9 -- scalar describing learning decay

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
	gameboard = self.symbol ~= FINAL_PLAYER and XORBoard(gameboard) or gameboard
	local boardStr = table.concat(gameboard)

	if not KnowledgeBase.stateExists(boardStr) then
		local usedIdcs = {} do
			for i, _ in ipairs(gameboard) do
				if self:IsValidMove(gameboard, i, FINAL_PLAYER) then
					table.insert(usedIdcs, i)
				end
			end
		end

		KnowledgeBase.addNewState(boardStr, BuildProbPair(usedIdcs))
	end

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

	table.insert(self.history, 1, {state = boardStr, idx = chosenIdx})
	return chosenIdx
end

function AgentMethods.AdjustProb(self, pairs, targetIdx, delta)
    -- Find and adjust the target move
    for _, pair in ipairs(pairs) do
        if pair["Idx"] == targetIdx then
			local prob = pair["Prob"] + delta
			if prob <= MIN_PROB then
				prob = 0
			elseif prob >= MAX_PROB then
				prob = 1
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
	KnowledgeBase.save()
end

return tHelp.freeze(AgentMethods)