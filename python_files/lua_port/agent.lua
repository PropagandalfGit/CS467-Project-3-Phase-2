local tHelp = require('table-helpers')
local sHelp = require('string-helpers')

local LOSS_PUNISH 	= 0.15
local DRAW_REWARD 	= 0.05
local WIN_REWARD 	= 0.1

local MIN_PROB = 0.001  -- never let a move reach 0, keep some exploration
local MAX_PROB = 0.99  -- never let a move reach 0, keep some exploration
local GAMMA = 0.9 -- scalar describing learning decay

local BasePlayer = require('base-player')

local AgentMethods = {}
AgentMethods.__index = AgentMethods
setmetatable(AgentMethods, {__index = BasePlayer})

---comment
---@param isX boolean
---@return table
function AgentMethods.new(isX, fileName)
	local player = BasePlayer.new(isX)
	player.kBase = {}
	player.history = {}
	player.fileName = fileName

	local file, err = io.open(fileName, "r")
	if not file then
		file, err = io.open(fileName, "a")
		assert(file, err)
		file:close()
    
		file, err = io.open(fileName, "r")
		assert(file, err)
	end

	for rawLine in file:lines() do
		local line = rawLine:gsub("\r", "")

		local state, stats = table.unpack(sHelp.split(line, "|"))
		local eachIdxStats = sHelp.split(stats or error("BAD"), ":")
		local splitPairs = {}
		for _, pair in ipairs(eachIdxStats) do
			local parts = sHelp.split(pair, ",")
			table.insert(splitPairs, {
				["Idx"] = tonumber(parts[1]),
				["Prob"] = tonumber(parts[2]),
			})
		end

       	player.kBase[state] = splitPairs
    end

	file:close()

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
	local boardStr = table.concat(gameboard)
	if not self.kBase[boardStr] then
		local usedIdcs = {} do
			for i, c in ipairs(gameboard) do
				if c == "-" then
					table.insert(usedIdcs, i)
				end
			end
		end

		self.kBase[boardStr] = BuildProbPair(usedIdcs)
	end

	local rand = math.random()
	local chosenIdx = nil
	for _, pair in ipairs(self.kBase[boardStr]) do
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
	local factor = (status == 1 and WIN_REWARD) or (status == 0 and DRAW_REWARD) or (status == -1 and -LOSS_PUNISH) or error("BAD STATUS")
	for _, move in ipairs(self.history) do
		local pairs = self.kBase[move.state]
		if pairs then
			self:AdjustProb(pairs, move.idx, factor * discount)
		end

		discount = discount * GAMMA
	end

	self.history = {}
end

function AgentMethods.StopPlaying(self)
	local file, err = io.open(self.fileName, "w")
	assert(file, err)

	for key, pairs in pairs(self.kBase) do
		local pairStr = "" do
			for _, pair in ipairs(pairs) do
				pairStr = pairStr .. string.format("%d,%f", pair["Idx"], pair["Prob"]) .. ":"
			end
			-- Delete last colon delimiter
			pairStr = pairStr:sub(1, pairStr:len()-1)
		end
		file:write(string.format("%s|%s\n", key, pairStr))
	end

	file:close()
end

return tHelp.freeze(AgentMethods)